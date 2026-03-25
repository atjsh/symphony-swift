import Foundation
import SymphonyShared
import Testing

@testable import SymphonyRuntime

@Suite("SQLiteAgentRunEventSink")
struct SQLiteAgentRunEventSinkTests {
  @Test func persistsRunSessionAndEventsAcrossLifecycle() async throws {
    let databaseURL = try makeAgentRunSinkTemporaryDirectory().appendingPathComponent(
      "agent-run-sink.sqlite3")
    let store = try SQLiteServerStateStore(databaseURL: databaseURL)
    let sink = SQLiteAgentRunEventSink(store: store)

    let issue = try makeAgentRunSinkIssue()
    let context = try makeAgentRunSinkContext(issueID: issue.id, number: issue.number)
    let startInfo = AgentRunStartInfo(
      context: context,
      issue: issue,
      provider: ProviderName.codex.rawValue,
      sessionID: SessionID("session-1"),
      workspacePath: "/tmp/symphony/o_r_1"
    )

    sink.runDidStart(startInfo)
    sink.runDidTransition(context, to: .streamingTurn)
    sink.runDidReceiveEvent(
      AgentRawEvent(
        sessionID: startInfo.sessionID,
        provider: startInfo.provider,
        sequence: EventSequence(0),
        timestamp: "2026-03-26T01:30:00Z",
        rawJSON: #"{"type":"message","payload":{"text":"hello"}}"#,
        providerEventType: "message",
        normalizedEventKind: "message"
      ))
    sink.runDidComplete(
      AgentRunResult(
        context: context,
        sessionID: startInfo.sessionID,
        finalState: .succeeded,
        eventCount: 1,
        error: nil
      ))

    let runDetail = try #require(try store.runDetail(id: context.runID))
    #expect(runDetail.status == RunLifecycleState.succeeded.rawValue)
    #expect(runDetail.workspacePath == startInfo.workspacePath)
    #expect(runDetail.sessionID == startInfo.sessionID)
    #expect(runDetail.turnCount == 1)
    #expect(runDetail.lastAgentEventType == "message")
    #expect(runDetail.logs.eventCount == 1)

    let session = try #require(try store.session(sessionID: startInfo.sessionID))
    #expect(session.status == RunLifecycleState.succeeded.rawValue)
    #expect(session.turnCount == 1)
    #expect(session.lastEventType == "message")
    #expect(session.lastEventAt == "2026-03-26T01:30:00Z")

    let logs = try #require(try store.logs(sessionID: startInfo.sessionID, cursor: nil, limit: 10))
    #expect(logs.items.count == 1)
    #expect(logs.items[0].sequence == EventSequence(1))
    #expect(logs.items[0].providerEventType == "message")
  }

  @Test func transitionBeforeStartBecomesInitialPersistedStatus() async throws {
    let databaseURL = try makeAgentRunSinkTemporaryDirectory().appendingPathComponent(
      "agent-run-sink-prestart.sqlite3")
    let store = try SQLiteServerStateStore(databaseURL: databaseURL)
    let sink = SQLiteAgentRunEventSink(store: store)

    let issue = try makeAgentRunSinkIssue(id: "I_2", number: 2)
    let context = try makeAgentRunSinkContext(
      issueID: issue.id,
      number: issue.number,
      runID: "R_2",
      attempt: 2
    )

    sink.runDidTransition(context, to: RunLifecycleState.buildingPrompt)

    let startInfo = AgentRunStartInfo(
      context: context,
      issue: issue,
      provider: ProviderName.claudeCode.rawValue,
      sessionID: SessionID("session-2"),
      workspacePath: "/tmp/symphony/o_r_2"
    )
    sink.runDidStart(startInfo)

    let runDetail = try #require(try store.runDetail(id: context.runID))
    #expect(runDetail.status == RunLifecycleState.buildingPrompt.rawValue)
    #expect(runDetail.attempt == 2)
    #expect(runDetail.provider == ProviderName.claudeCode.rawValue)
  }

  @Test func helperSnapshotsCoverFallbackAndEventMetadataPaths() throws {
    let databaseURL = try makeAgentRunSinkTemporaryDirectory().appendingPathComponent(
      "agent-run-sink-helper.sqlite3")
    let store = try SQLiteServerStateStore(databaseURL: databaseURL)
    let sink = SQLiteAgentRunEventSink(store: store)

    let issue = try makeAgentRunSinkIssue(id: "I_3", number: 3)
    let context = try makeAgentRunSinkContext(issueID: issue.id, number: issue.number, runID: "R_3")
    let fallbackStartedAt = sink.testingStartedAt(for: context.runID)
    #expect(!fallbackStartedAt.isEmpty)

    let initialSnapshot = sink.testingSnapshot(for: context.runID)
    #expect(initialSnapshot.count == 0)
    #expect(initialSnapshot.type == nil)
    #expect(initialSnapshot.time == nil)

    let startInfo = AgentRunStartInfo(
      context: context,
      issue: issue,
      provider: ProviderName.copilotCLI.rawValue,
      sessionID: SessionID("session-3"),
      workspacePath: "/tmp/symphony/o_r_3"
    )
    sink.runDidStart(startInfo)

    let event = AgentRawEvent(
      sessionID: startInfo.sessionID,
      provider: startInfo.provider,
      sequence: EventSequence(0),
      timestamp: "2026-03-26T01:31:00Z",
      rawJSON: #"{"type":"message","payload":{"text":"world"}}"#,
      providerEventType: "message",
      normalizedEventKind: "message"
    )
    sink.runDidReceiveEvent(event)

    let updatedSnapshot = sink.testingSnapshot(for: context.runID)
    #expect(updatedSnapshot.count == 1)
    #expect(updatedSnapshot.type == "message")
    #expect(updatedSnapshot.time == "2026-03-26T01:31:00Z")
  }

  @Test func receiveEventCanRecoverWhenEventCountStateWasCleared() throws {
    let databaseURL = try makeAgentRunSinkTemporaryDirectory().appendingPathComponent(
      "agent-run-sink-cleared-count.sqlite3")
    let store = try SQLiteServerStateStore(databaseURL: databaseURL)
    let sink = SQLiteAgentRunEventSink(store: store)

    let issue = try makeAgentRunSinkIssue(id: "I_4", number: 4)
    let context = try makeAgentRunSinkContext(issueID: issue.id, number: issue.number, runID: "R_4")
    let startInfo = AgentRunStartInfo(
      context: context,
      issue: issue,
      provider: ProviderName.codex.rawValue,
      sessionID: SessionID("session-4"),
      workspacePath: "/tmp/symphony/o_r_4"
    )

    sink.runDidStart(startInfo)
    sink.testingClearEventCount(for: context.runID)
    sink.runDidReceiveEvent(
      AgentRawEvent(
        sessionID: startInfo.sessionID,
        provider: startInfo.provider,
        sequence: EventSequence(0),
        timestamp: "2026-03-26T01:33:00Z",
        rawJSON: #"{"type":"message","payload":{"text":"recovered"}}"#,
        providerEventType: "message",
        normalizedEventKind: "message"
      ))

    let snapshot = sink.testingSnapshot(for: context.runID)
    #expect(snapshot.count == 1)
    #expect(snapshot.type == "message")
    #expect(snapshot.time == "2026-03-26T01:33:00Z")
  }

  @Test func receiveEventWithoutKnownSessionReturnsWithoutPersisting() throws {
    let databaseURL = try makeAgentRunSinkTemporaryDirectory().appendingPathComponent(
      "agent-run-sink-missing-session.sqlite3")
    let store = try SQLiteServerStateStore(databaseURL: databaseURL)
    let sink = SQLiteAgentRunEventSink(store: store)

    sink.runDidReceiveEvent(
      AgentRawEvent(
        sessionID: SessionID("missing-session"),
        provider: ProviderName.codex.rawValue,
        sequence: EventSequence(0),
        timestamp: "2026-03-26T01:32:00Z",
        rawJSON: #"{"type":"message"}"#,
        providerEventType: "message",
        normalizedEventKind: "message"
      ))

    let logs = try store.logs(sessionID: SessionID("missing-session"), cursor: nil, limit: 10)
    #expect(logs?.items.isEmpty != false)
  }
}

private func makeAgentRunSinkIssue(
  id: String = "I_1",
  number: Int = 1
) throws -> SymphonyShared.Issue {
  SymphonyShared.Issue(
    id: IssueID(id),
    identifier: try IssueIdentifier(validating: "owner/repo#\(number)"),
    repository: "owner/repo",
    number: number,
    title: "Persist runtime state",
    description: "Ensure the sink stores lifecycle updates.",
    priority: 1,
    state: "In Progress",
    issueState: "OPEN",
    projectItemID: nil,
    url: "https://github.com/owner/repo/issues/\(number)",
    labels: [],
    blockedBy: [],
    createdAt: "2026-03-26T01:00:00Z",
    updatedAt: "2026-03-26T01:00:00Z"
  )
}

private func makeAgentRunSinkContext(
  issueID: IssueID = IssueID("I_1"),
  number: Int = 1,
  runID: String = "R_1",
  attempt: Int = 1
) throws -> RunContext {
  RunContext(
    issueID: issueID,
    issueIdentifier: try IssueIdentifier(validating: "owner/repo#\(number)"),
    runID: RunID(runID),
    attempt: attempt
  )
}

private func makeAgentRunSinkTemporaryDirectory() throws -> URL {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    UUID().uuidString,
    isDirectory: true
  )
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  return root
}
