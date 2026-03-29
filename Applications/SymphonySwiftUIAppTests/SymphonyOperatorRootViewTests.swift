import SwiftUI
import SymphonyShared
import Testing

@testable import SymphonySwiftUIApp

#if canImport(AppKit)
  import AppKit
#endif
#if canImport(UIKit)
  import UIKit
#endif

@MainActor
@Suite("SymphonyOperatorRootView")
struct SymphonyOperatorRootViewTests {
  @Test func MarkdownRendererUsesNativeAttributedTextAndFallsBackToPlainText() throws {
    let rendered = OperatorMarkdownRenderer.makeContent(
      from: "Before **bold** [docs](https://example.com) `code`"
    )

    XCTAssertTrue(rendered.renderedWithMarkdown)
    XCTAssertEqual(String(rendered.attributedText.characters), "Before bold docs code")
    XCTAssertTrue(rendered.attributedText.runs.contains { $0.link != nil })
    XCTAssertTrue(rendered.attributedText.runs.contains { $0.inlinePresentationIntent != nil })

    enum StubFailure: Error {
      case parsingFailed
    }

    let fallback = OperatorMarkdownRenderer.makeContent(from: "**broken**") { _ in
      throw StubFailure.parsingFailed
    }

    XCTAssertFalse(fallback.renderedWithMarkdown)
    XCTAssertEqual(String(fallback.attributedText.characters), "**broken**")
    XCTAssertFalse(fallback.attributedText.runs.contains { $0.link != nil })
  }

  @Test func BodyEvaluatesWithEmptyOperatorState() {
    let model = SymphonyOperatorModel(client: PassiveSymphonyAPIClient())
    let view = SymphonyOperatorRootView(model: model)

    exercise(view)

    model.selectedIssueID = IssueID("issue-42")
    exercise(view)
  }

  @Test func BodyEvaluatesWithLoadedIssueRunAndLogs() throws {
    let model = SymphonyOperatorModel(
      client: PassiveSymphonyAPIClient(),
      initialEndpoint: try ServerEndpoint(scheme: "https", host: "example.com", port: 9443)
    )
    model.health = HealthResponse(
      status: "ok", serverTime: "2026-03-24T00:00:00Z", version: "1.0.0", trackerKind: "github")
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
    exercise(view)
  }

  @Test func BodyEvaluatesWithMarkdownMessageContentInRunAndLogs() throws {
    let model = SymphonyOperatorModel(client: PassiveSymphonyAPIClient())
    model.selectedIssueID = IssueID("issue-42")
    model.issueDetail = makeIssueDetail()
    model.selectedRunID = RunID("run-42")

    let markdown = """
      Summary with **bold** and [`code`](https://example.com).

      Follow-up paragraph.
      """
    model.runDetail = RunDetail(
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
      lastAgentMessage: markdown,
      tokens: try! TokenUsage(inputTokens: 7, outputTokens: 5),
      logs: RunLogStats(eventCount: 2, latestSequence: EventSequence(2))
    )
    model.logEvents = [
      makeEvent(
        sequence: 1,
        kind: "message",
        rawJSON:
          #"{"message":"Summary with **bold** and [`code`](https://example.com).\n\nFollow-up paragraph."}"#
      )
    ]

    let view = SymphonyOperatorRootView(model: model)
    exercise(view)

    render(host(view))
  }

  @Test func BodyEvaluatesAcrossOverviewSessionsAndLogsTabs() throws {
    let model = SymphonyOperatorModel(client: PassiveSymphonyAPIClient())
    model.selectedIssueID = IssueID("issue-42")
    model.issueDetail = makeIssueDetail()
    model.selectedRunID = RunID("run-42")
    model.runDetail = makeRunDetail()
    model.logEvents = [
      makeEvent(sequence: 1, kind: "message", rawJSON: #"{"message":"hello"}"#),
      makeEvent(sequence: 2, kind: "tool_call", rawJSON: #"{"arguments":"pwd"}"#),
    ]

    let view = SymphonyOperatorRootView(model: model)

    model.selectedDetailTab = .overview
    exercise(view)

    model.selectedDetailTab = .sessions
    exercise(view)

    model.selectedDetailTab = .logs
    exercise(view)
  }

  @Test func BodyEvaluatesWithSearchAndLogFilterState() throws {
    let model = SymphonyOperatorModel(client: PassiveSymphonyAPIClient())
    model.issueSearchText = "provider"
    model.issues = [makeIssueSummary()]
    model.selectedIssueID = IssueID("issue-42")
    model.issueDetail = makeIssueDetail()
    model.runDetail = makeRunDetail()
    model.selectedDetailTab = .logs
    model.selectedLogFilter = .tools
    model.logEvents = [
      makeEvent(sequence: 1, kind: "message", rawJSON: #"{"message":"hello"}"#),
      makeEvent(sequence: 2, kind: "tool_call", rawJSON: #"{"arguments":"pwd"}"#),
    ]

    let view = SymphonyOperatorRootView(model: model)
    exercise(view)

    render(host(view))
  }

  @Test func BodyEvaluatesWithTokensErrorBlockersLabelsAndAllEventKinds() throws {
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
      providerThreadID: "thread-42",
      providerTurnID: "turn-42",
      providerRunID: "provider-run-42",
      runID: RunID("run-42"),
      providerProcessPID: nil,
      status: "active",
      lastEventType: "message",
      lastEventAt: "2026-03-24T01:00:00Z",
      turnCount: 5,
      tokenUsage: try! TokenUsage(inputTokens: 10, outputTokens: 20),
      latestRateLimitPayload: #"{"remaining":12,"reset_at":"2026-03-24T01:05:00Z"}"#
    )
    let outputOnlySession = AgentSession(
      sessionID: SessionID("session-43"),
      provider: "copilot",
      providerSessionID: nil,
      providerThreadID: nil,
      providerTurnID: nil,
      providerRunID: nil,
      runID: RunID("run-43"),
      providerProcessPID: nil,
      status: "streaming_turn",
      lastEventType: "usage",
      lastEventAt: nil,
      turnCount: 1,
      tokenUsage: try! TokenUsage(outputTokens: 8),
      latestRateLimitPayload: nil
    )
    let totalOnlySession = AgentSession(
      sessionID: SessionID("session-44"),
      provider: "codex",
      providerSessionID: nil,
      providerThreadID: nil,
      providerTurnID: nil,
      providerRunID: nil,
      runID: RunID("run-44"),
      providerProcessPID: nil,
      status: "waiting_for_retry",
      lastEventType: "usage",
      lastEventAt: nil,
      turnCount: 1,
      tokenUsage: try! TokenUsage(totalTokens: 13),
      latestRateLimitPayload: nil
    )
    model.issueDetail = IssueDetail(
      issue: issueWithBlockers,
      latestRun: makeRunSummary(),
      workspacePath: "/tmp/ws",
      recentSessions: [session, outputOnlySession, totalOnlySession]
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
      makeEvent(sequence: 1, kind: "message", rawJSON: #"{"message":"hello"}"#),
      makeEvent(sequence: 2, kind: "tool_call", rawJSON: #"{"arguments":"/bin/zsh -lc pwd"}"#),
      makeEvent(sequence: 3, kind: "tool_result", rawJSON: #"{"result":"/tmp/example"}"#),
      makeEvent(sequence: 4, kind: "status", rawJSON: #"{"status":"done"}"#),
      makeEvent(sequence: 5, kind: "usage", rawJSON: #"{"total_tokens":42}"#),
      makeEvent(sequence: 6, kind: "approval_request", rawJSON: #"{"message":"approve?"}"#),
      makeEvent(sequence: 7, kind: "error", rawJSON: #"{"message":"fail"}"#),
      AgentRawEvent(
        sessionID: SessionID("session-42"),
        provider: "claude_code",
        sequence: EventSequence(8),
        timestamp: "2026-03-24T00:00:08Z",
        rawJSON: #"{"payload":{"notes":"inspect raw payload"}}"#,
        providerEventType: "provider_custom",
        normalizedEventKind: "unexpected_kind"
      ),
    ]

    let view = SymphonyOperatorRootView(model: model)
    exercise(view)
  }

  @Test func RecentSessionHasVisibleTokenUsageCoversInputOutputTotalAndEmptyBranches() throws {
    XCTAssertTrue(recentSessionHasVisibleTokenUsage(try TokenUsage(inputTokens: 1)))
    XCTAssertTrue(recentSessionHasVisibleTokenUsage(try TokenUsage(outputTokens: 2)))
    XCTAssertTrue(recentSessionHasVisibleTokenUsage(try TokenUsage(totalTokens: 3)))
    XCTAssertFalse(recentSessionHasVisibleTokenUsage(try TokenUsage()))

    #if canImport(AppKit)
      let compactTheme = OperatorTheme(compact: true)
      let intrinsicMetricsHost = NSHostingView(
        rootView: AnyView(
          MetricsStrip(
            theme: compactTheme,
            metrics: [("Input", "1,200"), ("Output", "950"), ("Total", "2,150")]
          )
        )
      )
      #expect(intrinsicMetricsHost.fittingSize.width > 0)

      let intrinsicEmptyFlowHost = NSHostingView(
        rootView: AnyView(
          OperatorFlowLayout(spacing: 8) {}
        )
      )
      #expect(intrinsicEmptyFlowHost.fittingSize.height >= 0)
    #endif

    let theme = OperatorTheme(compact: true)
    render(
      host(
        AnyView(
          VStack(alignment: .leading, spacing: 12) {
            OperatorFlowLayout(spacing: 8) {}
            MetricsStrip(
              theme: theme,
              metrics: [("Input", "1,200"), ("Output", "950"), ("Total", "2,150")]
            )
            TokenUsageStrip(
              theme: theme,
              tokens: try! TokenUsage(inputTokens: 1_200, outputTokens: 950, totalTokens: 2_150)
            )
            TokenUsageStrip(theme: theme, tokens: try! TokenUsage())
          }
        ),
        width: 320,
        height: 320
      )
    )
  }

  @Test func HostedViewLayoutsAcrossEmptyAndLoadedBranches() throws {
    let model = SymphonyOperatorModel(client: PassiveSymphonyAPIClient())
    let hostingView = host(SymphonyOperatorRootView(model: model))
    render(hostingView)

    // Render with selectedIssueID but no detail loaded (loading state)
    model.selectedIssueID = IssueID("issue-42")
    render(hostingView)
    model.selectedIssueID = nil

    model.health = HealthResponse(
      status: "ok", serverTime: "2026-03-24T00:00:00Z", version: "1.0.0", trackerKind: "github")
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

    model.issueDetail = IssueDetail(
      issue: makeIssueDetail().issue, latestRun: nil, workspacePath: nil, recentSessions: [])
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
    model.issueDetail = IssueDetail(
      issue: issueWithBlockers, latestRun: makeRunSummary(), workspacePath: "/tmp/ws",
      recentSessions: [])
    model.logEvents = [
      makeEvent(sequence: 1, kind: "error", rawJSON: #"{"message":"fail"}"#),
      makeEvent(sequence: 2, kind: "approval_request", rawJSON: #"{"message":"approve?"}"#),
      makeEvent(sequence: 3, kind: "status", rawJSON: #"{"status":"done"}"#),
    ]
    render(hostingView)
  }

  @Test func ActionMethodsDispatchConnectRefreshAndSelectionFlows() async throws {
    let client = ActionDrivenSymphonyAPIClient()
    let model = SymphonyOperatorModel(
      client: client,
      initialEndpoint: try ServerEndpoint(scheme: "https", host: "example.com", port: 9443)
    )
    let view = SymphonyOperatorRootView(model: model)
    exercise(view)

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

    let runDetailRequestCount = client.runDetailRequests.count
    let logRequestCount = client.logRequests.count
    view.triggerRunSelection(RunID("run-42"))
    try await Task.sleep(for: .milliseconds(50))

    XCTAssertEqual(client.healthCount, 1)
    XCTAssertEqual(client.issuesCount, 2)
    XCTAssertEqual(client.refreshCount, 1)
    XCTAssertEqual(client.issueDetailRequests, [IssueID("issue-42")])
    XCTAssertEqual(client.runDetailRequests.count, runDetailRequestCount)
    XCTAssertEqual(client.runDetailRequests.last, RunID("run-42"))
    XCTAssertEqual(client.logRequests.count, logRequestCount)
    XCTAssertEqual(client.logRequests.last?.sessionID, SessionID("session-42"))
  }

  @Test func TriggerRunSelectionDoesNotReloadAlreadySelectedRun() async throws {
    let client = ActionDrivenSymphonyAPIClient()
    let model = SymphonyOperatorModel(
      client: client,
      initialEndpoint: try ServerEndpoint(scheme: "https", host: "example.com", port: 9443)
    )
    let view = SymphonyOperatorRootView(model: model)

    view.triggerIssueSelection(makeIssueSummary())
    try await waitUntil {
      model.runDetail?.runID == RunID("run-42")
        && model.logEvents.count == 2
        && model.liveStatus == "Ended"
    }

    let initialRunDetailRequests = client.runDetailRequests.count
    let initialLogRequests = client.logRequests.count
    let initialLiveStatus = model.liveStatus

    view.triggerRunSelection(RunID("run-42"))
    try await Task.sleep(for: .milliseconds(50))

    #expect(client.runDetailRequests.count == initialRunDetailRequests)
    #expect(client.logRequests.count == initialLogRequests)
    #expect(model.liveStatus == initialLiveStatus)
  }

  @Test func TriggerRunSelectionLoadsNewRunWhenSelectionChanges() async throws {
    let client = ActionDrivenSymphonyAPIClient()
    let model = SymphonyOperatorModel(
      client: client,
      initialEndpoint: try ServerEndpoint(scheme: "https", host: "example.com", port: 9443)
    )
    let view = SymphonyOperatorRootView(model: model)

    view.triggerIssueSelection(makeIssueSummary())
    try await waitUntil {
      model.runDetail?.runID == RunID("run-42")
        && model.logEvents.count == 2
        && model.liveStatus == "Ended"
    }

    view.triggerRunSelection(RunID("run-43"))
    try await waitUntil { client.runDetailRequests.contains(RunID("run-43")) }

    #expect(client.runDetailRequests.last == RunID("run-43"))
  }

  @Test func SelectionActionFactoriesDispatchIssueAndRunSelections() async throws {
    let client = ActionDrivenSymphonyAPIClient()
    let model = SymphonyOperatorModel(
      client: client,
      initialEndpoint: try ServerEndpoint(scheme: "https", host: "example.com", port: 9443)
    )
    let view = SymphonyOperatorRootView(model: model)

    var isPresented = false
    let presentationBinding = Binding(
      get: { isPresented },
      set: { isPresented = $0 }
    )
    let presentEditor = view.makePresentationAction(for: presentationBinding)
    presentEditor()
    XCTAssertTrue(isPresented)

    var columnVisibility: NavigationSplitViewVisibility = .detailOnly
    let columnVisibilityBinding = Binding(
      get: { columnVisibility },
      set: { columnVisibility = $0 }
    )
    let revealIssuesSidebar = view.makeRevealIssuesSidebarAction(for: columnVisibilityBinding)
    revealIssuesSidebar()
    #expect(columnVisibility == .all)

    exercise(AnyView(view.makeEndpointEditorView()), width: 640, height: 480)

    XCTAssertEqual(
      operatorColumnVisibilityAfterIssueSelection(isCompact: false, current: .automatic),
      .automatic
    )
    XCTAssertEqual(
      operatorColumnVisibilityAfterIssueSelection(isCompact: true, current: .automatic),
      .detailOnly
    )

    let connectAction = view.makeConnectAction()
    connectAction()
    try await waitUntil { model.health?.trackerKind == "github" && model.issues.count == 1 }

    let refreshAction = view.makeRefreshAction()
    refreshAction()
    try await waitUntil { client.refreshCount == 1 }

    let issueAction = view.makeIssueSelectionAction(for: makeIssueSummary())
    let issueHandler = view.makeIssueSelectionHandler()
    issueAction()
    try await waitUntil {
      model.issueDetail?.issue.id == IssueID("issue-42")
        && model.runDetail?.runID == RunID("run-42")
        && model.logEvents.count == 2
    }

    issueHandler(makeIssueSummary())
    try await waitUntil { client.issueDetailRequests.count >= 2 }

    let runDetailRequestCount = client.runDetailRequests.count
    let runAction = view.makeRunSelectionAction(for: RunID("run-42"))
    runAction()
    try await Task.sleep(for: .milliseconds(50))

    let runHandler = view.makeRunSelectionHandler()
    runHandler(RunID("run-43"))
    try await waitUntil { client.runDetailRequests.contains(RunID("run-43")) }

    XCTAssertEqual(client.healthCount, 1)
    XCTAssertEqual(client.refreshCount, 1)
    XCTAssertTrue(client.issueDetailRequests.contains(IssueID("issue-42")))
    XCTAssertTrue(client.runDetailRequests.count >= runDetailRequestCount)
    XCTAssertEqual(client.runDetailRequests.last, RunID("run-43"))
  }

  @Test func HelperViewsCoverCompactHeaderSupplementalRowsAndStatusTints() throws {
    _ = OperatorTheme(compact: true).successTint
    _ = statusTint("failed")
    _ = statusTint("queued")
    _ = statusTint("done")

    let compactPanel = IssueOverviewPanel(
      theme: OperatorTheme(compact: true),
      detail: makeIssueDetail(),
      latestRunSelected: false,
      runSelectionAction: {},
      compact: true
    )
    render(host(AnyView(compactPanel), width: 320, height: 640))

    let supplementalEvent = AgentRawEvent(
      sessionID: SessionID("session-42"),
      provider: "claude_code",
      sequence: EventSequence(99),
      timestamp: "2026-03-24T03:00:99Z",
      rawJSON: #"{"payload":{"notes":"raw payload"}}"#,
      providerEventType: "provider_custom",
      normalizedEventKind: "unexpected_kind"
    )
    let supplementalRow = LogEventRow(
      theme: OperatorTheme(compact: false),
      event: supplementalEvent,
      presentation: SymphonyEventPresentation(event: supplementalEvent),
      isLast: true
    )
    render(host(AnyView(supplementalRow), width: 480, height: 240))

    let compactSessions = RecentSessionsPanel(
      theme: OperatorTheme(compact: true),
      sessions: makeIssueDetail().recentSessions
    )
    render(host(AnyView(compactSessions), width: 320, height: 420))
  }

  @MainActor
  @Test func LogViewsCoverFilterActionsCompactStatusRowsAndSupplementalRawJSON() throws {
    var selection = OperatorLogFilter.all
    let binding = Binding(
      get: { selection },
      set: { selection = $0 }
    )

    operatorSetLogFilter(selection: binding, filter: .alerts)
    #expect(selection == .alerts)

    makeLogFilterAction(selection: binding, filter: .messages)()
    #expect(selection == .messages)

    let statusEvent = AgentRawEvent(
      sessionID: SessionID("session-status"),
      provider: "copilot_cli",
      sequence: EventSequence(10),
      timestamp: "2026-03-24T03:00:10Z",
      rawJSON: #"{"type":"status","message":"Queued"}"#,
      providerEventType: "status",
      normalizedEventKind: "status"
    )
    let usageEvent = AgentRawEvent(
      sessionID: SessionID("session-usage"),
      provider: "codex",
      sequence: EventSequence(11),
      timestamp: "2026-03-24T03:00:11Z",
      rawJSON: #"{"tokens":{"total":21}}"#,
      providerEventType: "usage",
      normalizedEventKind: "usage"
    )
    let supplementalEvent = AgentRawEvent(
      sessionID: SessionID("session-unknown"),
      provider: "claude_code",
      sequence: EventSequence(12),
      timestamp: "2026-03-24T03:00:12Z",
      rawJSON: #"{"payload":{"notes":"inspect raw payload"}}"#,
      providerEventType: "provider_custom",
      normalizedEventKind: "unexpected_kind"
    )

    do {
      let compactTheme = OperatorTheme(compact: true)
      let regularTheme = OperatorTheme(compact: false)
      let model = SymphonyOperatorModel(client: PassiveSymphonyAPIClient())
      model.liveStatus = "Queued"
      model.selectedLogFilter = .all
      model.logEvents = [statusEvent, usageEvent, supplementalEvent]

      render(
        host(AnyView(OperatorLogsPane(model: model, theme: regularTheme)), width: 960, height: 720))
      render(
        host(AnyView(OperatorLogsPane(model: model, theme: compactTheme)), width: 320, height: 720))
      render(
        host(
          AnyView(LogTimelinePanel(theme: compactTheme, logEvents: [statusEvent, usageEvent])),
          width: 320,
          height: 420
        ))
      render(
        host(
          AnyView(
            LogEventRow(
              theme: compactTheme,
              event: statusEvent,
              presentation: SymphonyEventPresentation(event: statusEvent),
              isLast: false
            )),
          width: 320,
          height: 220
        ))
      render(
        host(
          AnyView(
            LogEventRow(
              theme: regularTheme,
              event: usageEvent,
              presentation: SymphonyEventPresentation(event: usageEvent),
              isLast: false
            )),
          width: 720,
          height: 220
        ))
      render(
        host(
          AnyView(
            LogEventRow(
              theme: compactTheme,
              event: supplementalEvent,
              presentation: SymphonyEventPresentation(event: supplementalEvent),
              isLast: true
            )),
          width: 320,
          height: 260
        ))
    }
  }

  @Test func CompactLayoutPoliciesPreferStackingInlineTitlesAndPlatformNativeChoiceControls() {
    #expect(operatorSummaryActionPlacement(isCompact: true) == .stacked)
    #expect(operatorSummaryActionPlacement(isCompact: false) == .trailing)
    #expect(operatorChoiceControlPresentation(isCompact: true) == .scrolling)
    #if os(macOS)
      #expect(operatorChoiceControlPresentation(isCompact: false) == .segmented)
    #else
      #expect(operatorChoiceControlPresentation(isCompact: false) == .glassBar)
    #endif
    #expect(operatorIssueRowMetadataPlacement(isCompact: true) == .stacked)
    #expect(operatorIssueRowMetadataPlacement(isCompact: false) == .trailing)
    #expect(operatorDetailNavigationTitleDisplayPreference(isCompact: true) == .inline)
    #expect(operatorDetailNavigationTitleDisplayPreference(isCompact: false) == .automatic)
  }

  @Test func CompactPanelsRenderLongTextAndManyBadgesWithoutLayoutRegressions() throws {
    let longIssue = IssueDetail(
      issue: SymphonyShared.Issue(
        id: IssueID("issue-long"),
        identifier: try! IssueIdentifier(
          validating: "atjsh/example-with-a-very-long-repository-name#108"),
        repository: "atjsh/example-with-a-very-long-repository-name",
        number: 108,
        title:
          "Investigate an extremely long issue title that should still remain readable on compact devices",
        description:
          "A deliberately long description used to verify that the compact summary view wraps content intentionally instead of squeezing badges into vertical capsules.",
        priority: 1,
        state: "in_progress",
        issueState: "OPEN",
        projectItemID: "item-108",
        url: "https://example.com/issues/108",
        labels: ["feature", "ui", "very-long-label-to-test-wrapping", "investigation"],
        blockedBy: [],
        createdAt: "2026-03-24T00:00:00Z",
        updatedAt: "2026-03-24T01:00:00Z"
      ),
      latestRun: RunSummary(
        runID: RunID("run-long"),
        issueID: IssueID("issue-long"),
        issueIdentifier: try! IssueIdentifier(
          validating: "atjsh/example-with-a-very-long-repository-name#108"),
        attempt: 7,
        status: "streaming_turn",
        provider: "claude_code_enterprise_with_an_unusually_long_provider_name",
        providerSessionID: "provider-session-long",
        providerRunID: "provider-run-long",
        startedAt: "2026-03-24T00:00:00Z",
        endedAt: nil,
        workspacePath:
          "/tmp/symphony/this/is/a/very/long/workspace/path/used/to/check/compact/rendering",
        sessionID: SessionID("session-long"),
        lastError: nil
      ),
      workspacePath:
        "/tmp/symphony/this/is/a/very/long/workspace/path/used/to/check/compact/rendering",
      recentSessions: [makeIssueDetail().recentSessions[0]]
    )

    do {
      let compactTheme = OperatorTheme(compact: true)
      let model = SymphonyOperatorModel(client: PassiveSymphonyAPIClient())
      model.selectedIssueID = longIssue.issue.id
      model.issueDetail = longIssue
      model.runDetail = RunDetail(
        runID: RunID("run-long"),
        issueID: longIssue.issue.id,
        issueIdentifier: longIssue.issue.identifier,
        attempt: 7,
        status: "running",
        provider: "claude_code_enterprise_with_an_unusually_long_provider_name",
        providerSessionID: "provider-session-long",
        providerRunID: "provider-run-long",
        startedAt: "2026-03-24T00:00:00Z",
        endedAt: nil,
        workspacePath: longIssue.workspacePath ?? "/tmp/symphony/long-workspace",
        sessionID: SessionID("session-long"),
        lastError: nil,
        issue: longIssue.issue,
        turnCount: 32,
        lastAgentEventType: "message",
        lastAgentMessage: "Long content should still remain readable.",
        tokens: try! TokenUsage(inputTokens: 1200, outputTokens: 950, totalTokens: 2150),
        logs: RunLogStats(eventCount: 44, latestSequence: EventSequence(44))
      )
      model.logEvents = [
        makeEvent(sequence: 1, kind: "message", rawJSON: #"{"message":"hello"}"#),
        makeEvent(sequence: 2, kind: "tool_call", rawJSON: #"{"arguments":"pwd"}"#),
      ]

      render(
        host(
          AnyView(
            OperatorDetailView(model: model, theme: compactTheme, selectRun: { _ in })
          ),
          width: 320,
          height: 900
        )
      )
      render(
        host(
          AnyView(
            OperatorSidebarView(
              model: model,
              theme: compactTheme,
              openLocalServerEditor: {},
              openExistingServerEditor: {},
              selectIssue: { _ in }
            )
          ),
          width: 320,
          height: 720
        )
      )
    }
  }

  @Test func EndpointEditorHelpersRenderDismissAndConnect() async throws {
    let client = ActionDrivenSymphonyAPIClient()
    let model = SymphonyOperatorModel(client: client)
    model.host = "  example.com  "
    model.portText = "  9443 "
    model.connectionError = "Timed out"

    render(host(AnyView(OperatorEndpointEditorView(model: model)), width: 640, height: 480))

    var dismissCount = 0
    let dismissAction = makeEndpointDismissAction {
      dismissCount += 1
    }
    dismissAction()
    XCTAssertEqual(dismissCount, 1)

    let connectAction = makeEndpointConnectAction(
      model: model,
      draftHost: "  example.com  ",
      draftPort: "  9443 "
    ) {
      dismissCount += 1
    }
    connectAction()

    try await waitUntil {
      model.health?.trackerKind == "github"
        && model.connectionError == nil
        && dismissCount == 2
    }

    XCTAssertEqual(model.host, "example.com")
    XCTAssertEqual(model.portText, "9443")

    #if os(macOS)
      let workflowURL = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString
      ).appendingPathComponent("WORKFLOW.md")
      try FileManager.default.createDirectory(
        at: workflowURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try "Resolve {{issue.title}}".write(to: workflowURL, atomically: true, encoding: .utf8)

      let localManager = UITestingLocalServerManager()
      let localModel = SymphonyOperatorModel(
        client: client,
        localServerServices: LocalServerServices(
          manager: localManager,
          profileStore: InMemoryLocalServerProfileStore(
            profile: LocalServerProfile(workflowPath: workflowURL.path)
          ),
          secretStore: InMemoryLocalServerSecretStore(),
          workflowSelector: StubWorkflowSelector(selectedURL: workflowURL),
          workflowSaver: UITestingWorkflowFileSaver(environmentProvider: { [:] }),
          variableScanner: WorkflowEnvironmentVariableScanner(),
          helperLocator: StubHelperLocator(
            url: URL(fileURLWithPath: "/tmp/SymphonyLocalServerHelper")
          ),
          environmentProvider: { [:] }
        )
      )
      render(
        host(
          AnyView(OperatorEndpointEditorView(model: localModel, initialMode: .localServer)),
          width: 700,
          height: 620
        )
      )

      let localStartAction = makeLocalServerStartAction(
        model: localModel,
        draftHost: "localhost",
        draftPort: "8080"
      ) {
        dismissCount += 1
      }
      localStartAction()

      try await waitUntil {
        localModel.localServerLaunchState == .running && dismissCount == 3
      }

      let localStopAction = makeLocalServerStopAction(model: localModel)
      localStopAction()
      try await waitUntil {
        localModel.localServerLaunchState == .idle
      }
    #endif
  }

  @Test func EndpointEditorMacOSMinimumHeightsStayWithinShortDisplayBudget() {
    #if os(macOS)
      #expect(OperatorEndpointEditorView.workflowAuthoringMinimumSize.height <= 620)
      #expect(OperatorEndpointEditorView.connectionFormMinimumSize.height <= 560)
    #endif

    #expect(ServerEditorMode.localServer.id == "localServer")
    #expect(ServerEditorMode.existingServer.id == "existingServer")
    #expect(ServerEditorMode.localServer.title == "Local Server")
    #expect(ServerEditorMode.existingServer.title == "Existing Server")
  }

  @Test func ServerEditorActionPresentsSheetForSelectedMode() {
    let model = SymphonyOperatorModel(client: PassiveSymphonyAPIClient())
    let view = SymphonyOperatorRootView(model: model)

    view.makeServerEditorAction(mode: .existingServer)()
    view.makeServerEditorAction(mode: .localServer)()
  }

  @Test func SidebarSelectionHelperAndRenderedStatesCoverSelectionRowsAndStatusBranches() throws {
    let theme = OperatorTheme(compact: false)
    let compactTheme = OperatorTheme(compact: true)
    let noProviderIssue = IssueSummary(
      issueID: IssueID("issue-84"),
      identifier: try IssueIdentifier(validating: "atjsh/example#84"),
      title: "Endpoint editor polish",
      state: "queued",
      issueState: "OPEN",
      priority: nil,
      currentProvider: nil,
      currentRunID: nil,
      currentSessionID: nil
    )

    do {
      let connectedModel = SymphonyOperatorModel(client: PassiveSymphonyAPIClient())
      connectedModel.health = HealthResponse(
        status: "ok",
        serverTime: "2026-03-24T00:00:00Z",
        version: "1.0.0",
        trackerKind: "github"
      )
      connectedModel.issues = [makeIssueSummary(), noProviderIssue]
      render(
        host(
          AnyView(
            OperatorSidebarView(
              model: connectedModel,
              theme: theme,
              openLocalServerEditor: {},
              openExistingServerEditor: {},
              selectIssue: { _ in }
            )),
          width: 420,
          height: 900
        ))

      render(
        host(
          AnyView(
            makeOperatorServerStatusSummaryView(
              theme: theme,
              model: connectedModel,
              health: connectedModel.health,
              connectionError: nil,
              host: connectedModel.host,
              portText: connectedModel.portText,
              openLocalServerEditor: {},
              openExistingServerEditor: {}
            )),
          width: 420,
          height: 180
        ))
      render(
        host(
          AnyView(
            makeOperatorIssueSidebarRow(theme: theme, issue: makeIssueSummary(), isSelected: true)),
          width: 420,
          height: 160
        ))
      render(
        host(
          AnyView(
            makeOperatorIssueSidebarRow(theme: theme, issue: noProviderIssue, isSelected: false)),
          width: 420,
          height: 160
        ))
      render(
        host(
          AnyView(
            makeOperatorIssueSidebarRow(
              theme: compactTheme,
              issue: makeIssueSummary(),
              isSelected: false
            )),
          width: 320,
          height: 220
        ))

      let failedModel = SymphonyOperatorModel(client: PassiveSymphonyAPIClient())
      failedModel.connectionError = "Refresh failed"
      render(
        host(
          AnyView(
            OperatorSidebarView(
              model: failedModel,
              theme: theme,
              openLocalServerEditor: {},
              openExistingServerEditor: {},
              selectIssue: { _ in }
            )),
          width: 420,
          height: 900
        ))

      let idleModel = SymphonyOperatorModel(client: PassiveSymphonyAPIClient())
      render(
        host(
          AnyView(
            OperatorSidebarView(
              model: idleModel,
              theme: theme,
              openServerEditor: {},
              selectIssue: { _ in }
            )),
          width: 420,
          height: 900
        ))
      render(
        host(
          AnyView(
            OperatorSidebarView(
              model: idleModel,
              theme: theme,
              openLocalServerEditor: {},
              openExistingServerEditor: {},
              selectIssue: { _ in }
            )),
          width: 420,
          height: 900
        ))
    }

    let selectionModel = SymphonyOperatorModel(client: PassiveSymphonyAPIClient())
    selectionModel.issues = [makeIssueSummary(), noProviderIssue]

    var selectedIssues = [IssueID]()
    let recordSelection: (IssueSummary) -> Void = { summary in
      selectedIssues.append(summary.issueID)
    }

    let issueSelection = operatorSidebarIssueSelectionBinding(
      model: selectionModel,
      selectIssue: recordSelection
    )

    issueSelection.wrappedValue = nil
    operatorSidebarSelectIssue(nil, model: selectionModel, selectIssue: recordSelection)
    operatorSidebarSelectIssue(
      IssueID("missing"), model: selectionModel, selectIssue: recordSelection)

    selectionModel.selectedIssueID = IssueID("issue-42")
    selectionModel.issueDetail = makeIssueDetail()
    issueSelection.wrappedValue = IssueID("issue-42")
    operatorSidebarSelectIssue(
      IssueID("issue-42"), model: selectionModel, selectIssue: recordSelection)

    selectionModel.issueDetail = nil
    issueSelection.wrappedValue = IssueID("issue-42")
    operatorSidebarSelectIssue(
      IssueID("issue-42"), model: selectionModel, selectIssue: recordSelection)
    operatorSidebarSelectIssue(
      IssueID("issue-84"), model: selectionModel, selectIssue: recordSelection)
    let selectIssueAction = makeOperatorSidebarSelectIssueAction(
      issueID: IssueID("issue-84"),
      model: selectionModel,
      selectIssue: recordSelection
    )
    selectIssueAction()

    XCTAssertFalse(selectedIssues.isEmpty)
  }

  @Test func DetailHelpersRenderSessionBranchesAndDispatchSelectionActions() throws {
    let theme = OperatorTheme(compact: false)

    do {
      let model = SymphonyOperatorModel(client: PassiveSymphonyAPIClient())
      model.selectedIssueID = IssueID("issue-42")
      model.selectedDetailTab = .sessions
      model.issueDetail = IssueDetail(
        issue: makeIssueDetail().issue,
        latestRun: makeRunSummary(),
        workspacePath: "/tmp/example",
        recentSessions: []
      )
      render(
        host(
          AnyView(
            OperatorDetailView(model: model, theme: theme, selectRun: { _ in })),
          width: 960,
          height: 900
        ))

      model.issueDetail = makeIssueDetail()
      render(
        host(
          AnyView(
            OperatorDetailView(model: model, theme: theme, selectRun: { _ in })),
          width: 960,
          height: 900
        ))

      render(
        host(
          AnyView(RecentSessionsPanel(theme: theme, sessions: makeIssueDetail().recentSessions)),
          width: 960,
          height: 720
        ))
    }

    var selectedRuns = [RunID]()
    operatorSelectLatestRun(detail: makeIssueDetail()) { runID in
      selectedRuns.append(runID)
    }
    operatorSelectLatestRun(
      detail: IssueDetail(
        issue: makeIssueDetail().issue,
        latestRun: nil,
        workspacePath: nil,
        recentSessions: []
      )
    ) { runID in
      selectedRuns.append(runID)
    }
    let latestRunAction = makeOperatorSelectLatestRunAction(detail: makeIssueDetail()) { runID in
      selectedRuns.append(runID)
    }
    latestRunAction()
    let issueOverviewRunSelectionAction = makeIssueOverviewRunSelectionAction(
      latestRun: makeRunSummary()
    ) { runID in
      selectedRuns.append(runID)
    }
    issueOverviewRunSelectionAction?()
    XCTAssertEqual(selectedRuns, [RunID("run-42"), RunID("run-42"), RunID("run-42")])

    var selection = OperatorDetailTab.overview
    let binding = Binding(
      get: { selection },
      set: { selection = $0 }
    )

    operatorSetDetailTab(selection: binding, tab: .sessions)
    XCTAssertEqual(selection, .sessions)
    makeOperatorDetailTabAction(selection: binding, tab: .overview)()
    XCTAssertEqual(selection, .overview)

    operatorSetDetailTab(selection: binding, tab: .logs)
    XCTAssertEqual(selection, .logs)

    render(
      host(
        AnyView(makeOperatorDetailSegmentedTabPicker(selection: binding)),
        width: 420,
        height: 80
      )
    )
  }

  @Test func LogsAndThemeHelpersCoverFilterActionsTimelineStatesAndSelectionBackground() throws {
    let regularTheme = OperatorTheme(compact: false)
    let compactTheme = OperatorTheme(compact: true)

    _ = compactTheme.rowSpacing
    _ = regularTheme.rowSpacing
    _ = compactTheme.iconSize
    _ = regularTheme.iconSize
    _ = regularTheme.selectedFill
    _ = regularTheme.selectedStroke
    let logFilterPalette = operatorLogFilterPalette()
    _ = logFilterPalette.selectedFill
    _ = logFilterPalette.unselectedFill
    _ = logFilterPalette.unselectedStroke

    XCTAssertEqual(statusSymbol("failed"), "xmark.octagon.fill")
    XCTAssertEqual(statusSymbol("queued"), "clock.badge.exclamationmark.fill")
    XCTAssertEqual(statusSymbol("completed"), "checkmark.circle.fill")
    XCTAssertEqual(statusSymbol("running"), "bolt.horizontal.circle.fill")
    XCTAssertEqual(statusSymbol("idle"), "circle.fill")

    var filter = OperatorLogFilter.all
    let filterBinding = Binding(
      get: { filter },
      set: { filter = $0 }
    )

    makeLogFilterAction(selection: filterBinding, filter: .messages)()
    XCTAssertEqual(filter, .messages)
    makeLogFilterAction(selection: filterBinding, filter: .tools)()
    XCTAssertEqual(filter, .tools)
    makeLogFilterAction(selection: filterBinding, filter: .alerts)()
    XCTAssertEqual(filter, .alerts)
    render(
      host(
        AnyView(makeOperatorLogFilterSegmentedPicker(selection: filterBinding)),
        width: 420,
        height: 80
      )
    )

    let messageEvent = makeEvent(
      sequence: 1,
      kind: "message",
      rawJSON: #"{"message":"hello"}"#
    )
    let toolEvent = makeEvent(
      sequence: 2,
      kind: "tool_call",
      rawJSON: #"{"arguments":"pwd"}"#
    )
    let compactEvent = makeEvent(
      sequence: 3,
      kind: "status",
      rawJSON: #"{"status":"queued"}"#
    )
    let approvalEvent = makeEvent(
      sequence: 4,
      kind: "approval_request",
      rawJSON: #"{"message":"approve?"}"#
    )
    let errorEvent = makeEvent(
      sequence: 5,
      kind: "error",
      rawJSON: #"{"message":"fail"}"#
    )
    let supplementalEvent = AgentRawEvent(
      sessionID: SessionID("session-42"),
      provider: "claude_code",
      sequence: EventSequence(6),
      timestamp: "2026-03-24T00:00:06Z",
      rawJSON: #"{"payload":{"notes":"inspect raw payload"}}"#,
      providerEventType: "provider_custom",
      normalizedEventKind: "unexpected_kind"
    )

    do {
      render(
        host(
          AnyView(
            EmptyStatePanel(
              theme: regularTheme,
              systemImage: "tray",
              title: "Nothing here yet"
            )),
          width: 480,
          height: 220
        ))
      let model = SymphonyOperatorModel(client: PassiveSymphonyAPIClient())
      model.liveStatus = "Running"
      model.selectedLogFilter = .all
      model.logEvents = [
        messageEvent,
        toolEvent,
        compactEvent,
        approvalEvent,
        errorEvent,
        supplementalEvent,
      ]

      render(
        host(AnyView(OperatorLogsPane(model: model, theme: regularTheme)), width: 960, height: 900))
      render(
        host(AnyView(OperatorLogsPane(model: model, theme: compactTheme)), width: 320, height: 900))
      render(
        host(AnyView(LogTimelinePanel(theme: regularTheme, logEvents: [])), width: 960, height: 320)
      )
      render(
        host(
          AnyView(
            LogTimelinePanel(
              theme: regularTheme,
              logEvents: [
                messageEvent,
                toolEvent,
                compactEvent,
                approvalEvent,
                errorEvent,
                supplementalEvent,
              ]
            )),
          width: 960,
          height: 900
        ))
      render(
        host(
          AnyView(
            LogEventRow(
              theme: regularTheme,
              event: messageEvent,
              presentation: SymphonyEventPresentation(event: messageEvent),
              isLast: false
            )),
          width: 720,
          height: 220
        ))
      render(
        host(
          AnyView(
            LogEventRow(
              theme: regularTheme,
              event: toolEvent,
              presentation: SymphonyEventPresentation(event: toolEvent),
              isLast: false
            )),
          width: 720,
          height: 220
        ))
      render(
        host(
          AnyView(
            LogEventRow(
              theme: regularTheme,
              event: compactEvent,
              presentation: SymphonyEventPresentation(event: compactEvent),
              isLast: false
            )),
          width: 720,
          height: 220
        ))
      render(
        host(
          AnyView(
            LogEventRow(
              theme: regularTheme,
              event: approvalEvent,
              presentation: SymphonyEventPresentation(event: approvalEvent),
              isLast: false
            )),
          width: 720,
          height: 220
        ))
      render(
        host(
          AnyView(
            LogEventRow(
              theme: regularTheme,
              event: errorEvent,
              presentation: SymphonyEventPresentation(event: errorEvent),
              isLast: false
            )),
          width: 720,
          height: 220
        ))
      render(
        host(
          AnyView(
            LogEventRow(
              theme: regularTheme,
              event: supplementalEvent,
              presentation: SymphonyEventPresentation(event: supplementalEvent),
              isLast: true
            )),
          width: 720,
          height: 240
        ))
      render(
        host(
          AnyView(
            LogEventRow(
              theme: regularTheme,
              event: supplementalEvent,
              presentation: SymphonyEventPresentation(
                rowStyle: .supplemental,
                title: "",
                detail: "Detail-only accessibility label",
                metadata: "claude_code • #6 • provider_custom",
                showsRawJSON: true
              ),
              isLast: true
            )),
          width: 720,
          height: 240
        ))
      render(
        host(
          AnyView(Text("Selected").operatorSelectionBackground(regularTheme, isSelected: true)),
          width: 240,
          height: 100
        ))
      render(
        host(
          AnyView(Text("Unselected").operatorSelectionBackground(regularTheme, isSelected: false)),
          width: 240,
          height: 100
        ))
    }
  }

  @Test func CompactRootToolbarAndRegularRunOverviewRenderRemainingBranches() throws {
    let compactModel = SymphonyOperatorModel(client: PassiveSymphonyAPIClient())
    compactModel.selectedIssueID = IssueID("issue-42")
    compactModel.issueDetail = makeIssueDetail()
    compactModel.selectedRunID = RunID("run-42")
    compactModel.runDetail = makeRunDetail()

    render(
      host(
        AnyView(
          SymphonyOperatorRootView(
            model: compactModel,
            initialColumnVisibility: .detailOnly,
            compactOverride: true
          )
        ),
        width: 320,
        height: 720
      )
    )

    let regularTheme = OperatorTheme(compact: false)
    let noRunModel = SymphonyOperatorModel(client: PassiveSymphonyAPIClient())
    noRunModel.selectedIssueID = IssueID("issue-42")
    noRunModel.issueDetail = makeIssueDetail()
    noRunModel.runDetail = nil
    noRunModel.selectedDetailTab = .overview

    render(
      host(
        AnyView(OperatorDetailView(model: noRunModel, theme: regularTheme, selectRun: { _ in })),
        width: 960,
        height: 720
      )
    )
    render(
      host(
        AnyView(RunOverviewPanel(theme: regularTheme, runDetail: makeRunDetail())),
        width: 960,
        height: 720
      )
    )
  }

  @Test func MacOSLocalServerSummaryStatesAndEditorActionCoverRemainingBranches() throws {
    #if os(macOS)
      let workflowURL = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString
      ).appendingPathComponent("WORKFLOW.md")
      try FileManager.default.createDirectory(
        at: workflowURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try "Resolve {{issue.title}}".write(to: workflowURL, atomically: true, encoding: .utf8)

      let localModel = SymphonyOperatorModel(
        client: PassiveSymphonyAPIClient(),
        localServerServices: LocalServerServices(
          manager: UITestingLocalServerManager(),
          profileStore: InMemoryLocalServerProfileStore(
            profile: LocalServerProfile(workflowPath: workflowURL.path)
          ),
          secretStore: InMemoryLocalServerSecretStore(),
          workflowSelector: StubWorkflowSelector(selectedURL: workflowURL),
          workflowSaver: UITestingWorkflowFileSaver(environmentProvider: { [:] }),
          variableScanner: WorkflowEnvironmentVariableScanner(),
          helperLocator: StubHelperLocator(
            url: URL(fileURLWithPath: "/tmp/SymphonyLocalServerHelper")
          ),
          environmentProvider: { [:] }
        )
      )
      localModel.localServerWorkflowPath = workflowURL.path
      let theme = OperatorTheme(compact: false)

      localModel.localServerLaunchState = .starting
      render(
        host(
          AnyView(
            OperatorSidebarView(
              model: localModel,
              theme: theme,
              openLocalServerEditor: {},
              openExistingServerEditor: {},
              selectIssue: { _ in }
            )),
          width: 420,
          height: 900
        ))

      localModel.localServerLaunchState = .running
      render(
        host(
          AnyView(
            OperatorSidebarView(
              model: localModel,
              theme: theme,
              openLocalServerEditor: {},
              openExistingServerEditor: {},
              selectIssue: { _ in }
            )),
          width: 420,
          height: 900
        ))

      localModel.localServerLaunchState = .failed
      localModel.localServerFailure = "Launch failed"
      render(
        host(
          AnyView(
            OperatorSidebarView(
              model: localModel,
              theme: theme,
              openLocalServerEditor: {},
              openExistingServerEditor: {},
              selectIssue: { _ in }
            )),
          width: 420,
          height: 900
        ))

      let rootView = SymphonyOperatorRootView(model: localModel)
      rootView.makeServerEditorAction(mode: .localServer)()
      rootView.makeServerEditorAction(mode: .existingServer)()
    #endif
  }

  @Test func SharedHelperViewsRenderDetailSelectionAndFlowRowsOnIOS() throws {
    let theme = OperatorTheme(compact: false)

    render(
      host(
        AnyView(
          VStack(alignment: .leading, spacing: 12) {
            DetailLine(compact: false, label: "Workspace", value: "/tmp/example", monospaced: true)
            DetailLine(compact: true, label: "Status", value: "Running")
            Text("Selectable")
              .operatorDetailTextSelection(enabled: true)
            EmptyStatePanel(
              theme: theme,
              systemImage: "tray",
              title: "Still empty",
              detail: "Waiting for a selected run."
            )
            OperatorFlowLayout(spacing: 8, rowSpacing: 8) {
              Text("One")
              Text("Two")
              Text("Three")
            }
          }
        ),
        width: 480,
        height: 420
      )
    )

    #if canImport(UIKit)
      let selectionHostingView = host(
        AnyView(Text("Selectable").operatorDetailTextSelection(enabled: true)),
        width: 180,
        height: 80
      )
      let selectionSize = selectionHostingView.controller.sizeThatFits(in: CGSize(width: 180, height: 80))
      #expect(selectionSize.height > 0)

      let flowHostingView = host(
        AnyView(
          OperatorFlowLayout(spacing: 8, rowSpacing: 8) {
            Text("One")
            Text("Two")
            Text("Three")
            Text("Four")
          }
        ),
        width: 90,
        height: 240
      )
      let flowSize = flowHostingView.controller.sizeThatFits(in: CGSize(width: 90, height: 240))
      #expect(flowSize.height > 0)
    #endif

    #if os(iOS)
      #expect(detailLineTextSelectionEnabled(for: true) == false)
    #else
      #expect(detailLineTextSelectionEnabled(for: true) == true)
    #endif
    #expect(
      operatorIssueRowMetadataPlacement(isCompact: false, prefersAccessibilityLayout: true) == .stacked
    )
    #expect(operatorFlowLayoutMaxWidth(for: nil) == .greatestFiniteMagnitude)
    #expect(operatorFlowLayoutMaxWidth(for: 144) == 144)
    let measuredFlowSize = operatorFlowLayoutMeasuredSize(
      proposedWidth: nil,
      rowWidths: [72, 96],
      rowHeights: [20, 28],
      rowSpacing: 8
    )
    #expect(measuredFlowSize.width == 96)
    #expect(measuredFlowSize.height == 56)
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

  func logs(endpoint: ServerEndpoint, sessionID: SessionID, cursor: EventCursor?, limit: Int)
    async throws -> LogEntriesResponse
  {
    LogEntriesResponse(
      sessionID: sessionID, provider: "claude_code", items: [], nextCursor: nil, hasMore: false)
  }

  func refresh(endpoint: ServerEndpoint) async throws -> RefreshResponse {
    RefreshResponse(queued: true, requestedAt: "")
  }

  func logStream(endpoint: ServerEndpoint, sessionID: SessionID, cursor: EventCursor?) throws
    -> AsyncThrowingStream<AgentRawEvent, Error>
  {
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
    return HealthResponse(
      status: "ok", serverTime: "2026-03-24T00:00:00Z", version: "1.0.0", trackerKind: "github")
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

  func logs(endpoint: ServerEndpoint, sessionID: SessionID, cursor: EventCursor?, limit: Int)
    async throws -> LogEntriesResponse
  {
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

  func logStream(endpoint: ServerEndpoint, sessionID: SessionID, cursor: EventCursor?) throws
    -> AsyncThrowingStream<AgentRawEvent, Error>
  {
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
    latestRateLimitPayload: #"{"remaining":7,"reset_at":"2026-03-24T00:05:00Z"}"#
  )
  return IssueDetail(
    issue: issue, latestRun: makeRunSummary(), workspacePath: "/tmp/example",
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
  timeout: Duration = .seconds(5),
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
  private func host(
    _ view: AnyView,
    width: CGFloat = 1280,
    height: CGFloat = 900
  ) -> NSHostingView<AnyView> {
    let hostingView = NSHostingView(rootView: view)
    hostingView.frame = NSRect(x: 0, y: 0, width: width, height: height)
    return hostingView
  }

  @MainActor
  private func render(_ hostingView: NSHostingView<SymphonyOperatorRootView>) {
    hostingView.layoutSubtreeIfNeeded()
    hostingView.displayIfNeeded()
  }

  @MainActor
  private func render(_ hostingView: NSHostingView<AnyView>) {
    hostingView.layoutSubtreeIfNeeded()
    hostingView.displayIfNeeded()
  }
#endif

#if canImport(UIKit)
  @MainActor
  private struct IOSHostedView<Content: View> {
    let window: UIWindow
    let controller: UIHostingController<Content>
  }

  @MainActor
  private func host(
    _ view: SymphonyOperatorRootView,
    width: CGFloat = 1280,
    height: CGFloat = 900
  ) -> IOSHostedView<SymphonyOperatorRootView> {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: height))
    let controller = UIHostingController(rootView: view)
    window.rootViewController = controller
    window.isHidden = false
    controller.view.frame = window.bounds
    controller.loadViewIfNeeded()
    return IOSHostedView(window: window, controller: controller)
  }

  @MainActor
  private func host(
    _ view: AnyView,
    width: CGFloat = 1280,
    height: CGFloat = 900
  ) -> IOSHostedView<AnyView> {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: height))
    let controller = UIHostingController(rootView: view)
    window.rootViewController = controller
    window.isHidden = false
    controller.view.frame = window.bounds
    controller.loadViewIfNeeded()
    return IOSHostedView(window: window, controller: controller)
  }

  @MainActor
  private func render(_ hostingView: IOSHostedView<SymphonyOperatorRootView>) {
    hostingView.controller.view.frame = hostingView.window.bounds
    hostingView.controller.view.setNeedsLayout()
    hostingView.controller.view.layoutIfNeeded()
  }

  @MainActor
  private func render(_ hostingView: IOSHostedView<AnyView>) {
    hostingView.controller.view.frame = hostingView.window.bounds
    hostingView.controller.view.setNeedsLayout()
    hostingView.controller.view.layoutIfNeeded()
  }
#endif

@MainActor
private func exercise(
  _ view: SymphonyOperatorRootView,
  width: CGFloat = 1280,
  height: CGFloat = 900
) {
  #if canImport(AppKit)
    render(host(view))
  #elseif canImport(UIKit)
    render(host(view, width: width, height: height))
  #else
    _ = view
  #endif
}

@MainActor
private func exercise(
  _ view: AnyView,
  width: CGFloat = 1280,
  height: CGFloat = 900
) {
  #if canImport(AppKit)
    render(host(view, width: width, height: height))
  #elseif canImport(UIKit)
    render(host(view, width: width, height: height))
  #else
    _ = view
  #endif
}
