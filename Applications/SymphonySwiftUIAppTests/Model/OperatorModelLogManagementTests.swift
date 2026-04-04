import Foundation
import SymphonyShared
import Testing

@testable import SymphonySwiftUIApp

@MainActor
@Suite("OperatorModel – Log Management", .tags(.model))
struct OperatorModelLogManagementTests {
  @Test func FilteredIssuesApplySearchAndKeepSelectedIssueVisible() throws {
    let model = SymphonyOperatorModel(client: MockSymphonyAPIClient())
    let selected = makeIssueSummary()
    let other = IssueSummary(
      issueID: IssueID("issue-84"),
      identifier: try IssueIdentifier(validating: "atjsh/example#84"),
      title: "Endpoint editor polish",
      state: "queued",
      issueState: "OPEN",
      priority: 2,
      currentProvider: "codex",
      currentRunID: RunID("run-84"),
      currentSessionID: SessionID("session-84")
    )
    let unassigned = IssueSummary(
      issueID: IssueID("issue-85"),
      identifier: try IssueIdentifier(validating: "atjsh/example#85"),
      title: "Unassigned search coverage",
      state: "queued",
      issueState: "OPEN",
      priority: nil,
      currentProvider: nil,
      currentRunID: nil,
      currentSessionID: nil
    )
    model.issues = [selected, other, unassigned]
    model.selectedIssueID = selected.issueID

    model.issueSearchText = "endpoint"

    #expect(model.filteredIssues.map(\.issueID.rawValue) == ["issue-42", "issue-84"])

    model.issueSearchText = "unassigned"

    #expect(model.filteredIssues.map(\.issueID.rawValue) == ["issue-42", "issue-85"])
  }

  @Test func FilteredVisibleLogEventsApplySelectedLogFilter() {
    let model = SymphonyOperatorModel(client: MockSymphonyAPIClient())

    model.testingMergeLogEvents([
      makeEvent(sequence: 1, kind: "message"),
      makeEvent(sequence: 2, kind: "tool_call"),
      makeEvent(sequence: 3, kind: "tool_result"),
      makeEvent(sequence: 4, kind: "approval_request"),
      makeEvent(sequence: 5, kind: "error"),
    ])

    model.selectedLogFilter = .messages
    #expect(model.filteredVisibleLogEvents.map(\.sequence.rawValue) == [1])

    model.selectedLogFilter = .tools
    #expect(model.filteredVisibleLogEvents.map(\.sequence.rawValue) == [2, 3])

    model.selectedLogFilter = .alerts
    #expect(model.filteredVisibleLogEvents.map(\.sequence.rawValue) == [4, 5])
  }

  @Test func VisibleLogEventsHideNoiseAndKeepRelevantEvents() {
    let model = SymphonyOperatorModel(client: MockSymphonyAPIClient())

    model.testingMergeLogEvents([
      AgentRawEvent(
        sessionID: SessionID("session-42"),
        provider: "codex",
        sequence: EventSequence(1),
        timestamp: "2026-03-24T03:00:01Z",
        rawJSON: #"{"method":"item/agentMessage/delta","params":{"delta":"partial"}}"#,
        providerEventType: "item/agentMessage/delta",
        normalizedEventKind: "message"
      ),
      AgentRawEvent(
        sessionID: SessionID("session-42"),
        provider: "codex",
        sequence: EventSequence(2),
        timestamp: "2026-03-24T03:00:02Z",
        rawJSON:
          #"{"method":"thread/tokenUsage/updated","params":{"tokenUsage":{"total":{"totalTokens":42}}}}"#,
        providerEventType: "thread/tokenUsage/updated",
        normalizedEventKind: "usage"
      ),
      AgentRawEvent(
        sessionID: SessionID("session-42"),
        provider: "codex",
        sequence: EventSequence(3),
        timestamp: "2026-03-24T03:00:03Z",
        rawJSON: #"{"method":"skills/changed","params":{}}"#,
        providerEventType: "skills/changed",
        normalizedEventKind: "status"
      ),
      AgentRawEvent(
        sessionID: SessionID("session-42"),
        provider: "codex",
        sequence: EventSequence(4),
        timestamp: "2026-03-24T03:00:04Z",
        rawJSON:
          #"{"method":"item/started","params":{"item":{"type":"commandExecution","command":"git status --short"}}}"#,
        providerEventType: "item/started",
        normalizedEventKind: "tool_call"
      ),
      AgentRawEvent(
        sessionID: SessionID("session-42"),
        provider: "codex",
        sequence: EventSequence(5),
        timestamp: "2026-03-24T03:00:05Z",
        rawJSON:
          #"{"method":"item/completed","params":{"item":{"type":"agentMessage","text":"done"}}}"#,
        providerEventType: "item/completed",
        normalizedEventKind: "message"
      ),
      AgentRawEvent(
        sessionID: SessionID("session-42"),
        provider: "codex",
        sequence: EventSequence(6),
        timestamp: "2026-03-24T03:00:05Z",
        rawJSON:
          #"{"method":"item/started","params":{"item":{"type":"agentMessage","id":"msg_42","text":"","phase":"commentary","memoryCitation":null},"threadId":"thread-42","turnId":"turn-42"}}"#,
        providerEventType: "item/started",
        normalizedEventKind: "message"
      ),
      AgentRawEvent(
        sessionID: SessionID("session-42"),
        provider: "codex",
        sequence: EventSequence(7),
        timestamp: "2026-03-24T03:00:06Z",
        rawJSON:
          #"{"method":"item/commandExecution/requestApproval","params":{"reason":"allow git rev-parse"}}"#,
        providerEventType: "item/commandExecution/requestApproval",
        normalizedEventKind: "approval_request"
      ),
    ])

    #expect(model.logEvents.map(\.sequence.rawValue) == [1, 2, 3, 4, 5, 6, 7])
    #expect(model.visibleLogEvents.map(\.sequence.rawValue) == [4, 5, 7])
  }

  @Test func LiveStreamCancellationOnDeinitAndOutOfOrderEventsAreSorted() async throws {
    let client = MockSymphonyAPIClient()
    client.runDetailResponse = makeRunDetail()
    client.logsResponse = LogEntriesResponse(
      sessionID: SessionID("session-42"),
      provider: "claude_code",
      items: [makeEvent(sequence: 2, kind: "message")],
      nextCursor: EventCursor(
        sessionID: SessionID("session-42"), lastDeliveredSequence: EventSequence(2)),
      hasMore: false
    )
    client.liveEvents = [makeEvent(sequence: 1, kind: "tool_call")]

    let sortedModel = SymphonyOperatorModel(client: client)
    await sortedModel.selectRun(RunID("run-42"))
    try await waitUntil("events sorted") { sortedModel.logEvents.count >= 2 }
    #expect(sortedModel.logEvents.map(\.sequence.rawValue) == [1, 2])

    let hangingClient = MockSymphonyAPIClient()
    hangingClient.runDetailResponse = makeRunDetail()
    hangingClient.logsResponse = LogEntriesResponse(
      sessionID: SessionID("session-42"),
      provider: "claude_code",
      items: [],
      nextCursor: nil,
      hasMore: false
    )
    hangingClient.suspendStream = true

    weak var weakModel: SymphonyOperatorModel?
    do {
      var model: SymphonyOperatorModel? = SymphonyOperatorModel(client: hangingClient)
      weakModel = model
      await model?.selectRun(RunID("run-42"))
      try await waitUntil("stream starts") { hangingClient.streamStartCount > 0 }
      model = nil
    }

    try await waitUntil("model deallocated") {
      weakModel == nil && hangingClient.streamTerminationCount > 0
    }

    #expect(weakModel == nil)
    #expect(hangingClient.streamTerminationCount == 1)
  }

  @Test func TestingLogHelpersAppendMergeDeduplicateAndAdvanceCursor() {
    let client = MockSymphonyAPIClient()
    let model = SymphonyOperatorModel(client: client)
    let third = makeEvent(sequence: 3, kind: "status")
    let first = makeEvent(sequence: 1, kind: "message")
    let duplicateThird = makeEvent(sequence: 3, kind: "status")
    let fourth = makeEvent(sequence: 4, kind: "tool_result")

    model.testingMergeLogEvents([third, first, duplicateThird])
    #expect(model.logEvents.map(\.sequence.rawValue) == [1, 3])

    model.testingAppendLogEvent(fourth)
    #expect(model.logEvents.map(\.sequence.rawValue) == [1, 3, 4])
    #expect(model.testingLogCursor == EventCursor(sessionID: fourth.sessionID, lastDeliveredSequence: fourth.sequence))
  }
}
