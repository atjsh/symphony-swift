import Foundation
import SymphonyShared

// MARK: - Orchestrator Engine Error

public enum OrchestratorEngineError: Error, Equatable, Sendable {
  case workflowLoadFailed(String)
  case trackerCreationFailed(String)
  case alreadyRunning
  case notRunning
}

// MARK: - Orchestrator Engine State

public enum OrchestratorEngineState: String, Equatable, Sendable {
  case idle
  case starting
  case running
  case stopping
  case stopped
}

// MARK: - Run Context

public struct RunContext: Equatable, Sendable {
  public let issueID: IssueID
  public let issueIdentifier: IssueIdentifier
  public let runID: RunID
  public let attempt: Int

  public init(issueID: IssueID, issueIdentifier: IssueIdentifier, runID: RunID, attempt: Int) {
    self.issueID = issueID
    self.issueIdentifier = issueIdentifier
    self.runID = runID
    self.attempt = attempt
  }
}

// MARK: - Engine Event Observer

public protocol EngineEventObserving: Sendable {
  func engineStateChanged(_ state: OrchestratorEngineState) async
  func engineTickCompleted(_ result: TickResult) async
  func engineDispatchStarted(_ context: RunContext) async
  func engineRunCompleted(_ context: RunContext, success: Bool) async
  func engineError(_ error: Error, context: String) async
}

// MARK: - Default No-Op Observer

public struct NoOpEngineEventObserver: EngineEventObserving, Sendable {
  public init() {}

  public func engineStateChanged(_ state: OrchestratorEngineState) async {}
  public func engineTickCompleted(_ result: TickResult) async {}
  public func engineDispatchStarted(_ context: RunContext) async {}
  public func engineRunCompleted(_ context: RunContext, success: Bool) async {}
  public func engineError(_ error: Error, context: String) async {}
}

// MARK: - Orchestrator Engine

public final class OrchestratorEngine: @unchecked Sendable {
  private let lock = NSLock()
  private var _state: OrchestratorEngineState = .idle
  private var _config: WorkflowConfig
  private var _loopTask: Task<Void, Never>?
  private let trackerFactory: @Sendable (TrackerConfig) throws -> any TrackerAdapting
  private let workspaceManagerFactory: @Sendable (WorkspaceConfig) -> any WorkspaceManaging
  private let agentRunnerFactory: (@Sendable (any WorkspaceManaging) -> any AgentRunning)?
  private let promptTemplate: String
  private let observer: any EngineEventObserving

  public var state: OrchestratorEngineState {
    lock.withLock { _state }
  }

  public var config: WorkflowConfig {
    lock.withLock { _config }
  }

  public init(
    config: WorkflowConfig,
    trackerFactory: @escaping @Sendable (TrackerConfig) throws -> any TrackerAdapting,
    workspaceManagerFactory: @escaping @Sendable (WorkspaceConfig) -> any WorkspaceManaging = {
      WorkspaceManager(root: $0.root)
    },
    agentRunnerFactory: (@Sendable (any WorkspaceManaging) -> any AgentRunning)? = nil,
    promptTemplate: String = "",
    observer: any EngineEventObserving = NoOpEngineEventObserver()
  ) {
    self._config = config
    self.trackerFactory = trackerFactory
    self.workspaceManagerFactory = workspaceManagerFactory
    self.agentRunnerFactory = agentRunnerFactory
    self.promptTemplate = promptTemplate
    self.observer = observer
  }

  // MARK: - Lifecycle

  public func start() throws {
    let shouldStart: Bool = lock.withLock {
      guard _state == .idle || _state == .stopped else { return false }
      _state = .starting
      return true
    }

    guard shouldStart else {
      throw OrchestratorEngineError.alreadyRunning
    }

    let currentConfig = config
    let observer = self.observer
    let trackerFactory = self.trackerFactory
    let workspaceManagerFactory = self.workspaceManagerFactory
    let agentRunnerFactory = self.agentRunnerFactory
    let promptTemplate = self.promptTemplate

    let task = Task { [weak self] in
      await observer.engineStateChanged(.starting)

      do {
        let tracker = try trackerFactory(currentConfig.tracker)
        let workspaceManager = workspaceManagerFactory(currentConfig.workspace)
        let agentRunner = agentRunnerFactory?(workspaceManager)
        let delegate = EngineOrchestratorDelegate(
          workspaceManager: workspaceManager,
          observer: observer,
          agentRunner: agentRunner,
          config: currentConfig,
          promptTemplate: promptTemplate)
        let orchestrator = Orchestrator(
          tracker: tracker, config: currentConfig, delegate: delegate)

        // Startup cleanup (Section 7.5)
        await self?.performStartupCleanup(
          tracker: tracker, config: currentConfig,
          workspaceManager: workspaceManager)

        self?.transitionTo(.running)
        await observer.engineStateChanged(.running)

        // Poll loop
        let intervalNS = UInt64(currentConfig.polling.intervalMS) * 1_000_000
        while !Task.isCancelled {
          if let result = try? await orchestrator.tick() {
            await observer.engineTickCompleted(result)
          }

          do {
            try await Task.sleep(nanoseconds: intervalNS)
          } catch {
            break
          }
        }
      } catch {
        await observer.engineError(error, context: "startup")
      }

      self?.transitionTo(.stopped)
      await observer.engineStateChanged(.stopped)
    }

    lock.withLock { _loopTask = task }
  }

  public func stop() {
    lock.lock()
    guard _state == .running || _state == .starting else {
      lock.unlock()
      return
    }
    _state = .stopping
    _loopTask?.cancel()
    _loopTask = nil
    lock.unlock()
  }

  // MARK: - Config Reload (Section 6.6)

  public func reloadConfig(_ newConfig: WorkflowConfig) {
    lock.withLock { _config = newConfig }
  }

  // MARK: - State Transitions

  private func transitionTo(_ newState: OrchestratorEngineState) {
    lock.withLock { _state = newState }
  }

  // MARK: - Startup Cleanup (Section 7.5)

  private func performStartupCleanup(
    tracker: any TrackerAdapting,
    config: WorkflowConfig,
    workspaceManager: any WorkspaceManaging
  ) async {
    do {
      let terminalIssues = try await tracker.fetchIssuesByStates(config.tracker.terminalStates)
      for issue in terminalIssues {
        let key = WorkspaceKey(issue.identifier.rawValue)
        try? workspaceManager.removeWorkspace(for: key, hooks: config.hooks)
      }
    } catch {
      await observer.engineError(error, context: "startupCleanup")
    }
  }
}

// MARK: - Engine Orchestrator Delegate

final class EngineOrchestratorDelegate: OrchestratorDelegate, @unchecked Sendable {
  private let workspaceManager: any WorkspaceManaging
  private let observer: any EngineEventObserving
  private let agentRunner: (any AgentRunning)?
  private let config: WorkflowConfig
  private let promptTemplate: String

  init(
    workspaceManager: any WorkspaceManaging,
    observer: any EngineEventObserving,
    agentRunner: (any AgentRunning)? = nil,
    config: WorkflowConfig = .defaults,
    promptTemplate: String = ""
  ) {
    self.workspaceManager = workspaceManager
    self.observer = observer
    self.agentRunner = agentRunner
    self.config = config
    self.promptTemplate = promptTemplate
  }

  func orchestratorDidDispatch(issue: Issue) async {
    let runID = RunID(UUID().uuidString)
    let context = RunContext(
      issueID: issue.id, issueIdentifier: issue.identifier, runID: runID, attempt: 1)
    await observer.engineDispatchStarted(context)

    if let agentRunner {
      let result = await agentRunner.executeRun(
        context: context, issue: issue, config: config, promptTemplate: promptTemplate)
      let success = result.finalState == .succeeded
      await observer.engineRunCompleted(context, success: success)
    }
  }

  func orchestratorDidCancel(
    issueID: IssueID, issueIdentifier: IssueIdentifier, reason: String, cleanup: Bool
  ) async {
    if cleanup {
      let key = WorkspaceKey(issueIdentifier.rawValue)
      try? workspaceManager.removeWorkspace(for: key, hooks: HooksConfig.defaults)
    }
    let runID = RunID(UUID().uuidString)
    let context = RunContext(
      issueID: issueID, issueIdentifier: issueIdentifier, runID: runID, attempt: 1)
    await observer.engineRunCompleted(context, success: false)
  }

  func orchestratorDidRefreshSnapshot(issue: Issue) async {
    let runID = RunID(UUID().uuidString)
    let context = RunContext(
      issueID: issue.id, issueIdentifier: issue.identifier, runID: runID, attempt: 1)
    await observer.engineDispatchStarted(context)
  }

  func orchestratorDidRetry(record: RetryRecord) async {
    let runID = RunID(UUID().uuidString)
    let context = RunContext(
      issueID: record.issueID, issueIdentifier: record.issueIdentifier,
      runID: runID, attempt: record.attempt)
    await observer.engineDispatchStarted(context)
  }
}

// MARK: - Workflow Reloader (Section 6.6)

public final class WorkflowReloader: @unchecked Sendable {
  private let lock = NSLock()
  private let workflowPath: String
  private var _lastConfig: WorkflowConfig?
  private var _dispatchSource: DispatchSourceFileSystemObject?
  private var _fileDescriptor: Int32 = -1
  private let onChange: @Sendable (WorkflowConfig) -> Void

  public init(
    workflowPath: String,
    onChange: @escaping @Sendable (WorkflowConfig) -> Void
  ) {
    self.workflowPath = workflowPath
    self.onChange = onChange
  }

  deinit {
    stopWatching()
  }

  public func startWatching() throws {
    let fd = open(workflowPath, O_EVTONLY)
    guard fd >= 0 else {
      throw OrchestratorEngineError.workflowLoadFailed(
        "Cannot open \(workflowPath) for watching"
      )
    }

    let source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: fd,
      eventMask: [.write, .rename, .delete],
      queue: DispatchQueue.global(qos: .utility)
    )

    source.setEventHandler { [weak self] in
      self?.processFileChange()
    }

    source.setCancelHandler {
      close(fd)
    }

    lock.withLock {
      _fileDescriptor = fd
      _dispatchSource = source
    }

    source.resume()
  }

  public func stopWatching() {
    lock.lock()
    let source = _dispatchSource
    _dispatchSource = nil
    _fileDescriptor = -1
    lock.unlock()

    source?.cancel()
  }

  public func processFileChange() {
    do {
      let content = try String(contentsOfFile: workflowPath, encoding: .utf8)
      let definition = try WorkflowParser.parse(content: content)
      let previousConfig = lock.withLock { _lastConfig }
      if previousConfig != definition.config {
        lock.withLock { _lastConfig = definition.config }
        onChange(definition.config)
      }
    } catch {
      // Invalid reloads must not crash; keep last known good config
    }
  }

  public var isWatching: Bool {
    lock.withLock { _dispatchSource != nil }
  }
}

// MARK: - Collecting Engine Observer (for testing)

public final class CollectingEngineObserver: EngineEventObserving, @unchecked Sendable {
  private let lock = NSLock()
  private var _stateChanges: [OrchestratorEngineState] = []
  private var _tickResults: [TickResult] = []
  private var _dispatches: [RunContext] = []
  private var _completions: [(RunContext, Bool)] = []
  private var _errors: [(String, String)] = []

  public init() {}

  public var stateChanges: [OrchestratorEngineState] {
    lock.withLock { _stateChanges }
  }

  public var tickResults: [TickResult] {
    lock.withLock { _tickResults }
  }

  public var dispatches: [RunContext] {
    lock.withLock { _dispatches }
  }

  public var completions: [(RunContext, Bool)] {
    lock.withLock { _completions }
  }

  public var errors: [(message: String, context: String)] {
    lock.withLock { _errors }
  }

  public nonisolated func engineStateChanged(_ state: OrchestratorEngineState) async {
    lock.withLock { _stateChanges.append(state) }
  }

  public nonisolated func engineTickCompleted(_ result: TickResult) async {
    lock.withLock { _tickResults.append(result) }
  }

  public nonisolated func engineDispatchStarted(_ context: RunContext) async {
    lock.withLock { _dispatches.append(context) }
  }

  public nonisolated func engineRunCompleted(_ context: RunContext, success: Bool) async {
    lock.withLock { _completions.append((context, success)) }
  }

  public nonisolated func engineError(_ error: Error, context: String) async {
    lock.withLock { _errors.append(("\(error)", context)) }
  }
}
