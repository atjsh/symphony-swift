import Foundation
import SymphonyServerCore
import SymphonyShared

private struct ProviderSessionSnapshot: Sendable {
  var providerSessionID: String?
  var providerThreadID: String?
  var providerTurnID: String?
  var providerRunID: String?
  var tokenUsage: TokenUsage
  var latestRateLimitPayload: String?
  var lastAgentMessage: String?
  var latestSequence: EventSequence?

  init(
    providerSessionID: String? = nil,
    providerThreadID: String? = nil,
    providerTurnID: String? = nil,
    providerRunID: String? = nil,
    tokenUsage: TokenUsage = try! TokenUsage(),
    latestRateLimitPayload: String? = nil,
    lastAgentMessage: String? = nil,
    latestSequence: EventSequence? = nil
  ) {
    self.providerSessionID = providerSessionID
    self.providerThreadID = providerThreadID
    self.providerTurnID = providerTurnID
    self.providerRunID = providerRunID
    self.tokenUsage = tokenUsage
    self.latestRateLimitPayload = latestRateLimitPayload
    self.lastAgentMessage = lastAgentMessage
    self.latestSequence = latestSequence
  }

  func merging(_ update: ProviderSessionSnapshotUpdate) -> ProviderSessionSnapshot {
    ProviderSessionSnapshot(
      providerSessionID: update.providerSessionID ?? providerSessionID,
      providerThreadID: update.providerThreadID ?? providerThreadID,
      providerTurnID: update.providerTurnID ?? providerTurnID,
      providerRunID: update.providerRunID ?? providerRunID,
      tokenUsage: update.tokenUsage ?? tokenUsage,
      latestRateLimitPayload: update.latestRateLimitPayload ?? latestRateLimitPayload,
      lastAgentMessage: update.lastAgentMessage ?? lastAgentMessage,
      latestSequence: update.latestSequence ?? latestSequence
    )
  }
}

private struct ProviderSessionSnapshotUpdate: Sendable {
  var providerSessionID: String?
  var providerThreadID: String?
  var providerTurnID: String?
  var providerRunID: String?
  var tokenUsage: TokenUsage?
  var latestRateLimitPayload: String?
  var lastAgentMessage: String?
  var latestSequence: EventSequence?
}

private enum ProviderSessionSnapshotExtractor {
  static func update(from event: AgentRawEvent, storedSequence: EventSequence)
    -> ProviderSessionSnapshotUpdate
  {
    let rawJSONObject = parseJSONObject(from: event.rawJSON)
    return ProviderSessionSnapshotUpdate(
      providerSessionID: rawJSONObject.flatMap {
        firstString(for: ["provider_session_id", "session_id", "sessionId"], in: $0)
      },
      providerThreadID: rawJSONObject.flatMap {
        nestedObjectID(for: "thread", in: $0)
          ?? firstString(for: ["provider_thread_id", "thread_id", "threadId"], in: $0)
      },
      providerTurnID: rawJSONObject.flatMap {
        nestedObjectID(for: "turn", in: $0)
          ?? firstString(for: ["provider_turn_id", "turn_id", "turnId"], in: $0)
      },
      providerRunID: rawJSONObject.flatMap {
        firstString(for: ["provider_run_id", "run_id", "runId"], in: $0)
      },
      tokenUsage: rawJSONObject.flatMap(tokenUsage(from:)),
      latestRateLimitPayload: rawJSONObject.flatMap(rateLimitPayload(from:)),
      lastAgentMessage: lastAgentMessage(from: event, rawJSONObject: rawJSONObject),
      latestSequence: storedSequence
    )
  }

  private static func parseJSONObject(from rawJSON: String) -> Any? {
    guard let data = rawJSON.data(using: .utf8) else { return nil }
    return try? JSONSerialization.jsonObject(with: data)
  }

  fileprivate static func tokenUsage(from rawJSONObject: Any) -> TokenUsage? {
    if let usageObject = firstValue(
      for: ["usage", "token_usage", "tokenUsage", "tokens", "tokenUsageTotals"],
      in: rawJSONObject
    ),
      let usage = tokenUsageObject(from: usageObject)
    {
      return usage
    }

    return tokenUsageObject(from: rawJSONObject)
  }

  private static func tokenUsageObject(from rawJSONObject: Any) -> TokenUsage? {
    guard let json = rawJSONObject as? [String: Any] else { return nil }
    let inputTokens = firstInt(for: ["input_tokens", "inputTokens"], in: json)
    let outputTokens = firstInt(for: ["output_tokens", "outputTokens"], in: json)
    let totalTokens = firstInt(for: ["total_tokens", "totalTokens"], in: json)
    guard inputTokens != nil || outputTokens != nil || totalTokens != nil else { return nil }
    return try? TokenUsage(
      inputTokens: inputTokens,
      outputTokens: outputTokens,
      totalTokens: totalTokens
    )
  }

  private static func rateLimitPayload(from rawJSONObject: Any) -> String? {
    guard
      let rateLimitObject = firstValue(
        for: ["rate_limit", "rate_limits", "rateLimit", "rateLimits"],
        in: rawJSONObject
      )
    else { return nil }
    return jsonString(from: rateLimitObject)
  }

  private static func lastAgentMessage(from event: AgentRawEvent, rawJSONObject: Any?) -> String? {
    guard event.normalizedKind == .message, let rawJSONObject else { return nil }
    return messageText(from: rawJSONObject)
  }

  fileprivate static func messageText(from rawJSONObject: Any) -> String? {
    if let string = rawJSONObject as? String {
      let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? nil : trimmed
    }

    if let array = rawJSONObject as? [Any] {
      for item in array {
        if let text = messageText(from: item) {
          return text
        }
      }
      return nil
    }

    guard let json = rawJSONObject as? [String: Any] else { return nil }

    for key in ["message", "content", "text"] {
      if let value = json[key], let text = messageText(from: value) {
        return text
      }
    }

    for key in ["payload", "data", "delta"] {
      if let value = json[key], let text = messageText(from: value) {
        return text
      }
    }

    return nil
  }

  private static func firstString(for keys: [String], in rawJSONObject: Any) -> String? {
    if let array = rawJSONObject as? [Any] {
      for item in array {
        if let string = firstString(for: keys, in: item) {
          return string
        }
      }
      return nil
    }

    guard let json = rawJSONObject as? [String: Any] else { return nil }
    guard !keys.isEmpty else { return nil }
    for key in keys {
      if let value = json[key] {
        if let string = stringValue(from: value) {
          return string
        }
        if let string = firstString(for: keys, in: value) {
          return string
        }
      }
    }

    for value in json.values {
      if let string = firstString(for: keys, in: value) {
        return string
      }
    }

    return nil
  }

  private static func firstValue(for keys: [String], in rawJSONObject: Any) -> Any? {
    if let array = rawJSONObject as? [Any] {
      for item in array {
        if let value = firstValue(for: keys, in: item) {
          return value
        }
      }
      return nil
    }

    guard let json = rawJSONObject as? [String: Any] else { return nil }
    for key in keys {
      if let value = json[key] {
        return value
      }
    }

    for value in json.values {
      if let nestedValue = firstValue(for: keys, in: value) {
        return nestedValue
      }
    }

    return nil
  }

  private static func nestedObjectID(for objectKey: String, in rawJSONObject: Any) -> String? {
    if let array = rawJSONObject as? [Any] {
      for item in array {
        if let identifier = nestedObjectID(for: objectKey, in: item) {
          return identifier
        }
      }
      return nil
    }

    guard let json = rawJSONObject as? [String: Any] else { return nil }
    if let nested = json[objectKey] as? [String: Any],
      let idValue = nested["id"],
      let identifier = stringValue(from: idValue)
    {
      return identifier
    }

    for value in json.values {
      if let identifier = nestedObjectID(for: objectKey, in: value) {
        return identifier
      }
    }

    return nil
  }

  private static func firstInt(for keys: [String], in json: [String: Any]) -> Int? {
    for key in keys {
      if let value = json[key], let intValue = intValue(from: value) {
        return intValue
      }
    }
    return nil
  }

  private static func intValue(from value: Any) -> Int? {
    if let intValue = value as? Int {
      return intValue
    }
    if let number = value as? NSNumber {
      return number.intValue
    }
    if let string = value as? String {
      return Int(string)
    }
    return nil
  }

  private static func stringValue(from value: Any) -> String? {
    if let string = value as? String {
      let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? nil : trimmed
    }
    if let number = value as? NSNumber {
      return number.stringValue
    }
    return nil
  }

  private static func jsonString(from value: Any) -> String? {
    if let string = value as? String {
      return string
    }
    guard JSONSerialization.isValidJSONObject(value),
      let data = try? JSONSerialization.data(withJSONObject: value),
      let string = String(data: data, encoding: .utf8)
    else { return nil }
    return string
  }
}

public final class SQLiteAgentRunEventSink: AgentRunEventSink, @unchecked Sendable {
  private let lock = NSLock()
  private let store: SQLiteServerStateStore
  private var startInfoByRunID: [RunID: AgentRunStartInfo] = [:]
  private var startedAtByRunID: [RunID: String] = [:]
  private var lastStateByRunID: [RunID: RunLifecycleState] = [:]
  private var eventCountByRunID: [RunID: Int] = [:]
  private var lastEventTypeByRunID: [RunID: String] = [:]
  private var lastEventAtByRunID: [RunID: String] = [:]
  private var providerSnapshotByRunID: [RunID: ProviderSessionSnapshot] = [:]
  private var runIDBySessionID: [SessionID: RunID] = [:]

  public init(store: SQLiteServerStateStore) {
    self.store = store
  }

  public func runDidStart(_ startInfo: AgentRunStartInfo) {
    try? persistStart(startInfo)
  }

  public func runDidTransition(_ context: RunContext, to state: RunLifecycleState) {
    try? persistTransition(context: context, state: state)
  }

  @inline(never)
  public func runDidReceiveEvent(_ event: AgentRawEvent) {
    let update = eventUpdate(for: event)

    guard let update else { return }

    try? persistEvent(event, update: update)
  }

  private func eventUpdate(for event: AgentRawEvent) -> (
    runID: RunID, startInfo: AgentRunStartInfo, state: RunLifecycleState
  )? {
    let update: (runID: RunID, startInfo: AgentRunStartInfo, state: RunLifecycleState)?
    lock.lock()
    if let runID = runIDBySessionID[event.sessionID],
      let startInfo = startInfoByRunID[runID]
    {
      let eventCount: Int
      if let storedEventCount = eventCountByRunID[runID] {
        eventCount = storedEventCount
      } else {
        eventCount = 0
      }
      eventCountByRunID[runID] = eventCount + 1
      lastEventTypeByRunID[runID] = event.providerEventType
      lastEventAtByRunID[runID] = event.timestamp
      let state: RunLifecycleState
      if let storedState = lastStateByRunID[runID] {
        state = storedState
      } else {
        state = .streamingTurn
      }
      update = (runID, startInfo, state)
    } else {
      update = nil
    }
    lock.unlock()

    return update
  }

  private func persistEvent(
    _ event: AgentRawEvent,
    update: (runID: RunID, startInfo: AgentRunStartInfo, state: RunLifecycleState)
  ) throws {
    let storedEvent = try store.appendEvent(
      sessionID: event.sessionID,
      provider: event.provider,
      timestamp: event.timestamp,
      rawJSON: event.rawJSON,
      providerEventType: event.providerEventType,
      normalizedEventKind: event.normalizedEventKind
    )
    mergeProviderSnapshot(
      for: update.runID,
      update: ProviderSessionSnapshotExtractor.update(
        from: event, storedSequence: storedEvent.sequence)
    )

    try store.upsertRun(
      makeRunDetail(
        startInfo: update.startInfo,
        status: update.state,
        startedAt: startedAt(for: update.runID),
        endedAt: nil,
        lastError: nil
      ))
  }

  public func runDidComplete(_ result: AgentRunResult) {
    try? persistCompletion(result)
  }

  private func persistStart(_ startInfo: AgentRunStartInfo) throws {
    let (startedAt, currentState) = recordStart(startInfo)
    try store.upsertIssue(startInfo.issue)
    try store.upsertRun(
      makeRunDetail(
        startInfo: startInfo,
        status: currentState,
        startedAt: startedAt,
        endedAt: nil,
        lastError: nil
      ))
    try store.upsertSession(
      makeSession(
        startInfo: startInfo,
        status: currentState,
        lastError: nil
      ))
  }

  private func persistTransition(context: RunContext, state: RunLifecycleState) throws {
    guard let startInfo = recordTransition(context: context, state: state) else { return }

    try store.upsertRun(
      makeRunDetail(
        startInfo: startInfo,
        status: state,
        startedAt: startedAt(for: context.runID),
        endedAt: state.isTerminal ? Self.timestampString() : nil,
        lastError: nil
      ))
    try store.upsertSession(
      makeSession(
        startInfo: startInfo,
        status: state,
        lastError: nil
      ))
  }

  private func persistCompletion(_ result: AgentRunResult) throws {
    guard let startInfo = startInfo(for: result.context.runID) else { return }

    try store.upsertRun(
      makeRunDetail(
        startInfo: startInfo,
        status: result.finalState,
        startedAt: startedAt(for: result.context.runID),
        endedAt: Self.timestampString(),
        lastError: result.error
      ))
    try store.upsertSession(
      makeSession(
        startInfo: startInfo,
        status: result.finalState,
        lastError: result.error
      ))

    clearState(for: result.context.runID, sessionID: result.sessionID)
  }

  private nonisolated func recordStart(_ startInfo: AgentRunStartInfo) -> (
    String, RunLifecycleState
  ) {
    let startedAt = Self.timestampString()
    lock.lock()
    defer { lock.unlock() }
    startInfoByRunID[startInfo.context.runID] = startInfo
    startedAtByRunID[startInfo.context.runID] = startedAt
    if eventCountByRunID[startInfo.context.runID] == nil {
      eventCountByRunID[startInfo.context.runID] = 0
    }
    if providerSnapshotByRunID[startInfo.context.runID] == nil {
      providerSnapshotByRunID[startInfo.context.runID] = ProviderSessionSnapshot()
    }
    runIDBySessionID[startInfo.sessionID] = startInfo.context.runID
    let currentState: RunLifecycleState
    if let storedState = lastStateByRunID[startInfo.context.runID] {
      currentState = storedState
    } else {
      currentState = .initializingSession
    }
    return (startedAt, currentState)
  }

  private nonisolated func recordTransition(context: RunContext, state: RunLifecycleState)
    -> AgentRunStartInfo?
  {
    lock.lock()
    defer { lock.unlock() }
    lastStateByRunID[context.runID] = state
    return startInfoByRunID[context.runID]
  }

  private nonisolated func startInfo(for runID: RunID) -> AgentRunStartInfo? {
    lock.lock()
    defer { lock.unlock() }
    return startInfoByRunID[runID]
  }

  private nonisolated func startedAt(for runID: RunID) -> String {
    lock.lock()
    let startedAt = startedAtByRunID[runID]
    lock.unlock()
    if let startedAt {
      return startedAt
    }
    return Self.timestampString()
  }

  private nonisolated func snapshot(for runID: RunID) -> (count: Int, type: String?, time: String?)
  {
    lock.lock()
    defer { lock.unlock() }
    let count: Int
    if let storedCount = eventCountByRunID[runID] {
      count = storedCount
    } else {
      count = 0
    }
    return (
      count,
      lastEventTypeByRunID[runID],
      lastEventAtByRunID[runID]
    )
  }

  private nonisolated func providerSnapshot(for runID: RunID) -> ProviderSessionSnapshot {
    lock.lock()
    defer { lock.unlock() }
    return providerSnapshotByRunID[runID] ?? ProviderSessionSnapshot()
  }

  private nonisolated func mergeProviderSnapshot(
    for runID: RunID,
    update: ProviderSessionSnapshotUpdate
  ) {
    lock.lock()
    let currentSnapshot = providerSnapshotByRunID[runID] ?? ProviderSessionSnapshot()
    providerSnapshotByRunID[runID] = currentSnapshot.merging(update)
    lock.unlock()
  }

  private nonisolated func clearState(for runID: RunID, sessionID: SessionID) {
    lock.lock()
    defer { lock.unlock() }
    startInfoByRunID.removeValue(forKey: runID)
    startedAtByRunID.removeValue(forKey: runID)
    lastStateByRunID.removeValue(forKey: runID)
    eventCountByRunID.removeValue(forKey: runID)
    lastEventTypeByRunID.removeValue(forKey: runID)
    lastEventAtByRunID.removeValue(forKey: runID)
    providerSnapshotByRunID.removeValue(forKey: runID)
    runIDBySessionID.removeValue(forKey: sessionID)
  }

  func testingStartedAt(for runID: RunID) -> String {
    startedAt(for: runID)
  }

  func testingSnapshot(for runID: RunID) -> (count: Int, type: String?, time: String?) {
    snapshot(for: runID)
  }

  func testingProviderSnapshot(for runID: RunID) -> (
    providerSessionID: String?,
    providerThreadID: String?,
    providerTurnID: String?,
    providerRunID: String?,
    tokenUsage: TokenUsage,
    latestRateLimitPayload: String?,
    lastAgentMessage: String?,
    latestSequence: EventSequence?
  ) {
    let snapshot = providerSnapshot(for: runID)
    return (
      snapshot.providerSessionID,
      snapshot.providerThreadID,
      snapshot.providerTurnID,
      snapshot.providerRunID,
      snapshot.tokenUsage,
      snapshot.latestRateLimitPayload,
      snapshot.lastAgentMessage,
      snapshot.latestSequence
    )
  }

  func testingMergeProviderUpdate(
    for runID: RunID,
    event: AgentRawEvent,
    storedSequence: EventSequence
  ) {
    mergeProviderSnapshot(
      for: runID,
      update: ProviderSessionSnapshotExtractor.update(from: event, storedSequence: storedSequence)
    )
  }

  func testingMergeProviderSnapshot(
    for runID: RunID,
    providerSessionID: String? = nil,
    providerThreadID: String? = nil,
    providerTurnID: String? = nil,
    providerRunID: String? = nil,
    tokenUsage: TokenUsage? = nil,
    latestRateLimitPayload: String? = nil,
    lastAgentMessage: String? = nil,
    latestSequence: EventSequence? = nil
  ) {
    mergeProviderSnapshot(
      for: runID,
      update: ProviderSessionSnapshotUpdate(
        providerSessionID: providerSessionID,
        providerThreadID: providerThreadID,
        providerTurnID: providerTurnID,
        providerRunID: providerRunID,
        tokenUsage: tokenUsage,
        latestRateLimitPayload: latestRateLimitPayload,
        lastAgentMessage: lastAgentMessage,
        latestSequence: latestSequence
      )
    )
  }

  func testingProviderMessageText(from rawJSONObject: Any) -> String? {
    ProviderSessionSnapshotExtractor.messageText(from: rawJSONObject)
  }

  func testingProviderTokenUsage(from rawJSONObject: Any) -> TokenUsage? {
    ProviderSessionSnapshotExtractor.tokenUsage(from: rawJSONObject)
  }

  func testingClearEventCount(for runID: RunID) {
    lock.lock()
    eventCountByRunID.removeValue(forKey: runID)
    lock.unlock()
  }

  private func makeRunDetail(
    startInfo: AgentRunStartInfo,
    status: RunLifecycleState,
    startedAt: String,
    endedAt: String?,
    lastError: String?
  ) throws -> RunDetail {
    let runID = startInfo.context.runID
    let snapshot = snapshot(for: runID)
    let providerSnapshot = providerSnapshot(for: runID)
    return RunDetail(
      runID: runID,
      issueID: startInfo.issue.id,
      issueIdentifier: startInfo.issue.identifier,
      attempt: startInfo.context.attempt,
      status: status.rawValue,
      provider: startInfo.provider,
      providerSessionID: providerSnapshot.providerSessionID,
      providerRunID: providerSnapshot.providerRunID,
      startedAt: startedAt,
      endedAt: endedAt,
      workspacePath: startInfo.workspacePath,
      sessionID: startInfo.sessionID,
      lastError: lastError,
      issue: startInfo.issue,
      turnCount: snapshot.count,
      lastAgentEventType: snapshot.type,
      lastAgentMessage: providerSnapshot.lastAgentMessage,
      tokens: providerSnapshot.tokenUsage,
      logs: RunLogStats(eventCount: snapshot.count, latestSequence: providerSnapshot.latestSequence)
    )
  }

  private func makeSession(
    startInfo: AgentRunStartInfo,
    status: RunLifecycleState,
    lastError: String?
  ) throws -> AgentSession {
    let runID = startInfo.context.runID
    let snapshot = snapshot(for: runID)
    let providerSnapshot = providerSnapshot(for: runID)
    _ = lastError
    return AgentSession(
      sessionID: startInfo.sessionID,
      provider: startInfo.provider,
      providerSessionID: providerSnapshot.providerSessionID,
      providerThreadID: providerSnapshot.providerThreadID,
      providerTurnID: providerSnapshot.providerTurnID,
      providerRunID: providerSnapshot.providerRunID,
      runID: runID,
      providerProcessPID: nil,
      status: status.rawValue,
      lastEventType: snapshot.type,
      lastEventAt: snapshot.time,
      turnCount: snapshot.count,
      tokenUsage: providerSnapshot.tokenUsage,
      latestRateLimitPayload: providerSnapshot.latestRateLimitPayload
    )
  }

  private static func timestampString(from date: Date = Date()) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
  }
}
