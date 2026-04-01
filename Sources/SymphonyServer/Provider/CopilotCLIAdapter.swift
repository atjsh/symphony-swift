import Foundation
import SymphonyShared
import SymphonyServerCore

// MARK: - Copilot Session State

private final class CopilotSessionState: @unchecked Sendable {
  private let lock = NSLock()
  private let startupPrompt: String
  private var _providerSessionID: String?
  private var didSendStartupPrompt = false
  private var nextRequestID = 3

  init(startupPrompt: String) {
    self.startupPrompt = startupPrompt
  }

  func recordProviderSessionID(_ providerSessionID: String) {
    lock.withLock {
      _providerSessionID = providerSessionID
    }
  }

  func startupPromptMessageIfNeeded() -> [String: Any]? {
    lock.withLock {
      guard !didSendStartupPrompt, let providerSessionID = _providerSessionID else { return nil }
      didSendStartupPrompt = true
      let requestID = nextRequestID
      nextRequestID += 1
      return makeCopilotPromptMessage(
        id: requestID,
        providerSessionID: providerSessionID,
        prompt: startupPrompt
      )
    }
  }

  func continuationPromptMessage(guidance: String) -> [String: Any]? {
    lock.withLock {
      guard let providerSessionID = _providerSessionID else { return nil }
      let requestID = nextRequestID
      nextRequestID += 1
      return makeCopilotPromptMessage(
        id: requestID,
        providerSessionID: providerSessionID,
        prompt: guidance
      )
    }
  }
}

// MARK: - Copilot Session Registry

private final class CopilotSessionRegistry: @unchecked Sendable {
  private let lock = NSLock()
  private var states: [SessionID: CopilotSessionState] = [:]

  func store(_ state: CopilotSessionState, for sessionID: SessionID) {
    lock.withLock {
      states[sessionID] = state
    }
  }

  func state(for sessionID: SessionID) -> CopilotSessionState? {
    lock.withLock {
      states[sessionID]
    }
  }

  func remove(sessionID: SessionID) {
    lock.withLock {
      states.removeValue(forKey: sessionID)
    }
  }
}

// MARK: - Copilot CLI Adapter (Section 10.9)

public final class CopilotCLIAdapter: ProviderAdapting, @unchecked Sendable {
  public let providerName: ProviderName = .copilotCLI
  public let capabilities = ProviderCapabilities(
    supportsResume: true,
    supportsInterrupt: false,
    supportsUsageTotals: false,
    supportsRateLimits: false,
    supportsExplicitApprovals: false,
    supportsStructuredToolEvents: false,
    toolExecutionMode: .providerManaged
  )

  private let config: CopilotCLIProviderConfig
  private let processLauncher: ProcessLaunching
  private let activeSessions = SessionStore()
  private let sessionRegistry = CopilotSessionRegistry()

  public init(config: CopilotCLIProviderConfig, processLauncher: ProcessLaunching? = nil) {
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
    let sessionState = CopilotSessionState(startupPrompt: prompt)
    let process = try processLauncher.launch(
      command: config.command,
      workspacePath: workspacePath,
      environment: environment
    )
    try submitJSONMessages(
      [
        [
          "id": 1,
          "method": "initialize",
          "params": [
            "clientCapabilities": [:],
            "clientInfo": [
              "name": "symphony",
              "version": "0.0.1",
            ],
            "protocolVersion": 1,
          ],
        ],
        [
          "id": 2,
          "method": "newSession",
          "params": [
            "cwd": workspacePath,
            "mcpServers": [],
          ],
        ],
      ],
      to: process
    )
    activeSessions.store(
      sessionID: sessionID,
      process: process,
      workspacePath: workspacePath,
      environment: environment
    )
    sessionRegistry.store(sessionState, for: sessionID)
    return makeEventStream(from: process, sessionID: sessionID, sessionState: sessionState)
  }

  public func continueSession(
    sessionID: SessionID,
    guidance: String
  ) async throws -> AsyncThrowingStream<AgentRawEvent, Error> {
    guard let managedSession = activeSessions.managedSession(for: sessionID),
      let sessionState = sessionRegistry.state(for: sessionID),
      let promptMessage = sessionState.continuationPromptMessage(guidance: guidance)
    else {
      throw ProviderAdapterError.sessionNotFound(sessionID)
    }
    try submitJSONMessages(
      [promptMessage],
      to: managedSession.process
    )
    return makeEventStream(
      from: managedSession.process,
      sessionID: sessionID,
      sessionState: sessionState
    )
  }

  public func interruptSession(sessionID: SessionID) async throws -> Bool {
    false
  }

  public func cancelSession(sessionID: SessionID) async throws {
    guard let process = activeSessions.remove(sessionID: sessionID) else {
      throw ProviderAdapterError.sessionNotFound(sessionID)
    }
    sessionRegistry.remove(sessionID: sessionID)
    process.terminate()
  }

  func makeEventStream(
    from process: LaunchedProcess,
    sessionID: SessionID
  ) -> AsyncThrowingStream<AgentRawEvent, Error> {
    makeEventStream(
      from: process,
      sessionID: sessionID,
      sessionState: CopilotSessionState(startupPrompt: "")
    )
  }

  private func makeEventStream(
    from process: LaunchedProcess,
    sessionID: SessionID,
    sessionState: CopilotSessionState
  ) -> AsyncThrowingStream<AgentRawEvent, Error> {
    let counter = SessionSequenceCounter()
    let activeSessions = self.activeSessions
    let sessionRegistry = self.sessionRegistry
    let finishState = StreamFinishState()
    return AsyncThrowingStream { continuation in
      process.onOutput { data in
        guard let output = String(data: data, encoding: .utf8) else { return }

        for line in protocolLines(from: output) {
          guard !finishState.isFinished else { return }

          let jsonObject = protocolJSONObject(from: line)
          if let json = jsonObject {
            do {
              try handleCopilotProtocolMessage(json, process: process, sessionState: sessionState)
            } catch {
              finishState.finishIfNeeded {
                continuation.finish(throwing: error)
              }
              return
            }
          }

          let descriptor = ProviderEventInspection.describe(from: line, provider: .copilotCLI)
          let event = AgentRawEvent(
            sessionID: sessionID,
            provider: "copilot_cli",
            sequence: counter.next(),
            timestamp: ISO8601DateFormatter().string(from: Date()),
            rawJSON: line,
            providerEventType: descriptor.eventType,
            normalizedEventKind: descriptor.normalizedKind.rawValue
          )
          continuation.yield(event)

          if descriptor.isTerminal {
            finishState.finishIfNeeded {
              if let stopReason = copilotPromptStopReason(from: jsonObject) {
                if stopReason == "end_turn" {
                  continuation.finish()
                } else {
                  continuation.finish(
                    throwing: ProviderAdapterError.terminalOutcome(
                      sessionID: sessionID,
                      outcome: stopReason
                    ))
                }
              } else {
                continuation.finish(
                  throwing: ProviderAdapterError.terminalOutcome(
                    sessionID: sessionID,
                    outcome: "error"
                  ))
              }
            }
            return
          }
        }
      }
      process.onTermination { exitCode in
        activeSessions.remove(sessionID: sessionID)
        sessionRegistry.remove(sessionID: sessionID)
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

// MARK: - Copilot Protocol Helpers

private func handleCopilotProtocolMessage(
  _ json: [String: Any],
  process: LaunchedProcess,
  sessionState: CopilotSessionState
) throws {
  if let providerSessionID = copilotProviderSessionID(from: json) {
    sessionState.recordProviderSessionID(providerSessionID)
    if let startupPrompt = sessionState.startupPromptMessageIfNeeded() {
      try submitJSONMessages([startupPrompt], to: process)
    }
  }

  guard let method = json["method"] as? String,
    ["session/request_permission", "requestPermission"].contains(method),
    let id = json["id"] as? Int,
    let response = copilotPermissionResponse(for: json, requestID: id)
  else {
    return
  }
  try submitJSONMessages([response], to: process)
}

private func copilotPermissionResponse(
  for jsonObject: [String: Any],
  requestID: Int
) -> [String: Any]? {
  let params = jsonObject["params"] as? [String: Any]
  let options = params?["options"] as? [Any]
  let optionID = options?
    .compactMap { $0 as? [String: Any] }
    .compactMap { $0["optionId"] as? String }
    .first

  let outcome: [String: Any]
  if let optionID {
    outcome = [
      "outcome": "selected",
      "optionId": optionID,
    ]
  } else {
    outcome = [
      "outcome": "cancelled"
    ]
  }

  return [
    "id": requestID,
    "result": [
      "outcome": outcome
    ],
  ]
}

private func makeCopilotPromptMessage(
  id: Int,
  providerSessionID: String,
  prompt: String
) -> [String: Any] {
  [
    "id": id,
    "method": "prompt",
    "params": [
      "sessionId": providerSessionID,
      "prompt": [
        [
          "type": "text",
          "text": prompt,
        ]
      ],
    ],
  ]
}
