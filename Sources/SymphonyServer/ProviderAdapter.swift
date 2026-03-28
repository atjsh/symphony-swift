import Foundation
import SymphonyShared
import SymphonyServerCore

// MARK: - Provider Adapter Error

public enum ProviderAdapterError: Error, Equatable, Sendable {
  case processLaunchFailed(String)
  case sessionNotFound(SessionID)
  case processExitedUnexpectedly(exitCode: Int32)
  case terminalOutcome(sessionID: SessionID, outcome: String)
  case readTimeout(sessionID: SessionID, readTimeoutMS: Int)
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
    issue: Issue?,
    workspacePath: String,
    prompt: String,
    environment: [String: String]
  ) async throws -> AsyncThrowingStream<AgentRawEvent, Error>

  func continueSession(
    sessionID: SessionID,
    guidance: String
  ) async throws -> AsyncThrowingStream<AgentRawEvent, Error>

  func interruptSession(sessionID: SessionID) async throws -> Bool
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

private final class CodexSessionState: @unchecked Sendable {
  private let lock = NSLock()
  private let sequenceCounter = SessionSequenceCounter()
  private var _issueIdentifier: String?
  private var _issueTitle: String?
  private var _threadID: String?
  private var _turnID: String?
  private var nextRequestID = 4

  func recordIssueContext(identifier: String, title: String) {
    lock.withLock {
      _issueIdentifier = identifier
      _issueTitle = title
    }
  }

  var issueIdentifier: String? {
    lock.withLock { _issueIdentifier }
  }

  var issueTitle: String? {
    lock.withLock { _issueTitle }
  }

  var threadID: String? {
    lock.withLock { _threadID }
  }

  var turnID: String? {
    lock.withLock { _turnID }
  }

  func recordThreadID(_ threadID: String) {
    lock.withLock {
      _threadID = threadID
    }
  }

  func recordTurnID(_ turnID: String) {
    lock.withLock {
      _turnID = turnID
    }
  }

  func nextSequence() -> EventSequence {
    sequenceCounter.next()
  }

  func nextTurnRequestID() -> Int {
    lock.withLock {
      defer { nextRequestID += 1 }
      return nextRequestID
    }
  }
}

private final class CodexSessionRegistry: @unchecked Sendable {
  private let lock = NSLock()
  private var states: [SessionID: CodexSessionState] = [:]

  func state(for sessionID: SessionID) -> CodexSessionState {
    lock.withLock {
      if let existing = states[sessionID] {
        return existing
      }

      let state = CodexSessionState()
      states[sessionID] = state
      return state
    }
  }

  func threadID(for sessionID: SessionID) -> String? {
    lock.withLock { states[sessionID]?.threadID }
  }

  func turnID(for sessionID: SessionID) -> String? {
    lock.withLock { states[sessionID]?.turnID }
  }

  func remove(sessionID: SessionID) {
    _ = lock.withLock {
      states.removeValue(forKey: sessionID)
    }
  }
}

enum CodexTerminalOutcome: String, Sendable {
  case completed
  case failed
  case interrupted
}

private final class CodexTimeoutMonitor: @unchecked Sendable {
  private let lock = NSLock()
  private var readTimeoutTask: Task<Void, Never>?
  private var turnTimeoutTask: Task<Void, Never>?
  private var _terminalError: Error?

  func startReadTimeout(
    sessionID: SessionID,
    readTimeoutMS: Int,
    process: LaunchedProcess,
    finish: @escaping @Sendable (Error) -> Void
  ) {
    guard readTimeoutMS > 0 else { return }
    lock.withLock {
      readTimeoutTask?.cancel()
      readTimeoutTask = Task {
        do {
          try await Task.sleep(nanoseconds: UInt64(readTimeoutMS) * 1_000_000)
        } catch {
          return
        }
        guard !Task.isCancelled else { return }
        let timeoutError = ProviderAdapterError.readTimeout(
          sessionID: sessionID,
          readTimeoutMS: readTimeoutMS
        )
        finish(timeoutError)
        process.terminate()
      }
    }
  }

  func cancelReadTimeout() {
    lock.withLock {
      readTimeoutTask?.cancel()
      readTimeoutTask = nil
    }
  }

  func startTurnTimeout(
    sessionID: SessionID,
    turnTimeoutMS: Int,
    process: LaunchedProcess
  ) {
    guard turnTimeoutMS > 0 else { return }
    lock.withLock {
      turnTimeoutTask?.cancel()
      turnTimeoutTask = Task {
        do {
          try await Task.sleep(nanoseconds: UInt64(turnTimeoutMS) * 1_000_000)
        } catch {
          return
        }
        guard !Task.isCancelled else { return }
        lock.withLock {
          _terminalError = ProviderAdapterError.turnTimeout(
            sessionID: sessionID,
            turnTimeoutMS: turnTimeoutMS
          )
        }
        process.terminate()
      }
    }
  }

  func consumeTerminalError() -> Error? {
    lock.withLock {
      defer { _terminalError = nil }
      return _terminalError
    }
  }

  func cancelAll() {
    lock.withLock {
      readTimeoutTask?.cancel()
      readTimeoutTask = nil
      turnTimeoutTask?.cancel()
      turnTimeoutTask = nil
      _terminalError = nil
    }
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
    if codexApprovalLikeIdentifier(type) {
      return .approvalRequest
    }

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
    if isCodexApprovalEvent(method: method, json: json) {
      return .approvalRequest
    }

    switch method {
    case "turn/completed", "turn/failed", "turn/cancelled", "turn/interrupted", "initialized",
      "thread/start", "turn/start", "thread/started", "turn/started", "thread/status/changed":
      return .status
    case "thread/tokenUsage/updated":
      return .usage
    case "item/agentMessage/delta":
      return .message
    case "item/started", "item/completed":
      switch codexItemType(in: json) {
      case "agentMessage":
        return .message
      case "commandExecution":
        return method == "item/started" ? .toolCall : .toolResult
      default:
        return codexApprovalLikePayload(in: json) ? .approvalRequest : nil
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

  private static func isCodexApprovalEvent(method: String, json: [String: Any]) -> Bool {
    codexApprovalLikeIdentifier(method) || codexApprovalLikePayload(in: json)
  }

  private static func codexApprovalLikePayload(in json: [String: Any]) -> Bool {
    codexApprovalCandidateStrings(in: json).contains(where: codexApprovalLikeIdentifier)
  }

  private static func codexApprovalCandidateStrings(in json: [String: Any]) -> [String] {
    let paths = [
      ["type"],
      ["method"],
      ["params", "item", "type"],
      ["params", "item", "kind"],
      ["params", "request", "type"],
      ["params", "request", "kind"],
      ["params", "approval", "type"],
      ["params", "approval", "kind"],
      ["params", "permission", "type"],
      ["params", "permission", "kind"],
      ["params", "input", "type"],
      ["params", "input", "kind"],
      ["params", "tool", "type"],
      ["params", "tool", "kind"],
      ["params", "status", "type"],
      ["result", "item", "type"],
      ["result", "request", "type"],
      ["result", "request", "kind"],
    ]

    return paths.compactMap { stringValue(at: $0, in: json) }
  }

  private static func stringValue(at path: [String], in json: [String: Any]) -> String? {
    guard let first = path.first else { return nil }
    guard let value = json[first] else { return nil }
    if path.count == 1 {
      return value as? String
    }

    guard let nested = value as? [String: Any] else { return nil }
    return stringValue(at: Array(path.dropFirst()), in: nested)
  }

  private static func codexApprovalLikeIdentifier(_ identifier: String?) -> Bool {
    guard let identifier else { return false }
    let compact = identifier.lowercased().filter { $0.isLetter || $0.isNumber }
    guard !compact.isEmpty else { return false }

    if compact.contains("requestapproval") || compact.contains("approvalrequest") {
      return true
    }

    if compact.contains("filechange")
      && (compact.contains("approval") || compact.contains("request") || compact.contains("required"))
    {
      return true
    }

    if compact.contains("permission")
      && (compact.contains("approval") || compact.contains("request") || compact.contains("required"))
    {
      return true
    }

    if compact.contains("inputrequired") || compact.contains("userinputrequired")
      || compact.contains("requestinput")
    {
      return true
    }

    if compact.contains("unsupportedtool")
      || (compact.contains("unsupported") && compact.contains("tool"))
    {
      return true
    }

    return false
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
    if let method = json["method"] as? String,
      ["session/request_permission", "requestPermission"].contains(method)
    {
      return .approvalRequest
    }
    if let method = json["method"] as? String, ["session/update", "sessionUpdate"].contains(method)
    {
      return .status
    }
    if copilotPromptStopReason(from: json) != nil {
      return .status
    }
    if json["error"] != nil {
      return .error
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
      if json["error"] != nil {
        return "error"
      }
      if json["result"] != nil {
        return "result"
      }
      return json["method"] as? String ?? json["type"] as? String ?? json["event"] as? String
        ?? "unknown"
    }
  }

  private static func isTerminalEvent(_ json: [String: Any], provider: ProviderName) -> Bool {
    switch provider {
    case .codex:
      let method = json["method"] as? String
      return ["turn/completed", "turn/failed", "turn/cancelled", "turn/interrupted"].contains(method)
    case .claudeCode:
      let type = json["type"] as? String
      return ["result", "error"].contains(type)
    case .copilotCLI:
      return copilotPromptStopReason(from: json) != nil || json["error"] != nil
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
  private let issueIdentifier: String
  private let issueTitle: String
  private let workspacePath: String
  private let prompt: String
  private let config: CodexProviderConfig
  private var didSendTurnStart = false

  init(issue: Issue?, workspacePath: String, prompt: String, config: CodexProviderConfig) {
    self.issueIdentifier = issue?.identifier.rawValue ?? "unknown"
    self.issueTitle = issue?.title ?? "Untitled"
    self.workspacePath = workspacePath
    self.prompt = prompt
    self.config = config
  }

  func turnStartMessageIfNeeded(threadID: String) -> [String: Any]? {
    lock.withLock {
      guard !didSendTurnStart else { return nil }
      didSendTurnStart = true
      return makeCodexTurnStartMessage(
        id: 3,
        threadID: threadID,
        issueIdentifier: issueIdentifier,
        issueTitle: issueTitle,
        workspacePath: workspacePath,
        input: prompt,
        config: config
      )
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
    let jsonObject = protocolJSONObject(from: line)
    timeoutMonitor.cancelReadTimeout()
    if let threadID = codexStartupThreadID(from: jsonObject) {
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

    if let turnID = codexTurnID(from: jsonObject) {
      sessionState.recordTurnID(turnID)
    }

    if shouldSuppressSuccessfulCodexResponse(jsonObject) {
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
  func interrupt()
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

  func interrupt() {
    process.interrupt()
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
  private var _interruptCount = 0
  private var _terminationCount = 0
  private var _terminated = false

  public init() {}

  public var recordedInputStrings: [String] {
    lock.withLock {
      _recordedInputs.compactMap { String(data: $0, encoding: .utf8) }
    }
  }

  public var interruptCount: Int {
    lock.withLock { _interruptCount }
  }

  public var terminationCount: Int {
    lock.withLock { _terminationCount }
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
      if
        let string = String(data: data, encoding: .utf8)?
          .trimmingCharacters(in: .whitespacesAndNewlines),
        let messageData = string.data(using: .utf8),
        let json = try? JSONSerialization.jsonObject(with: messageData) as? [String: Any],
        json["method"] as? String == "turn/interrupt"
      {
        _interruptCount += 1
      }
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

  public func interrupt() {
    lock.lock()
    guard !_terminated else {
      lock.unlock()
      return
    }
    _interruptCount += 1
    lock.unlock()
  }

  public func terminate() {
    lock.lock()
    guard !_terminated else {
      lock.unlock()
      return
    }
    _terminated = true
    _terminationCount += 1
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
    _terminationCount += 1
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

private final class CodexOutputBuffer: @unchecked Sendable {
  private let lock = NSLock()
  private var remainder = ""

  func append(_ chunk: String) -> [String] {
    lock.withLock {
      remainder += chunk
      return drainCompleteLines()
    }
  }

  func finish() -> [String] {
    lock.withLock {
      defer { remainder = "" }
      let trimmed = remainder.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { return [] }
      return [trimmed]
    }
  }

  private func drainCompleteLines() -> [String] {
    var lines = [String]()
    while let newlineIndex = remainder.firstIndex(where: \.isNewline) {
      let line = String(remainder[..<newlineIndex]).trimmingCharacters(
        in: .whitespacesAndNewlines)
      remainder = newlineIndex < remainder.index(before: remainder.endIndex)
        ? String(remainder[remainder.index(after: newlineIndex)...])
        : ""
      if !line.isEmpty {
        lines.append(line)
      }
    }
    return lines
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

private func copilotProviderSessionID(from jsonObject: [String: Any]?) -> String? {
  guard let result = jsonObject?["result"] as? [String: Any] else { return nil }
  return result["sessionId"] as? String
}

private func copilotPromptStopReason(from jsonObject: [String: Any]?) -> String? {
  guard let result = jsonObject?["result"] as? [String: Any] else { return nil }
  return result["stopReason"] as? String
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

  if let params = jsonObject["params"] as? [String: Any],
    let threadID = params["thread_id"] as? String ?? params["threadId"] as? String,
    !threadID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  {
    return threadID
  }

  return nil
}

private func codexTurnID(from jsonObject: [String: Any]?) -> String? {
  guard let jsonObject else { return nil }

  if let params = jsonObject["params"] as? [String: Any] {
    if let turn = params["turn"] as? [String: Any],
      let turnID = turn["id"] as? String,
      !turnID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      return turnID
    }

    if let turnID = params["turn_id"] as? String ?? params["turnId"] as? String,
      !turnID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      return turnID
    }
  }

  if let result = jsonObject["result"] as? [String: Any],
    let turn = result["turn"] as? [String: Any],
    let turnID = turn["id"] as? String,
    !turnID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  {
    return turnID
  }

  return nil
}

private func shouldSuppressSuccessfulCodexResponse(_ jsonObject: [String: Any]?) -> Bool {
  guard let jsonObject else { return false }
  guard jsonObject["error"] == nil else { return false }
  guard jsonObject["id"] != nil, jsonObject["result"] != nil else { return false }
  return jsonObject["method"] == nil && jsonObject["type"] == nil
}

private func makeCodexTurnStartMessage(
  id: Int,
  threadID: String,
  issueIdentifier: String,
  issueTitle: String,
  workspacePath: String,
  input: String,
  config: CodexProviderConfig
) -> [String: Any] {
  var params: [String: Any] = [
    "threadId": threadID,
    "cwd": workspacePath,
    "title": "\(issueIdentifier): \(issueTitle)",
    "input": [["type": "text", "text": input]],
  ]
  if let approvalPolicy = config.turnApprovalPolicy {
    params["approvalPolicy"] = approvalPolicy
  }
  if let sandboxPolicy = config.turnSandboxPolicy {
    params["sandboxPolicy"] = sandboxPolicy.foundationValue
  }

  return [
    "id": id,
    "method": "turn/start",
    "params": params,
  ]
}

private func makeCodexInterruptMessage(
  id: Int,
  threadID: String,
  turnID: String
) -> [String: Any] {
  [
    "id": id,
    "method": "turn/interrupt",
    "params": [
      "threadId": threadID,
      "turnId": turnID,
    ],
  ]
}

func codexTurnOutcome(from rawJSON: String) -> CodexTerminalOutcome? {
  guard
    let data = rawJSON.data(using: .utf8),
    let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
  else { return nil }

  guard let method = json["method"] as? String else { return nil }
  switch method {
  case "turn/completed":
    switch firstCodexOutcomeString(in: json)?.lowercased() {
    case "failed", "error":
      return .failed
    case "cancelled", "canceled", "interrupted":
      return .interrupted
    default:
      return .completed
    }
  case "turn/failed":
    return .failed
  case "turn/cancelled":
    return .interrupted
  case "turn/interrupted":
    return .interrupted
  default:
    return nil
  }
}

private func firstCodexOutcomeString(in value: Any?) -> String? {
  if let string = value as? String {
    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  if let array = value as? [Any] {
    for entry in array {
      if let found = firstCodexOutcomeString(in: entry) {
        return found
      }
    }
    return nil
  }

  guard let json = value as? [String: Any] else { return nil }
  for key in ["status", "result", "outcome", "terminalStatus", "state", "type"] {
    if let found = firstCodexOutcomeString(in: json[key]) {
      return found
    }
  }
  for key in ["params", "turn", "terminal", "payload"] {
    if let found = firstCodexOutcomeString(in: json[key]) {
      return found
    }
  }
  return nil
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
