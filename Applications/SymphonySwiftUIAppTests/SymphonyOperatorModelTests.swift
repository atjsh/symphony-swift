import Foundation
import SymphonyShared
import Testing

@testable import SymphonySwiftUIApp

@MainActor
@Suite("SymphonyOperatorModel")
struct SymphonyOperatorModelTests {
  @Test func DefaultInitializerUsesOverviewTabAllLogFilterAndEmptySearch() {
    let model = SymphonyOperatorModel()

    XCTAssertEqual(model.issueSearchText, "")
    XCTAssertEqual(model.selectedDetailTab, .overview)
    XCTAssertEqual(model.selectedLogFilter, .all)
    XCTAssertTrue(model.filteredIssues.isEmpty)
    XCTAssertTrue(model.filteredVisibleLogEvents.isEmpty)
  }

  @Test func DefaultInitializerUsesDefaultEndpointAndIdleState() {
    let model = SymphonyOperatorModel()

    XCTAssertEqual(model.host, "localhost")
    XCTAssertEqual(model.portText, "8080")
    XCTAssertNil(model.health)
    XCTAssertTrue(model.issues.isEmpty)
    XCTAssertTrue(model.logEvents.isEmpty)
    XCTAssertFalse(model.isConnecting)
    XCTAssertFalse(model.isRefreshing)
    XCTAssertEqual(model.liveStatus, "Idle")
  }

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

    XCTAssertEqual(model.filteredIssues.map(\.issueID.rawValue), ["issue-42", "issue-84"])

    model.issueSearchText = "unassigned"

    XCTAssertEqual(model.filteredIssues.map(\.issueID.rawValue), ["issue-42", "issue-85"])
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
    XCTAssertEqual(model.filteredVisibleLogEvents.map(\.sequence.rawValue), [1])

    model.selectedLogFilter = .tools
    XCTAssertEqual(model.filteredVisibleLogEvents.map(\.sequence.rawValue), [2, 3])

    model.selectedLogFilter = .alerts
    XCTAssertEqual(model.filteredVisibleLogEvents.map(\.sequence.rawValue), [4, 5])
  }

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

    XCTAssertEqual(model.selectedDetailTab, .overview)
    XCTAssertEqual(model.selectedLogFilter, .all)
  }

  @Test func ConnectLoadsHealthAndIssuesFromConfiguredEndpoint() async throws {
    let client = MockSymphonyAPIClient()
    client.healthResponse = HealthResponse(
      status: "ok", serverTime: "2026-03-24T12:00:00Z", version: "1.0.0", trackerKind: "github")
    client.issuesResponse = IssuesResponse(items: [makeIssueSummary()])

    let model = SymphonyOperatorModel(
      client: client,
      initialEndpoint: try ServerEndpoint(host: "localhost", port: 8080)
    )

    await model.connect()

    XCTAssertEqual(client.recordedHosts, ["localhost", "localhost"])
    XCTAssertEqual(model.health?.trackerKind, "github")
    XCTAssertEqual(model.issues.map(\.issueID.rawValue), ["issue-42"])
    XCTAssertNil(model.connectionError)
  }

  @Test func InitialStateServerEndpointResolutionAndConnectCanRestoreSelection() async throws {
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
      items: [],
      nextCursor: nil,
      hasMore: false
    )

    let model = SymphonyOperatorModel(
      client: client,
      initialEndpoint: try ServerEndpoint(scheme: "https", host: "example.com", port: 9443)
    )

    XCTAssertEqual(model.host, "example.com")
    XCTAssertEqual(model.portText, "9443")
    XCTAssertNil(model.health)
    XCTAssertTrue(model.issues.isEmpty)
    XCTAssertTrue(model.logEvents.isEmpty)
    XCTAssertEqual(model.liveStatus, "Idle")
    XCTAssertEqual(model.serverEndpoint, try ServerEndpoint(host: "example.com", port: 9443))

    model.selectedIssueID = issueSummary.issueID
    await model.connect()
    for _ in 0..<20 where model.liveStatus != "Ended" {
      try await Task.sleep(for: .milliseconds(20))
    }

    XCTAssertEqual(client.issueDetailRequests, [IssueID("issue-42")])
    XCTAssertEqual(model.issueDetail?.issue.id, IssueID("issue-42"))
    XCTAssertEqual(model.runDetail?.runID, RunID("run-42"))
    XCTAssertEqual(model.liveStatus, "Ended")

    model.host = ""
    XCTAssertNil(model.serverEndpoint)
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

    XCTAssertEqual(model.issueDetail?.issue.id.rawValue, "issue-42")
    XCTAssertEqual(model.runDetail?.runID.rawValue, "run-42")
    XCTAssertEqual(model.logEvents.map(\.sequence.rawValue), [1, 2])
    XCTAssertEqual(model.logEvents.last?.normalizedKind, .toolCall)
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

    XCTAssertEqual(model.logEvents.map(\.sequence.rawValue), [1, 2, 3, 4, 5, 6, 7])
    XCTAssertEqual(model.visibleLogEvents.map(\.sequence.rawValue), [4, 5, 7])
  }

  @Test func RefreshReloadsIssuesAndRetainsSelection() async throws {
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
      items: [],
      nextCursor: nil,
      hasMore: false
    )

    let model = SymphonyOperatorModel(client: client)
    await model.connect()
    await model.selectIssue(issueSummary)

    client.issuesResponse = IssuesResponse(items: [
      issueSummary,
      IssueSummary(
        issueID: IssueID("issue-84"),
        identifier: try IssueIdentifier(validating: "atjsh/example#84"),
        title: "Second issue",
        state: "queued",
        issueState: "OPEN",
        priority: 2,
        currentProvider: nil,
        currentRunID: nil,
        currentSessionID: nil
      ),
    ])

    await model.refresh()

    XCTAssertEqual(client.refreshCallCount, 1)
    XCTAssertEqual(model.issues.map(\.issueID.rawValue), ["issue-42", "issue-84"])
    XCTAssertEqual(model.selectedIssueID?.rawValue, "issue-42")
  }

  @Test func RefreshWithMatchingSelectionReloadsSelectedIssueDetail() async throws {
    let client = MockSymphonyAPIClient()
    let issueSummary = makeIssueSummary()
    client.issuesResponse = IssuesResponse(items: [issueSummary])
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
    model.selectedIssueID = issueSummary.issueID

    await model.refresh()
    try await waitUntil {
      model.issueDetail?.issue.id == issueSummary.issueID && model.liveStatus == "Ended"
    }

    XCTAssertEqual(client.issueDetailRequests, [issueSummary.issueID])
    XCTAssertEqual(model.runDetail?.runID, RunID("run-42"))
  }

  @Test func RefreshWithMissingSelectionDoesNotReloadIssueDetail() async {
    let client = MockSymphonyAPIClient()
    client.issuesResponse = IssuesResponse(items: [
      IssueSummary(
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
    ])

    let model = SymphonyOperatorModel(client: client)
    model.selectedIssueID = IssueID("issue-42")

    await model.refresh()

    XCTAssertTrue(client.issueDetailRequests.isEmpty)
    XCTAssertEqual(model.selectedIssueID, IssueID("issue-42"))
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

    XCTAssertEqual(
      model.testingSelectedIssueSummary(
        restoring: selectedIssue.issueID,
        in: [otherIssue, selectedIssue]
      ),
      selectedIssue
    )
    XCTAssertNil(
      model.testingSelectedIssueSummary(
        restoring: selectedIssue.issueID,
        in: [otherIssue]
      )
    )
    XCTAssertNil(model.testingSelectedIssueSummary(restoring: nil, in: [selectedIssue]))
  }

  @Test func RefreshReusesLastDeliveredCursorForSelectedRun() async throws {
    let client = MockSymphonyAPIClient()
    let issueSummary = makeIssueSummary()
    let firstCursor = EventCursor(
      sessionID: SessionID("session-42"), lastDeliveredSequence: EventSequence(2))
    let secondCursor = EventCursor(
      sessionID: SessionID("session-42"), lastDeliveredSequence: EventSequence(3))
    let firstEvent = makeEvent(sequence: 1, kind: "message")
    let secondEvent = makeEvent(sequence: 2, kind: "tool_call")
    let thirdEvent = makeEvent(sequence: 3, kind: "tool_result")
    let fourthEvent = makeEvent(sequence: 4, kind: "status")

    client.healthResponse = HealthResponse(
      status: "ok", serverTime: "2026-03-24T12:00:00Z", version: "1.0.0", trackerKind: "github")
    client.issuesResponse = IssuesResponse(items: [issueSummary])
    client.issueDetailResponse = makeIssueDetail()
    client.runDetailResponse = makeRunDetail()
    client.logsResponse = LogEntriesResponse(
      sessionID: SessionID("session-42"),
      provider: "claude_code",
      items: [firstEvent, secondEvent],
      nextCursor: firstCursor,
      hasMore: false
    )

    let model = SymphonyOperatorModel(client: client)
    await model.connect()
    await model.selectIssue(issueSummary)
    try await waitUntil {
      model.logEvents.map(\.sequence.rawValue) == [1, 2] && model.liveStatus == "Ended"
    }

    client.logsResponse = LogEntriesResponse(
      sessionID: SessionID("session-42"),
      provider: "claude_code",
      items: [thirdEvent],
      nextCursor: secondCursor,
      hasMore: false
    )
    client.liveEvents = [fourthEvent]

    await model.refresh()
    try await waitUntil {
      model.logEvents.map(\.sequence.rawValue) == [1, 2, 3, 4] && model.liveStatus == "Ended"
    }

    XCTAssertEqual(client.logRequests.count, 2)
    XCTAssertNil(client.logRequests[0].cursor)
    XCTAssertEqual(client.logRequests[1].cursor, firstCursor)
    XCTAssertEqual(client.streamRequests.count, 2)
    XCTAssertEqual(client.streamRequests[0].cursor, firstCursor)
    XCTAssertEqual(client.streamRequests[1].cursor, secondCursor)
  }

  @Test func RefreshStartedBeforeSelectionDoesNotRerequestIssueDetail() async throws {
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
      items: [],
      nextCursor: nil,
      hasMore: false
    )
    client.suspendRefresh = true

    let model = SymphonyOperatorModel(client: client)
    await model.connect()

    let refreshTask = Task {
      await model.refresh()
    }

    try await waitUntil {
      client.refreshCallCount == 1 && model.isRefreshing
    }

    await model.selectIssue(issueSummary)
    client.resumeRefresh()
    await refreshTask.value

    try await waitUntil {
      model.issueDetail?.issue.id == IssueID("issue-42")
        && model.runDetail?.runID == RunID("run-42")
        && model.liveStatus == "Ended"
    }

    XCTAssertEqual(client.issueDetailRequests, [IssueID("issue-42")])
  }

  @Test func InvalidEndpointAndFailuresUpdateConnectionState() async throws {
    let client = MockSymphonyAPIClient()
    client.healthError = TestModelFailure.failed("health")

    let model = SymphonyOperatorModel(
      client: client,
      initialEndpoint: try ServerEndpoint(host: "localhost", port: 8080)
    )
    model.portText = "invalid"

    await model.connect()
    XCTAssertEqual(model.connectionError, SymphonyClientError.invalidEndpoint.localizedDescription)

    model.portText = "8080"
    await model.connect()
    XCTAssertNil(model.health)
    XCTAssertTrue(model.issues.isEmpty)
    XCTAssertEqual(model.connectionError, "health")

    client.healthError = nil
    client.refreshError = TestModelFailure.failed("refresh")
    await model.refresh()
    XCTAssertEqual(model.connectionError, "refresh")
  }

  @Test func ConnectSurfacesServerEnvelopeMessage() async throws {
    let client = MockSymphonyAPIClient()
    client.healthError = SymphonyClientError.serverEnvelope(
      statusCode: 404,
      code: "issue_not_found",
      message: "Issue issue-42 was not found."
    )

    let model = SymphonyOperatorModel(
      client: client,
      initialEndpoint: try ServerEndpoint(host: "localhost", port: 8080)
    )

    await model.connect()

    XCTAssertEqual(model.connectionError, "Issue issue-42 was not found.")
  }

  @Test func ConnectAndRefreshFailuresClearStateAndRespectInvalidEndpoints() async throws {
    let client = MockSymphonyAPIClient()
    client.healthResponse = HealthResponse(
      status: "ok", serverTime: "2026-03-24T12:00:00Z", version: "1.0.0", trackerKind: "github")
    client.issuesError = TestModelFailure.failed("issues")

    let model = SymphonyOperatorModel(
      client: client,
      initialEndpoint: try ServerEndpoint(host: "localhost", port: 8080)
    )
    model.health = HealthResponse(
      status: "stale", serverTime: "2026-03-24T00:00:00Z", version: "0.9.0", trackerKind: "github")
    model.issues = [makeIssueSummary()]

    await model.connect()

    XCTAssertNil(model.health)
    XCTAssertTrue(model.issues.isEmpty)
    XCTAssertEqual(model.connectionError, "issues")
    XCTAssertFalse(model.isConnecting)

    model.portText = "invalid"
    await model.refresh()
    XCTAssertEqual(model.connectionError, SymphonyClientError.invalidEndpoint.localizedDescription)
    XCTAssertFalse(model.isRefreshing)

    model.portText = "8080"
    client.issuesError = TestModelFailure.failed("refresh issues")
    await model.refresh()
    XCTAssertEqual(model.connectionError, "refresh issues")
    XCTAssertFalse(model.isRefreshing)
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
    XCTAssertEqual(model.connectionError, SymphonyClientError.invalidEndpoint.localizedDescription)

    await model.selectRun(RunID("run-42"))
    XCTAssertEqual(model.connectionError, SymphonyClientError.invalidEndpoint.localizedDescription)

    model.portText = "8080"
    client.issueDetailError = TestModelFailure.failed("issue detail")
    await model.selectIssue(makeIssueSummary())
    XCTAssertEqual(model.connectionError, "issue detail")

    client.issueDetailError = nil
    client.runDetailResponse = makeRunDetail()
    client.logsError = TestModelFailure.failed("logs")
    await model.selectRun(RunID("run-42"))
    XCTAssertEqual(model.connectionError, "logs")
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

    XCTAssertNil(model.selectedRunID)
    XCTAssertNil(model.runDetail)
    XCTAssertTrue(model.logEvents.isEmpty)
    XCTAssertEqual(model.liveStatus, "Idle")
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

    XCTAssertTrue(model.logEvents.isEmpty)
    XCTAssertEqual(model.liveStatus, "No session")

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

    XCTAssertEqual(model.liveStatus, "stream")
  }

  @Test func SelectRunFailureSetsConnectionErrorAndPresentationExtractsFallbackContent()
    async throws
  {
    let client = MockSymphonyAPIClient()
    client.runDetailError = TestModelFailure.failed("run detail")

    let model = SymphonyOperatorModel(client: client)
    await model.selectRun(RunID("run-42"))
    XCTAssertEqual(model.connectionError, "run detail")

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
    XCTAssertEqual(nested.detail, "7")

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
    XCTAssertEqual(fallback.detail, "status_update")
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
    for _ in 0..<20 where sortedModel.logEvents.count < 2 {
      try await Task.sleep(for: .milliseconds(20))
    }
    XCTAssertEqual(sortedModel.logEvents.map(\.sequence.rawValue), [1, 2])

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
      for _ in 0..<20 where hangingClient.streamStartCount == 0 {
        try await Task.sleep(for: .milliseconds(20))
      }
      model = nil
    }

    for _ in 0..<20 where weakModel != nil || hangingClient.streamTerminationCount == 0 {
      try await Task.sleep(for: .milliseconds(20))
    }

    XCTAssertNil(weakModel)
    XCTAssertEqual(hangingClient.streamTerminationCount, 1)
  }

  @Test func TestingLogHelpersAppendMergeDeduplicateAndAdvanceCursor() {
    let client = MockSymphonyAPIClient()
    let model = SymphonyOperatorModel(client: client)
    let third = makeEvent(sequence: 3, kind: "status")
    let first = makeEvent(sequence: 1, kind: "message")
    let duplicateThird = makeEvent(sequence: 3, kind: "status")
    let fourth = makeEvent(sequence: 4, kind: "tool_result")

    model.testingMergeLogEvents([third, first, duplicateThird])
    XCTAssertEqual(model.logEvents.map(\.sequence.rawValue), [1, 3])

    model.testingAppendLogEvent(fourth)
    XCTAssertEqual(model.logEvents.map(\.sequence.rawValue), [1, 3, 4])
    XCTAssertEqual(
      model.testingLogCursor,
      EventCursor(sessionID: fourth.sessionID, lastDeliveredSequence: fourth.sequence)
    )
  }

  @Test func EventPresentationCoversKnownKindsAndUnknownFallback() {
    let message = SymphonyEventPresentation(event: makeEvent(sequence: 1, kind: "message"))
    XCTAssertEqual(message.title, "Message")
    XCTAssertEqual(message.rowStyle, .message)
    XCTAssertFalse(message.showsRawJSON)

    let messageFallback = SymphonyEventPresentation(
      event: AgentRawEvent(
        sessionID: SessionID("session-42"),
        provider: "claude_code",
        sequence: EventSequence(16),
        timestamp: "2026-03-24T03:00:16Z",
        rawJSON: #"{"payload":{}}"#,
        providerEventType: "message_fallback",
        normalizedEventKind: "message"
      ))
    XCTAssertEqual(messageFallback.detail, "message_fallback")

    let codexCompletedMessage = SymphonyEventPresentation(
      event: AgentRawEvent(
        sessionID: SessionID("session-42"),
        provider: "codex",
        sequence: EventSequence(21),
        timestamp: "2026-03-24T03:00:21Z",
        rawJSON:
          #"{"method":"item/completed","params":{"item":{"type":"agentMessage","id":"msg_1","text":"Hello from Codex","phase":"commentary","memoryCitation":null},"threadId":"thread-1","turnId":"turn-1"}}"#,
        providerEventType: "item/completed",
        normalizedEventKind: "message"
      ))
    XCTAssertEqual(codexCompletedMessage.detail, "Hello from Codex")
    XCTAssertEqual(codexCompletedMessage.rowStyle, .message)

    let toolCall = SymphonyEventPresentation(event: makeEvent(sequence: 2, kind: "tool_call"))
    XCTAssertEqual(toolCall.title, "Tool Call")
    XCTAssertEqual(toolCall.rowStyle, .tool)

    let codexToolCall = SymphonyEventPresentation(
      event: AgentRawEvent(
        sessionID: SessionID("session-42"),
        provider: "codex",
        sequence: EventSequence(22),
        timestamp: "2026-03-24T03:00:22Z",
        rawJSON:
          #"{"method":"item/started","params":{"item":{"type":"commandExecution","id":"call_1","command":"/bin/zsh -lc pwd","cwd":"/tmp","processId":"1","status":"inProgress","commandActions":[],"aggregatedOutput":null,"exitCode":null,"durationMs":null},"threadId":"thread-1","turnId":"turn-1"}}"#,
        providerEventType: "item/started",
        normalizedEventKind: "tool_call"
      ))
    XCTAssertEqual(codexToolCall.detail, "/bin/zsh -lc pwd")
    XCTAssertEqual(codexToolCall.rowStyle, .tool)

    let toolCallFallback = SymphonyEventPresentation(
      event: AgentRawEvent(
        sessionID: SessionID("session-42"),
        provider: "claude_code",
        sequence: EventSequence(17),
        timestamp: "2026-03-24T03:00:17Z",
        rawJSON: #"{"payload":{}}"#,
        providerEventType: "tool_call_fallback",
        normalizedEventKind: "tool_call"
      ))
    XCTAssertEqual(toolCallFallback.detail, "tool_call_fallback")

    let toolResult = SymphonyEventPresentation(event: makeEvent(sequence: 3, kind: "tool_result"))
    XCTAssertEqual(toolResult.title, "Tool Result")
    XCTAssertEqual(toolResult.rowStyle, .tool)

    let toolResultFallback = SymphonyEventPresentation(
      event: AgentRawEvent(
        sessionID: SessionID("session-42"),
        provider: "claude_code",
        sequence: EventSequence(18),
        timestamp: "2026-03-24T03:00:18Z",
        rawJSON: #"{"payload":{}}"#,
        providerEventType: "tool_result_fallback",
        normalizedEventKind: "tool_result"
      ))
    XCTAssertEqual(toolResultFallback.detail, "tool_result_fallback")

    let status = SymphonyEventPresentation(event: makeEvent(sequence: 4, kind: "status"))
    XCTAssertEqual(status.title, "Status")
    XCTAssertEqual(status.rowStyle, .compact)

    let codexStatus = SymphonyEventPresentation(
      event: AgentRawEvent(
        sessionID: SessionID("session-42"),
        provider: "codex",
        sequence: EventSequence(23),
        timestamp: "2026-03-24T03:00:23Z",
        rawJSON:
          #"{"method":"thread/status/changed","params":{"status":{"type":"active"},"threadId":"thread-1","turnId":"turn-1"}}"#,
        providerEventType: "thread/status/changed",
        normalizedEventKind: "status"
      ))
    XCTAssertEqual(codexStatus.detail, "active")
    XCTAssertEqual(codexStatus.rowStyle, .compact)

    let usage = SymphonyEventPresentation(event: makeEvent(sequence: 5, kind: "usage"))
    XCTAssertEqual(usage.title, "Usage")
    XCTAssertEqual(usage.rowStyle, .compact)

    let approval = SymphonyEventPresentation(
      event: makeEvent(sequence: 6, kind: "approval_request"))
    XCTAssertEqual(approval.title, "Approval Request")
    XCTAssertEqual(approval.rowStyle, .callout)

    let approvalFallback = SymphonyEventPresentation(
      event: AgentRawEvent(
        sessionID: SessionID("session-42"),
        provider: "claude_code",
        sequence: EventSequence(19),
        timestamp: "2026-03-24T03:00:19Z",
        rawJSON: #"{"payload":{}}"#,
        providerEventType: "approval_fallback",
        normalizedEventKind: "approval_request"
      ))
    XCTAssertEqual(approvalFallback.detail, #"{"payload":{}}"#)

    let error = SymphonyEventPresentation(event: makeEvent(sequence: 7, kind: "error"))
    XCTAssertEqual(error.title, "Error")
    XCTAssertEqual(error.rowStyle, .callout)

    let errorFallback = SymphonyEventPresentation(
      event: AgentRawEvent(
        sessionID: SessionID("session-42"),
        provider: "claude_code",
        sequence: EventSequence(20),
        timestamp: "2026-03-24T03:00:20Z",
        rawJSON: #"{"payload":{}}"#,
        providerEventType: "error_fallback",
        normalizedEventKind: "error"
      ))
    XCTAssertEqual(errorFallback.detail, #"{"payload":{}}"#)

    let unknown = SymphonyEventPresentation(
      event: AgentRawEvent(
        sessionID: SessionID("session-42"),
        provider: "claude_code",
        sequence: EventSequence(8),
        timestamp: "2026-03-24T03:00:08Z",
        rawJSON: #"{"payload":{"notes":"inspect raw payload"}}"#,
        providerEventType: "provider_custom",
        normalizedEventKind: "unexpected_kind"
      ))
    XCTAssertEqual(unknown.title, "Unknown Event")
    XCTAssertEqual(unknown.rowStyle, .supplemental)
    XCTAssertEqual(unknown.detail, "inspect raw payload")
    XCTAssertTrue(unknown.showsRawJSON)

    let rawString = SymphonyEventPresentation(
      event: AgentRawEvent(
        sessionID: SessionID("session-42"),
        provider: "claude_code",
        sequence: EventSequence(11),
        timestamp: "2026-03-24T03:00:11Z",
        rawJSON: #"["hello"]"#,
        providerEventType: "message",
        normalizedEventKind: "message"
      ))
    XCTAssertEqual(rawString.detail, "hello")

    let arrayContent = SymphonyEventPresentation(
      event: AgentRawEvent(
        sessionID: SessionID("session-42"),
        provider: "claude_code",
        sequence: EventSequence(12),
        timestamp: "2026-03-24T03:00:12Z",
        rawJSON: #"[{"content":"inside"}]"#,
        providerEventType: "tool_result",
        normalizedEventKind: "tool_result"
      ))
    XCTAssertEqual(arrayContent.detail, "inside")

    let numeric = SymphonyEventPresentation(
      event: AgentRawEvent(
        sessionID: SessionID("session-42"),
        provider: "claude_code",
        sequence: EventSequence(13),
        timestamp: "2026-03-24T03:00:13Z",
        rawJSON: #"42"#,
        providerEventType: "usage",
        normalizedEventKind: "usage"
      ))
    XCTAssertEqual(numeric.detail, "42")

    let arrayFallback = SymphonyEventPresentation(
      event: AgentRawEvent(
        sessionID: SessionID("session-42"),
        provider: "claude_code",
        sequence: EventSequence(15),
        timestamp: "2026-03-24T03:00:15Z",
        rawJSON: #"[{}]"#,
        providerEventType: "usage",
        normalizedEventKind: "usage"
      ))
    XCTAssertEqual(arrayFallback.detail, #"[{}]"#)

    let invalidJSON = SymphonyEventPresentation(
      event: AgentRawEvent(
        sessionID: SessionID("session-42"),
        provider: "claude_code",
        sequence: EventSequence(14),
        timestamp: "2026-03-24T03:00:14Z",
        rawJSON: #"{invalid"#,
        providerEventType: "provider_status",
        normalizedEventKind: "status"
      ))
    XCTAssertEqual(invalidJSON.detail, "provider_status")
    XCTAssertTrue(invalidJSON.metadata.contains("claude code"))
  }

  @Test func EventPresentationCoversAdditionalCodexExtractionBranches() {
    XCTAssertTrue(
      SymphonyEventPresentation.isEmptyAgentMessageShell(
        event: AgentRawEvent(
          sessionID: SessionID("session-42"),
          provider: "codex",
          sequence: EventSequence(24),
          timestamp: "2026-03-24T03:00:24Z",
          rawJSON:
            #"{"params":{"item":{"type":"agentMessage","text":"   "}}}"#,
          providerEventType: "item/started",
          normalizedEventKind: "message"
        )))

    XCTAssertFalse(
      SymphonyEventPresentation.isEmptyAgentMessageShell(
        event: AgentRawEvent(
          sessionID: SessionID("session-42"),
          provider: "codex",
          sequence: EventSequence(25),
          timestamp: "2026-03-24T03:00:25Z",
          rawJSON:
            #"{"params":{"item":{"type":"agentMessage","text":"visible"}}}"#,
          providerEventType: "item/started",
          normalizedEventKind: "message"
        )))

    let delta = SymphonyEventPresentation(
      event: AgentRawEvent(
        sessionID: SessionID("session-42"),
        provider: "codex",
        sequence: EventSequence(26),
        timestamp: "2026-03-24T03:00:26Z",
        rawJSON:
          #"{"method":"item/agentMessage/delta","params":{"delta":{"text":"delta text"}}}"#,
        providerEventType: "item/agentMessage/delta",
        normalizedEventKind: "message"
      ))
    XCTAssertEqual(delta.detail, "delta text")

    let approval = SymphonyEventPresentation(
      event: AgentRawEvent(
        sessionID: SessionID("session-42"),
        provider: "codex",
        sequence: EventSequence(27),
        timestamp: "2026-03-24T03:00:27Z",
        rawJSON:
          #"{"method":"item/commandExecution/requestApproval","params":{"reason":"Need approval"}}"#,
        providerEventType: "item/commandExecution/requestApproval",
        normalizedEventKind: "approval_request"
      ))
    XCTAssertEqual(approval.detail, "Need approval")

    let threadStarted = SymphonyEventPresentation(
      event: AgentRawEvent(
        sessionID: SessionID("session-42"),
        provider: "codex",
        sequence: EventSequence(28),
        timestamp: "2026-03-24T03:00:28Z",
        rawJSON:
          #"{"method":"thread/started","params":{"thread":{"status":"queued"}}}"#,
        providerEventType: "thread/started",
        normalizedEventKind: "status"
      ))
    XCTAssertEqual(threadStarted.detail, "queued")

    let turnStarted = SymphonyEventPresentation(
      event: AgentRawEvent(
        sessionID: SessionID("session-42"),
        provider: "codex",
        sequence: EventSequence(29),
        timestamp: "2026-03-24T03:00:29Z",
        rawJSON:
          #"{"method":"turn/started","params":{"status":"running"}}"#,
        providerEventType: "turn/started",
        normalizedEventKind: "status"
      ))
    XCTAssertEqual(turnStarted.detail, "running")

    let summarizedMessage = SymphonyEventPresentation(
      event: AgentRawEvent(
        sessionID: SessionID("session-42"),
        provider: "codex",
        sequence: EventSequence(30),
        timestamp: "2026-03-24T03:00:30Z",
        rawJSON:
          #"{"method":"item/started","params":{"item":{"type":"agentMessage","summary":"Summary only"}}}"#,
        providerEventType: "item/started",
        normalizedEventKind: "message"
      ))
    XCTAssertEqual(summarizedMessage.detail, "Summary only")

    let aggregatedCommand = SymphonyEventPresentation(
      event: AgentRawEvent(
        sessionID: SessionID("session-42"),
        provider: "codex",
        sequence: EventSequence(31),
        timestamp: "2026-03-24T03:00:31Z",
        rawJSON:
          #"{"method":"item/completed","params":{"item":{"type":"commandExecution","aggregatedOutput":"short output"}}}"#,
        providerEventType: "item/completed",
        normalizedEventKind: "tool_result"
      ))
    XCTAssertEqual(aggregatedCommand.detail, "short output")

    let commandResult = SymphonyEventPresentation(
      event: AgentRawEvent(
        sessionID: SessionID("session-42"),
        provider: "codex",
        sequence: EventSequence(32),
        timestamp: "2026-03-24T03:00:32Z",
        rawJSON:
          #"{"method":"item/completed","params":{"item":{"type":"commandExecution","aggregatedOutput":"abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz","result":{"output":"command result"}}}}"#,
        providerEventType: "item/completed",
        normalizedEventKind: "tool_result"
      ))
    XCTAssertEqual(commandResult.detail, "command result")

    let reasoningSummary = SymphonyEventPresentation(
      event: AgentRawEvent(
        sessionID: SessionID("session-42"),
        provider: "codex",
        sequence: EventSequence(33),
        timestamp: "2026-03-24T03:00:33Z",
        rawJSON:
          #"{"method":"item/completed","params":{"item":{"type":"reasoning","summary":"Reasoned summary"}}}"#,
        providerEventType: "item/completed",
        normalizedEventKind: "message"
      ))
    XCTAssertEqual(reasoningSummary.detail, "Reasoned summary")

    let reasoningFallback = SymphonyEventPresentation(
      event: AgentRawEvent(
        sessionID: SessionID("session-42"),
        provider: "codex",
        sequence: EventSequence(34),
        timestamp: "2026-03-24T03:00:34Z",
        rawJSON:
          #"{"method":"item/completed","params":{"item":{"type":"reasoning"}}}"#,
        providerEventType: "item/completed",
        normalizedEventKind: "message"
      ))
    XCTAssertEqual(reasoningFallback.detail, "Reasoning")

    let defaultItemType = SymphonyEventPresentation(
      event: AgentRawEvent(
        sessionID: SessionID("session-42"),
        provider: "codex",
        sequence: EventSequence(35),
        timestamp: "2026-03-24T03:00:35Z",
        rawJSON:
          #"{"method":"item/started","params":{"item":{"type":"customType"}}}"#,
        providerEventType: "item/started",
        normalizedEventKind: "message"
      ))
    XCTAssertEqual(defaultItemType.detail, "customType")

    let itemMessageFallback = SymphonyEventPresentation(
      event: AgentRawEvent(
        sessionID: SessionID("session-42"),
        provider: "codex",
        sequence: EventSequence(36),
        timestamp: "2026-03-24T03:00:36Z",
        rawJSON:
          #"{"method":"item/started","params":{"message":"fallback message"}}"#,
        providerEventType: "item/started",
        normalizedEventKind: "message"
      ))
    XCTAssertEqual(itemMessageFallback.detail, "fallback message")

    let defaultParamsFallback = SymphonyEventPresentation(
      event: AgentRawEvent(
        sessionID: SessionID("session-42"),
        provider: "codex",
        sequence: EventSequence(37),
        timestamp: "2026-03-24T03:00:37Z",
        rawJSON:
          #"{"method":"custom/method","params":{"content":[{"text":"fallback content"}]}}"#,
        providerEventType: "custom/method",
        normalizedEventKind: "message"
      ))
    XCTAssertEqual(defaultParamsFallback.detail, "fallback content")
  }

  @Test func EventPresentationHelperMethodsCoverDirectFallbackBranches() {
    XCTAssertEqual(SymphonyEventPresentation.humanizedItemType("agentMessage"), "Message")
    XCTAssertEqual(
      SymphonyEventPresentation.humanizedItemType("commandExecution"), "Command execution")
    XCTAssertEqual(SymphonyEventPresentation.humanizedItemType("customType"), "customType")
    XCTAssertNil(SymphonyEventPresentation.humanizedItemType(""))
    XCTAssertNil(SymphonyEventPresentation.humanizedItemType(nil))

    XCTAssertNil(SymphonyEventPresentation.extractText(from: nil as Any?))
    XCTAssertEqual(
      SymphonyEventPresentation.extractText(fromItem: ["type": "customType"]),
      "customType"
    )
    XCTAssertEqual(
      SymphonyEventPresentation.extractText(method: "custom/method", params: ["result": "direct"]),
      "direct"
    )

    let unknownFallback = SymphonyEventPresentation(
      event: AgentRawEvent(
        sessionID: SessionID("session-42"),
        provider: "claude_code",
        sequence: EventSequence(38),
        timestamp: "2026-03-24T03:00:38Z",
        rawJSON: #"{}"#,
        providerEventType: "provider_unknown",
        normalizedEventKind: "unexpected_kind"
      ))
    XCTAssertEqual(unknownFallback.detail, #"{}"#)
    XCTAssertEqual(SymphonyEventPresentation.extractText(from: "wrapped" as Any?), "wrapped")
    XCTAssertNil(SymphonyEventPresentation.extractText(fromItem: [:]))

    XCTAssertNil(
      SymphonyEventPresentation.extractText(
        method: "item/started",
        params: [:]
      )
    )
    XCTAssertEqual(
      SymphonyEventPresentation.extractText(
        fromItem: ["type": "agentMessage", "content": "content body"]
      ),
      "content body"
    )
    XCTAssertEqual(
      SymphonyEventPresentation.extractText(
        fromItem: ["type": "commandExecution", "arguments": ["--flag"]]
      ),
      "--flag"
    )
    XCTAssertEqual(
      SymphonyEventPresentation.extractText(
        fromItem: ["type": "commandExecution", "status": "completed"]
      ),
      "completed"
    )
    XCTAssertEqual(
      SymphonyEventPresentation.extractText(
        fromItem: ["type": "reasoning", "content": "reasoning body"]
      ),
      "reasoning body"
    )
    XCTAssertEqual(
      SymphonyEventPresentation.extractText(
        method: "thread/started",
        params: ["status": "queued"]
      ),
      "queued"
    )
    XCTAssertEqual(
      SymphonyEventPresentation.extractText(
        method: "turn/started",
        params: ["turn": ["status": "running"]]
      ),
      "running"
    )
  }

  #if os(macOS)
    @Test func LocalServerEditorStartsInWorkflowStepWhenWorkflowIsMissing() {
      let services = LocalServerServices(
        manager: RecordingLocalServerManager(),
        profileStore: InMemoryLocalServerProfileStore(),
        secretStore: InMemoryLocalServerSecretStore(),
        workflowSelector: StubWorkflowSelector(selectedURL: nil),
        workflowSaver: UITestingWorkflowFileSaver(environmentProvider: { [:] }),
        variableScanner: WorkflowEnvironmentVariableScanner(),
        helperLocator: StubHelperLocator(url: URL(fileURLWithPath: "/tmp/SymphonyLocalServerHelper")),
        environmentProvider: { [:] }
      )
      let model = SymphonyOperatorModel(
        client: MockSymphonyAPIClient(),
        localServerServices: services
      )

      model.prepareLocalServerEditor(mode: .localServer)

      XCTAssertEqual(model.localWorkflowWizardStep, .workflow)
    }

    @Test func LocalServerEditorStartsInLocalServerStepWhenWorkflowAlreadyExists() throws {
      let workflowURL = try makeTemporaryWorkflowFile()
      let services = LocalServerServices(
        manager: RecordingLocalServerManager(),
        profileStore: InMemoryLocalServerProfileStore(
          profile: LocalServerProfile(workflowPath: workflowURL.path)
        ),
        secretStore: InMemoryLocalServerSecretStore(),
        workflowSelector: StubWorkflowSelector(selectedURL: workflowURL),
        workflowSaver: UITestingWorkflowFileSaver(environmentProvider: { [:] }),
        variableScanner: WorkflowEnvironmentVariableScanner(),
        helperLocator: StubHelperLocator(url: URL(fileURLWithPath: "/tmp/SymphonyLocalServerHelper")),
        environmentProvider: { [:] }
      )
      let model = SymphonyOperatorModel(
        client: MockSymphonyAPIClient(),
        localServerServices: services
      )

      model.prepareLocalServerEditor(mode: .localServer)

      XCTAssertEqual(model.localWorkflowWizardStep, .localServer)
    }

    @Test func SavingGeneratedWorkflowPersistsProfileUpdatesEnvEntriesAndAdvances() throws {
      let profileStore = InMemoryLocalServerProfileStore()
      let secretStore = InMemoryLocalServerSecretStore()
      let manager = RecordingLocalServerManager()
      let saveURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
        .appendingPathComponent("WORKFLOW.md", isDirectory: false)
      let saver = RecordingWorkflowSaver(saveURL: saveURL)
      let services = LocalServerServices(
        manager: manager,
        profileStore: profileStore,
        secretStore: secretStore,
        workflowSelector: StubWorkflowSelector(selectedURL: nil),
        workflowSaver: saver,
        variableScanner: WorkflowEnvironmentVariableScanner(),
        helperLocator: StubHelperLocator(url: URL(fileURLWithPath: "/tmp/SymphonyLocalServerHelper")),
        environmentProvider: { [:] }
      )

      let model = SymphonyOperatorModel(
        client: MockSymphonyAPIClient(),
        localServerServices: services
      )
      model.prepareLocalServerEditor(mode: .localServer)
      model.workflowAuthoringDraft.trackerProjectOwner = "atjsh"
      model.workflowAuthoringDraft.trackerProjectOwnerType = "organization"
      model.workflowAuthoringDraft.trackerProjectNumber = "7"
      model.workflowAuthoringDraft.promptBody = """
        Resolve {{issue.title}} with $OPENAI_API_KEY.
        """

      model.saveGeneratedWorkflow()

      XCTAssertEqual(model.localWorkflowWizardStep, .localServer)
      XCTAssertEqual(model.localServerWorkflowPath, saveURL.path)
      XCTAssertEqual(model.localServerEnvironmentEntries.map(\.name), ["GITHUB_TOKEN", "OPENAI_API_KEY"])

      let persistedProfile = try #require(profileStore.loadProfile())
      XCTAssertEqual(persistedProfile.workflowPath, saveURL.path)
      XCTAssertEqual(saver.savedFileNames, [WorkflowAuthoringDraft.defaultWorkflowFileName])
      XCTAssertEqual(try String(contentsOf: saveURL, encoding: .utf8), saver.savedContents.last)
    }

    @Test func LocalServerWorkflowSelectionBuildsLaunchEnvironmentAndPersistsDraft() throws {
      let workflowURL = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString
      ).appendingPathComponent("WORKFLOW.md")
      try FileManager.default.createDirectory(
        at: workflowURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try """
        ---
        tracker:
          api_key: $GITHUB_TOKEN
        ---
        Use $OPENAI_API_KEY and {{issue.title}}
        """.write(to: workflowURL, atomically: true, encoding: .utf8)

      let profileStore = InMemoryLocalServerProfileStore()
      let secretStore = InMemoryLocalServerSecretStore()
      let manager = RecordingLocalServerManager()
      let services = LocalServerServices(
        manager: manager,
        profileStore: profileStore,
        secretStore: secretStore,
        workflowSelector: StubWorkflowSelector(selectedURL: workflowURL),
        workflowSaver: UITestingWorkflowFileSaver(environmentProvider: { ["BASE": "1"] }),
        variableScanner: WorkflowEnvironmentVariableScanner(),
        helperLocator: StubHelperLocator(url: URL(fileURLWithPath: "/tmp/SymphonyLocalServerHelper")),
        environmentProvider: { ["BASE": "1"] }
      )

      let model = SymphonyOperatorModel(
        client: MockSymphonyAPIClient(),
        localServerServices: services
      )

      model.chooseLocalWorkflow()
      XCTAssertEqual(model.localServerWorkflowPath, workflowURL.path)
      XCTAssertEqual(
        model.localServerEnvironmentEntries.map(\.name),
        ["GITHUB_TOKEN", "OPENAI_API_KEY"]
      )

      model.host = "127.0.0.1"
      model.portText = "9090"
      model.localServerSQLitePath = "/tmp/symphony.sqlite3"
      model.localServerEnvironmentEntries[0].value = "gh-token"
      model.localServerEnvironmentEntries[1].value = "openai-token"

      let request = try model.testingMakeLocalServerLaunchRequest()
      XCTAssertEqual(request.endpoint.host, "127.0.0.1")
      XCTAssertEqual(request.endpoint.port, 9090)
      XCTAssertEqual(request.currentDirectoryURL, workflowURL.deletingLastPathComponent())
      XCTAssertEqual(request.environment["BASE"], "1")
      XCTAssertEqual(request.environment["GITHUB_TOKEN"], "gh-token")
      XCTAssertEqual(request.environment["OPENAI_API_KEY"], "openai-token")
      XCTAssertEqual(request.environment[BootstrapEnvironment.serverHostKey], "127.0.0.1")
      XCTAssertEqual(request.environment[BootstrapEnvironment.serverPortKey], "9090")
      XCTAssertEqual(
        request.environment[SymphonyServerBootstrapEnvironment.workflowPathKey],
        workflowURL.path
      )
      XCTAssertEqual(
        request.environment[SymphonyServerBootstrapEnvironment.serverSQLitePathKey],
        "/tmp/symphony.sqlite3"
      )

      try model.testingPersistLocalServerDraft()
      let persistedProfile = try #require(profileStore.loadProfile())
      XCTAssertEqual(persistedProfile.workflowPath, workflowURL.path)
      XCTAssertEqual(persistedProfile.host, "127.0.0.1")
      XCTAssertEqual(persistedProfile.port, 9090)
      XCTAssertEqual(persistedProfile.sqlitePath, "/tmp/symphony.sqlite3")
      XCTAssertEqual(persistedProfile.environmentKeys, ["GITHUB_TOKEN", "OPENAI_API_KEY"])
      XCTAssertEqual(secretStore.secret(for: "GITHUB_TOKEN"), "gh-token")
      XCTAssertEqual(secretStore.secret(for: "OPENAI_API_KEY"), "openai-token")
    }

    @Test func LocalServerStartTransitionsToRunningAndAutoConnects() async throws {
      let workflowURL = try makeTemporaryWorkflowFile()
      let client = MockSymphonyAPIClient()
      client.healthResponse = HealthResponse(
        status: "ok",
        serverTime: "2026-03-24T12:00:00Z",
        version: "1.0.0",
        trackerKind: "github"
      )
      client.issuesResponse = IssuesResponse(items: [makeIssueSummary()])

      let manager = RecordingLocalServerManager()
      manager.nextStartSnapshot = LocalServerStatusSnapshot(
        state: .running,
        endpoint: BootstrapServerEndpoint(scheme: "http", host: "localhost", port: 8080),
        transcript: ["[SymphonyServer] starting"],
        failureDescription: nil,
        processIdentifier: 4242
      )
      let services = LocalServerServices(
        manager: manager,
        profileStore: InMemoryLocalServerProfileStore(),
        secretStore: InMemoryLocalServerSecretStore(),
        workflowSelector: StubWorkflowSelector(selectedURL: workflowURL),
        workflowSaver: UITestingWorkflowFileSaver(environmentProvider: { [:] }),
        variableScanner: WorkflowEnvironmentVariableScanner(),
        helperLocator: StubHelperLocator(url: URL(fileURLWithPath: "/tmp/SymphonyLocalServerHelper")),
        environmentProvider: { [:] }
      )
      let model = SymphonyOperatorModel(client: client, localServerServices: services)
      model.chooseLocalWorkflow()

      await model.startLocalServer()
      try await waitUntil {
        model.localServerLaunchState == .running && model.health?.trackerKind == "github"
      }

      XCTAssertEqual(manager.startedRequests.count, 1)
      XCTAssertEqual(model.host, "localhost")
      XCTAssertEqual(model.portText, "8080")
      XCTAssertNil(model.localServerFailure)
      XCTAssertEqual(model.health?.status, "ok")
    }

    @Test func LocalServerStartMapsValidationAndManagerFailures() async throws {
      let workflowURL = try makeTemporaryWorkflowFile(contents: """
        ---
        tracker:
          api_key: $GITHUB_TOKEN
        ---
        Resolve {{issue.title}}
        """)
      let manager = RecordingLocalServerManager()
      manager.nextStartSnapshot = LocalServerStatusSnapshot(
        state: .failed,
        endpoint: BootstrapServerEndpoint.defaultEndpoint,
        transcript: ["[SymphonyServer] failed to start: Address already in use"],
        failureDescription: "Port 8080 is already in use.",
        processIdentifier: nil
      )
      let services = LocalServerServices(
        manager: manager,
        profileStore: InMemoryLocalServerProfileStore(),
        secretStore: InMemoryLocalServerSecretStore(),
        workflowSelector: StubWorkflowSelector(selectedURL: workflowURL),
        workflowSaver: UITestingWorkflowFileSaver(environmentProvider: { [:] }),
        variableScanner: WorkflowEnvironmentVariableScanner(),
        helperLocator: StubHelperLocator(url: URL(fileURLWithPath: "/tmp/SymphonyLocalServerHelper")),
        environmentProvider: { [:] }
      )
      let model = SymphonyOperatorModel(
        client: MockSymphonyAPIClient(),
        localServerServices: services
      )
      model.chooseLocalWorkflow()

      await model.startLocalServer()
      XCTAssertEqual(model.localServerLaunchState, .needsSetup)
      XCTAssertEqual(
        model.localServerFailure,
        "Fill in the required environment values: GITHUB_TOKEN."
      )

      model.localServerEnvironmentEntries[0].value = "gh-token"
      await model.startLocalServer()
      try await waitUntil {
        model.localServerLaunchState == .failed
      }

      XCTAssertEqual(model.localServerFailure, "Port 8080 is already in use.")
      XCTAssertEqual(model.localServerTranscript, ["[SymphonyServer] failed to start: Address already in use"])
    }

    @Test func LocalServerStopAndRestartUseManagerAndClearConnectionState() async throws {
      let workflowURL = try makeTemporaryWorkflowFile()
      let manager = RecordingLocalServerManager()
      manager.nextStartSnapshot = LocalServerStatusSnapshot(
        state: .running,
        endpoint: BootstrapServerEndpoint.defaultEndpoint,
        transcript: ["[SymphonyServer] starting"],
        failureDescription: nil,
        processIdentifier: 7
      )
      let client = MockSymphonyAPIClient()
      client.healthResponse = HealthResponse(
        status: "ok",
        serverTime: "2026-03-24T12:00:00Z",
        version: "1.0.0",
        trackerKind: "github"
      )
      client.issuesResponse = IssuesResponse(items: [makeIssueSummary()])
      let services = LocalServerServices(
        manager: manager,
        profileStore: InMemoryLocalServerProfileStore(),
        secretStore: InMemoryLocalServerSecretStore(),
        workflowSelector: StubWorkflowSelector(selectedURL: workflowURL),
        workflowSaver: UITestingWorkflowFileSaver(environmentProvider: { [:] }),
        variableScanner: WorkflowEnvironmentVariableScanner(),
        helperLocator: StubHelperLocator(url: URL(fileURLWithPath: "/tmp/SymphonyLocalServerHelper")),
        environmentProvider: { [:] }
      )
      let model = SymphonyOperatorModel(client: client, localServerServices: services)
      model.chooseLocalWorkflow()

      await model.startLocalServer()
      try await waitUntil {
        model.localServerLaunchState == .running && model.health != nil
      }

      await model.stopLocalServer()
      XCTAssertEqual(manager.stopCallCount, 1)
      XCTAssertNil(model.health)
      XCTAssertTrue(model.issues.isEmpty)
      XCTAssertEqual(model.localServerLaunchState, .idle)

      manager.nextRestartSnapshot = LocalServerStatusSnapshot(
        state: .running,
        endpoint: BootstrapServerEndpoint.defaultEndpoint,
        transcript: ["[SymphonyServer] restarting"],
        failureDescription: nil,
        processIdentifier: 9
      )
      await model.restartLocalServer()
      try await waitUntil {
        model.localServerLaunchState == .running && model.health != nil
      }

      XCTAssertEqual(manager.restartRequests.count, 1)
    }
  #endif

  private func makeIssueSummary() -> IssueSummary {
    IssueSummary(
      issueID: IssueID("issue-42"),
      identifier: try! IssueIdentifier(validating: "atjsh/example#42"),
      title: "Implement provider-neutral server",
      state: "in_progress",
      issueState: "OPEN",
      priority: 1,
      currentProvider: "claude_code",
      currentRunID: RunID("run-42"),
      currentSessionID: SessionID("session-42")
    )
  }

  private func makeIssueDetail() -> IssueDetail {
    let issue = SymphonyShared.Issue(
      id: IssueID("issue-42"),
      identifier: try! IssueIdentifier(validating: "atjsh/example#42"),
      repository: "atjsh/example",
      number: 42,
      title: "Implement provider-neutral server",
      description: "The bootstrap runtime must become a real API.",
      priority: 1,
      state: "in_progress",
      issueState: "OPEN",
      projectItemID: "item-42",
      url: "https://example.com/issues/42",
      labels: ["Server"],
      blockedBy: [],
      createdAt: "2026-03-24T01:00:00Z",
      updatedAt: "2026-03-24T02:00:00Z"
    )
    let run = makeRunSummary()
    let session = AgentSession(
      sessionID: SessionID("session-42"),
      provider: "claude_code",
      providerSessionID: "provider-session-42",
      providerThreadID: "thread-42",
      providerTurnID: "turn-42",
      providerRunID: "provider-run-42",
      runID: RunID("run-42"),
      providerProcessPID: "999",
      status: "active",
      lastEventType: "message",
      lastEventAt: "2026-03-24T03:00:02Z",
      turnCount: 2,
      tokenUsage: try! TokenUsage(inputTokens: 7, outputTokens: 5),
      latestRateLimitPayload: nil
    )
    return IssueDetail(
      issue: issue, latestRun: run, workspacePath: "/tmp/symphony/atjsh_example_42",
      recentSessions: [session])
  }

  private func makeRunSummary() -> RunSummary {
    RunSummary(
      runID: RunID("run-42"),
      issueID: IssueID("issue-42"),
      issueIdentifier: try! IssueIdentifier(validating: "atjsh/example#42"),
      attempt: 1,
      status: "running",
      provider: "claude_code",
      providerSessionID: "provider-session-42",
      providerRunID: "provider-run-42",
      startedAt: "2026-03-24T03:00:00Z",
      endedAt: nil,
      workspacePath: "/tmp/symphony/atjsh_example_42",
      sessionID: SessionID("session-42"),
      lastError: nil
    )
  }

  private func makeRunDetail() -> RunDetail {
    RunDetail(
      runID: RunID("run-42"),
      issueID: IssueID("issue-42"),
      issueIdentifier: try! IssueIdentifier(validating: "atjsh/example#42"),
      attempt: 1,
      status: "running",
      provider: "claude_code",
      providerSessionID: "provider-session-42",
      providerRunID: "provider-run-42",
      startedAt: "2026-03-24T03:00:00Z",
      endedAt: nil,
      workspacePath: "/tmp/symphony/atjsh_example_42",
      sessionID: SessionID("session-42"),
      lastError: nil,
      issue: makeIssueDetail().issue,
      turnCount: 2,
      lastAgentEventType: "message",
      lastAgentMessage: "hello",
      tokens: try! TokenUsage(inputTokens: 7, outputTokens: 5),
      logs: RunLogStats(eventCount: 1, latestSequence: EventSequence(1))
    )
  }

  private func makeEvent(sequence: Int, kind: String) -> AgentRawEvent {
    AgentRawEvent(
      sessionID: SessionID("session-42"),
      provider: "claude_code",
      sequence: EventSequence(sequence),
      timestamp: "2026-03-24T03:00:0\(sequence)Z",
      rawJSON: #"{"type":"event","payload":{"text":"hello"}}"#,
      providerEventType: "event",
      normalizedEventKind: kind
    )
  }
}

private final class MockSymphonyAPIClient: SymphonyAPIClientProtocol, @unchecked Sendable {
  var healthResponse: HealthResponse
  var issuesResponse: IssuesResponse
  var issueDetailResponse: IssueDetail
  var runDetailResponse: RunDetail
  var logsResponse: LogEntriesResponse
  var liveEvents = [AgentRawEvent]()
  var healthError: Error?
  var issuesError: Error?
  var issueDetailError: Error?
  var runDetailError: Error?
  var logsError: Error?
  var refreshError: Error?
  var streamError: Error?
  var suspendStream = false
  var suspendRefresh = false

  private(set) var recordedHosts = [String]()
  private(set) var refreshCallCount = 0
  private(set) var issueDetailRequests = [IssueID]()
  private(set) var runDetailRequests = [RunID]()
  private(set) var logRequests = [(sessionID: SessionID, cursor: EventCursor?, limit: Int)]()
  private(set) var streamRequests = [(sessionID: SessionID, cursor: EventCursor?)]()
  private(set) var streamStartCount = 0
  private(set) var streamTerminationCount = 0
  private var refreshContinuation: CheckedContinuation<Void, Never>?

  init() {
    self.healthResponse = HealthResponse(status: "ok", serverTime: "", version: "", trackerKind: "")
    self.issuesResponse = IssuesResponse(items: [])
    let issue = SymphonyShared.Issue(
      id: IssueID("issue-0"),
      identifier: try! IssueIdentifier(validating: "atjsh/example#1"),
      repository: "atjsh/example",
      number: 1,
      title: "",
      description: nil,
      priority: nil,
      state: "queued",
      issueState: "OPEN",
      projectItemID: nil,
      url: nil,
      labels: [],
      blockedBy: [],
      createdAt: nil,
      updatedAt: nil
    )
    self.issueDetailResponse = IssueDetail(
      issue: issue, latestRun: nil, workspacePath: nil, recentSessions: [])
    self.runDetailResponse = RunDetail(
      runID: RunID("run-0"),
      issueID: IssueID("issue-0"),
      issueIdentifier: try! IssueIdentifier(validating: "atjsh/example#1"),
      attempt: 1,
      status: "queued",
      provider: "claude_code",
      providerSessionID: nil,
      providerRunID: nil,
      startedAt: "2026-03-24T00:00:00Z",
      endedAt: nil,
      workspacePath: "/tmp",
      sessionID: nil,
      lastError: nil,
      issue: issue,
      turnCount: 0,
      lastAgentEventType: nil,
      lastAgentMessage: nil,
      tokens: try! TokenUsage(),
      logs: RunLogStats(eventCount: 0, latestSequence: nil)
    )
    self.logsResponse = LogEntriesResponse(
      sessionID: SessionID("session-0"), provider: "claude_code", items: [], nextCursor: nil,
      hasMore: false)
  }

  func health(endpoint: ServerEndpoint) async throws -> HealthResponse {
    if let healthError {
      throw healthError
    }
    recordedHosts.append(endpoint.host)
    return healthResponse
  }

  func issues(endpoint: ServerEndpoint) async throws -> IssuesResponse {
    if let issuesError {
      throw issuesError
    }
    recordedHosts.append(endpoint.host)
    return issuesResponse
  }

  func issueDetail(endpoint: ServerEndpoint, issueID: IssueID) async throws -> IssueDetail {
    if let issueDetailError {
      throw issueDetailError
    }
    issueDetailRequests.append(issueID)
    return issueDetailResponse
  }

  func runDetail(endpoint: ServerEndpoint, runID: RunID) async throws -> RunDetail {
    if let runDetailError {
      throw runDetailError
    }
    runDetailRequests.append(runID)
    return runDetailResponse
  }

  func logs(endpoint: ServerEndpoint, sessionID: SessionID, cursor: EventCursor?, limit: Int)
    async throws -> LogEntriesResponse
  {
    if let logsError {
      throw logsError
    }
    logRequests.append((sessionID, cursor, limit))
    return logsResponse
  }

  func refresh(endpoint: ServerEndpoint) async throws -> RefreshResponse {
    if let refreshError {
      throw refreshError
    }
    refreshCallCount += 1
    if suspendRefresh {
      await withCheckedContinuation { continuation in
        refreshContinuation = continuation
      }
    }
    return RefreshResponse(queued: true, requestedAt: "2026-03-24T12:00:00Z")
  }

  func resumeRefresh() {
    refreshContinuation?.resume()
    refreshContinuation = nil
  }

  func logStream(endpoint: ServerEndpoint, sessionID: SessionID, cursor: EventCursor?) throws
    -> AsyncThrowingStream<AgentRawEvent, Error>
  {
    streamRequests.append((sessionID, cursor))
    streamStartCount += 1
    return AsyncThrowingStream(AgentRawEvent.self) { continuation in
      continuation.onTermination = { [weak self] _ in
        self?.streamTerminationCount += 1
      }
      if let streamError {
        continuation.finish(throwing: streamError)
        return
      }
      if suspendStream {
        return
      }
      for event in liveEvents {
        continuation.yield(event)
      }
      continuation.finish()
    }
  }
}

private enum TestModelFailure: LocalizedError {
  case failed(String)

  var errorDescription: String? {
    switch self {
    case .failed(let message):
      return message
    }
  }
}

#if os(macOS)
  private final class RecordingLocalServerManager: LocalServerManaging {
    var onStatusChange: ((LocalServerStatusSnapshot) -> Void)?
    private(set) var statusSnapshot = LocalServerStatusSnapshot(
      state: .needsSetup,
      endpoint: .defaultEndpoint
    )
    private(set) var startedRequests = [LocalServerLaunchRequest]()
    private(set) var restartRequests = [LocalServerLaunchRequest]()
    private(set) var stopCallCount = 0
    var nextStartSnapshot = LocalServerStatusSnapshot(
      state: .running,
      endpoint: .defaultEndpoint
    )
    var nextRestartSnapshot: LocalServerStatusSnapshot?

    func start(request: LocalServerLaunchRequest) async {
      startedRequests.append(request)
      statusSnapshot = nextStartSnapshot
      await MainActor.run {
        onStatusChange?(statusSnapshot)
      }
    }

    func stop() async {
      stopCallCount += 1
      statusSnapshot = LocalServerStatusSnapshot(
        state: .idle,
        endpoint: statusSnapshot.endpoint,
        transcript: statusSnapshot.transcript
      )
      await MainActor.run {
        onStatusChange?(statusSnapshot)
      }
    }

    func restart(request: LocalServerLaunchRequest) async {
      restartRequests.append(request)
      statusSnapshot = nextRestartSnapshot ?? nextStartSnapshot
      await MainActor.run {
        onStatusChange?(statusSnapshot)
      }
    }
  }

  private final class RecordingWorkflowSaver: LocalWorkflowSaving {
    let saveURL: URL
    private(set) var savedFileNames = [String]()
    private(set) var savedContents = [String]()

    init(saveURL: URL) {
      self.saveURL = saveURL
    }

    func saveWorkflow(
      named fileName: String,
      suggestedDirectoryURL _: URL?,
      content: String
    ) throws -> URL? {
      savedFileNames.append(fileName)
      savedContents.append(content)
      try FileManager.default.createDirectory(
        at: saveURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try content.write(to: saveURL, atomically: true, encoding: .utf8)
      return saveURL
    }
  }

  private func makeTemporaryWorkflowFile(
    contents: String = """
      ---
      tracker:
        project_owner: atjsh
        project_owner_type: organization
        project_number: 1
      ---
      Resolve {{issue.title}}
      """
  ) throws -> URL {
    let workflowURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
      .appendingPathComponent("WORKFLOW.md", isDirectory: false)
    try FileManager.default.createDirectory(
      at: workflowURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try contents.write(to: workflowURL, atomically: true, encoding: .utf8)
    return workflowURL
  }
#endif

@MainActor
private func waitUntil(
  timeout: Duration = .seconds(2),
  pollInterval: Duration = .milliseconds(10),
  condition: @escaping @MainActor () -> Bool
) async throws {
  let clock = ContinuousClock()
  let deadline = clock.now.advanced(by: timeout)
  while !condition() {
    if clock.now >= deadline {
      XCTFail("Timed out waiting for condition.")
      return
    }
    try await Task.sleep(for: pollInterval)
  }
}
