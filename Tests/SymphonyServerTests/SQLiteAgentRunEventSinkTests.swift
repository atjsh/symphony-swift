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

  @Test func completionUsesZeroCountSnapshotWhenEventCountStateWasCleared() throws {
    let databaseURL = try makeAgentRunSinkTemporaryDirectory().appendingPathComponent(
      "agent-run-sink-cleared-count-completion.sqlite3")
    let store = try SQLiteServerStateStore(databaseURL: databaseURL)
    let sink = SQLiteAgentRunEventSink(store: store)

    let issue = try makeAgentRunSinkIssue(id: "I_4b", number: 41)
    let context = try makeAgentRunSinkContext(
      issueID: issue.id, number: issue.number, runID: "R_4b")
    let startInfo = AgentRunStartInfo(
      context: context,
      issue: issue,
      provider: ProviderName.codex.rawValue,
      sessionID: SessionID("session-4b"),
      workspacePath: "/tmp/symphony/o_r_4b"
    )

    sink.runDidStart(startInfo)
    sink.testingClearEventCount(for: context.runID)
    sink.runDidComplete(
      AgentRunResult(
        context: context,
        sessionID: startInfo.sessionID,
        finalState: .succeeded,
        eventCount: 0,
        error: nil
      ))

    let runDetail = try #require(try store.runDetail(id: context.runID))
    #expect(runDetail.turnCount == 0)
    #expect(runDetail.logs.eventCount == 0)

    let session = try #require(try store.session(sessionID: startInfo.sessionID))
    #expect(session.turnCount == 0)
    #expect(session.lastEventType == nil)
    #expect(session.lastEventAt == nil)
  }

  @Test func providerSnapshotHelpersCoverDefaultMergeAndNestedExtractionPaths() throws {
    let databaseURL = try makeAgentRunSinkTemporaryDirectory().appendingPathComponent(
      "agent-run-sink-provider-helpers.sqlite3")
    let store = try SQLiteServerStateStore(databaseURL: databaseURL)
    let sink = SQLiteAgentRunEventSink(store: store)
    let runID = RunID("R_helper")

    let defaultSnapshot = sink.testingProviderSnapshot(for: runID)
    #expect(defaultSnapshot.providerSessionID == nil)
    #expect(defaultSnapshot.providerThreadID == nil)
    #expect(defaultSnapshot.providerTurnID == nil)
    #expect(defaultSnapshot.providerRunID == nil)
    #expect(defaultSnapshot.tokenUsage == (try TokenUsage()))
    #expect(defaultSnapshot.latestRateLimitPayload == nil)
    #expect(defaultSnapshot.lastAgentMessage == nil)
    #expect(defaultSnapshot.latestSequence == nil)

    let metadataEvent = AgentRawEvent(
      sessionID: SessionID("session-helper"),
      provider: ProviderName.claudeCode.rawValue,
      sequence: EventSequence(0),
      timestamp: "2026-03-26T01:34:00Z",
      rawJSON:
        #"[{"wrapper":{"session_id":{"session_id":"provider-session-array"},"thread_id":42,"turn_id":{"turn_id":"turn-array"},"run_id":{"run_id":"provider-run-array"},"usage":{"input_tokens":"9","output_tokens":"3","total_tokens":"12"},"rate_limit":"{\"remaining\":5}"}}]"#,
      providerEventType: "system",
      normalizedEventKind: "status"
    )

    sink.testingMergeProviderUpdate(
      for: runID, event: metadataEvent, storedSequence: EventSequence(9))

    let mergedSnapshot = sink.testingProviderSnapshot(for: runID)
    let expectedUsage = try TokenUsage(inputTokens: 9, outputTokens: 3, totalTokens: 12)
    #expect(mergedSnapshot.providerSessionID == "provider-session-array")
    #expect(mergedSnapshot.providerThreadID == "42")
    #expect(mergedSnapshot.providerTurnID == "turn-array")
    #expect(mergedSnapshot.providerRunID == "provider-run-array")
    #expect(mergedSnapshot.tokenUsage == expectedUsage)
    #expect(mergedSnapshot.latestRateLimitPayload == #"{"remaining":5}"#)
    #expect(mergedSnapshot.lastAgentMessage == nil)
    #expect(mergedSnapshot.latestSequence == EventSequence(9))

    sink.testingMergeProviderSnapshot(for: runID)
    let preservedSnapshot = sink.testingProviderSnapshot(for: runID)
    #expect(preservedSnapshot.latestSequence == EventSequence(9))
  }

  @Test func providerSnapshotHelpersCaptureCurrentCodexNestedIdentifiers() throws {
    let databaseURL = try makeAgentRunSinkTemporaryDirectory().appendingPathComponent(
      "agent-run-sink-provider-current-codex.sqlite3")
    let store = try SQLiteServerStateStore(databaseURL: databaseURL)
    let sink = SQLiteAgentRunEventSink(store: store)
    let runID = RunID("R_current_codex")

    let threadResponseEvent = AgentRawEvent(
      sessionID: SessionID("session-current-codex"),
      provider: ProviderName.codex.rawValue,
      sequence: EventSequence(0),
      timestamp: "2026-03-26T01:34:10Z",
      rawJSON: #"{"id":2,"result":{"thread":{"id":"thread-current"}}}"#,
      providerEventType: "response",
      normalizedEventKind: "status"
    )

    sink.testingMergeProviderUpdate(
      for: runID, event: threadResponseEvent, storedSequence: EventSequence(10))

    let turnStartedEvent = AgentRawEvent(
      sessionID: SessionID("session-current-codex"),
      provider: ProviderName.codex.rawValue,
      sequence: EventSequence(1),
      timestamp: "2026-03-26T01:34:11Z",
      rawJSON:
        #"{"method":"turn/started","params":{"threadId":"thread-current","turn":{"id":"turn-current"}}}"#,
      providerEventType: "turn/started",
      normalizedEventKind: "status"
    )

    sink.testingMergeProviderUpdate(
      for: runID, event: turnStartedEvent, storedSequence: EventSequence(11))

    let snapshot = sink.testingProviderSnapshot(for: runID)
    #expect(snapshot.providerThreadID == "thread-current")
    #expect(snapshot.providerTurnID == "turn-current")
    #expect(snapshot.latestSequence == EventSequence(11))
  }

  @Test func providerSnapshotHelpersCaptureNestedIdentifiersInsideArrays() throws {
    let databaseURL = try makeAgentRunSinkTemporaryDirectory().appendingPathComponent(
      "agent-run-sink-provider-array-codex.sqlite3")
    let store = try SQLiteServerStateStore(databaseURL: databaseURL)
    let sink = SQLiteAgentRunEventSink(store: store)
    let runID = RunID("R_array_codex")

    let arrayEvent = AgentRawEvent(
      sessionID: SessionID("session-array-codex"),
      provider: ProviderName.codex.rawValue,
      sequence: EventSequence(0),
      timestamp: "2026-03-26T01:34:12Z",
      rawJSON:
        #"[{"payload":{"items":[{"thread":{"id":"thread-array"}},{"turn":{"id":"turn-array"}}]}}]"#,
      providerEventType: "response",
      normalizedEventKind: "status"
    )

    sink.testingMergeProviderUpdate(
      for: runID,
      event: arrayEvent,
      storedSequence: EventSequence(12)
    )

    let snapshot = sink.testingProviderSnapshot(for: runID)
    #expect(snapshot.providerThreadID == "thread-array")
    #expect(snapshot.providerTurnID == "turn-array")
  }

  @Test func providerSnapshotHelpersCoverArrayMessageAndNilFallbackPaths() throws {
    let databaseURL = try makeAgentRunSinkTemporaryDirectory().appendingPathComponent(
      "agent-run-sink-provider-message.sqlite3")
    let store = try SQLiteServerStateStore(databaseURL: databaseURL)
    let sink = SQLiteAgentRunEventSink(store: store)
    let runID = RunID("R_message")

    let messageArrayEvent = AgentRawEvent(
      sessionID: SessionID("session-message"),
      provider: ProviderName.codex.rawValue,
      sequence: EventSequence(0),
      timestamp: "2026-03-26T01:34:30Z",
      rawJSON: #"[ "   ", {"payload":[{"text":"array hello"}]} ]"#,
      providerEventType: "assistant",
      normalizedEventKind: "message"
    )

    sink.testingMergeProviderUpdate(
      for: runID, event: messageArrayEvent, storedSequence: EventSequence(3))

    let initialSnapshot = sink.testingProviderSnapshot(for: runID)
    #expect(initialSnapshot.lastAgentMessage == "array hello")
    #expect(initialSnapshot.latestSequence == EventSequence(3))

    let emptyPayloadEvent = AgentRawEvent(
      sessionID: SessionID("session-message"),
      provider: ProviderName.codex.rawValue,
      sequence: EventSequence(1),
      timestamp: "2026-03-26T01:34:31Z",
      rawJSON: #"{"payload":{}}"#,
      providerEventType: "assistant",
      normalizedEventKind: "message"
    )

    sink.testingMergeProviderUpdate(
      for: runID, event: emptyPayloadEvent, storedSequence: EventSequence(4))

    let fallbackSnapshot = sink.testingProviderSnapshot(for: runID)
    let numericUsage = try TokenUsage(inputTokens: 11)
    #expect(fallbackSnapshot.lastAgentMessage == "array hello")
    #expect(fallbackSnapshot.latestSequence == EventSequence(4))
    #expect(sink.testingProviderMessageText(from: [[:]]) == nil)
    #expect(
      sink.testingProviderTokenUsage(from: ["input_tokens": NSNumber(value: 11.5)]) == numericUsage)
    #expect(sink.testingProviderTokenUsage(from: ["input_tokens": ["unexpected": true]]) == nil)
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

  @Test func persistsProviderMetadataUsageAndLastMessageAcrossRestart() async throws {
    let databaseURL = try makeAgentRunSinkTemporaryDirectory().appendingPathComponent(
      "agent-run-sink-metadata.sqlite3")
    let store = try SQLiteServerStateStore(databaseURL: databaseURL)
    let sink = SQLiteAgentRunEventSink(store: store)

    let issue = try makeAgentRunSinkIssue(id: "I_5", number: 5)
    let context = try makeAgentRunSinkContext(issueID: issue.id, number: issue.number, runID: "R_5")
    let startInfo = AgentRunStartInfo(
      context: context,
      issue: issue,
      provider: ProviderName.claudeCode.rawValue,
      sessionID: SessionID("session-5"),
      workspacePath: "/tmp/symphony/o_r_5"
    )

    sink.runDidStart(startInfo)
    sink.runDidTransition(context, to: .streamingTurn)
    sink.runDidReceiveEvent(
      AgentRawEvent(
        sessionID: startInfo.sessionID,
        provider: startInfo.provider,
        sequence: EventSequence(0),
        timestamp: "2026-03-26T01:35:00Z",
        rawJSON:
          #"{"type":"system","session_id":"provider-session-5","thread_id":"thread-5","turn_id":"turn-5","run_id":"provider-run-5","rate_limit":{"remaining":100}}"#,
        providerEventType: "system",
        normalizedEventKind: "status"
      ))
    sink.runDidReceiveEvent(
      AgentRawEvent(
        sessionID: startInfo.sessionID,
        provider: startInfo.provider,
        sequence: EventSequence(1),
        timestamp: "2026-03-26T01:35:01Z",
        rawJSON: #"{"type":"assistant","message":"hello from claude"}"#,
        providerEventType: "assistant",
        normalizedEventKind: "message"
      ))
    sink.runDidReceiveEvent(
      AgentRawEvent(
        sessionID: startInfo.sessionID,
        provider: startInfo.provider,
        sequence: EventSequence(2),
        timestamp: "2026-03-26T01:35:02Z",
        rawJSON:
          #"{"type":"usage","usage":{"input_tokens":7,"output_tokens":5,"total_tokens":12}}"#,
        providerEventType: "usage",
        normalizedEventKind: "usage"
      ))
    sink.runDidComplete(
      AgentRunResult(
        context: context,
        sessionID: startInfo.sessionID,
        finalState: .succeeded,
        eventCount: 3,
        error: nil
      ))

    let expectedUsage = try TokenUsage(inputTokens: 7, outputTokens: 5, totalTokens: 12)
    let runDetail = try #require(try store.runDetail(id: context.runID))
    #expect(runDetail.providerSessionID == "provider-session-5")
    #expect(runDetail.providerRunID == "provider-run-5")
    #expect(runDetail.lastAgentMessage == "hello from claude")
    #expect(runDetail.tokens == expectedUsage)
    #expect(runDetail.logs.eventCount == 3)
    #expect(runDetail.logs.latestSequence == EventSequence(3))

    let session = try #require(try store.session(sessionID: startInfo.sessionID))
    #expect(session.providerSessionID == "provider-session-5")
    #expect(session.providerThreadID == "thread-5")
    #expect(session.providerTurnID == "turn-5")
    #expect(session.providerRunID == "provider-run-5")
    #expect(session.tokenUsage == expectedUsage)
    #expect(session.latestRateLimitPayload == #"{"remaining":100}"#)

    let reopenedStore = try SQLiteServerStateStore(databaseURL: databaseURL)
    let reopenedRunDetail = try #require(try reopenedStore.runDetail(id: context.runID))
    #expect(reopenedRunDetail.providerSessionID == "provider-session-5")
    #expect(reopenedRunDetail.providerRunID == "provider-run-5")
    #expect(reopenedRunDetail.lastAgentMessage == "hello from claude")
    #expect(reopenedRunDetail.tokens == expectedUsage)
    #expect(reopenedRunDetail.logs.latestSequence == EventSequence(3))

    let reopenedSession = try #require(try reopenedStore.session(sessionID: startInfo.sessionID))
    #expect(reopenedSession.providerThreadID == "thread-5")
    #expect(reopenedSession.providerTurnID == "turn-5")
    #expect(reopenedSession.latestRateLimitPayload == #"{"remaining":100}"#)
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
