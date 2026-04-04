import Foundation
import SymphonyShared
import SymphonyServerCore

// MARK: - Codex Adapter (Section 10.7)

// SAFETY: @unchecked Sendable — all stored fields are immutable (`let`).
// Nested types have their own synchronization.
public final class CodexAdapter: ProviderAdapting, @unchecked Sendable {
  public let providerName: ProviderName = .codex
  public let capabilities = ProviderCapabilities(
    supportsResume: false,
    supportsInterrupt: true,
    supportsUsageTotals: true,
    supportsRateLimits: false,
    supportsExplicitApprovals: true,
    supportsStructuredToolEvents: true,
    toolExecutionMode: .mixed
  )

  private let config: CodexProviderConfig
  private let processLauncher: ProcessLaunching
  private let activeSessions = SessionStore()
  private let sessionRegistry = CodexSessionRegistry()

  public init(config: CodexProviderConfig, processLauncher: ProcessLaunching? = nil) {
    self.config = config
    self.processLauncher = processLauncher ?? DefaultProcessLauncher()
  }

  public func startSession(
    sessionID: SessionID,
    issue: Issue? = nil,
    workspacePath: String,
    prompt: String,
    environment: [String: String]
  ) async throws -> AsyncThrowingStream<AgentRawEvent, Error> {
    let process = try processLauncher.launch(
      command: config.command,
      workspacePath: workspacePath,
      environment: environment
    )
    let startupState = CodexStartupState(
      issue: issue,
      workspacePath: workspacePath,
      prompt: prompt,
      config: config
    )
    let sessionState = sessionRegistry.state(for: sessionID)
    if let issue {
      sessionState.recordIssueContext(
        identifier: issue.identifier.rawValue,
        title: issue.title
      )
    }
    activeSessions.store(
      sessionID: sessionID,
      process: process,
      workspacePath: workspacePath,
      environment: environment
    )
    let timeoutMonitor = CodexTimeoutMonitor()
    let stream = makeEventStream(
      from: process,
      sessionID: sessionID,
      startupState: startupState,
      timeoutMonitor: timeoutMonitor
    )

    do {
      try submitJSONMessages(startupMessages(workspacePath: workspacePath), to: process)
    } catch {
      timeoutMonitor.cancelAll()
      sessionRegistry.remove(sessionID: sessionID)
      _ = activeSessions.remove(sessionID: sessionID)
      process.terminate()
      throw error
    }

    return stream
  }

  public func continueSession(
    sessionID: SessionID,
    guidance: String
  ) async throws -> AsyncThrowingStream<AgentRawEvent, Error> {
    guard let managedSession = activeSessions.managedSession(for: sessionID),
      let threadID = sessionRegistry.threadID(for: sessionID)
    else {
      throw ProviderAdapterError.sessionNotFound(sessionID)
    }
    let sessionState = sessionRegistry.state(for: sessionID)
    let timeoutMonitor = CodexTimeoutMonitor()

    let stream = makeEventStream(
      from: managedSession.process,
      sessionID: sessionID,
      startupState: nil,
      timeoutMonitor: timeoutMonitor
    )
    do {
      try submitJSONMessages(
        [
          makeCodexTurnStartMessage(
            id: sessionState.nextTurnRequestID(),
            threadID: threadID,
            issueIdentifier: sessionState.issueIdentifier ?? "unknown",
            issueTitle: sessionState.issueTitle ?? "Untitled",
            workspacePath: managedSession.workspacePath,
            input: guidance,
            config: config
          )
        ],
        to: managedSession.process
      )
      timeoutMonitor.startTurnTimeout(
        sessionID: sessionID,
        turnTimeoutMS: config.turnTimeoutMS,
        process: managedSession.process
      )
    } catch {
      timeoutMonitor.cancelAll()
      sessionRegistry.remove(sessionID: sessionID)
      _ = activeSessions.remove(sessionID: sessionID)
      managedSession.process.terminate()
      throw error
    }

    return stream
  }

  public func interruptSession(sessionID: SessionID) async throws -> Bool {
    guard let managedSession = activeSessions.managedSession(for: sessionID),
      let threadID = sessionRegistry.threadID(for: sessionID),
      let turnID = sessionRegistry.turnID(for: sessionID)
    else {
      return false
    }

    let sessionState = sessionRegistry.state(for: sessionID)
    do {
      try submitJSONMessages(
        [
          makeCodexInterruptMessage(
            id: sessionState.nextTurnRequestID(),
            threadID: threadID,
            turnID: turnID
          )
        ],
        to: managedSession.process
      )
      return true
    } catch {
      return false
    }
  }

  public func cancelSession(sessionID: SessionID) async throws {
    guard let managedSession = activeSessions.managedSession(for: sessionID) else {
      throw ProviderAdapterError.sessionNotFound(sessionID)
    }
    if try await interruptSession(sessionID: sessionID) {
      return
    }
    sessionRegistry.remove(sessionID: sessionID)
    _ = activeSessions.remove(sessionID: sessionID)
    managedSession.process.terminate()
  }

  func makeEventStream(
    from process: LaunchedProcess,
    sessionID: SessionID
  ) -> AsyncThrowingStream<AgentRawEvent, Error> {
    makeEventStream(
      from: process,
      sessionID: sessionID,
      startupState: nil,
      timeoutMonitor: CodexTimeoutMonitor()
    )
  }

  private func makeEventStream(
    from process: LaunchedProcess,
    sessionID: SessionID,
    startupState: CodexStartupState?,
    timeoutMonitor: CodexTimeoutMonitor
  ) -> AsyncThrowingStream<AgentRawEvent, Error> {
    let sessionState = sessionRegistry.state(for: sessionID)
    let activeSessions = self.activeSessions
    let finishState = StreamFinishState()
    let outputBuffer = CodexOutputBuffer()
    return AsyncThrowingStream { continuation in
      let finishWithError: @Sendable (Error) -> Void = { error in
        timeoutMonitor.cancelAll()
        self.sessionRegistry.remove(sessionID: sessionID)
        activeSessions.remove(sessionID: sessionID)
        finishState.finishIfNeeded {
          continuation.finish(throwing: error)
        }
      }

      let finishSuccessfully: @Sendable () -> Void = {
        timeoutMonitor.cancelAll()
        self.sessionRegistry.remove(sessionID: sessionID)
        activeSessions.remove(sessionID: sessionID)
        finishState.finishIfNeeded {
          continuation.finish()
        }
      }

      timeoutMonitor.startReadTimeout(
        sessionID: sessionID,
        readTimeoutMS: self.config.readTimeoutMS,
        process: process,
        finish: finishWithError
      )

      process.onOutput { data in
        guard let output = String(data: data, encoding: .utf8) else { return }

        for line in outputBuffer.append(output) {
          self.handleCodexLine(
            line,
            sessionID: sessionID,
            startupState: startupState,
            sessionState: sessionState,
            process: process,
            activeSessions: activeSessions,
            timeoutMonitor: timeoutMonitor,
            finishState: finishState,
            finishWithError: finishWithError,
            finishSuccessfully: finishSuccessfully,
            continuation: continuation
          )
        }
      }

      process.onTermination { exitCode in
        let timeoutError = timeoutMonitor.consumeTerminalError()
        for line in outputBuffer.finish() {
          self.handleCodexLine(
            line,
            sessionID: sessionID,
            startupState: startupState,
            sessionState: sessionState,
            process: process,
            activeSessions: activeSessions,
            timeoutMonitor: timeoutMonitor,
            finishState: finishState,
            finishWithError: finishWithError,
            finishSuccessfully: finishSuccessfully,
            continuation: continuation
          )
        }

        timeoutMonitor.cancelAll()
        self.sessionRegistry.remove(sessionID: sessionID)
        activeSessions.remove(sessionID: sessionID)
        finishState.finishIfNeeded {
          if let timeoutError {
            continuation.finish(throwing: timeoutError)
          } else if exitCode == 0 {
            continuation.finish()
          } else {
            continuation.finish(
              throwing: ProviderAdapterError.processExitedUnexpectedly(exitCode: exitCode))
          }
        }
      }
    }
  }

  private func handleCodexLine(
    _ line: String,
    sessionID: SessionID,
    startupState: CodexStartupState?,
    sessionState: CodexSessionState,
    process: LaunchedProcess,
    activeSessions: SessionStore,
    timeoutMonitor: CodexTimeoutMonitor,
    finishState: StreamFinishState,
    finishWithError: @escaping @Sendable (Error) -> Void,
    finishSuccessfully: @escaping @Sendable () -> Void,
    continuation: AsyncThrowingStream<AgentRawEvent, Error>.Continuation
  ) {
    let msg = protocolJSONMessage(from: line)
    timeoutMonitor.cancelReadTimeout()
    if let threadID = codexStartupThreadID(from: msg) {
      sessionState.recordThreadID(threadID)
      if let startupState,
        let turnStartMessage = startupState.turnStartMessageIfNeeded(threadID: threadID)
      {
        do {
          try submitJSONMessages([turnStartMessage], to: process)
          timeoutMonitor.startTurnTimeout(
            sessionID: sessionID,
            turnTimeoutMS: config.turnTimeoutMS,
            process: process
          )
        } catch {
          finishWithError(error)
          return
        }
      }
    }

    if let turnID = codexTurnID(from: msg) {
      sessionState.recordTurnID(turnID)
    }

    if shouldSuppressSuccessfulCodexResponse(msg) {
      return
    }

    let descriptor = ProviderEventInspection.describe(from: line, provider: .codex)
    let event = AgentRawEvent(
      sessionID: sessionID,
      provider: "codex",
      sequence: sessionState.nextSequence(),
      timestamp: ISO8601DateFormatter().string(from: Date()),
      rawJSON: line,
      providerEventType: descriptor.eventType,
      normalizedEventKind: descriptor.normalizedKind.rawValue
    )
    continuation.yield(event)

    if descriptor.isTerminal {
      switch codexTurnOutcome(from: line) {
      case .failed:
        finishWithError(
          ProviderAdapterError.terminalOutcome(
            sessionID: sessionID,
            outcome: CodexTerminalOutcome.failed.rawValue
          ))
      case .interrupted:
        finishWithError(
          ProviderAdapterError.terminalOutcome(
            sessionID: sessionID,
            outcome: CodexTerminalOutcome.interrupted.rawValue
          ))
      case .completed, nil:
        finishSuccessfully()
      }
    }
  }

  private func startupMessages(workspacePath: String) -> [[String: Any]] {
    var threadStartParams: [String: Any] = [
      "cwd": workspacePath,
      "ephemeral": true,
    ]
    if let approvalPolicy = config.sessionApprovalPolicy {
      threadStartParams["approvalPolicy"] = approvalPolicy
    }
    if let sandbox = config.sessionSandbox {
      threadStartParams["sandbox"] = sandbox.foundationValue
    }

    return [
      [
        "id": 1,
        "method": "initialize",
        "params": [
          "clientInfo": [
            "name": "symphony",
            "version": "0.0.1",
          ]
        ],
      ],
      [
        "method": "initialized"
      ],
      [
        "id": 2,
        "method": "thread/start",
        "params": threadStartParams,
      ],
    ]
  }
}
