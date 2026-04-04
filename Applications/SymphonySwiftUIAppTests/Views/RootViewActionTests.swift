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
@Suite("RootView – Actions & Layout", .tags(.views))
struct RootViewActionTests {
  @Test func HostedViewLayoutsAcrossEmptyAndLoadedBranches() throws {
    let model = SymphonyOperatorModel(client: PassiveSymphonyAPIClient())
    let hostingView = host(SymphonyOperatorRootView(model: model))
    render(hostingView)

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
        identifier: try! IssueIdentifier(validating: "atjsh/example#43"), // swiftlint:disable:this force_try
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
      issueIdentifier: try! IssueIdentifier(validating: "atjsh/example#42"), // swiftlint:disable:this force_try
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
      tokens: try! TokenUsage(inputTokens: 1, outputTokens: 2), // swiftlint:disable:this force_try
      logs: RunLogStats(eventCount: 0, latestSequence: nil)
    )
    model.logEvents = []
    model.isConnecting = false
    model.isRefreshing = false
    render(hostingView)

    let blockerRef = BlockerReference(
      issueID: IssueID("issue-99"),
      identifier: try! IssueIdentifier(validating: "atjsh/example#99"), // swiftlint:disable:this force_try
      state: "in_progress",
      issueState: "OPEN",
      url: "https://example.com/issues/99"
    )
    let issueWithBlockers = SymphonyShared.Issue(
      id: IssueID("issue-42"),
      identifier: try! IssueIdentifier(validating: "atjsh/example#42"), // swiftlint:disable:this force_try
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

    #expect(client.healthCount == 1)
    #expect(client.issuesCount == 2)
    #expect(client.refreshCount == 1)
    #expect(client.issueDetailRequests == [IssueID("issue-42")])
    #expect(client.runDetailRequests.count == runDetailRequestCount)
    #expect(client.runDetailRequests.last == RunID("run-42"))
    #expect(client.logRequests.count == logRequestCount)
    #expect(client.logRequests.last?.sessionID == SessionID("session-42"))
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
    #expect(isPresented)

    var columnVisibility: NavigationSplitViewVisibility = .detailOnly
    let columnVisibilityBinding = Binding(
      get: { columnVisibility },
      set: { columnVisibility = $0 }
    )
    let revealIssuesSidebar = view.makeRevealIssuesSidebarAction(for: columnVisibilityBinding)
    revealIssuesSidebar()
    #expect(columnVisibility == .all)

    exercise(AnyView(view.makeEndpointEditorView()), width: 640, height: 480)

    #expect(
      SymphonyOperatorRootView.columnVisibilityAfterIssueSelection(
        isCompact: false, current: .automatic) == .automatic)
    #expect(
      SymphonyOperatorRootView.columnVisibilityAfterIssueSelection(
        isCompact: true, current: .automatic) == .detailOnly)

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

    #expect(client.healthCount == 1)
    #expect(client.refreshCount == 1)
    #expect(client.issueDetailRequests.contains(IssueID("issue-42")))
    #expect(client.runDetailRequests.count >= runDetailRequestCount)
    #expect(client.runDetailRequests.last == RunID("run-43"))
  }

  @Test func ServerEditorActionPresentsSheetForSelectedMode() {
    let model = SymphonyOperatorModel(client: PassiveSymphonyAPIClient())
    let view = SymphonyOperatorRootView(model: model)

    view.makeServerEditorAction(mode: .existingServer)()
    view.makeServerEditorAction(mode: .localServer)()
  }

  @Test func MacOSRootViewFittingHeightStaysWithinBoundedIdealSize() throws {
    #if os(macOS)
      let emptyModel = SymphonyOperatorModel(client: PassiveSymphonyAPIClient())
      let emptySize = fittingSize(AnyView(SymphonyOperatorRootView(model: emptyModel)))
      #expect(emptySize.width >= 1024)
      #expect(emptySize.height >= 680)
      #expect(emptySize.height <= 820)

      let loadedModel = SymphonyOperatorModel(client: PassiveSymphonyAPIClient())
      loadedModel.health = HealthResponse(
        status: "ok", serverTime: "2026-03-24T00:00:00Z", version: "1.0.0",
        trackerKind: "github")
      loadedModel.issues = [makeIssueSummary()]
      loadedModel.selectedIssueID = IssueID("issue-42")
      loadedModel.issueDetail = makeIssueDetail()
      loadedModel.selectedRunID = RunID("run-42")
      loadedModel.runDetail = makeRunDetail()
      loadedModel.logEvents = [
        makeEvent(sequence: 1, kind: "message", rawJSON: #"{"message":"hello"}"#)
      ]

      let loadedSize = fittingSize(AnyView(SymphonyOperatorRootView(model: loadedModel)))
      #expect(loadedSize.width >= 1024)
      #expect(loadedSize.height >= 680)
      #expect(loadedSize.height <= 820)
    #endif
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
        AnyView(
          OperatorDetailView(model: noRunModel, theme: regularTheme, selectRun: { _ in })),
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
}
