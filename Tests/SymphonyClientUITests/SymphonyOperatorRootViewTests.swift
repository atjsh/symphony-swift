import SwiftUI
import XCTest
@testable import SymphonyClientUI
import SymphonyShared
#if canImport(AppKit)
import AppKit
#endif

@MainActor
final class SymphonyOperatorRootViewTests: XCTestCase {
    func testBodyEvaluatesWithEmptyOperatorState() {
        let model = SymphonyOperatorModel(client: PassiveSymphonyAPIClient())
        let view = SymphonyOperatorRootView(model: model)

        _ = view.body
    }

    func testBodyEvaluatesWithLoadedIssueRunAndLogs() throws {
        let model = SymphonyOperatorModel(
            client: PassiveSymphonyAPIClient(),
            initialEndpoint: try ServerEndpoint(scheme: "https", host: "example.com", port: 9443)
        )
        model.health = HealthResponse(status: "ok", serverTime: "2026-03-24T00:00:00Z", version: "1.0.0", trackerKind: "github")
        model.connectionError = "refresh failed"
        model.isConnecting = true
        model.isRefreshing = true
        model.issues = [makeIssueSummary()]
        model.selectedIssueID = IssueID("issue-42")
        model.issueDetail = makeIssueDetail()
        model.selectedRunID = RunID("run-42")
        model.runDetail = makeRunDetail()
        model.logEvents = [
            makeEvent(sequence: 1, kind: "message", rawJSON: #"{"message":"hello"}"#),
            makeEvent(sequence: 2, kind: "unknown", rawJSON: #"{"unexpected":"payload"}"#),
        ]
        model.liveStatus = "Live"

        let view = SymphonyOperatorRootView(model: model)
        _ = view.body
    }

    func testBodyEvaluatesWithTokensErrorBlockersLabelsAndAllEventKinds() throws {
        let model = SymphonyOperatorModel(
            client: PassiveSymphonyAPIClient(),
            initialEndpoint: try ServerEndpoint(host: "localhost", port: 8080)
        )

        let blockerRef = BlockerReference(
            issueID: IssueID("issue-99"),
            identifier: try! IssueIdentifier(validating: "atjsh/example#99"),
            state: "in_progress",
            issueState: "OPEN",
            url: "https://example.com/issues/99"
        )
        let issueWithBlockers = SymphonyShared.Issue(
            id: IssueID("issue-42"),
            identifier: try! IssueIdentifier(validating: "atjsh/example#42"),
            repository: "atjsh/example",
            number: 42,
            title: "Blocked issue",
            description: "Testing all fields",
            priority: 1,
            state: "in_progress",
            issueState: "OPEN",
            projectItemID: "item-42",
            url: "https://example.com/issues/42",
            labels: ["Bug", "Server"],
            blockedBy: [blockerRef],
            createdAt: "2026-03-24T00:00:00Z",
            updatedAt: "2026-03-24T01:00:00Z"
        )
        let session = AgentSession(
            sessionID: SessionID("session-42"),
            provider: "claude_code",
            providerSessionID: "ps-42",
            providerThreadID: nil,
            providerTurnID: nil,
            providerRunID: nil,
            runID: RunID("run-42"),
            providerProcessPID: nil,
            status: "active",
            lastEventType: "message",
            lastEventAt: "2026-03-24T01:00:00Z",
            turnCount: 5,
            tokenUsage: try! TokenUsage(inputTokens: 10, outputTokens: 20),
            latestRateLimitPayload: nil
        )
        model.issueDetail = IssueDetail(
            issue: issueWithBlockers,
            latestRun: makeRunSummary(),
            workspacePath: "/tmp/ws",
            recentSessions: [session]
        )
        model.issues = [
            IssueSummary(
                issueID: IssueID("issue-42"),
                identifier: try! IssueIdentifier(validating: "atjsh/example#42"),
                title: "Priority issue",
                state: "in_progress",
                issueState: "OPEN",
                priority: 1,
                currentProvider: "claude_code",
                currentRunID: RunID("run-42"),
                currentSessionID: SessionID("session-42")
            ),
            IssueSummary(
                issueID: IssueID("issue-43"),
                identifier: try! IssueIdentifier(validating: "atjsh/example#43"),
                title: "No priority issue",
                state: "queued",
                issueState: "OPEN",
                priority: nil,
                currentProvider: nil,
                currentRunID: nil,
                currentSessionID: nil
            ),
        ]
        model.runDetail = RunDetail(
            runID: RunID("run-42"),
            issueID: IssueID("issue-42"),
            issueIdentifier: try! IssueIdentifier(validating: "atjsh/example#42"),
            attempt: 1,
            status: "failed",
            provider: "claude_code",
            providerSessionID: "ps-42",
            providerRunID: nil,
            startedAt: "2026-03-24T00:00:00Z",
            endedAt: "2026-03-24T01:00:00Z",
            workspacePath: "/tmp/ws",
            sessionID: SessionID("session-42"),
            lastError: "Provider timed out after 300s",
            issue: issueWithBlockers,
            turnCount: 5,
            lastAgentEventType: "error",
            lastAgentMessage: "Timeout exceeded",
            tokens: try! TokenUsage(inputTokens: 1000, outputTokens: 500),
            logs: RunLogStats(eventCount: 10, latestSequence: EventSequence(10))
        )
        model.logEvents = [
            makeEvent(sequence: 1, kind: "error", rawJSON: #"{"message":"fail"}"#),
            makeEvent(sequence: 2, kind: "approval_request", rawJSON: #"{"message":"approve?"}"#),
            makeEvent(sequence: 3, kind: "status", rawJSON: #"{"status":"done"}"#),
        ]

        let view = SymphonyOperatorRootView(model: model)
        _ = view.body
    }

    func testHostedViewLayoutsAcrossEmptyAndLoadedBranches() throws {
#if canImport(AppKit)
        let model = SymphonyOperatorModel(client: PassiveSymphonyAPIClient())
        let hostingView = host(SymphonyOperatorRootView(model: model))
        render(hostingView)

        model.health = HealthResponse(status: "ok", serverTime: "2026-03-24T00:00:00Z", version: "1.0.0", trackerKind: "github")
        model.connectionError = "refresh failed"
        model.isConnecting = true
        model.isRefreshing = true
        model.issues = [
            makeIssueSummary(),
            IssueSummary(
                issueID: IssueID("issue-43"),
                identifier: try! IssueIdentifier(validating: "atjsh/example#43"),
                title: "Issue without provider badge",
                state: "queued",
                issueState: "OPEN",
                priority: 2,
                currentProvider: nil,
                currentRunID: nil,
                currentSessionID: nil
            ),
        ]
        model.selectedIssueID = IssueID("issue-42")
        model.issueDetail = makeIssueDetail()
        model.selectedRunID = RunID("run-42")
        model.runDetail = makeRunDetail()
        model.logEvents = [
            makeEvent(sequence: 1, kind: "message", rawJSON: #"{"message":"hello"}"#),
            makeEvent(sequence: 2, kind: "unknown", rawJSON: #"{"unexpected":"payload"}"#),
        ]
        model.liveStatus = "Live"
        render(hostingView)

        model.issueDetail = IssueDetail(issue: makeIssueDetail().issue, latestRun: nil, workspacePath: nil, recentSessions: [])
        model.runDetail = RunDetail(
            runID: RunID("run-43"),
            issueID: IssueID("issue-42"),
            issueIdentifier: try! IssueIdentifier(validating: "atjsh/example#42"),
            attempt: 2,
            status: "finished",
            provider: "copilot",
            providerSessionID: nil,
            providerRunID: nil,
            startedAt: "2026-03-24T00:00:00Z",
            endedAt: "2026-03-24T00:05:00Z",
            workspacePath: "/tmp/example",
            sessionID: nil,
            lastError: "none",
            issue: makeIssueDetail().issue,
            turnCount: 0,
            lastAgentEventType: nil,
            lastAgentMessage: nil,
            tokens: try! TokenUsage(inputTokens: 1, outputTokens: 2),
            logs: RunLogStats(eventCount: 0, latestSequence: nil)
        )
        model.logEvents = []
        model.isConnecting = false
        model.isRefreshing = false
        render(hostingView)

        let blockerRef = BlockerReference(
            issueID: IssueID("issue-99"),
            identifier: try! IssueIdentifier(validating: "atjsh/example#99"),
            state: "in_progress",
            issueState: "OPEN",
            url: "https://example.com/issues/99"
        )
        let issueWithBlockers = SymphonyShared.Issue(
            id: IssueID("issue-42"),
            identifier: try! IssueIdentifier(validating: "atjsh/example#42"),
            repository: "atjsh/example",
            number: 42,
            title: "Blocked issue",
            description: "Testing blockers",
            priority: 1,
            state: "in_progress",
            issueState: "OPEN",
            projectItemID: "item-42",
            url: "https://example.com/issues/42",
            labels: ["Bug"],
            blockedBy: [blockerRef],
            createdAt: "2026-03-24T00:00:00Z",
            updatedAt: "2026-03-24T01:00:00Z"
        )
        model.issueDetail = IssueDetail(issue: issueWithBlockers, latestRun: makeRunSummary(), workspacePath: "/tmp/ws", recentSessions: [])
        model.logEvents = [
            makeEvent(sequence: 1, kind: "error", rawJSON: #"{"message":"fail"}"#),
            makeEvent(sequence: 2, kind: "approval_request", rawJSON: #"{"message":"approve?"}"#),
            makeEvent(sequence: 3, kind: "status", rawJSON: #"{"status":"done"}"#),
        ]
        render(hostingView)
#endif
    }

    func testActionMethodsDispatchConnectRefreshAndSelectionFlows() async throws {
        let client = ActionDrivenSymphonyAPIClient()
        let model = SymphonyOperatorModel(
            client: client,
            initialEndpoint: try ServerEndpoint(scheme: "https", host: "example.com", port: 9443)
        )
        let view = SymphonyOperatorRootView(model: model)
#if canImport(AppKit)
        let hostingView = host(view)
        render(hostingView)
#endif

        view.triggerConnect()
        try await waitUntil { model.health?.trackerKind == "github" && model.issues.count == 1 }

        view.triggerRefresh()
        try await waitUntil { client.refreshCount == 1 }

        view.triggerIssueSelection(makeIssueSummary())
        try await waitUntil {
            model.issueDetail?.issue.id == IssueID("issue-42")
                && model.runDetail?.runID == RunID("run-42")
                && model.logEvents.count == 2
                && model.liveStatus == "Ended"
        }

        view.triggerRunSelection(RunID("run-42"))
        try await waitUntil { client.runDetailRequests.count >= 2 && model.logEvents.count == 2 }

        XCTAssertEqual(client.healthCount, 1)
        XCTAssertEqual(client.issuesCount, 2)
        XCTAssertEqual(client.refreshCount, 1)
        XCTAssertEqual(client.issueDetailRequests, [IssueID("issue-42")])
        XCTAssertEqual(client.runDetailRequests.last, RunID("run-42"))
        XCTAssertEqual(client.logRequests.last?.sessionID, SessionID("session-42"))
    }

    func testSelectionActionFactoriesDispatchIssueAndRunSelections() async throws {
        let client = ActionDrivenSymphonyAPIClient()
        let model = SymphonyOperatorModel(
            client: client,
            initialEndpoint: try ServerEndpoint(scheme: "https", host: "example.com", port: 9443)
        )
        let view = SymphonyOperatorRootView(model: model)

        let issueAction = view.makeIssueSelectionAction(for: makeIssueSummary())
        issueAction()
        try await waitUntil {
            model.issueDetail?.issue.id == IssueID("issue-42")
                && model.runDetail?.runID == RunID("run-42")
                && model.logEvents.count == 2
        }

        let runAction = view.makeRunSelectionAction(for: RunID("run-42"))
        runAction()
        try await waitUntil { client.runDetailRequests.count >= 2 }

        XCTAssertEqual(client.issueDetailRequests, [IssueID("issue-42")])
        XCTAssertEqual(client.runDetailRequests.last, RunID("run-42"))
    }
}

private struct PassiveSymphonyAPIClient: SymphonyAPIClientProtocol {
    func health(endpoint: ServerEndpoint) async throws -> HealthResponse {
        HealthResponse(status: "ok", serverTime: "", version: "", trackerKind: "")
    }

    func issues(endpoint: ServerEndpoint) async throws -> IssuesResponse {
        IssuesResponse(items: [])
    }

    func issueDetail(endpoint: ServerEndpoint, issueID: IssueID) async throws -> IssueDetail {
        makeIssueDetail()
    }

    func runDetail(endpoint: ServerEndpoint, runID: RunID) async throws -> RunDetail {
        makeRunDetail()
    }

    func logs(endpoint: ServerEndpoint, sessionID: SessionID, cursor: EventCursor?, limit: Int) async throws -> LogEntriesResponse {
        LogEntriesResponse(sessionID: sessionID, provider: "claude_code", items: [], nextCursor: nil, hasMore: false)
    }

    func refresh(endpoint: ServerEndpoint) async throws -> RefreshResponse {
        RefreshResponse(queued: true, requestedAt: "")
    }

    func logStream(endpoint: ServerEndpoint, sessionID: SessionID, cursor: EventCursor?) throws -> AsyncThrowingStream<AgentRawEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}

private final class ActionDrivenSymphonyAPIClient: SymphonyAPIClientProtocol, @unchecked Sendable {
    private(set) var healthCount = 0
    private(set) var issuesCount = 0
    private(set) var refreshCount = 0
    private(set) var issueDetailRequests = [IssueID]()
    private(set) var runDetailRequests = [RunID]()
    private(set) var logRequests = [(sessionID: SessionID, cursor: EventCursor?, limit: Int)]()

    func health(endpoint: ServerEndpoint) async throws -> HealthResponse {
        healthCount += 1
        return HealthResponse(status: "ok", serverTime: "2026-03-24T00:00:00Z", version: "1.0.0", trackerKind: "github")
    }

    func issues(endpoint: ServerEndpoint) async throws -> IssuesResponse {
        issuesCount += 1
        return IssuesResponse(items: [makeIssueSummary()])
    }

    func issueDetail(endpoint: ServerEndpoint, issueID: IssueID) async throws -> IssueDetail {
        issueDetailRequests.append(issueID)
        return makeIssueDetail()
    }

    func runDetail(endpoint: ServerEndpoint, runID: RunID) async throws -> RunDetail {
        runDetailRequests.append(runID)
        return makeRunDetail()
    }

    func logs(endpoint: ServerEndpoint, sessionID: SessionID, cursor: EventCursor?, limit: Int) async throws -> LogEntriesResponse {
        logRequests.append((sessionID, cursor, limit))
        return LogEntriesResponse(
            sessionID: sessionID,
            provider: "claude_code",
            items: [makeEvent(sequence: 1, kind: "message", rawJSON: #"{"message":"hello"}"#)],
            nextCursor: EventCursor(sessionID: sessionID, lastDeliveredSequence: EventSequence(1)),
            hasMore: false
        )
    }

    func refresh(endpoint: ServerEndpoint) async throws -> RefreshResponse {
        refreshCount += 1
        return RefreshResponse(queued: true, requestedAt: "2026-03-24T00:00:02Z")
    }

    func logStream(endpoint: ServerEndpoint, sessionID: SessionID, cursor: EventCursor?) throws -> AsyncThrowingStream<AgentRawEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(makeEvent(sequence: 2, kind: "tool_result", rawJSON: #"{"result":"ok"}"#))
            continuation.finish()
        }
    }
}

private func makeIssueSummary() -> IssueSummary {
    IssueSummary(
        issueID: IssueID("issue-42"),
        identifier: try! IssueIdentifier(validating: "atjsh/example#42"),
        title: "Provider-neutral operator",
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
        title: "Provider-neutral operator",
        description: "Show the real issue detail.",
        priority: 1,
        state: "in_progress",
        issueState: "OPEN",
        projectItemID: "item-42",
        url: "https://example.com/issues/42",
        labels: ["Operator"],
        blockedBy: [],
        createdAt: "2026-03-24T00:00:00Z",
        updatedAt: "2026-03-24T00:01:00Z"
    )
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
        lastEventAt: "2026-03-24T00:02:00Z",
        turnCount: 2,
        tokenUsage: try! TokenUsage(inputTokens: 7, outputTokens: 5),
        latestRateLimitPayload: nil
    )
    return IssueDetail(issue: issue, latestRun: makeRunSummary(), workspacePath: "/tmp/example", recentSessions: [session])
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
        startedAt: "2026-03-24T00:00:00Z",
        endedAt: nil,
        workspacePath: "/tmp/example",
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
        startedAt: "2026-03-24T00:00:00Z",
        endedAt: nil,
        workspacePath: "/tmp/example",
        sessionID: SessionID("session-42"),
        lastError: nil,
        issue: makeIssueDetail().issue,
        turnCount: 2,
        lastAgentEventType: "message",
        lastAgentMessage: "hello",
        tokens: try! TokenUsage(inputTokens: 7, outputTokens: 5),
        logs: RunLogStats(eventCount: 2, latestSequence: EventSequence(2))
    )
}

private func makeEvent(sequence: Int, kind: String, rawJSON: String) -> AgentRawEvent {
    AgentRawEvent(
        sessionID: SessionID("session-42"),
        provider: "claude_code",
        sequence: EventSequence(sequence),
        timestamp: "2026-03-24T00:00:0\(sequence)Z",
        rawJSON: rawJSON,
        providerEventType: "event",
        normalizedEventKind: kind
    )
}

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

#if canImport(AppKit)
@MainActor
private func host(_ view: SymphonyOperatorRootView) -> NSHostingView<SymphonyOperatorRootView> {
    let hostingView = NSHostingView(rootView: view)
    hostingView.frame = NSRect(x: 0, y: 0, width: 1280, height: 900)
    return hostingView
}

@MainActor
private func render(_ hostingView: NSHostingView<SymphonyOperatorRootView>) {
    hostingView.layoutSubtreeIfNeeded()
    hostingView.displayIfNeeded()
}
#endif
