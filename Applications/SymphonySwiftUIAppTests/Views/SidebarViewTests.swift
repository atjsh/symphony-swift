import SwiftUI
import SymphonyShared
import Testing

@testable import SymphonySwiftUIApp

#if canImport(AppKit)
  import AppKit
#endif

@MainActor
@Suite("SidebarView – Selection & Rendering", .tags(.views))
struct SidebarViewTests {
  @Test func CompactLayoutPoliciesPreferStackingInlineTitlesAndPlatformNativeChoiceControls() {
    #expect(operatorSummaryActionPlacement(isCompact: true) == .stacked)
    #expect(operatorSummaryActionPlacement(isCompact: false) == .trailing)
    #expect(operatorChoiceControlPresentation(isCompact: true) == .scrolling)
    #expect(operatorChoiceControlButtonStyle(isCompact: true) == .quietCapsule)
    #expect(operatorChoiceControlButtonStyle(isCompact: false) == .platformDefault)
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
            OperatorSidebarView.makeServerStatusSummaryView(
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
            OperatorSidebarView.makeIssueSidebarRow(
              theme: theme, issue: makeIssueSummary(), isSelected: true)),
          width: 420,
          height: 160
        ))
      render(
        host(
          AnyView(
            OperatorSidebarView.makeIssueSidebarRow(
              theme: theme, issue: noProviderIssue, isSelected: false)),
          width: 420,
          height: 160
        ))
      render(
        host(
          AnyView(
            OperatorSidebarView.makeIssueSidebarRow(
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

    let issueSelection = OperatorSidebarView.issueSelectionBinding(
      model: selectionModel,
      selectIssue: recordSelection
    )

    issueSelection.wrappedValue = nil
    OperatorSidebarView.selectIssue(
      nil, model: selectionModel, selectIssue: recordSelection)
    OperatorSidebarView.selectIssue(
      IssueID("missing"), model: selectionModel, selectIssue: recordSelection)

    selectionModel.selectedIssueID = IssueID("issue-42")
    selectionModel.issueDetail = makeIssueDetail()
    issueSelection.wrappedValue = IssueID("issue-42")
    OperatorSidebarView.selectIssue(
      IssueID("issue-42"), model: selectionModel, selectIssue: recordSelection)

    selectionModel.issueDetail = nil
    issueSelection.wrappedValue = IssueID("issue-42")
    OperatorSidebarView.selectIssue(
      IssueID("issue-42"), model: selectionModel, selectIssue: recordSelection)
    OperatorSidebarView.selectIssue(
      IssueID("issue-84"), model: selectionModel, selectIssue: recordSelection)
    let selectIssueAction = OperatorSidebarView.makeSelectIssueAction(
      issueID: IssueID("issue-84"),
      model: selectionModel,
      selectIssue: recordSelection
    )
    selectIssueAction()

    #expect(selectedIssues.isEmpty == false)
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

  @Test func CompactPanelsRenderLongTextAndManyBadgesWithoutLayoutRegressions() throws {
    let longIssue = IssueDetail(
      issue: SymphonyShared.Issue(
        id: IssueID("issue-long"),
        identifier: try! IssueIdentifier( // swiftlint:disable:this force_try
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
        issueIdentifier: try! IssueIdentifier( // swiftlint:disable:this force_try
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
        tokens: try! TokenUsage(inputTokens: 1200, outputTokens: 950, totalTokens: 2150), // swiftlint:disable:this force_try
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
}
