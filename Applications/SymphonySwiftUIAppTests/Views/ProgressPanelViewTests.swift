import Charts
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
@Suite("ProgressPanelView – Coverage Gaps", .tags(.views))
struct ProgressPanelViewTests {

  private func makeModel(report: IssueProgressReportResponse? = nil) -> SymphonyOperatorModel {
    let client = MockSymphonyAPIClient()
    let model = SymphonyOperatorModel(client: client, progressReportCache: TestProgressReportCache())
    if let report {
      model.progressReportModel.testingSetReport(report)
    }
    return model
  }

  @Test func progressPanelRendersIdleStateWithoutReport() throws {
    let model = makeModel()
    let detail = makeIssueDetail()
    let panel = OperatorProgressPanel(model: model, theme: OperatorTheme(compact: false), detail: detail)
    exercise(AnyView(panel), width: 480, height: 320)
  }

  @Test func progressPanelRendersFailedState() throws {
    let client = MockSymphonyAPIClient()
    let model = SymphonyOperatorModel(client: client, progressReportCache: TestProgressReportCache())
    // Set up failed status on the ViewModel
    model.progressReportModel.updateIssueContext(issueID: IssueID("issue-42"), workspacePath: "/tmp/ws")

    let detail = makeIssueDetail()
    // Render in compact mode (covers compact summaryStrip/metricPicker)
    let compactPanel = OperatorProgressPanel(
      model: model, theme: OperatorTheme(compact: true), detail: detail
    )
    exercise(AnyView(compactPanel), width: 320, height: 640)
  }

  @Test func progressPanelRendersWithLoadedReport() throws {
    let model = makeModel(report: makeIssueProgressReport())
    let detail = makeIssueDetail()
    let panel = OperatorProgressPanel(model: model, theme: OperatorTheme(compact: false), detail: detail)
    exercise(AnyView(panel), width: 1280, height: 800)
  }

  @Test func progressPanelRendersCompactLayoutWithReport() throws {
    let model = makeModel(report: makeIssueProgressReport())
    let detail = makeIssueDetail()
    let panel = OperatorProgressPanel(model: model, theme: OperatorTheme(compact: true), detail: detail)
    exercise(AnyView(panel), width: 320, height: 640)
  }

  @Test func progressPanelRendersWithSyntaxHealthConfigured() throws {
    let report = makeIssueProgressReport(
      syntaxHealth: RepositorySyntaxHealth(
        status: .configured,
        checkedFileCount: 10,
        diagnosticCount: 3,
        diagnostics: [
          RepositorySyntaxDiagnostic(
            path: "Sources/main.swift", message: "Warning", severity: "warning", line: 5, column: 1
          ),
        ]
      )
    )
    let model = makeModel(report: report)
    let detail = makeIssueDetail()
    let panel = OperatorProgressPanel(model: model, theme: OperatorTheme(compact: false), detail: detail)
    exercise(AnyView(panel), width: 1280, height: 800)
  }

  @Test func progressPanelRendersWithSyntaxHealthFailed() throws {
    let report = makeIssueProgressReport(
      syntaxHealth: RepositorySyntaxHealth(
        status: .failed,
        checkedFileCount: 0,
        diagnosticCount: 0,
        failureMessage: "Parse failed"
      )
    )
    let model = makeModel(report: report)
    let detail = makeIssueDetail()
    let panel = OperatorProgressPanel(model: model, theme: OperatorTheme(compact: true), detail: detail)
    exercise(AnyView(panel), width: 320, height: 640)
  }

  @Test func progressPanelRendersWithSyntaxHealthUnsupported() throws {
    let report = makeIssueProgressReport(
      syntaxHealth: RepositorySyntaxHealth(
        status: .unsupported,
        checkedFileCount: 0,
        diagnosticCount: 0
      )
    )
    let model = makeModel(report: report)
    let detail = makeIssueDetail()
    let panel = OperatorProgressPanel(model: model, theme: OperatorTheme(compact: false), detail: detail)
    exercise(AnyView(panel), width: 1280, height: 800)
  }

  @Test func progressPanelRendersMetricSelectionChanges() throws {
    let model = makeModel(report: makeIssueProgressReport())
    model.progressReportModel.selectMetric(.bytes)

    let detail = makeIssueDetail()
    let panel = OperatorProgressPanel(model: model, theme: OperatorTheme(compact: false), detail: detail)
    exercise(AnyView(panel), width: 1280, height: 800)
  }

  @Test func progressPanelRendersNoWorkspaceState() throws {
    let client = MockSymphonyAPIClient()
    let model = SymphonyOperatorModel(client: client, progressReportCache: TestProgressReportCache())
    model.progressReportModel.updateIssueContext(issueID: IssueID("issue-42"), workspacePath: nil)

    let detail = makeIssueDetail()
    let panel = OperatorProgressPanel(model: model, theme: OperatorTheme(compact: false), detail: detail)
    exercise(AnyView(panel), width: 480, height: 320)
  }

  @Test func progressPanelRendersFailedStatusContent() throws {
    let model = makeModel()
    model.progressReportModel.testingSetStatus(.failed("Connection timed out"))

    let detail = makeIssueDetail()
    let panel = OperatorProgressPanel(model: model, theme: OperatorTheme(compact: false), detail: detail)
    exercise(AnyView(panel), width: 480, height: 320)
  }

  @Test func progressPanelRendersLoadedStatusContentWithoutReport() throws {
    let model = makeModel()
    model.progressReportModel.testingSetStatus(.loaded)

    let detail = makeIssueDetail()
    let panel = OperatorProgressPanel(model: model, theme: OperatorTheme(compact: false), detail: detail)
    exercise(AnyView(panel), width: 480, height: 320)
  }

  @Test func progressPanelRendersRefreshErrorMessage() throws {
    let model = makeModel(report: makeIssueProgressReport())
    model.progressReportModel.testingSetRefreshErrorMessage("Server returned 502")

    let detail = makeIssueDetail()
    let panel = OperatorProgressPanel(model: model, theme: OperatorTheme(compact: false), detail: detail)
    exercise(AnyView(panel), width: 1280, height: 800)
  }

  @Test func progressPanelRendersWithEmptyBuckets() throws {
    let report = makeIssueProgressReport()
    let emptyBucketsReport = IssueProgressReportResponse(
      issueID: report.issueID,
      generatedAt: report.generatedAt,
      report: RepositoryHistoryReport(
        headCommitID: report.report.headCommitID,
        summary: report.report.summary,
        commits: report.report.commits,
        buckets: []
      ),
      syntaxHealth: report.syntaxHealth
    )
    let model = makeModel(report: emptyBucketsReport)

    let detail = makeIssueDetail()
    let panel = OperatorProgressPanel(model: model, theme: OperatorTheme(compact: false), detail: detail)
    exercise(AnyView(panel), width: 1280, height: 800)
  }
}
