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
@Suite("RootView – Body Evaluation", .tags(.views))
struct RootViewBodyTests {
  @Test func MarkdownRendererUsesNativeAttributedTextAndFallsBackToPlainText() throws {
    let rendered = OperatorMarkdownRenderer.makeContent(
      from: "Before **bold** [docs](https://example.com) `code`"
    )

    #expect(rendered.renderedWithMarkdown)
    #expect(String(rendered.attributedText.characters) == "Before bold docs code")
    #expect(rendered.attributedText.runs.contains { $0.link != nil })
    #expect(rendered.attributedText.runs.contains { $0.inlinePresentationIntent != nil })

    enum StubFailure: Error {
      case parsingFailed
    }

    let fallback = OperatorMarkdownRenderer.makeContent(from: "**broken**") { _ in
      throw StubFailure.parsingFailed
    }

    #expect(fallback.renderedWithMarkdown == false)
    #expect(String(fallback.attributedText.characters) == "**broken**")
    #expect(fallback.attributedText.runs.contains { $0.link != nil } == false)
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
    model.progressReportModel.testingSetReport(makeIssueProgressReport())

    let view = SymphonyOperatorRootView(model: model)

    model.selectedDetailTab = .overview
    exercise(view)

    model.selectedDetailTab = .sessions
    exercise(view)

    model.selectedDetailTab = .logs
    exercise(view)

    model.selectedDetailTab = .progress
    exercise(view)
  }

  @Test func CompactRunOverviewOnlyShowsLatestMessagePreviewInRegularLayouts() {
    #expect(OperatorDetailSummaryView.runOverviewShowsLatestMessage(compact: true) == false)
    #expect(OperatorDetailSummaryView.runOverviewShowsLatestMessage(compact: false) == true)
    #expect(OperatorDetailSummaryView.runOverviewShowsLastEvent(compact: true) == false)
    #expect(OperatorDetailSummaryView.runOverviewShowsLastEvent(compact: false) == true)
  }

  @Test func ProgressTabEvaluatesInCompactAndRegularLayouts() throws {
    let model = SymphonyOperatorModel(client: PassiveSymphonyAPIClient())
    model.selectedIssueID = IssueID("issue-42")
    model.issueDetail = makeIssueDetail()
    model.selectedDetailTab = .progress
    model.progressReportModel.testingSetReport(makeIssueProgressReport())

    exercise(
      SymphonyOperatorRootView(model: model, compactOverride: false), width: 1280, height: 900)
    exercise(
      SymphonyOperatorRootView(model: model, compactOverride: true), width: 390, height: 844)
  }

  @Test func ProgressTabEvaluatesUnsupportedAndFailedSyntaxHealthStates() throws {
    let unsupportedModel = SymphonyOperatorModel(client: PassiveSymphonyAPIClient())
    unsupportedModel.selectedIssueID = IssueID("issue-42")
    unsupportedModel.issueDetail = makeIssueDetail()
    unsupportedModel.selectedDetailTab = .progress
    unsupportedModel.progressReportModel.testingSetReport(
      makeIssueProgressReport(
        syntaxHealth: RepositorySyntaxHealth(
          status: .unsupported,
          checkedFileCount: 0,
          diagnosticCount: 0
        )
      )
    )

    let failedModel = SymphonyOperatorModel(client: PassiveSymphonyAPIClient())
    failedModel.selectedIssueID = IssueID("issue-42")
    failedModel.issueDetail = makeIssueDetail()
    failedModel.selectedDetailTab = .progress
    failedModel.progressReportModel.testingSetReport(
      makeIssueProgressReport(
        syntaxHealth: RepositorySyntaxHealth(
          status: .failed,
          checkedFileCount: 0,
          diagnosticCount: 0,
          failureMessage: "syntax command failed"
        )
      )
    )

    exercise(
      SymphonyOperatorRootView(model: unsupportedModel, compactOverride: false), width: 1280,
      height: 900)
    exercise(
      SymphonyOperatorRootView(model: failedModel, compactOverride: true), width: 390,
      height: 844)
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
}
