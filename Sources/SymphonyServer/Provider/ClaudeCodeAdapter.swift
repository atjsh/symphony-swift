import Foundation
import SymphonyShared
import SymphonyServerCore

// MARK: - Claude Code CLI Adapter (Section 10.8)

public final class ClaudeCodeAdapter: ProviderAdapting, @unchecked Sendable {
  public let providerName: ProviderName = .claudeCode
  public let capabilities = ProviderCapabilities(
    supportsResume: true,
    supportsInterrupt: false,
    supportsUsageTotals: true,
    supportsRateLimits: false,
    supportsExplicitApprovals: false,
    supportsStructuredToolEvents: true,
    toolExecutionMode: .providerManaged
  )

  private let config: ClaudeCodeProviderConfig
  private let processLauncher: ProcessLaunching
  private let activeSessions = SessionStore()

  public init(config: ClaudeCodeProviderConfig, processLauncher: ProcessLaunching? = nil) {
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
    var args = config.command
    args += " -p --output-format stream-json"
    if let permissionMode = config.permissionMode {
      args += " --permission-mode \(permissionMode)"
    }

    let process = try processLauncher.launch(
      command: args,
      workspacePath: workspacePath,
      environment: environment
    )
    try submitInput(prompt, to: process)
    activeSessions.store(
      sessionID: sessionID,
      process: process,
      workspacePath: workspacePath,
      environment: environment
    )
    return makeEventStream(from: process, sessionID: sessionID)
  }

  public func continueSession(
    sessionID: SessionID,
    guidance: String
  ) async throws -> AsyncThrowingStream<AgentRawEvent, Error> {
    guard let existingSession = activeSessions.managedSession(for: sessionID) else {
      throw ProviderAdapterError.sessionNotFound(sessionID)
    }
    _ = activeSessions.remove(sessionID: sessionID)
    existingSession.process.terminate()

    var args = config.command
    args += " -p --output-format stream-json --continue"
    if let permissionMode = config.permissionMode {
      args += " --permission-mode \(permissionMode)"
    }

    let process = try processLauncher.launch(
      command: args,
      workspacePath: existingSession.workspacePath,
      environment: existingSession.environment
    )
    try submitInput(guidance, to: process)
    activeSessions.store(
      sessionID: sessionID,
      process: process,
      workspacePath: existingSession.workspacePath,
      environment: existingSession.environment
    )
    return makeEventStream(from: process, sessionID: sessionID)
  }

  public func interruptSession(sessionID: SessionID) async throws -> Bool {
    false
  }

  public func cancelSession(sessionID: SessionID) async throws {
    guard let process = activeSessions.remove(sessionID: sessionID) else {
      throw ProviderAdapterError.sessionNotFound(sessionID)
    }
    process.terminate()
  }

  func makeEventStream(
    from process: LaunchedProcess,
    sessionID: SessionID
  ) -> AsyncThrowingStream<AgentRawEvent, Error> {
    let counter = SessionSequenceCounter()
    let activeSessions = self.activeSessions
    let finishState = StreamFinishState()
    return AsyncThrowingStream { continuation in
      process.onOutput { data in
        guard let output = String(data: data, encoding: .utf8) else { return }

        for line in protocolLines(from: output) {
          guard !finishState.isFinished else { return }

          let descriptor = ProviderEventInspection.describe(from: line, provider: .claudeCode)
          let event = AgentRawEvent(
            sessionID: sessionID,
            provider: "claude_code",
            sequence: counter.next(),
            timestamp: ISO8601DateFormatter().string(from: Date()),
            rawJSON: line,
            providerEventType: descriptor.eventType,
            normalizedEventKind: descriptor.normalizedKind.rawValue
          )
          continuation.yield(event)

          if descriptor.isTerminal {
            activeSessions.remove(sessionID: sessionID)
            finishState.finishIfNeeded {
              continuation.finish()
            }
            return
          }
        }
      }
      process.onTermination { exitCode in
        activeSessions.remove(sessionID: sessionID)
        finishState.finishIfNeeded {
          if exitCode == 0 {
            continuation.finish()
          } else {
            continuation.finish(
              throwing: ProviderAdapterError.processExitedUnexpectedly(exitCode: exitCode))
          }
        }
      }
    }
  }
}
