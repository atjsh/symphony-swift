// swiftlint:disable force_try
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
@Suite("DetailView – Panels & Selection", .tags(.views))
struct DetailViewTests {
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
          OperatorDetailView(model: model, theme: theme, selectRun: { _ in }),
          width: 960,
          height: 900
        ))

      model.issueDetail = makeIssueDetail()
      render(
        host(
          OperatorDetailView(model: model, theme: theme, selectRun: { _ in }),
          width: 960,
          height: 900
        ))

      render(
        host(
          RecentSessionsPanel(theme: theme, sessions: makeIssueDetail().recentSessions),
          width: 960,
          height: 720
        ))
    }

    var selectedRuns = [RunID]()
    OperatorDetailSummaryView.selectLatestRun(detail: makeIssueDetail()) { runID in
      selectedRuns.append(runID)
    }
    OperatorDetailSummaryView.selectLatestRun(
      detail: IssueDetail(
        issue: makeIssueDetail().issue,
        latestRun: nil,
        workspacePath: nil,
        recentSessions: []
      )
    ) { runID in
      selectedRuns.append(runID)
    }
    let latestRunAction = OperatorDetailSummaryView.makeSelectLatestRunAction(
      detail: makeIssueDetail()
    ) { runID in
      selectedRuns.append(runID)
    }
    latestRunAction()
    let issueOverviewRunSelectionAction =
      OperatorDetailSummaryView.makeIssueOverviewRunSelectionAction(
        latestRun: makeRunSummary()
      ) { runID in
        selectedRuns.append(runID)
      }
    issueOverviewRunSelectionAction?()
    #expect(selectedRuns == [RunID("run-42"), RunID("run-42"), RunID("run-42")])

    var selection = OperatorDetailTab.overview
    let binding = Binding(
      get: { selection },
      set: { selection = $0 }
    )

    OperatorDetailTabBar.setDetailTab(selection: binding, tab: .sessions)
    #expect(selection == .sessions)
    OperatorDetailTabBar.makeTabAction(selection: binding, tab: .overview)()
    #expect(selection == .overview)

    OperatorDetailTabBar.setDetailTab(selection: binding, tab: .logs)
    #expect(selection == .logs)

    render(
      host(
        OperatorDetailTabBar.makeSegmentedTabPicker(selection: binding),
        width: 420,
        height: 80
      )
    )
  }

  @Test func DetailEmptyStateKeepsBoundedContentHeightAndPreservesMacOSActionIdentifiers() throws {
    let theme = OperatorTheme(compact: false)
    let source = try String(contentsOf: operatorDetailPanelsSourceURL, encoding: .utf8)
    #expect(source.contains(#""No Issue Selected""#))
    #expect(source.contains(#""operator-detail-empty-state""#))
    #expect(source.contains(#""empty-start-local-server-button""#))
    #expect(source.contains(#""empty-existing-server-button""#))

    #if os(macOS)
      let workflowURL = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString
      ).appendingPathComponent("WORKFLOW.md")
      try FileManager.default.createDirectory(
        at: workflowURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try "Resolve {{issue.title}}".write(to: workflowURL, atomically: true, encoding: .utf8)

      let model = SymphonyOperatorModel(
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
      let intrinsicSize = fittingSize(
        OperatorDetailView(
          model: model,
          theme: theme,
          selectRun: { _ in }
        )
      )
      #expect(intrinsicSize.height > 0)
      #expect(intrinsicSize.height < 720)

      let hostingView = host(
        OperatorDetailView(
          model: model,
          theme: theme,
          selectRun: { _ in }
        ),
        width: 960,
        height: 720
      )
      render(hostingView)
    #else
      let model = SymphonyOperatorModel(client: PassiveSymphonyAPIClient())
      let hostingView = host(
        OperatorDetailView(
          model: model,
          theme: theme,
          selectRun: { _ in }
        ),
        width: 390,
        height: 844
      )
      render(hostingView)
      let intrinsicSize = hostingView.controller.sizeThatFits(
        in: CGSize(width: 390, height: 844))
      #expect(intrinsicSize.height > 0)
    #endif
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
    render(host(compactPanel, width: 320, height: 640))

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
    render(host(supplementalRow, width: 480, height: 240))

    let compactSessions = RecentSessionsPanel(
      theme: OperatorTheme(compact: true),
      sessions: makeIssueDetail().recentSessions
    )
    render(host(compactSessions, width: 320, height: 420))
  }

  @Test func scrollingTabBarRendersCompactIOSGridLayout() throws {
    let compactTheme = OperatorTheme(compact: true)
    let tabBar = OperatorDetailTabBar(
      theme: compactTheme,
      selection: .constant(.overview)
    )
    exercise(tabBar, width: 320, height: 200)

    let regularTheme = OperatorTheme(compact: false)
    let regularTabBar = OperatorDetailTabBar(
      theme: regularTheme,
      selection: .constant(.progress)
    )
    exercise(regularTabBar, width: 480, height: 100)
  }

  @Test func sessionsListRendersEmptyState() throws {
    let theme = OperatorTheme(compact: false)
    let emptyPanel = RecentSessionsPanel(
      theme: theme,
      sessions: []
    )
    exercise(emptyPanel, width: 480, height: 300)
  }

  @Test func sessionsListRendersMultipleSessions() throws {
    let detail = makeIssueDetail()
    let theme = OperatorTheme(compact: false)
    let sessionsPanel = RecentSessionsPanel(
      theme: theme,
      sessions: detail.recentSessions + detail.recentSessions
    )
    exercise(sessionsPanel, width: 480, height: 600)
  }

  @Test func sessionsListRendersSessionWithRateLimitPayload() throws {
    let session = AgentSession(
      sessionID: SessionID("session-rl"),
      provider: "claude_code",
      providerSessionID: "provider-session-rl",
      providerThreadID: "thread-rl",
      providerTurnID: "turn-rl",
      providerRunID: "provider-run-rl",
      runID: RunID("run-rl"),
      providerProcessPID: "1000",
      status: "active",
      lastEventType: "rate_limit",
      lastEventAt: "2026-03-24T03:05:00Z",
      turnCount: 3,
      tokenUsage: try! TokenUsage(inputTokens: 10, outputTokens: 8),
      latestRateLimitPayload: #"{"remaining":12,"reset_at":"2026-03-24T01:05:00Z"}"#
    )
    let theme = OperatorTheme(compact: false)
    let sessionsPanel = RecentSessionsPanel(theme: theme, sessions: [session])
    exercise(sessionsPanel, width: 480, height: 400)
  }
}

// swiftlint:enable force_try
