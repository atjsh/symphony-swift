import Foundation
import SymphonyShared
import Testing

@testable import SymphonySwiftUIApp

@MainActor
@Suite("OperatorModel – Selection", .tags(.model))
struct OperatorModelSelectionTests {
  @Test func SelectingIssueResetsDetailTabAndLogFilterToOverviewAndAll() async throws {
    let client = MockSymphonyAPIClient()
    let issueSummary = makeIssueSummary()
    client.issueDetailResponse = makeIssueDetail()
    client.runDetailResponse = makeRunDetail()
    client.logsResponse = LogEntriesResponse(
      sessionID: SessionID("session-42"),
      provider: "claude_code",
      items: [],
      nextCursor: nil,
      hasMore: false
    )

    let model = SymphonyOperatorModel(client: client)
    model.selectedDetailTab = .logs
    model.selectedLogFilter = .alerts

    await model.selectIssue(issueSummary)

    #expect(model.selectedDetailTab == .overview)
    #expect(model.selectedLogFilter == .all)
  }

  @Test func SelectingIssueLoadsRunDetailHistoricalLogsAndLiveTail() async throws {
    let client = MockSymphonyAPIClient()
    let issueSummary = makeIssueSummary()
    client.healthResponse = HealthResponse(
      status: "ok", serverTime: "2026-03-24T12:00:00Z", version: "1.0.0", trackerKind: "github")
    client.issuesResponse = IssuesResponse(items: [issueSummary])
    client.issueDetailResponse = makeIssueDetail()
    client.runDetailResponse = makeRunDetail()
    client.logsResponse = LogEntriesResponse(
      sessionID: SessionID("session-42"),
      provider: "claude_code",
      items: [makeEvent(sequence: 1, kind: "message")],
      nextCursor: EventCursor(
        sessionID: SessionID("session-42"), lastDeliveredSequence: EventSequence(1)),
      hasMore: false
    )
    client.liveEvents = [
      makeEvent(sequence: 1, kind: "message"),
      makeEvent(sequence: 2, kind: "tool_call"),
    ]

    let model = SymphonyOperatorModel(client: client)
    await model.connect()
    await model.selectIssue(issueSummary)
    for _ in 0..<20 where model.logEvents.count < 2 {
      try await Task.sleep(for: .milliseconds(50))
    }

    #expect(model.issueDetail?.issue.id.rawValue == "issue-42")
    #expect(model.runDetail?.runID.rawValue == "run-42")
    #expect(model.logEvents.map(\.sequence.rawValue) == [1, 2])
    #expect(model.logEvents.last?.normalizedKind == .toolCall)
  }

  @Test func SelectIssueAndSelectRunFailuresCoverIssueLogsAndInvalidEndpointBranches() async throws
  {
    let client = MockSymphonyAPIClient()
    let model = SymphonyOperatorModel(
      client: client,
      initialEndpoint: try ServerEndpoint(host: "localhost", port: 8080)
    )

    model.portText = "bad-port"
    await model.selectIssue(makeIssueSummary())
    #expect(model.connectionError == SymphonyClientError.invalidEndpoint.localizedDescription)

    await model.selectRun(RunID("run-42"))
    #expect(model.connectionError == SymphonyClientError.invalidEndpoint.localizedDescription)

    model.portText = "8080"
    client.issueDetailError = TestModelFailure.failed("issue detail")
    await model.selectIssue(makeIssueSummary())
    #expect(model.connectionError == "issue detail")

    client.issueDetailError = nil
    client.runDetailResponse = makeRunDetail()
    client.logsError = TestModelFailure.failed("logs")
    await model.selectRun(RunID("run-42"))
    #expect(model.connectionError == "logs")
  }

  @Test func SelectIssueWithoutLatestRunClearsRunAndLogs() async throws {
    let client = MockSymphonyAPIClient()
    let issueSummary = makeIssueSummary()
    client.issueDetailResponse = IssueDetail(
      issue: makeIssueDetail().issue,
      latestRun: nil,
      workspacePath: "/tmp/symphony/atjsh_example_42",
      recentSessions: []
    )

    let model = SymphonyOperatorModel(client: client)
    model.logEvents = [makeEvent(sequence: 1, kind: "message")]
    model.runDetail = makeRunDetail()
    model.selectedRunID = RunID("run-42")
    model.liveStatus = "Live"

    await model.selectIssue(issueSummary)

    #expect(model.selectedRunID == nil)
    #expect(model.runDetail == nil)
    #expect(model.logEvents.isEmpty)
    #expect(model.liveStatus == "Idle")
  }

  @Test func SelectRunWithoutSessionAndLiveStreamErrorsUpdateStatus() async throws {
    let client = MockSymphonyAPIClient()
    client.runDetailResponse = RunDetail(
      runID: RunID("run-42"),
      issueID: IssueID("issue-42"),
      issueIdentifier: try! IssueIdentifier(validating: "atjsh/example#42"),
      attempt: 1,
      status: "running",
      provider: "claude_code",
      providerSessionID: nil,
      providerRunID: nil,
      startedAt: "2026-03-24T03:00:00Z",
      endedAt: nil,
      workspacePath: "/tmp/symphony/atjsh_example_42",
      sessionID: nil,
      lastError: nil,
      issue: makeIssueDetail().issue,
      turnCount: 0,
      lastAgentEventType: nil,
      lastAgentMessage: nil,
      tokens: try! TokenUsage(),
      logs: RunLogStats(eventCount: 0, latestSequence: nil)
    )

    let model = SymphonyOperatorModel(client: client)
    model.logEvents = [makeEvent(sequence: 3, kind: "message")]
    model.liveStatus = "Live"
    await model.selectRun(RunID("run-42"))

    #expect(model.logEvents.isEmpty)
    #expect(model.liveStatus == "No session")

    client.runDetailResponse = makeRunDetail()
    client.logsResponse = LogEntriesResponse(
      sessionID: SessionID("session-42"),
      provider: "claude_code",
      items: [makeEvent(sequence: 2, kind: "status")],
      nextCursor: nil,
      hasMore: false
    )
    client.streamError = TestModelFailure.failed("stream")

    await model.selectRun(RunID("run-42"))
    for _ in 0..<20 where model.liveStatus == "Connecting live stream" || model.liveStatus == "Live"
    {
      try await Task.sleep(for: .milliseconds(20))
    }

    #expect(model.liveStatus == "stream")
  }

  @Test func SelectRunFailureSetsConnectionErrorAndPresentationExtractsFallbackContent()
    async throws
  {
    let client = MockSymphonyAPIClient()
    client.runDetailError = TestModelFailure.failed("run detail")

    let model = SymphonyOperatorModel(client: client)
    await model.selectRun(RunID("run-42"))
    #expect(model.connectionError == "run detail")

    let nested = SymphonyEventPresentation(
      event: AgentRawEvent(
        sessionID: SessionID("session-42"),
        provider: "claude_code",
        sequence: EventSequence(9),
        timestamp: "2026-03-24T03:00:09Z",
        rawJSON: #"{"payload":[{"output":7}]}"#,
        providerEventType: "usage",
        normalizedEventKind: "usage"
      ))
    #expect(nested.detail == "7")

    let fallback = SymphonyEventPresentation(
      event: AgentRawEvent(
        sessionID: SessionID("session-42"),
        provider: "claude_code",
        sequence: EventSequence(10),
        timestamp: "2026-03-24T03:00:10Z",
        rawJSON: #"{"payload":{}}"#,
        providerEventType: "status_update",
        normalizedEventKind: "status"
      ))
    #expect(fallback.detail == "status_update")
  }

  @Test func TestingSelectedIssueSummaryCoversMatchedAndMissingSelections() {
    let model = SymphonyOperatorModel(client: MockSymphonyAPIClient())
    let selectedIssue = makeIssueSummary()
    let otherIssue = IssueSummary(
      issueID: IssueID("issue-84"),
      identifier: try! IssueIdentifier(validating: "atjsh/example#84"),
      title: "Other issue",
      state: "queued",
      issueState: "OPEN",
      priority: 2,
      currentProvider: nil,
      currentRunID: nil,
      currentSessionID: nil
    )

    #expect(model.testingSelectedIssueSummary(
        restoring: selectedIssue.issueID,
        in: [otherIssue, selectedIssue]
      ) == selectedIssue)
    #expect(
      model.testingSelectedIssueSummary(
        restoring: selectedIssue.issueID,
        in: [otherIssue]
      ) == nil
    )
    #expect(model.testingSelectedIssueSummary(restoring: nil, in: [selectedIssue]) == nil)
  }
}
