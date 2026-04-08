import Foundation
import SymphonyShared
import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore

// MARK: - SQLiteAgentRunEventSink mutation hardening

@Test func eventSinkEventCountIncrementsSteadily() throws {
  let databaseURL = try makeAgentRunSinkTemporaryDirectory().appendingPathComponent(
    "sink-count.sqlite3")
  let store = try SQLiteServerStateStore(databaseURL: databaseURL)
  let sink = SQLiteAgentRunEventSink(store: store)

  let issue = try makeAgentRunSinkIssue()
  let context = try makeAgentRunSinkContext()
  let startInfo = AgentRunStartInfo(
    context: context,
    issue: issue,
    provider: "codex",
    sessionID: SessionID("s-count"),
    workspacePath: "/tmp/ws"
  )
  sink.runDidStart(startInfo)
  sink.runDidTransition(context, to: .streamingTurn)

  // Send 5 events, verify each increments correctly
  for i in 0..<5 {
    sink.runDidReceiveEvent(AgentRawEvent(
      sessionID: startInfo.sessionID,
      provider: "codex",
      sequence: EventSequence(i),
      timestamp: "2026-01-01T00:00:0\(i)Z",
      rawJSON: #"{"n":\#(i)}"#,
      providerEventType: "message",
      normalizedEventKind: "message"
    ))
  }

  let snapshot = sink.testingSnapshot(for: context.runID)
  #expect(snapshot.count == 5)

  let runDetail = try #require(try store.runDetail(id: context.runID))
  #expect(runDetail.logs.eventCount == 5)
}

@Test func eventSinkFirstEventCountStartsFromZero() throws {
  let databaseURL = try makeAgentRunSinkTemporaryDirectory().appendingPathComponent(
    "sink-zero.sqlite3")
  let store = try SQLiteServerStateStore(databaseURL: databaseURL)
  let sink = SQLiteAgentRunEventSink(store: store)

  let issue = try makeAgentRunSinkIssue()
  let context = try makeAgentRunSinkContext()
  let startInfo = AgentRunStartInfo(
    context: context,
    issue: issue,
    provider: "codex",
    sessionID: SessionID("s-zero"),
    workspacePath: "/tmp/ws"
  )
  sink.runDidStart(startInfo)

  let beforeSnapshot = sink.testingSnapshot(for: context.runID)
  #expect(beforeSnapshot.count == 0)

  sink.runDidReceiveEvent(AgentRawEvent(
    sessionID: startInfo.sessionID,
    provider: "codex",
    sequence: EventSequence(0),
    timestamp: "2026-01-01T00:00:00Z",
    rawJSON: "{}",
    providerEventType: "status",
    normalizedEventKind: "status"
  ))

  let afterSnapshot = sink.testingSnapshot(for: context.runID)
  #expect(afterSnapshot.count == 1)
}

@Test func eventSinkDefaultStateIsInitializingSession() throws {
  let databaseURL = try makeAgentRunSinkTemporaryDirectory().appendingPathComponent(
    "sink-state.sqlite3")
  let store = try SQLiteServerStateStore(databaseURL: databaseURL)
  let sink = SQLiteAgentRunEventSink(store: store)

  let issue = try makeAgentRunSinkIssue()
  let context = try makeAgentRunSinkContext()
  let startInfo = AgentRunStartInfo(
    context: context,
    issue: issue,
    provider: "codex",
    sessionID: SessionID("s-init"),
    workspacePath: "/tmp/ws"
  )
  sink.runDidStart(startInfo)

  let runDetail = try #require(try store.runDetail(id: context.runID))
  #expect(runDetail.status == RunLifecycleState.initializingSession.rawValue)
}

@Test func eventSinkTransitionUpdatesState() throws {
  let databaseURL = try makeAgentRunSinkTemporaryDirectory().appendingPathComponent(
    "sink-trans.sqlite3")
  let store = try SQLiteServerStateStore(databaseURL: databaseURL)
  let sink = SQLiteAgentRunEventSink(store: store)

  let issue = try makeAgentRunSinkIssue()
  let context = try makeAgentRunSinkContext()
  let startInfo = AgentRunStartInfo(
    context: context,
    issue: issue,
    provider: "codex",
    sessionID: SessionID("s-trans"),
    workspacePath: "/tmp/ws"
  )
  sink.runDidStart(startInfo)
  sink.runDidTransition(context, to: .streamingTurn)

  let runDetail = try #require(try store.runDetail(id: context.runID))
  #expect(runDetail.status == RunLifecycleState.streamingTurn.rawValue)
}

@Test func eventSinkCompletionSetsEndedAtAndError() throws {
  let databaseURL = try makeAgentRunSinkTemporaryDirectory().appendingPathComponent(
    "sink-comp.sqlite3")
  let store = try SQLiteServerStateStore(databaseURL: databaseURL)
  let sink = SQLiteAgentRunEventSink(store: store)

  let issue = try makeAgentRunSinkIssue()
  let context = try makeAgentRunSinkContext()
  let startInfo = AgentRunStartInfo(
    context: context,
    issue: issue,
    provider: "codex",
    sessionID: SessionID("s-comp"),
    workspacePath: "/tmp/ws"
  )
  sink.runDidStart(startInfo)
  sink.runDidComplete(AgentRunResult(
    context: context,
    sessionID: startInfo.sessionID,
    finalState: .failed,
    eventCount: 0,
    error: "boom"
  ))

  let runDetail = try #require(try store.runDetail(id: context.runID))
  #expect(runDetail.status == RunLifecycleState.failed.rawValue)
  #expect(runDetail.lastError == "boom")
  #expect(runDetail.endedAt != nil)
}

@Test func eventSinkTracksLastEventTypeAndTimestamp() throws {
  let databaseURL = try makeAgentRunSinkTemporaryDirectory().appendingPathComponent(
    "sink-last.sqlite3")
  let store = try SQLiteServerStateStore(databaseURL: databaseURL)
  let sink = SQLiteAgentRunEventSink(store: store)

  let issue = try makeAgentRunSinkIssue()
  let context = try makeAgentRunSinkContext()
  let startInfo = AgentRunStartInfo(
    context: context,
    issue: issue,
    provider: "codex",
    sessionID: SessionID("s-last"),
    workspacePath: "/tmp/ws"
  )
  sink.runDidStart(startInfo)

  sink.runDidReceiveEvent(AgentRawEvent(
    sessionID: startInfo.sessionID,
    provider: "codex",
    sequence: EventSequence(0),
    timestamp: "2026-01-01T00:00:01Z",
    rawJSON: "{}",
    providerEventType: "status",
    normalizedEventKind: "status"
  ))

  let snap1 = sink.testingSnapshot(for: context.runID)
  #expect(snap1.type == "status")
  #expect(snap1.time == "2026-01-01T00:00:01Z")

  sink.runDidReceiveEvent(AgentRawEvent(
    sessionID: startInfo.sessionID,
    provider: "codex",
    sequence: EventSequence(1),
    timestamp: "2026-01-01T00:00:02Z",
    rawJSON: "{}",
    providerEventType: "message",
    normalizedEventKind: "message"
  ))

  let snap2 = sink.testingSnapshot(for: context.runID)
  #expect(snap2.type == "message")
  #expect(snap2.time == "2026-01-01T00:00:02Z")
}

@Test func eventSinkProviderSnapshotMergesAcrossEvents() throws {
  let databaseURL = try makeAgentRunSinkTemporaryDirectory().appendingPathComponent(
    "sink-merge.sqlite3")
  let store = try SQLiteServerStateStore(databaseURL: databaseURL)
  let sink = SQLiteAgentRunEventSink(store: store)

  let issue = try makeAgentRunSinkIssue()
  let context = try makeAgentRunSinkContext()
  let startInfo = AgentRunStartInfo(
    context: context,
    issue: issue,
    provider: "codex",
    sessionID: SessionID("s-merge"),
    workspacePath: "/tmp/ws"
  )
  sink.runDidStart(startInfo)

  // First event has session_id
  sink.runDidReceiveEvent(AgentRawEvent(
    sessionID: startInfo.sessionID,
    provider: "codex",
    sequence: EventSequence(0),
    timestamp: "2026-01-01T00:00:00Z",
    rawJSON: #"{"session_id":"ps1","thread":{"id":"t1"}}"#,
    providerEventType: "status",
    normalizedEventKind: "status"
  ))

  // Second event has usage
  sink.runDidReceiveEvent(AgentRawEvent(
    sessionID: startInfo.sessionID,
    provider: "codex",
    sequence: EventSequence(1),
    timestamp: "2026-01-01T00:00:01Z",
    rawJSON: #"{"usage":{"input_tokens":10,"output_tokens":20}}"#,
    providerEventType: "usage",
    normalizedEventKind: "usage"
  ))

  let provSnap = sink.testingProviderSnapshot(for: context.runID)
  #expect(provSnap.providerSessionID == "ps1")
  #expect(provSnap.providerThreadID == "t1")
  #expect(provSnap.tokenUsage.inputTokens == 10)
  #expect(provSnap.tokenUsage.outputTokens == 20)
}

@Test func eventSinkCompletionClearsInMemoryState() throws {
  let databaseURL = try makeAgentRunSinkTemporaryDirectory().appendingPathComponent(
    "sink-clear.sqlite3")
  let store = try SQLiteServerStateStore(databaseURL: databaseURL)
  let sink = SQLiteAgentRunEventSink(store: store)

  let issue = try makeAgentRunSinkIssue()
  let context = try makeAgentRunSinkContext()
  let startInfo = AgentRunStartInfo(
    context: context,
    issue: issue,
    provider: "codex",
    sessionID: SessionID("s-clear"),
    workspacePath: "/tmp/ws"
  )
  sink.runDidStart(startInfo)
  sink.runDidReceiveEvent(AgentRawEvent(
    sessionID: startInfo.sessionID,
    provider: "codex",
    sequence: EventSequence(0),
    timestamp: "2026-01-01T00:00:00Z",
    rawJSON: "{}",
    providerEventType: "status",
    normalizedEventKind: "status"
  ))

  sink.runDidComplete(AgentRunResult(
    context: context,
    sessionID: startInfo.sessionID,
    finalState: .succeeded,
    eventCount: 1,
    error: nil
  ))

  // After completion, in-memory state should be cleared
  let snapshot = sink.testingSnapshot(for: context.runID)
  #expect(snapshot.count == 0)
  #expect(snapshot.type == nil)
  #expect(snapshot.time == nil)
}

@Test func eventSinkIgnoresEventForUnknownSession() throws {
  let databaseURL = try makeAgentRunSinkTemporaryDirectory().appendingPathComponent(
    "sink-unk.sqlite3")
  let store = try SQLiteServerStateStore(databaseURL: databaseURL)
  let sink = SQLiteAgentRunEventSink(store: store)

  // No run started — event should be silently ignored
  sink.runDidReceiveEvent(AgentRawEvent(
    sessionID: SessionID("unknown-session"),
    provider: "codex",
    sequence: EventSequence(0),
    timestamp: "2026-01-01T00:00:00Z",
    rawJSON: "{}",
    providerEventType: "status",
    normalizedEventKind: "status"
  ))

  // No crash, no stored events
  let runDetail = try store.runDetail(id: RunID("R_1"))
  #expect(runDetail == nil)
}

@Test func eventSinkInitializesProviderSnapshotOnStart() throws {
  let databaseURL = try makeAgentRunSinkTemporaryDirectory().appendingPathComponent(
    "sink-psinit.sqlite3")
  let store = try SQLiteServerStateStore(databaseURL: databaseURL)
  let sink = SQLiteAgentRunEventSink(store: store)

  let issue = try makeAgentRunSinkIssue()
  let context = try makeAgentRunSinkContext()
  let startInfo = AgentRunStartInfo(
    context: context,
    issue: issue,
    provider: "codex",
    sessionID: SessionID("s-psinit"),
    workspacePath: "/tmp/ws"
  )
  sink.runDidStart(startInfo)

  let provSnap = sink.testingProviderSnapshot(for: context.runID)
  #expect(provSnap.providerSessionID == nil)
  #expect(provSnap.providerThreadID == nil)
  #expect(provSnap.tokenUsage.inputTokens == nil)
  #expect(provSnap.tokenUsage.outputTokens == nil)
}

@Test func eventSinkTransitionBeforeStartStoresState() throws {
  let databaseURL = try makeAgentRunSinkTemporaryDirectory().appendingPathComponent(
    "sink-pretr.sqlite3")
  let store = try SQLiteServerStateStore(databaseURL: databaseURL)
  let sink = SQLiteAgentRunEventSink(store: store)

  let context = try makeAgentRunSinkContext()
  let issue = try makeAgentRunSinkIssue()

  // Transition before start — stores state in memory but no persist (no startInfo)
  sink.runDidTransition(context, to: .buildingPrompt)

  let startInfo = AgentRunStartInfo(
    context: context,
    issue: issue,
    provider: "codex",
    sessionID: SessionID("s-pretr"),
    workspacePath: "/tmp/ws"
  )
  sink.runDidStart(startInfo)

  // Start should use the stored state (.buildingPrompt) not default (.initializingSession)
  let runDetail = try #require(try store.runDetail(id: context.runID))
  #expect(runDetail.status == RunLifecycleState.buildingPrompt.rawValue)
}
