import Foundation
import SymphonyShared

// MARK: - Agent Runner Error

public enum AgentRunnerError: Error, Equatable, Sendable {
  case workspacePreparationFailed(String)
  case promptRenderFailed(String)
  case hookFailed(hook: String, reason: String)
  case runAlreadyActive(RunID)
  case runNotFound(RunID)
}

// MARK: - Agent Run Result

public struct AgentRunResult: Equatable, Sendable {
  public let context: RunContext
  public let sessionID: SessionID
  public let finalState: RunLifecycleState
  public let eventCount: Int
  public let error: String?

  public init(
    context: RunContext,
    sessionID: SessionID,
    finalState: RunLifecycleState,
    eventCount: Int,
    error: String?
  ) {
    self.context = context
    self.sessionID = sessionID
    self.finalState = finalState
    self.eventCount = eventCount
    self.error = error
  }
}

public struct AgentRunStartInfo: Equatable, Sendable {
  public let context: RunContext
  public let issue: Issue
  public let provider: String
  public let sessionID: SessionID
  public let workspacePath: String

  public init(
    context: RunContext,
    issue: Issue,
    provider: String,
    sessionID: SessionID,
    workspacePath: String
  ) {
    self.context = context
    self.issue = issue
    self.provider = provider
    self.sessionID = sessionID
    self.workspacePath = workspacePath
  }
}

// MARK: - Agent Run Event Sink

public protocol AgentRunEventSink: Sendable {
  func runDidStart(_ startInfo: AgentRunStartInfo)
  func runDidTransition(_ context: RunContext, to state: RunLifecycleState)
  func runDidReceiveEvent(_ event: AgentRawEvent)
  func runDidComplete(_ result: AgentRunResult)
}

// MARK: - Agent Running Protocol

public protocol AgentRunning: Sendable {
  func executeRun(
    context: RunContext,
    issue: Issue,
    config: WorkflowConfig,
    promptTemplate: String
  ) async -> AgentRunResult

  func cancelRun(runID: RunID) async throws
}

private final class StallWatchState: @unchecked Sendable {
  private let lock = NSLock()
  private var _lastEventAt: Date
  private var _stallError: String?

  init(lastEventAt: Date) {
    _lastEventAt = lastEventAt
  }

  var lastEventAt: Date {
    lock.withLock { _lastEventAt }
  }

  var stallError: String? {
    lock.withLock { _stallError }
  }

  func recordEvent(at date: Date) {
    lock.withLock { _lastEventAt = date }
  }

  func markStalled(timeoutMS: Int) {
    lock.withLock {
      _stallError = "Stall detected: no events for \(timeoutMS)ms"
    }
  }
}

// MARK: - Agent Runner

public final class AgentRunner: AgentRunning, @unchecked Sendable {
  private let lock = NSLock()
  private let workspaceManager: any WorkspaceManaging
  private let processLauncher: any ProcessLaunching
  private let eventSink: any AgentRunEventSink
  private var _activeRuns: [RunID: ActiveRun] = [:]

  struct ActiveRun: Sendable {
    let context: RunContext
    let sessionID: SessionID
    let adapter: any ProviderAdapting
  }

  public init(
    workspaceManager: any WorkspaceManaging,
    processLauncher: any ProcessLaunching,
    eventSink: any AgentRunEventSink
  ) {
    self.workspaceManager = workspaceManager
    self.processLauncher = processLauncher
    self.eventSink = eventSink
  }

  // MARK: - Synchronous State Helpers

  private nonisolated func registerActiveRun(_ run: ActiveRun, for runID: RunID) {
    lock.withLock { _activeRuns[runID] = run }
  }

  @discardableResult
  private nonisolated func removeActiveRun(for runID: RunID) -> ActiveRun? {
    lock.withLock { _activeRuns.removeValue(forKey: runID) }
  }

  // MARK: - Execute Run

  public func executeRun(
    context: RunContext,
    issue: Issue,
    config: WorkflowConfig,
    promptTemplate: String
  ) async -> AgentRunResult {
    let sessionID = SessionID(UUID().uuidString)

    // Step 1: Prepare workspace
    eventSink.runDidTransition(context, to: .preparingWorkspace)
    let workspacePath: String
    do {
      let key = issue.identifier.workspaceKey
      workspacePath = try workspaceManager.ensureWorkspace(for: key, hooks: config.hooks)
    } catch {
      let result = AgentRunResult(
        context: context, sessionID: sessionID, finalState: .failed,
        eventCount: 0, error: "Workspace preparation failed: \(error)")
      eventSink.runDidComplete(result)
      return result
    }

    // Step 2: Build prompt
    eventSink.runDidTransition(context, to: .buildingPrompt)
    let prompt: String
    do {
      prompt = try PromptRenderer.render(
        template: promptTemplate, issue: issue, attempt: context.attempt)
    } catch {
      let result = AgentRunResult(
        context: context, sessionID: sessionID, finalState: .failed,
        eventCount: 0, error: "Prompt render failed: \(error)")
      eventSink.runDidComplete(result)
      return result
    }

    // Step 3: Launch agent process
    eventSink.runDidTransition(context, to: .launchingAgentProcess)
    let adapter = ProviderAdapterFactory.makeAdapter(
      for: config.agent.defaultProvider,
      config: config.providers,
      processLauncher: processLauncher
    )

    // Register active run
    let activeRun = ActiveRun(context: context, sessionID: sessionID, adapter: adapter)
    registerActiveRun(activeRun, for: context.runID)

    // Step 4: Initialize session
    eventSink.runDidTransition(context, to: .initializingSession)
    let eventStream: AsyncThrowingStream<AgentRawEvent, Error>
    do {
      eventStream = try await adapter.startSession(
        sessionID: sessionID,
        workspacePath: workspacePath,
        prompt: prompt,
        environment: [:]
      )
    } catch {
      removeActiveRun(for: context.runID)
      let result = AgentRunResult(
        context: context, sessionID: sessionID, finalState: .failed,
        eventCount: 0, error: "Session start failed: \(error)")
      eventSink.runDidComplete(result)
      return result
    }

    eventSink.runDidStart(
      AgentRunStartInfo(
        context: context,
        issue: issue,
        provider: adapter.providerName.rawValue,
        sessionID: sessionID,
        workspacePath: workspacePath
      ))

    // Step 5: Stream events with stall detection
    eventSink.runDidTransition(context, to: .streamingTurn)
    var eventCount = 0
    var streamError: String?

    let stallTimeoutMS = config.providers.stallTimeoutMS(for: config.agent.defaultProvider)
    let stallDetector = StallDetector(stallTimeoutMS: stallTimeoutMS)
    let stallState = StallWatchState(lastEventAt: Date())
    let stallWatchdog: Task<Void, Never>?
    if stallDetector.isEnabled {
      stallWatchdog = Task {
        while !Task.isCancelled {
          do {
            try await Task.sleep(nanoseconds: UInt64(stallTimeoutMS) * 1_000_000)
          } catch {
            break
          }

          if stallDetector.isStalled(lastEventAt: stallState.lastEventAt) {
            stallState.markStalled(timeoutMS: stallTimeoutMS)
            try? await adapter.cancelSession(sessionID: sessionID)
            break
          }
        }
      }
    } else {
      stallWatchdog = nil
    }

    do {
      for try await event in eventStream {
        stallState.recordEvent(at: Date())
        eventCount += 1
        eventSink.runDidReceiveEvent(event)
      }
    } catch {
      if stallState.stallError == nil {
        streamError = String(describing: error)
      }
    }

    stallWatchdog?.cancel()
    if let stallError = stallState.stallError {
      streamError = stallError
    }

    // Step 6: Finishing
    let finalState: RunLifecycleState
    if streamError?.hasPrefix("Stall detected") == true {
      finalState = .stalled
    } else if streamError == nil {
      finalState = .succeeded
    } else {
      finalState = .failed
    }

    eventSink.runDidTransition(context, to: .finishing)
    removeActiveRun(for: context.runID)
    let result = AgentRunResult(
      context: context, sessionID: sessionID, finalState: finalState,
      eventCount: eventCount, error: streamError)
    eventSink.runDidComplete(result)
    return result
  }

  // MARK: - Cancel Run

  public func cancelRun(runID: RunID) async throws {
    guard let activeRun = removeActiveRun(for: runID) else {
      throw AgentRunnerError.runNotFound(runID)
    }
    try await activeRun.adapter.cancelSession(sessionID: activeRun.sessionID)
  }

  public var activeRunCount: Int {
    lock.withLock { _activeRuns.count }
  }
}

// MARK: - No-Op Event Sink

public struct NoOpAgentRunEventSink: AgentRunEventSink, Sendable {
  public init() {}
  public func runDidStart(_ startInfo: AgentRunStartInfo) {}
  public func runDidTransition(_ context: RunContext, to state: RunLifecycleState) {}
  public func runDidReceiveEvent(_ event: AgentRawEvent) {}
  public func runDidComplete(_ result: AgentRunResult) {}
}
