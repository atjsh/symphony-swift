import Foundation
import SymphonyShared

public final class SQLiteAgentRunEventSink: AgentRunEventSink, @unchecked Sendable {
  private let lock = NSLock()
  private let store: SQLiteServerStateStore
  private var startInfoByRunID: [RunID: AgentRunStartInfo] = [:]
  private var startedAtByRunID: [RunID: String] = [:]
  private var lastStateByRunID: [RunID: RunLifecycleState] = [:]
  private var eventCountByRunID: [RunID: Int] = [:]
  private var lastEventTypeByRunID: [RunID: String] = [:]
  private var lastEventAtByRunID: [RunID: String] = [:]
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
    _ = try? store.appendEvent(
      sessionID: event.sessionID,
      provider: event.provider,
      timestamp: event.timestamp,
      rawJSON: event.rawJSON,
      providerEventType: event.providerEventType,
      normalizedEventKind: event.normalizedEventKind
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

  private nonisolated func clearState(for runID: RunID, sessionID: SessionID) {
    lock.lock()
    defer { lock.unlock() }
    startInfoByRunID.removeValue(forKey: runID)
    startedAtByRunID.removeValue(forKey: runID)
    lastStateByRunID.removeValue(forKey: runID)
    eventCountByRunID.removeValue(forKey: runID)
    lastEventTypeByRunID.removeValue(forKey: runID)
    lastEventAtByRunID.removeValue(forKey: runID)
    runIDBySessionID.removeValue(forKey: sessionID)
  }

  func testingStartedAt(for runID: RunID) -> String {
    startedAt(for: runID)
  }

  func testingSnapshot(for runID: RunID) -> (count: Int, type: String?, time: String?) {
    snapshot(for: runID)
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
    return RunDetail(
      runID: runID,
      issueID: startInfo.issue.id,
      issueIdentifier: startInfo.issue.identifier,
      attempt: startInfo.context.attempt,
      status: status.rawValue,
      provider: startInfo.provider,
      providerSessionID: nil,
      providerRunID: nil,
      startedAt: startedAt,
      endedAt: endedAt,
      workspacePath: startInfo.workspacePath,
      sessionID: startInfo.sessionID,
      lastError: lastError,
      issue: startInfo.issue,
      turnCount: snapshot.count,
      lastAgentEventType: snapshot.type,
      lastAgentMessage: nil,
      tokens: try TokenUsage(),
      logs: RunLogStats(eventCount: snapshot.count, latestSequence: nil)
    )
  }

  private func makeSession(
    startInfo: AgentRunStartInfo,
    status: RunLifecycleState,
    lastError: String?
  ) throws -> AgentSession {
    let runID = startInfo.context.runID
    let snapshot = snapshot(for: runID)
    _ = lastError
    return AgentSession(
      sessionID: startInfo.sessionID,
      provider: startInfo.provider,
      providerSessionID: nil,
      providerThreadID: nil,
      providerTurnID: nil,
      providerRunID: nil,
      runID: runID,
      providerProcessPID: nil,
      status: status.rawValue,
      lastEventType: snapshot.type,
      lastEventAt: snapshot.time,
      turnCount: snapshot.count,
      tokenUsage: try TokenUsage(),
      latestRateLimitPayload: nil
    )
  }

  private static func timestampString(from date: Date = Date()) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
  }
}
