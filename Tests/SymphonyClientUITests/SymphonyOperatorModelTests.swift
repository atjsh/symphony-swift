import XCTest
@testable import SymphonyClientUI
import SymphonyShared

@MainActor
final class SymphonyOperatorModelTests: XCTestCase {
    func testDefaultInitializerUsesDefaultEndpointAndIdleState() {
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

    func testConnectLoadsHealthAndIssuesFromConfiguredEndpoint() async throws {
        let client = MockSymphonyAPIClient()
        client.healthResponse = HealthResponse(status: "ok", serverTime: "2026-03-24T12:00:00Z", version: "1.0.0", trackerKind: "github")
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

    func testInitialStateServerEndpointResolutionAndConnectCanRestoreSelection() async throws {
        let client = MockSymphonyAPIClient()
        let issueSummary = makeIssueSummary()
        client.healthResponse = HealthResponse(status: "ok", serverTime: "2026-03-24T12:00:00Z", version: "1.0.0", trackerKind: "github")
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

    func testSelectingIssueLoadsRunDetailHistoricalLogsAndLiveTail() async throws {
        let client = MockSymphonyAPIClient()
        let issueSummary = makeIssueSummary()
        client.healthResponse = HealthResponse(status: "ok", serverTime: "2026-03-24T12:00:00Z", version: "1.0.0", trackerKind: "github")
        client.issuesResponse = IssuesResponse(items: [issueSummary])
        client.issueDetailResponse = makeIssueDetail()
        client.runDetailResponse = makeRunDetail()
        client.logsResponse = LogEntriesResponse(
            sessionID: SessionID("session-42"),
            provider: "claude_code",
            items: [makeEvent(sequence: 1, kind: "message")],
            nextCursor: EventCursor(sessionID: SessionID("session-42"), lastDeliveredSequence: EventSequence(1)),
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
        client.healthResponse = HealthResponse(status: "ok", serverTime: "2026-03-24T12:00:00Z", version: "1.0.0", trackerKind: "github")
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

        client.issuesResponse = IssuesResponse(items: [issueSummary, IssueSummary(
            issueID: IssueID("issue-84"),
            identifier: try IssueIdentifier(validating: "atjsh/example#84"),
            title: "Second issue",
            state: "queued",
            issueState: "OPEN",
            priority: 2,
            currentProvider: nil,
            currentRunID: nil,
            currentSessionID: nil
        )])

        await model.refresh()

        XCTAssertEqual(client.refreshCallCount, 1)
        XCTAssertEqual(model.issues.map(\.issueID.rawValue), ["issue-42", "issue-84"])
        XCTAssertEqual(model.selectedIssueID?.rawValue, "issue-42")
    }

    func testInvalidEndpointAndFailuresUpdateConnectionState() async throws {
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

    func testConnectAndRefreshFailuresClearStateAndRespectInvalidEndpoints() async throws {
        let client = MockSymphonyAPIClient()
        client.healthResponse = HealthResponse(status: "ok", serverTime: "2026-03-24T12:00:00Z", version: "1.0.0", trackerKind: "github")
        client.issuesError = TestModelFailure.failed("issues")

        let model = SymphonyOperatorModel(
            client: client,
            initialEndpoint: try ServerEndpoint(host: "localhost", port: 8080)
        )
        model.health = HealthResponse(status: "stale", serverTime: "2026-03-24T00:00:00Z", version: "0.9.0", trackerKind: "github")
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

    func testSelectIssueAndSelectRunFailuresCoverIssueLogsAndInvalidEndpointBranches() async throws {
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

    func testSelectIssueWithoutLatestRunClearsRunAndLogs() async throws {
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

    func testSelectRunWithoutSessionAndLiveStreamErrorsUpdateStatus() async throws {
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
        for _ in 0..<20 where model.liveStatus == "Connecting live stream" || model.liveStatus == "Live" {
            try await Task.sleep(for: .milliseconds(20))
        }

        XCTAssertEqual(model.liveStatus, "stream")
    }

    func testSelectRunFailureSetsConnectionErrorAndPresentationExtractsFallbackContent() async throws {
        let client = MockSymphonyAPIClient()
        client.runDetailError = TestModelFailure.failed("run detail")

        let model = SymphonyOperatorModel(client: client)
        await model.selectRun(RunID("run-42"))
        XCTAssertEqual(model.connectionError, "run detail")

        let nested = SymphonyEventPresentation(event: AgentRawEvent(
            sessionID: SessionID("session-42"),
            provider: "claude_code",
            sequence: EventSequence(9),
            timestamp: "2026-03-24T03:00:09Z",
            rawJSON: #"{"payload":[{"output":7}]}"#,
            providerEventType: "usage",
            normalizedEventKind: "usage"
        ))
        XCTAssertEqual(nested.detail, "7")

        let fallback = SymphonyEventPresentation(event: AgentRawEvent(
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

    func testLiveStreamCancellationOnDeinitAndOutOfOrderEventsAreSorted() async throws {
        let client = MockSymphonyAPIClient()
        client.runDetailResponse = makeRunDetail()
        client.logsResponse = LogEntriesResponse(
            sessionID: SessionID("session-42"),
            provider: "claude_code",
            items: [makeEvent(sequence: 2, kind: "message")],
            nextCursor: EventCursor(sessionID: SessionID("session-42"), lastDeliveredSequence: EventSequence(2)),
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

    func testEventPresentationCoversKnownKindsAndUnknownFallback() {
        let message = SymphonyEventPresentation(event: makeEvent(sequence: 1, kind: "message"))
        XCTAssertEqual(message.title, "Message")
        XCTAssertFalse(message.showsRawJSON)

        let messageFallback = SymphonyEventPresentation(event: AgentRawEvent(
            sessionID: SessionID("session-42"),
            provider: "claude_code",
            sequence: EventSequence(16),
            timestamp: "2026-03-24T03:00:16Z",
            rawJSON: #"{"payload":{}}"#,
            providerEventType: "message_fallback",
            normalizedEventKind: "message"
        ))
        XCTAssertEqual(messageFallback.detail, "message_fallback")

        let toolCall = SymphonyEventPresentation(event: makeEvent(sequence: 2, kind: "tool_call"))
        XCTAssertEqual(toolCall.title, "Tool Call")

        let toolCallFallback = SymphonyEventPresentation(event: AgentRawEvent(
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

        let toolResultFallback = SymphonyEventPresentation(event: AgentRawEvent(
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

        let usage = SymphonyEventPresentation(event: makeEvent(sequence: 5, kind: "usage"))
        XCTAssertEqual(usage.title, "Usage")

        let approval = SymphonyEventPresentation(event: makeEvent(sequence: 6, kind: "approval_request"))
        XCTAssertEqual(approval.title, "Approval Request")

        let approvalFallback = SymphonyEventPresentation(event: AgentRawEvent(
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

        let errorFallback = SymphonyEventPresentation(event: AgentRawEvent(
            sessionID: SessionID("session-42"),
            provider: "claude_code",
            sequence: EventSequence(20),
            timestamp: "2026-03-24T03:00:20Z",
            rawJSON: #"{"payload":{}}"#,
            providerEventType: "error_fallback",
            normalizedEventKind: "error"
        ))
        XCTAssertEqual(errorFallback.detail, #"{"payload":{}}"#)

        let unknown = SymphonyEventPresentation(event: makeEvent(sequence: 8, kind: "unexpected_kind"))
        XCTAssertEqual(unknown.title, "Unknown Event")
        XCTAssertTrue(unknown.showsRawJSON)

        let rawString = SymphonyEventPresentation(event: AgentRawEvent(
            sessionID: SessionID("session-42"),
            provider: "claude_code",
            sequence: EventSequence(11),
            timestamp: "2026-03-24T03:00:11Z",
            rawJSON: #"["hello"]"#,
            providerEventType: "message",
            normalizedEventKind: "message"
        ))
        XCTAssertEqual(rawString.detail, "hello")

        let arrayContent = SymphonyEventPresentation(event: AgentRawEvent(
            sessionID: SessionID("session-42"),
            provider: "claude_code",
            sequence: EventSequence(12),
            timestamp: "2026-03-24T03:00:12Z",
            rawJSON: #"[{"content":"inside"}]"#,
            providerEventType: "tool_result",
            normalizedEventKind: "tool_result"
        ))
        XCTAssertEqual(arrayContent.detail, "inside")

        let numeric = SymphonyEventPresentation(event: AgentRawEvent(
            sessionID: SessionID("session-42"),
            provider: "claude_code",
            sequence: EventSequence(13),
            timestamp: "2026-03-24T03:00:13Z",
            rawJSON: #"42"#,
            providerEventType: "usage",
            normalizedEventKind: "usage"
        ))
        XCTAssertEqual(numeric.detail, "42")

        let arrayFallback = SymphonyEventPresentation(event: AgentRawEvent(
            sessionID: SessionID("session-42"),
            provider: "claude_code",
            sequence: EventSequence(15),
            timestamp: "2026-03-24T03:00:15Z",
            rawJSON: #"[{}]"#,
            providerEventType: "usage",
            normalizedEventKind: "usage"
        ))
        XCTAssertEqual(arrayFallback.detail, #"[{}]"#)

        let invalidJSON = SymphonyEventPresentation(event: AgentRawEvent(
            sessionID: SessionID("session-42"),
            provider: "claude_code",
            sequence: EventSequence(14),
            timestamp: "2026-03-24T03:00:14Z",
            rawJSON: #"{invalid"#,
            providerEventType: "provider_status",
            normalizedEventKind: "status"
        ))
        XCTAssertEqual(invalidJSON.detail, "provider_status")
        XCTAssertTrue(invalidJSON.metadata.contains("claude_code"))
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
        return IssueDetail(issue: issue, latestRun: run, workspacePath: "/tmp/symphony/atjsh_example_42", recentSessions: [session])
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

    private(set) var recordedHosts = [String]()
    private(set) var refreshCallCount = 0
    private(set) var issueDetailRequests = [IssueID]()
    private(set) var runDetailRequests = [RunID]()
    private(set) var logRequests = [(sessionID: SessionID, cursor: EventCursor?, limit: Int)]()
    private(set) var streamStartCount = 0
    private(set) var streamTerminationCount = 0

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
        self.issueDetailResponse = IssueDetail(issue: issue, latestRun: nil, workspacePath: nil, recentSessions: [])
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
        self.logsResponse = LogEntriesResponse(sessionID: SessionID("session-0"), provider: "claude_code", items: [], nextCursor: nil, hasMore: false)
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

    func logs(endpoint: ServerEndpoint, sessionID: SessionID, cursor: EventCursor?, limit: Int) async throws -> LogEntriesResponse {
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
        return RefreshResponse(queued: true, requestedAt: "2026-03-24T12:00:00Z")
    }

    func logStream(endpoint: ServerEndpoint, sessionID: SessionID, cursor: EventCursor?) throws -> AsyncThrowingStream<AgentRawEvent, Error> {
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
