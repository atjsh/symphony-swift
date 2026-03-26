import Foundation
import SymphonyShared

// MARK: - Provider Adapter Error

public enum ProviderAdapterError: Error, Equatable, Sendable {
  case processLaunchFailed(String)
  case sessionNotFound(SessionID)
  case processExitedUnexpectedly(exitCode: Int32)
  case stallDetected(sessionID: SessionID, stallTimeoutMS: Int)
  case turnTimeout(sessionID: SessionID, turnTimeoutMS: Int)
  case unsupportedProvider(ProviderName)
}

// MARK: - Provider Adapter Protocol (Section 10.2)

public protocol ProviderAdapting: Sendable {
  var providerName: ProviderName { get }
  var capabilities: ProviderCapabilities { get }

  func startSession(
    sessionID: SessionID,
    workspacePath: String,
    prompt: String,
    environment: [String: String]
  ) async throws -> AsyncThrowingStream<AgentRawEvent, Error>

  func continueSession(
    sessionID: SessionID,
    guidance: String
  ) async throws -> AsyncThrowingStream<AgentRawEvent, Error>

  func cancelSession(sessionID: SessionID) async throws
}

// MARK: - Session Metadata (Section 10.4)

public struct ProviderSessionMetadata: Equatable, Sendable {
  public let sessionID: SessionID
  public let provider: ProviderName
  public let providerSessionID: String?
  public let providerThreadID: String?
  public let providerTurnID: String?
  public let providerRunID: String?

  public init(
    sessionID: SessionID,
    provider: ProviderName,
    providerSessionID: String? = nil,
    providerThreadID: String? = nil,
    providerTurnID: String? = nil,
    providerRunID: String? = nil
  ) {
    self.sessionID = sessionID
    self.provider = provider
    self.providerSessionID = providerSessionID
    self.providerThreadID = providerThreadID
    self.providerTurnID = providerTurnID
    self.providerRunID = providerRunID
  }
}

public struct ProviderManagedSession: Sendable {
  public let process: LaunchedProcess
  public let workspacePath: String
  public let environment: [String: String]

  public init(
    process: LaunchedProcess,
    workspacePath: String,
    environment: [String: String]
  ) {
    self.process = process
    self.workspacePath = workspacePath
    self.environment = environment
  }
}

// MARK: - Event Kind Inference

enum EventKindInference {
  static func infer(from rawJSON: String, provider: ProviderName) -> NormalizedEventKind {
    guard let data = rawJSON.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return .unknown }

    switch provider {
    case .codex:
      return inferCodex(json)
    case .claudeCode:
      return inferClaudeCode(json)
    case .copilotCLI:
      return inferCopilotCLI(json)
    }
  }

  private static func inferCodex(_ json: [String: Any]) -> NormalizedEventKind {
    if json["error"] != nil {
      return .error
    }

    if let method = json["method"] as? String {
      if let kind = inferCodex(method: method, json: json) {
        return kind
      }
    }

    guard let type = json["type"] as? String else { return .unknown }
    switch type {
    case "message", "text": return .message
    case "tool_call": return .toolCall
    case "tool_result": return .toolResult
    case "status": return .status
    case "usage": return .usage
    case "approval_request": return .approvalRequest
    case "error": return .error
    default: return .unknown
    }
  }

  static func inferCodex(method: String, json: [String: Any]) -> NormalizedEventKind? {
    switch method {
    case "turn/completed", "turn/failed", "turn/cancelled", "initialized", "thread/start",
      "turn/start", "thread/started", "turn/started", "thread/status/changed":
      return .status
    case "thread/tokenUsage/updated":
      return .usage
    case "item/commandExecution/requestApproval":
      return .approvalRequest
    case "item/agentMessage/delta":
      return .message
    case "item/started", "item/completed":
      switch codexItemType(in: json) {
      case "agentMessage":
        return .message
      case "commandExecution":
        return method == "item/started" ? .toolCall : .toolResult
      default:
        return nil
      }
    default:
      return nil
    }
  }

  private static func codexItemType(in json: [String: Any]) -> String? {
    let params = json["params"] as? [String: Any]
    let item = params?["item"] as? [String: Any]
    return item?["type"] as? String
  }

  private static func inferClaudeCode(_ json: [String: Any]) -> NormalizedEventKind {
    guard let type = json["type"] as? String else { return .unknown }
    switch type {
    case "assistant", "text", "message", "result": return .message
    case "tool_use": return .toolCall
    case "tool_result": return .toolResult
    case "system", "status": return .status
    case "usage": return .usage
    case "error": return .error
    default: return .unknown
    }
  }

  private static func inferCopilotCLI(_ json: [String: Any]) -> NormalizedEventKind {
    if let method = json["method"] as? String, method == "session/update" {
      return .status
    }

    guard let type = json["type"] as? String ?? json["event"] as? String else { return .unknown }
    switch type {
    case "message", "update", "text": return .message
    case "tool_call": return .toolCall
    case "tool_result": return .toolResult
    case "status": return .status
    case "usage": return .usage
    case "error": return .error
    default: return .unknown
    }
  }
}

struct ProviderEventDescriptor {
  let eventType: String
  let normalizedKind: NormalizedEventKind
  let isTerminal: Bool
}

enum ProviderEventInspection {
  static func describe(from rawJSON: String, provider: ProviderName) -> ProviderEventDescriptor {
    guard let data = rawJSON.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return ProviderEventDescriptor(
        eventType: "unknown",
        normalizedKind: .unknown,
        isTerminal: false
      )
    }

    let eventType = eventType(from: json, provider: provider)
    let normalizedKind = EventKindInference.infer(from: rawJSON, provider: provider)
    let isTerminal = isTerminalEvent(json, provider: provider)
    return ProviderEventDescriptor(
      eventType: eventType,
      normalizedKind: normalizedKind,
      isTerminal: isTerminal
    )
  }

  static func eventType(from json: [String: Any], provider: ProviderName) -> String {
    switch provider {
    case .codex:
      if json["error"] != nil {
        return "error"
      }
      return json["method"] as? String ?? json["type"] as? String ?? "unknown"
    case .claudeCode:
      return json["type"] as? String ?? "unknown"
    case .copilotCLI:
      return json["method"] as? String ?? json["type"] as? String ?? json["event"] as? String
        ?? "unknown"
    }
  }

  private static func isTerminalEvent(_ json: [String: Any], provider: ProviderName) -> Bool {
    switch provider {
    case .codex:
      let method = json["method"] as? String
      return ["turn/completed", "turn/failed", "turn/cancelled"].contains(method)
    case .claudeCode:
      let type = json["type"] as? String
      return ["result", "error"].contains(type)
    case .copilotCLI:
      if let method = json["method"] as? String,
        method == "session/update",
        let params = json["params"] as? [String: Any],
        let status = params["status"] as? String
      {
        return ["completed", "cancelled", "failed", "timed_out", "timeout"].contains(status)
      }
      return false
    }
  }
}

private final class StreamFinishState: @unchecked Sendable {
  private let lock = NSLock()
  private var _finished = false

  var isFinished: Bool {
    lock.withLock { _finished }
  }

  func finishIfNeeded(_ action: () -> Void) {
    let shouldFinish = lock.withLock {
      guard !_finished else { return false }
      _finished = true
      return true
    }

    if shouldFinish {
      action()
    }
  }
}

// MARK: - Session Sequence Counter

final class SessionSequenceCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var _value: Int = 0

  func next() -> EventSequence {
    lock.lock()
    let current = _value
    _value += 1
    lock.unlock()
    return EventSequence(current)
  }
}

// MARK: - Session Store

public final class SessionStore: @unchecked Sendable {
  private let lock = NSLock()
  private var _sessions: [SessionID: ProviderManagedSession] = [:]

  public init() {}

  public func store(
    sessionID: SessionID,
    process: LaunchedProcess,
    workspacePath: String = "",
    environment: [String: String] = [:]
  ) {
    let session = ProviderManagedSession(
      process: process,
      workspacePath: workspacePath,
      environment: environment
    )
    lock.withLock { _sessions[sessionID] = session }
  }

  @discardableResult
  public func remove(sessionID: SessionID) -> LaunchedProcess? {
    lock.withLock { _sessions.removeValue(forKey: sessionID)?.process }
  }

  public func process(for sessionID: SessionID) -> LaunchedProcess? {
    lock.withLock { _sessions[sessionID]?.process }
  }

  public func managedSession(for sessionID: SessionID) -> ProviderManagedSession? {
    lock.withLock { _sessions[sessionID] }
  }

  public var count: Int {
    lock.withLock { _sessions.count }
  }
}

// MARK: - Codex Adapter (Section 10.7)

private final class CodexStartupState: @unchecked Sendable {
  private let lock = NSLock()
  private let workspacePath: String
  private let prompt: String
  private let config: CodexProviderConfig
  private var didSendTurnStart = false

  init(workspacePath: String, prompt: String, config: CodexProviderConfig) {
    self.workspacePath = workspacePath
    self.prompt = prompt
    self.config = config
  }

  func turnStartMessageIfNeeded(threadID: String) -> [String: Any]? {
    lock.withLock {
      guard !didSendTurnStart else { return nil }
      didSendTurnStart = true

      var params: [String: Any] = [
        "threadId": threadID,
        "cwd": workspacePath,
        "input": [["type": "text", "text": prompt]],
      ]
      if let approvalPolicy = config.approvalPolicy {
        params["approvalPolicy"] = approvalPolicy
      }
      if let sandboxPolicy = config.turnSandboxPolicy {
        params["sandboxPolicy"] = sandboxPolicy
      }

      return [
        "id": 3,
        "method": "turn/start",
        "params": params,
      ]
    }
  }
}

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

  public init(config: CodexProviderConfig, processLauncher: ProcessLaunching? = nil) {
    self.config = config
    self.processLauncher = processLauncher ?? DefaultProcessLauncher()
  }

  public func startSession(
    sessionID: SessionID,
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
      workspacePath: workspacePath,
      prompt: prompt,
      config: config
    )
    activeSessions.store(
      sessionID: sessionID,
      process: process,
      workspacePath: workspacePath,
      environment: environment
    )
    let stream = makeEventStream(
      from: process,
      sessionID: sessionID,
      startupState: startupState
    )

    do {
      try submitJSONMessages(startupMessages(workspacePath: workspacePath), to: process)
    } catch {
      activeSessions.remove(sessionID: sessionID)
      process.terminate()
      throw error
    }

    return stream
  }

  public func continueSession(
    sessionID: SessionID,
    guidance: String
  ) async throws -> AsyncThrowingStream<AgentRawEvent, Error> {
    throw ProviderAdapterError.unsupportedProvider(.codex)
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
    makeEventStream(from: process, sessionID: sessionID, startupState: nil)
  }

  private func makeEventStream(
    from process: LaunchedProcess,
    sessionID: SessionID,
    startupState: CodexStartupState?
  ) -> AsyncThrowingStream<AgentRawEvent, Error> {
    let counter = SessionSequenceCounter()
    let activeSessions = self.activeSessions
    let finishState = StreamFinishState()
    return AsyncThrowingStream { continuation in
      process.onOutput { data in
        guard let output = String(data: data, encoding: .utf8) else { return }

        for line in protocolLines(from: output) {
          guard !finishState.isFinished else { return }

          let jsonObject = protocolJSONObject(from: line)
          if let startupState,
            let threadID = codexStartupThreadID(from: jsonObject),
            let turnStartMessage = startupState.turnStartMessageIfNeeded(threadID: threadID)
          {
            do {
              try submitJSONMessages([turnStartMessage], to: process)
            } catch {
              activeSessions.remove(sessionID: sessionID)
              finishState.finishIfNeeded {
                continuation.finish(throwing: error)
              }
              return
            }
          }

          if shouldSuppressSuccessfulCodexResponse(jsonObject) {
            continue
          }

          let descriptor = ProviderEventInspection.describe(from: line, provider: .codex)
          let event = AgentRawEvent(
            sessionID: sessionID,
            provider: "codex",
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

  private func startupMessages(workspacePath: String) -> [[String: Any]] {
    var threadStartParams: [String: Any] = [
      "cwd": workspacePath,
      "ephemeral": true,
    ]
    if let approvalPolicy = config.approvalPolicy {
      threadStartParams["approvalPolicy"] = approvalPolicy
    }
    if let sandbox = config.threadSandbox {
      threadStartParams["sandbox"] = sandbox
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

// MARK: - Copilot CLI Adapter (Section 10.9)

public final class CopilotCLIAdapter: ProviderAdapting, @unchecked Sendable {
  public let providerName: ProviderName = .copilotCLI
  public let capabilities = ProviderCapabilities(
    supportsResume: false,
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

  public init(config: CopilotCLIProviderConfig, processLauncher: ProcessLaunching? = nil) {
    self.config = config
    self.processLauncher = processLauncher ?? DefaultProcessLauncher()
  }

  public func startSession(
    sessionID: SessionID,
    workspacePath: String,
    prompt: String,
    environment: [String: String]
  ) async throws -> AsyncThrowingStream<AgentRawEvent, Error> {
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
            "client": "symphony",
            "protocol": "acp",
          ],
        ],
        [
          "id": 2,
          "method": "session/start",
          "params": [
            "session_id": sessionID.rawValue
          ],
        ],
        [
          "id": 3,
          "method": "session/prompt",
          "params": [
            "session_id": sessionID.rawValue,
            "prompt": prompt,
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
    return makeEventStream(from: process, sessionID: sessionID)
  }

  public func continueSession(
    sessionID: SessionID,
    guidance: String
  ) async throws -> AsyncThrowingStream<AgentRawEvent, Error> {
    throw ProviderAdapterError.unsupportedProvider(.copilotCLI)
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

// MARK: - Process Launching Abstraction

public protocol ProcessLaunching: Sendable {
  func launch(
    command: String,
    workspacePath: String,
    environment: [String: String]
  ) throws -> LaunchedProcess
}

// MARK: - Launched Process

public protocol LaunchedProcess: Sendable {
  func onOutput(_ handler: @escaping @Sendable (Data) -> Void)
  func onTermination(_ handler: @escaping @Sendable (Int32) -> Void)
  func sendInput(_ data: Data) throws
  func terminate()
}

// MARK: - Default Process Launcher

public final class DefaultProcessLauncher: ProcessLaunching, Sendable {
  public init() {}

  public func launch(
    command: String,
    workspacePath: String,
    environment: [String: String]
  ) throws -> LaunchedProcess {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = ["-lc", command]
    process.currentDirectoryURL = URL(fileURLWithPath: workspacePath)

    var env = ProcessInfo.processInfo.environment
    for (key, value) in environment {
      env[key] = value
    }
    process.environment = env

    let stdout = Pipe()
    let stdin = Pipe()
    process.standardOutput = stdout
    process.standardInput = stdin
    process.standardError = FileHandle.nullDevice

    do {
      try process.run()
    } catch {
      throw ProviderAdapterError.processLaunchFailed(error.localizedDescription)
    }

    return DefaultLaunchedProcess(process: process, stdoutPipe: stdout, stdinPipe: stdin)
  }
}

// MARK: - Default Launched Process

final class DefaultLaunchedProcess: LaunchedProcess, @unchecked Sendable {
  private let process: Process
  private let stdoutPipe: Pipe
  private let stdinPipe: Pipe

  init(process: Process, stdoutPipe: Pipe, stdinPipe: Pipe) {
    self.process = process
    self.stdoutPipe = stdoutPipe
    self.stdinPipe = stdinPipe
  }

  func onOutput(_ handler: @escaping @Sendable (Data) -> Void) {
    stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
      let data = handle.availableData
      if data.isEmpty {
        handle.readabilityHandler = nil
      } else {
        handler(data)
      }
    }
  }

  func onTermination(_ handler: @escaping @Sendable (Int32) -> Void) {
    process.terminationHandler = { proc in
      handler(proc.terminationStatus)
    }
  }

  func sendInput(_ data: Data) throws {
    try stdinPipe.fileHandleForWriting.write(contentsOf: data)
  }

  func terminate() {
    process.terminate()
  }
}

// MARK: - Stub Process Launcher (for testing)

public final class StubProcessLauncher: ProcessLaunching, @unchecked Sendable {
  private let lock = NSLock()
  private var _invocations:
    [(command: String, workspacePath: String, environment: [String: String])] = []
  private var _stubProcesses: [StubLaunchedProcess] = []
  private var _launchError: Error?

  public init() {}

  public var invocations: [(command: String, workspacePath: String, environment: [String: String])]
  {
    lock.lock()
    defer { lock.unlock() }
    return _invocations
  }

  public func setStubProcess(_ process: StubLaunchedProcess) {
    lock.lock()
    _stubProcesses = [process]
    lock.unlock()
  }

  public func setStubProcesses(_ processes: [StubLaunchedProcess]) {
    lock.lock()
    _stubProcesses = processes
    lock.unlock()
  }

  public func setLaunchError(_ error: Error) {
    lock.lock()
    _launchError = error
    lock.unlock()
  }

  public func launch(
    command: String,
    workspacePath: String,
    environment: [String: String]
  ) throws -> LaunchedProcess {
    lock.lock()
    _invocations.append(
      (
        command: command,
        workspacePath: workspacePath,
        environment: environment
      ))
    let error = _launchError
    let process = _stubProcesses.isEmpty ? StubLaunchedProcess() : _stubProcesses.removeFirst()
    lock.unlock()

    if let error { throw error }
    return process
  }
}

public final class StubLaunchedProcess: LaunchedProcess, @unchecked Sendable {
  private let lock = NSLock()
  private var _outputHandler: (@Sendable (Data) -> Void)?
  private var _terminationHandler: (@Sendable (Int32) -> Void)?
  private var _recordedInputs: [Data] = []
  private var _inputError: Error?
  private var _terminated = false

  public init() {}

  public var recordedInputStrings: [String] {
    lock.withLock {
      _recordedInputs.compactMap { String(data: $0, encoding: .utf8) }
    }
  }

  public func onOutput(_ handler: @escaping @Sendable (Data) -> Void) {
    lock.lock()
    _outputHandler = handler
    lock.unlock()
  }

  public func onTermination(_ handler: @escaping @Sendable (Int32) -> Void) {
    lock.lock()
    _terminationHandler = handler
    lock.unlock()
  }

  public func sendInput(_ data: Data) throws {
    lock.lock()
    let inputError = _inputError
    if inputError == nil {
      _recordedInputs.append(data)
    }
    lock.unlock()
    if let inputError {
      throw inputError
    }
  }

  public func setInputError(_ error: Error?) {
    lock.lock()
    _inputError = error
    lock.unlock()
  }

  public func terminate() {
    lock.lock()
    guard !_terminated else {
      lock.unlock()
      return
    }
    _terminated = true
    let handler = _terminationHandler
    lock.unlock()
    handler?(15)
  }

  public func simulateOutput(_ string: String) {
    lock.lock()
    let handler = _outputHandler
    lock.unlock()
    if let data = string.data(using: .utf8) {
      handler?(data)
    }
  }

  public func simulateTermination(exitCode: Int32) {
    lock.lock()
    guard !_terminated else {
      lock.unlock()
      return
    }
    _terminated = true
    let handler = _terminationHandler
    lock.unlock()
    handler?(exitCode)
  }
}

private func submitInput(_ input: String, to process: LaunchedProcess) throws {
  guard !input.isEmpty else { return }
  do {
    try process.sendInput(Data(input.utf8))
  } catch {
    throw ProviderAdapterError.processLaunchFailed(error.localizedDescription)
  }
}

private func submitJSONMessages(_ messages: [[String: Any]], to process: LaunchedProcess) throws {
  do {
    for message in messages {
      let data = try JSONSerialization.data(withJSONObject: message)
      try process.sendInput(data + Data("\n".utf8))
    }
  } catch {
    throw ProviderAdapterError.processLaunchFailed(error.localizedDescription)
  }
}

private func protocolLines(from output: String) -> [String] {
  output
    .split(whereSeparator: \.isNewline)
    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
    .filter { !$0.isEmpty }
}

private func protocolJSONObject(from line: String) -> [String: Any]? {
  guard let data = line.data(using: .utf8) else { return nil }
  return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
}

private func codexStartupThreadID(from jsonObject: [String: Any]?) -> String? {
  guard let jsonObject else { return nil }

  if let method = jsonObject["method"] as? String,
    method == "thread/started",
    let params = jsonObject["params"] as? [String: Any],
    let thread = params["thread"] as? [String: Any],
    let threadID = thread["id"] as? String,
    !threadID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  {
    return threadID
  }

  if let result = jsonObject["result"] as? [String: Any],
    let thread = result["thread"] as? [String: Any],
    let threadID = thread["id"] as? String,
    !threadID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  {
    return threadID
  }

  return nil
}

private func shouldSuppressSuccessfulCodexResponse(_ jsonObject: [String: Any]?) -> Bool {
  guard let jsonObject else { return false }
  guard jsonObject["error"] == nil else { return false }
  guard jsonObject["id"] != nil, jsonObject["result"] != nil else { return false }
  return jsonObject["method"] == nil && jsonObject["type"] == nil
}

// MARK: - Provider Adapter Factory

public enum ProviderAdapterFactory {
  public static func makeAdapter(
    for provider: ProviderName,
    config: ProvidersConfig,
    processLauncher: ProcessLaunching? = nil
  ) -> any ProviderAdapting {
    switch provider {
    case .codex:
      return CodexAdapter(config: config.codex, processLauncher: processLauncher)
    case .claudeCode:
      return ClaudeCodeAdapter(config: config.claudeCode, processLauncher: processLauncher)
    case .copilotCLI:
      return CopilotCLIAdapter(config: config.copilotCLI, processLauncher: processLauncher)
    }
  }
}
