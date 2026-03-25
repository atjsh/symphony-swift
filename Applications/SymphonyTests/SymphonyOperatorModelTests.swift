import SymphonyClientUI
import SymphonyShared
import XCTest

@MainActor
final class SymphonyOperatorModelTests: XCTestCase {
  func testConnectLoadsHealthAndIssuesFromConfiguredEndpoint() async throws {
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

  func testSelectingIssueLoadsRunDetailHistoricalLogsAndLiveTail() async throws {
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

  func testRefreshReloadsIssuesAndRetainsSelection() async throws {
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

  func testEventPresentationCoversKnownKindsAndUnknownFallback() {
    let message = SymphonyEventPresentation(event: makeEvent(sequence: 1, kind: "message"))
    XCTAssertEqual(message.title, "Message")
    XCTAssertFalse(message.showsRawJSON)

    let toolCall = SymphonyEventPresentation(event: makeEvent(sequence: 2, kind: "tool_call"))
    XCTAssertEqual(toolCall.title, "Tool Call")

    let toolResult = SymphonyEventPresentation(event: makeEvent(sequence: 3, kind: "tool_result"))
    XCTAssertEqual(toolResult.title, "Tool Result")

    let status = SymphonyEventPresentation(event: makeEvent(sequence: 4, kind: "status"))
    XCTAssertEqual(status.title, "Status")

    let usage = SymphonyEventPresentation(event: makeEvent(sequence: 5, kind: "usage"))
    XCTAssertEqual(usage.title, "Usage")

    let approval = SymphonyEventPresentation(
      event: makeEvent(sequence: 6, kind: "approval_request"))
    XCTAssertEqual(approval.title, "Approval Request")

    let error = SymphonyEventPresentation(event: makeEvent(sequence: 7, kind: "error"))
    XCTAssertEqual(error.title, "Error")

    let unknown = SymphonyEventPresentation(event: makeEvent(sequence: 8, kind: "unexpected_kind"))
    XCTAssertEqual(unknown.title, "Unknown Event")
    XCTAssertTrue(unknown.showsRawJSON)
  }

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

  private(set) var recordedHosts = [String]()
  private(set) var refreshCallCount = 0

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
    recordedHosts.append(endpoint.host)
    return healthResponse
  }

  func issues(endpoint: ServerEndpoint) async throws -> IssuesResponse {
    recordedHosts.append(endpoint.host)
    return issuesResponse
  }

  func issueDetail(endpoint: ServerEndpoint, issueID: IssueID) async throws -> IssueDetail {
    issueDetailResponse
  }

  func runDetail(endpoint: ServerEndpoint, runID: RunID) async throws -> RunDetail {
    runDetailResponse
  }

  func logs(endpoint: ServerEndpoint, sessionID: SessionID, cursor: EventCursor?, limit: Int)
    async throws -> LogEntriesResponse
  {
    logsResponse
  }

  func refresh(endpoint: ServerEndpoint) async throws -> RefreshResponse {
    refreshCallCount += 1
    return RefreshResponse(queued: true, requestedAt: "2026-03-24T12:00:00Z")
  }

  func logStream(endpoint: ServerEndpoint, sessionID: SessionID, cursor: EventCursor?) throws
    -> AsyncThrowingStream<AgentRawEvent, Error>
  {
    AsyncThrowingStream(AgentRawEvent.self) { continuation in
      for event in liveEvents {
        continuation.yield(event)
      }
      continuation.finish()
    }
  }
}
