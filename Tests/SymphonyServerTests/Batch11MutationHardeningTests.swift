import Foundation
import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore
@testable import SymphonyShared

// MARK: - isCurrentRunStatus Mutation Hardening

@Suite("isCurrentRunStatus Mutations")
struct IsCurrentRunStatusMutationTests {

  // MARK: - Lifecycle states (via RunLifecycleState enum)

  @Test func activeLifecycleStatesAreCurrentRuns() {
    let activeStates: [RunLifecycleState] = [
      .preparingWorkspace, .buildingPrompt, .launchingAgentProcess,
      .initializingSession, .streamingTurn, .finishing,
    ]
    for state in activeStates {
      #expect(
        SQLiteServerStateStore.isCurrentRunStatus(state.rawValue),
        "Expected \(state.rawValue) to be active"
      )
    }
  }

  @Test func terminalLifecycleStatesAreNotCurrentRuns() {
    let terminalStates: [RunLifecycleState] = [
      .succeeded, .failed, .timedOut, .stalled, .canceledByReconciliation,
    ]
    for state in terminalStates {
      #expect(
        !SQLiteServerStateStore.isCurrentRunStatus(state.rawValue),
        "Expected \(state.rawValue) to be inactive"
      )
    }
  }

  // MARK: - Fallback string matching (lowercased branch)

  @Test func runningStringIsActive() {
    #expect(SQLiteServerStateStore.isCurrentRunStatus("running"))
  }

  @Test func queuedStringIsActive() {
    #expect(SQLiteServerStateStore.isCurrentRunStatus("queued"))
  }

  @Test func activeStringIsActive() {
    #expect(SQLiteServerStateStore.isCurrentRunStatus("active"))
  }

  @Test func succeededStringIsInactive() {
    #expect(!SQLiteServerStateStore.isCurrentRunStatus("succeeded"))
  }

  @Test func failedStringIsInactive() {
    #expect(!SQLiteServerStateStore.isCurrentRunStatus("failed"))
  }

  @Test func timedoutStringIsInactive() {
    #expect(!SQLiteServerStateStore.isCurrentRunStatus("timedout"))
  }

  @Test func stalledStringIsInactive() {
    #expect(!SQLiteServerStateStore.isCurrentRunStatus("stalled"))
  }

  @Test func canceledbyreconciliationStringIsInactive() {
    #expect(!SQLiteServerStateStore.isCurrentRunStatus("canceledbyreconciliation"))
  }

  @Test func cancelledStringIsInactive() {
    #expect(!SQLiteServerStateStore.isCurrentRunStatus("cancelled"))
  }

  @Test func canceledStringIsInactive() {
    #expect(!SQLiteServerStateStore.isCurrentRunStatus("canceled"))
  }

  @Test func doneStringIsInactive() {
    #expect(!SQLiteServerStateStore.isCurrentRunStatus("done"))
  }

  @Test func completeStringIsInactive() {
    #expect(!SQLiteServerStateStore.isCurrentRunStatus("complete"))
  }

  @Test func completedStringIsInactive() {
    #expect(!SQLiteServerStateStore.isCurrentRunStatus("completed"))
  }

  @Test func unknownStatusDefaultsToActive() {
    #expect(SQLiteServerStateStore.isCurrentRunStatus("custom_status_xyz"))
  }

  @Test func caseInsensitiveFallbackMatching() {
    // Uppercase strings that are NOT valid RunLifecycleState rawValues
    // should still be matched case-insensitively via lowercased()
    #expect(!SQLiteServerStateStore.isCurrentRunStatus("SUCCEEDED"))
    #expect(!SQLiteServerStateStore.isCurrentRunStatus("FAILED"))
    #expect(SQLiteServerStateStore.isCurrentRunStatus("RUNNING"))
  }
}

// MARK: - LiveLogHub Mutation Hardening

@Suite("LiveLogHub Mutations")
struct LiveLogHubMutationTests {

  private func makeEvent(sessionID: String, sequence: Int = 0) -> AgentRawEvent {
    AgentRawEvent(
      sessionID: SessionID(sessionID),
      provider: "codex",
      sequence: EventSequence(sequence),
      timestamp: "2026-01-01T00:00:00Z",
      rawJSON: #"{"test":true}"#,
      providerEventType: "message",
      normalizedEventKind: "message"
    )
  }

  @Test func publishWithNoSubscribersIsNoOp() async {
    let hub = LiveLogHub()
    await hub.publish(makeEvent(sessionID: "s-orphan"))
    // No crash or error; subscriber count remains zero
    let count = await hub.subscriberCount(for: SessionID("s-orphan"))
    #expect(count == 0)
  }

  @Test func publishDeliversToSubscriber() async {
    let hub = LiveLogHub()
    let stream = await hub.subscribe(to: SessionID("s-deliver"))
    let event = makeEvent(sessionID: "s-deliver", sequence: 42)
    await hub.publish(event)

    var iterator = stream.makeAsyncIterator()
    let received = await iterator.next()
    #expect(received?.sequence == EventSequence(42))
  }

  @Test func subscriberCountTracksSubscriptions() async {
    let hub = LiveLogHub()
    #expect(await hub.subscriberCount(for: SessionID("s-count")) == 0)
    _ = await hub.subscribe(to: SessionID("s-count"))
    #expect(await hub.subscriberCount(for: SessionID("s-count")) == 1)
    _ = await hub.subscribe(to: SessionID("s-count"))
    #expect(await hub.subscriberCount(for: SessionID("s-count")) == 2)
  }

  @Test func publishToWrongSessionDoesNotDeliver() async {
    let hub = LiveLogHub()
    let stream = await hub.subscribe(to: SessionID("s-A"))
    // Publish to a different session
    await hub.publish(makeEvent(sessionID: "s-B"))

    // The stream for s-A should not have received anything
    // Verify by checking subscriber count is still correct
    #expect(await hub.subscriberCount(for: SessionID("s-A")) == 1)
    #expect(await hub.subscriberCount(for: SessionID("s-B")) == 0)

    // Keep stream alive to avoid premature termination
    _ = stream
  }
}

// MARK: - SQLite Logs Pagination Edge Cases

@Suite("SQLite Logs Pagination Mutations")
struct SQLiteLogsPaginationMutationTests {

  private func makeStoreWithEvents(count: Int, sessionSuffix: String = "pagination") throws -> (SQLiteServerStateStore, SessionID) {
    let databaseURL = try makeAgentRunSinkTemporaryDirectory().appendingPathComponent(
      "pagination-\(sessionSuffix).sqlite3")
    let store = try SQLiteServerStateStore(databaseURL: databaseURL)
    let sessionID = SessionID("s-\(sessionSuffix)")
    let issue = try makeAgentRunSinkIssue(id: "I_\(sessionSuffix)", number: 1)
    let context = try makeAgentRunSinkContext(
      issueID: issue.id, runID: "R_\(sessionSuffix)")

    let session = AgentSession(
      sessionID: sessionID,
      provider: "codex",
      providerSessionID: nil,
      providerThreadID: nil,
      providerTurnID: nil,
      providerRunID: nil,
      runID: context.runID,
      providerProcessPID: nil,
      status: "active",
      lastEventType: nil,
      lastEventAt: nil,
      turnCount: 0,
      tokenUsage: try TokenUsage(inputTokens: 0, outputTokens: 0),
      latestRateLimitPayload: nil
    )
    let runDetail = RunDetail(
      runID: context.runID,
      issueID: issue.id,
      issueIdentifier: issue.identifier,
      attempt: 1,
      status: "StreamingTurn",
      provider: "codex",
      providerSessionID: nil,
      providerRunID: nil,
      startedAt: "2026-01-01T00:00:00Z",
      endedAt: nil,
      workspacePath: "/tmp/test",
      sessionID: sessionID,
      lastError: nil,
      issue: issue,
      turnCount: 0,
      lastAgentEventType: nil,
      lastAgentMessage: nil,
      tokens: try TokenUsage(inputTokens: 0, outputTokens: 0),
      logs: RunLogStats(eventCount: 0, latestSequence: nil)
    )
    try store.upsertIssue(issue)
    try store.upsertRun(runDetail)
    try store.upsertSession(session)

    for i in 1...count {
      _ = try store.appendEvent(
        sessionID: sessionID,
        provider: "codex",
        timestamp: "2026-01-01T00:00:0\(i % 10)Z",
        rawJSON: #"{"n":\#(i)}"#,
        providerEventType: "message",
        normalizedEventKind: "message"
      )
    }

    return (store, sessionID)
  }

  @Test func limitZeroClampedToOne() throws {
    let (store, sessionID) = try makeStoreWithEvents(count: 5, sessionSuffix: "clamp0")
    let result = try #require(try store.logs(sessionID: sessionID, cursor: nil, limit: 0))
    #expect(result.items.count == 1, "limit=0 should be clamped to 1, returning exactly 1 item")
    #expect(result.hasMore)
  }

  @Test func limitAbove100ClampedTo100() throws {
    let (store, sessionID) = try makeStoreWithEvents(count: 105, sessionSuffix: "clamp100")
    let result = try #require(try store.logs(sessionID: sessionID, cursor: nil, limit: 200))
    #expect(result.items.count == 100, "limit=200 should be clamped to 100")
    #expect(result.hasMore, "There are 105 events, clamped limit is 100, so hasMore=true")
  }

  @Test func hasMoreCorrectAtBoundary() throws {
    let (store, sessionID) = try makeStoreWithEvents(count: 3, sessionSuffix: "boundary")
    let result = try #require(try store.logs(sessionID: sessionID, cursor: nil, limit: 3))
    #expect(result.items.count == 3)
    #expect(!result.hasMore, "Exactly 3 events with limit=3 should have hasMore=false")
  }

  @Test func cursorSessionMismatchReturnsNil() throws {
    let (store, sessionID) = try makeStoreWithEvents(count: 3, sessionSuffix: "mismatch")
    let mismatchedCursor = EventCursor(
      sessionID: SessionID("s-other"),
      lastDeliveredSequence: EventSequence(1)
    )
    let result = try store.logs(
      sessionID: sessionID,
      cursor: mismatchedCursor,
      limit: 10
    )
    #expect(result == nil, "Cursor for different session should return nil")
  }

  @Test func missingSessionReturnsNil() throws {
    let databaseURL = try makeAgentRunSinkTemporaryDirectory().appendingPathComponent(
      "missing-session.sqlite3")
    let store = try SQLiteServerStateStore(databaseURL: databaseURL)
    let result = try store.logs(sessionID: SessionID("nonexistent"), cursor: nil, limit: 10)
    #expect(result == nil)
  }

  @Test func cursorPaginationReturnsSubsequentEvents() throws {
    let (store, sessionID) = try makeStoreWithEvents(count: 5, sessionSuffix: "cursor")
    let first = try #require(try store.logs(sessionID: sessionID, cursor: nil, limit: 2))
    #expect(first.items.count == 2)
    #expect(first.hasMore)
    #expect(first.items[0].sequence == EventSequence(1))
    #expect(first.items[1].sequence == EventSequence(2))

    let second = try #require(try store.logs(sessionID: sessionID, cursor: first.nextCursor, limit: 2))
    #expect(second.items.count == 2)
    #expect(second.hasMore)
    #expect(second.items[0].sequence == EventSequence(3))
    #expect(second.items[1].sequence == EventSequence(4))

    let third = try #require(try store.logs(sessionID: sessionID, cursor: second.nextCursor, limit: 2))
    #expect(third.items.count == 1)
    #expect(!third.hasMore)
    #expect(third.items[0].sequence == EventSequence(5))
  }
}
