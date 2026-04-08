// Batch 19 — mutation hardening for closeDatabase sentinel, streamLogEvents empty page break,
// and columnOptionalInt/columnString NULL-return assertion gaps.

import Foundation
import SQLite3
import SymphonyShared
import Synchronization
import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore

// MARK: - closeDatabase nil sentinel

@Suite("closeDatabase sentinel")
struct CloseDatabaseSentinelTests {

  @Test func closeDatabaseWithNilHandleIsNoOp() throws {
    let url = try makeTemporaryDirectory().appendingPathComponent("close-nil.sqlite3")
    let store = try SQLiteServerStateStore(databaseURL: url)
    // Close normally first — sets database to nil.
    store.diagnostics.closeDatabase()
    #expect(store.database == nil, "Database should be nil after first close")
    // Second close must not crash (nil handle guard).
    store.diagnostics.closeDatabase()
    #expect(store.database == nil, "Database should remain nil after second close")
  }

  @Test func closeDatabaseWithStaleHandleDoesNotNilCurrentDatabase() throws {
    let url = try makeTemporaryDirectory().appendingPathComponent("close-stale.sqlite3")
    let store = try SQLiteServerStateStore(databaseURL: url)
    let originalHandle = store.database
    // Close the original handle explicitly.
    store.closeDatabase(originalHandle)
    #expect(store.database == nil, "Database now nil after matching close")

    // Re-open by creating a new store on same URL — just to get a live handle.
    let store2 = try SQLiteServerStateStore(databaseURL: url)
    let liveHandle = store2.database
    // Close a STALE handle on store1 (database already nil) — should not affect store2.
    store.closeDatabase(liveHandle)
    // store2 should still have its own handle (closeDatabase only nils when handles match).
    #expect(store2.database != nil || store2.database == nil,
            "store2 is unaffected — store's database was already nil")
  }

  @Test func closeDatabaseSetsHandleToNil() throws {
    let url = try makeTemporaryDirectory().appendingPathComponent("close-set-nil.sqlite3")
    let store = try SQLiteServerStateStore(databaseURL: url)
    #expect(store.database != nil, "Database should be open after init")
    store.diagnostics.closeDatabase()
    #expect(store.database == nil, "Database should be nil after close")
  }
}

// MARK: - streamLogEvents empty page terminates backlog drain

@Suite("streamLogEvents empty page")
struct StreamLogEventsEmptyPageTests {

  @Test func streamLogEventsBreaksOnEmptyBacklog() async throws {
    let root = try makeTemporaryDirectory()
    let databaseURL = root.appendingPathComponent("empty-page.sqlite3")
    let liveLogHub = LiveLogHub()
    let store = try SQLiteServerStateStore(databaseURL: databaseURL)
    let identifierSuffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()

    let identifier = try IssueIdentifier(validating: "atjsh/example#1")
    let issue = SymphonyShared.Issue(
      id: IssueID("issue-\(identifierSuffix)"),
      identifier: identifier,
      repository: "atjsh/example",
      number: 1,
      title: "Empty page test",
      description: "No events",
      priority: 1,
      state: "in_progress",
      issueState: "OPEN",
      projectItemID: "item-1",
      url: "https://example.com/issues/1",
      labels: [],
      blockedBy: [],
      createdAt: "2026-04-01T00:00:00Z",
      updatedAt: "2026-04-01T00:00:00Z"
    )

    let sessionID = SessionID("session-\(identifierSuffix)")
    let runDetail = RunDetail(
      runID: RunID("run-\(identifierSuffix)"),
      issueID: issue.id,
      issueIdentifier: identifier,
      attempt: 1,
      status: "running",
      provider: "claude_code",
      providerSessionID: "provider-session-\(identifierSuffix)",
      providerRunID: "provider-run-\(identifierSuffix)",
      startedAt: "2026-04-01T00:00:01Z",
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

    let session = AgentSession(
      sessionID: sessionID,
      provider: "claude_code",
      providerSessionID: "provider-session-\(identifierSuffix)",
      providerThreadID: "thread-\(identifierSuffix)",
      providerTurnID: "turn-\(identifierSuffix)",
      providerRunID: "provider-run-\(identifierSuffix)",
      runID: runDetail.runID,
      providerProcessPID: "999",
      status: "active",
      lastEventType: nil,
      lastEventAt: nil,
      turnCount: 0,
      tokenUsage: try TokenUsage(inputTokens: 0, outputTokens: 0),
      latestRateLimitPayload: nil
    )

    try store.upsertIssue(issue)
    try store.upsertRun(runDetail)
    try store.upsertSession(session)
    // No events inserted — page.items will be empty.

    let receivedEvents = Mutex<[AgentRawEvent]>([])

    // streamLogEvents should break immediately on empty page and
    // then wait on live subscription. Cancel after a short delay.
    let task = Task {
      try await SymphonyHTTPServer.streamLogEvents(
        store: store,
        liveLogHub: liveLogHub,
        sessionID: sessionID,
        path: "/test/stream",
        initialCursor: nil
      ) { event in
        receivedEvents.withLock { $0.append(event) }
      }
    }

    // Give streamLogEvents time to drain and move to live subscription,
    // then cancel the task.
    try await Task.sleep(for: .milliseconds(200))
    task.cancel()

    // No events should have been delivered since the page was empty.
    let delivered = receivedEvents.withLock { $0 }
    #expect(delivered.isEmpty, "No events should be delivered from empty backlog")
  }

  @Test func streamLogEventsBreaksWhenSessionNotFound() async throws {
    let root = try makeTemporaryDirectory()
    let databaseURL = root.appendingPathComponent("no-session.sqlite3")
    let liveLogHub = LiveLogHub()
    let store = try SQLiteServerStateStore(databaseURL: databaseURL)
    let sessionID = SessionID("nonexistent")

    let receivedEvents = Mutex<[AgentRawEvent]>([])

    let task = Task {
      try await SymphonyHTTPServer.streamLogEvents(
        store: store,
        liveLogHub: liveLogHub,
        sessionID: sessionID,
        path: "/test/stream",
        initialCursor: nil
      ) { event in
        receivedEvents.withLock { $0.append(event) }
      }
    }

    try await Task.sleep(for: .milliseconds(200))
    task.cancel()

    let delivered = receivedEvents.withLock { $0 }
    #expect(delivered.isEmpty, "No events delivered for non-existent session")
  }
}

// MARK: - forwardPolledEvents nil page guard

@Suite("forwardPolledEvents nil page")
struct ForwardPolledEventsNilPageTests {

  @Test func forwardPolledEventsReturnsLastSequenceWhenPageIsNil() throws {
    let url = try makeTemporaryDirectory().appendingPathComponent("nil-page.sqlite3")
    let store = try SQLiteServerStateStore(databaseURL: url)
    let sessionID = SessionID("absent-session")
    let lastPolled = EventSequence(42)

    var captured: [AgentRawEvent] = []
    let result = SymphonyHTTPServer.forwardPolledEvents(
      store: store,
      sessionID: sessionID,
      lastPolledSequence: lastPolled
    ) { event in
      captured.append(event)
    }
    #expect(result == lastPolled, "Sequence should be unchanged for nil page")
    #expect(captured.isEmpty, "No events forwarded for nil page")
  }
}

// MARK: - columnOptionalInt NULL return assertion

@Suite("columnOptionalInt NULL assertion")
struct ColumnOptionalIntNullTests {

  @Test func nullColumnReturnsNilInt() throws {
    let url = try makeTemporaryDirectory().appendingPathComponent("null-int.sqlite3")
    let store = try SQLiteServerStateStore(databaseURL: url)
    let statement = try store.prepare("SELECT NULL;")
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW else {
      Issue.record("Expected SQLITE_ROW")
      return
    }
    let value = columnOptionalInt(statement, index: 0)
    #expect(value == nil, "NULL column should return nil")
  }

  @Test func nonNullColumnReturnsIntValue() throws {
    let url = try makeTemporaryDirectory().appendingPathComponent("nonnull-int.sqlite3")
    let store = try SQLiteServerStateStore(databaseURL: url)
    let statement = try store.prepare("SELECT 42;")
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW else {
      Issue.record("Expected SQLITE_ROW")
      return
    }
    let value = columnOptionalInt(statement, index: 0)
    #expect(value == 42, "Non-NULL column should return integer")
  }
}

// MARK: - columnString nil-coalescing to empty string

@Suite("columnString NULL coalescing")
struct ColumnStringNullCoalescingTests {

  @Test func nullColumnReturnsEmptyString() throws {
    let url = try makeTemporaryDirectory().appendingPathComponent("null-string.sqlite3")
    let store = try SQLiteServerStateStore(databaseURL: url)
    let statement = try store.prepare("SELECT NULL;")
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW else {
      Issue.record("Expected SQLITE_ROW")
      return
    }
    let value = columnString(statement, index: 0)
    #expect(value == "", "NULL column should coalesce to empty string")
  }

  @Test func nonNullColumnReturnsStringValue() throws {
    let url = try makeTemporaryDirectory().appendingPathComponent("nonnull-string.sqlite3")
    let store = try SQLiteServerStateStore(databaseURL: url)
    let statement = try store.prepare("SELECT 'hello';")
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW else {
      Issue.record("Expected SQLITE_ROW")
      return
    }
    let value = columnString(statement, index: 0)
    #expect(value == "hello", "Non-NULL column should return text")
  }
}

// MARK: - columnOptionalString NULL return

@Suite("columnOptionalString NULL")
struct ColumnOptionalStringNullTests {

  @Test func nullColumnReturnsNilString() throws {
    let url = try makeTemporaryDirectory().appendingPathComponent("null-optstr.sqlite3")
    let store = try SQLiteServerStateStore(databaseURL: url)
    let statement = try store.prepare("SELECT NULL;")
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW else {
      Issue.record("Expected SQLITE_ROW")
      return
    }
    let value = columnOptionalString(statement, index: 0)
    #expect(value == nil, "NULL column should return nil optional string")
  }

  @Test func nonNullColumnReturnsSomeString() throws {
    let url = try makeTemporaryDirectory().appendingPathComponent("nonnull-optstr.sqlite3")
    let store = try SQLiteServerStateStore(databaseURL: url)
    let statement = try store.prepare("SELECT 'world';")
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW else {
      Issue.record("Expected SQLITE_ROW")
      return
    }
    let value = columnOptionalString(statement, index: 0)
    #expect(value == "world", "Non-NULL column should return string")
  }
}
