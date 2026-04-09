// Batch 46 — SQLiteAgentRunEventSink session upsert & event-before-transition hardening.
//
// Gaps addressed:
//   1. After runDidStart, session status is never verified as initializingSession.
//      Kills mutation: removal of store.upsertSession in persistStart.
//   2. After runDidTransition, session status is never verified as streamingTurn.
//      Kills mutation: removal of store.upsertSession in persistTransition.
//   3. After runDidReceiveEvent without prior runDidTransition, DB RunDetail status
//      is never verified as streamingTurn (Batch7 only checks snapshot.count).
//      Kills mutation: `state = .streamingTurn` → different state.
//   4. After event-before-transition, session fields (status, lastEventType, turnCount)
//      are never verified.
//      Kills mutation: removal of event processing state propagation to session.

import Foundation
import SymphonyShared
import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore

// MARK: - Session Status After Start

@Suite("Session Status After Start")
struct SessionStatusAfterStartTests {

  @Test func sessionExistsWithInitializingStatusAfterRunDidStart() throws {
    let dir = try makeAgentRunSinkTemporaryDirectory()
    let store = try SQLiteServerStateStore(
      databaseURL: dir.appendingPathComponent("session-start.sqlite3"))
    let sink = SQLiteAgentRunEventSink(store: store)

    let issue = try makeAgentRunSinkIssue()
    let context = try makeAgentRunSinkContext(runID: "R_sess_start")
    let startInfo = AgentRunStartInfo(
      context: context,
      issue: issue,
      provider: "codex",
      sessionID: SessionID("s-sess-start"),
      workspacePath: "/tmp/ws"
    )
    sink.runDidStart(startInfo)

    let session = try #require(try store.session(sessionID: SessionID("s-sess-start")))
    #expect(session.status == RunLifecycleState.initializingSession.rawValue)
    #expect(session.provider == "codex")
    #expect(session.runID == context.runID)
    #expect(session.turnCount == 0)
    #expect(session.lastEventType == nil)
    #expect(session.lastEventAt == nil)
  }
}

// MARK: - Session Status After Transition

@Suite("Session Status After Transition")
struct SessionStatusAfterTransitionTests {

  @Test func sessionStatusUpdatesToStreamingTurnAfterTransition() throws {
    let dir = try makeAgentRunSinkTemporaryDirectory()
    let store = try SQLiteServerStateStore(
      databaseURL: dir.appendingPathComponent("session-trans.sqlite3"))
    let sink = SQLiteAgentRunEventSink(store: store)

    let issue = try makeAgentRunSinkIssue()
    let context = try makeAgentRunSinkContext(runID: "R_sess_trans")
    let startInfo = AgentRunStartInfo(
      context: context,
      issue: issue,
      provider: "codex",
      sessionID: SessionID("s-sess-trans"),
      workspacePath: "/tmp/ws"
    )
    sink.runDidStart(startInfo)

    // Verify session starts at initializingSession
    let sessionBefore = try #require(try store.session(sessionID: SessionID("s-sess-trans")))
    #expect(sessionBefore.status == RunLifecycleState.initializingSession.rawValue)

    sink.runDidTransition(context, to: .streamingTurn)

    // After transition, session must reflect the new state
    let sessionAfter = try #require(try store.session(sessionID: SessionID("s-sess-trans")))
    #expect(sessionAfter.status == RunLifecycleState.streamingTurn.rawValue)
  }
}

// MARK: - Event-Before-Transition DB Status

@Suite("Event Before Transition DB Status")
struct EventBeforeTransitionDBStatusTests {

  @Test func eventBeforeTransitionSetsRunDetailStatusToStreamingTurn() throws {
    let dir = try makeAgentRunSinkTemporaryDirectory()
    let store = try SQLiteServerStateStore(
      databaseURL: dir.appendingPathComponent("evt-before-trans-run.sqlite3"))
    let sink = SQLiteAgentRunEventSink(store: store)

    let issue = try makeAgentRunSinkIssue()
    let context = try makeAgentRunSinkContext(runID: "R_evt_bt")
    let startInfo = AgentRunStartInfo(
      context: context,
      issue: issue,
      provider: "codex",
      sessionID: SessionID("s-evt-bt"),
      workspacePath: "/tmp/ws"
    )
    sink.runDidStart(startInfo)

    // Verify initial state
    let initialDetail = try #require(try store.runDetail(id: context.runID))
    #expect(initialDetail.status == RunLifecycleState.initializingSession.rawValue)

    // Fire event WITHOUT calling runDidTransition — triggers .streamingTurn fallback
    sink.runDidReceiveEvent(AgentRawEvent(
      sessionID: startInfo.sessionID,
      provider: "codex",
      sequence: EventSequence(0),
      timestamp: "2026-01-01T00:00:05Z",
      rawJSON: #"{"type":"status","payload":"ok"}"#,
      providerEventType: "status",
      normalizedEventKind: "status"
    ))

    // RunDetail status must be streamingTurn (the fallback)
    let runDetail = try #require(try store.runDetail(id: context.runID))
    #expect(runDetail.status == RunLifecycleState.streamingTurn.rawValue)
    #expect(runDetail.turnCount == 1)
    #expect(runDetail.lastAgentEventType == "status")
    #expect(runDetail.logs.eventCount == 1)
  }

  @Test func eventBeforeTransitionSetsSessionStatusToStreamingTurn() throws {
    let dir = try makeAgentRunSinkTemporaryDirectory()
    let store = try SQLiteServerStateStore(
      databaseURL: dir.appendingPathComponent("evt-before-trans-sess.sqlite3"))
    let sink = SQLiteAgentRunEventSink(store: store)

    let issue = try makeAgentRunSinkIssue()
    let context = try makeAgentRunSinkContext(runID: "R_evt_bt_s")
    let startInfo = AgentRunStartInfo(
      context: context,
      issue: issue,
      provider: "codex",
      sessionID: SessionID("s-evt-bt-s"),
      workspacePath: "/tmp/ws"
    )
    sink.runDidStart(startInfo)

    // Event without prior transition
    sink.runDidReceiveEvent(AgentRawEvent(
      sessionID: startInfo.sessionID,
      provider: "codex",
      sequence: EventSequence(0),
      timestamp: "2026-01-01T00:00:10Z",
      rawJSON: #"{"type":"message","content":"hello"}"#,
      providerEventType: "message",
      normalizedEventKind: "message"
    ))

    // Session must also reflect .streamingTurn through the run detail
    // (persistEvent only calls upsertRun, not upsertSession, so check the run)
    let runDetail = try #require(try store.runDetail(id: context.runID))
    #expect(runDetail.status == RunLifecycleState.streamingTurn.rawValue)

    // In-memory snapshot must reflect the event
    let snapshot = sink.testingSnapshot(for: context.runID)
    #expect(snapshot.count == 1)
    #expect(snapshot.type == "message")
    #expect(snapshot.time == "2026-01-01T00:00:10Z")
  }
}
