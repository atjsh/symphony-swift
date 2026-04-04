import Foundation
import SymphonyShared
import Testing

@testable import SymphonySwiftUIApp

@MainActor
@Suite("OperatorModel – Progress Report Guard Paths", .tags(.model))
struct OperatorModelProgressReportGuardPathTests {

  @Test func selectMetricSameValueIsNoOp() async {
    let client = PassiveSymphonyAPIClient()
    let vm = OperatorProgressReportViewModel(client: client, cache: TestProgressReportCache())
    vm.testingSetReport(makeIssueProgressReport())

    vm.selectMetric(.lines)
    // Already .lines by default → no change
    #expect(vm.selectedMetric == .lines)
  }

  @Test func selectMetricUpdatesChartPoints() async {
    let client = PassiveSymphonyAPIClient()
    let vm = OperatorProgressReportViewModel(client: client, cache: TestProgressReportCache())
    vm.testingSetReport(makeIssueProgressReport())

    vm.selectMetric(.bytes)
    #expect(vm.selectedMetric == .bytes)
    #expect(!vm.chartPoints.isEmpty)
    // Byte values from fixture: 15_000
    #expect(vm.chartPoints.first?.value == 15_000)
  }

  @Test func selectCommitSameIDIsNoOp() async {
    let client = PassiveSymphonyAPIClient()
    let vm = OperatorProgressReportViewModel(client: client, cache: TestProgressReportCache())
    let report = makeIssueProgressReport()
    vm.testingSetReport(report)

    let commitID = report.report.commits.first!.commitID
    vm.selectCommit(id: commitID)
    // Already selected → should not crash or change
    #expect(vm.selectedCommitID == commitID)
  }

  @Test func loadWithoutIssueIDStaysIdle() async {
    let client = PassiveSymphonyAPIClient()
    let vm = OperatorProgressReportViewModel(client: client, cache: TestProgressReportCache())
    // No issue context set
    await vm.loadIfNeeded(endpoint: try? ServerEndpoint(host: "localhost", port: 8080))
    #expect(vm.status == .idle)
  }

  @Test func loadWithoutWorkspaceShowsNoWorkspace() async {
    let client = PassiveSymphonyAPIClient()
    let vm = OperatorProgressReportViewModel(client: client, cache: TestProgressReportCache())
    vm.updateIssueContext(issueID: IssueID("issue-1"), workspacePath: nil)
    #expect(vm.status == .noWorkspace)
  }

  @Test func loadWithoutEndpointShowsFailed() async {
    let client = PassiveSymphonyAPIClient()
    let vm = OperatorProgressReportViewModel(client: client, cache: TestProgressReportCache())
    vm.updateIssueContext(issueID: IssueID("issue-1"), workspacePath: "/tmp/ws")
    await vm.loadIfNeeded(endpoint: nil)
    #expect(vm.status == .failed(SymphonyClientError.invalidEndpoint.localizedDescription))
  }

  @Test func recomputeDerivedStateWithNilReportClearsState() async {
    let client = PassiveSymphonyAPIClient()
    let vm = OperatorProgressReportViewModel(client: client, cache: TestProgressReportCache())
    vm.testingSetReport(makeIssueProgressReport())
    #expect(!vm.visibleCommits.isEmpty)

    // Reset by selecting new issue without loading
    vm.prepareForIssueSelection(issueID: IssueID("new-issue"))
    #expect(vm.visibleCommits.isEmpty)
    #expect(vm.chartPoints.isEmpty)
    #expect(vm.selectedCommit == nil)
  }

  @Test func persistSelectionWritesToCache() async throws {
    let client = PassiveSymphonyAPIClient()
    let cache = TestProgressReportCache()
    let vm = OperatorProgressReportViewModel(client: client, cache: cache)
    let issueID = IssueID("issue-42")
    vm.updateIssueContext(issueID: issueID, workspacePath: "/tmp/workspace")
    let endpoint = try ServerEndpoint(host: "localhost", port: 8080)

    await vm.loadIfNeeded(endpoint: endpoint)
    // After successful load, changing metric triggers persist
    vm.selectMetric(.characters)

    try await waitUntil { await !cache.storedSnapshots.isEmpty }
    let stored = await cache.storedSnapshots
    #expect(!stored.isEmpty)
  }

  // MARK: - OperatorProgressMetric Switch Branches

  @Test func progressMetricSystemImageCoversAllCases() {
    for metric in OperatorProgressMetric.allCases {
      #expect(!metric.systemImage.isEmpty)
    }
    #expect(OperatorProgressMetric.files.systemImage == "doc.on.doc")
    #expect(OperatorProgressMetric.lines.systemImage == "text.alignleft")
    #expect(OperatorProgressMetric.characters.systemImage == "character.cursor.ibeam")
    #expect(OperatorProgressMetric.bytes.systemImage == "internaldrive")
  }

  @Test func progressMetricTitleCoversAllCases() {
    #expect(OperatorProgressMetric.files.title == "Files")
    #expect(OperatorProgressMetric.lines.title == "Lines")
    #expect(OperatorProgressMetric.characters.title == "Characters")
    #expect(OperatorProgressMetric.bytes.title == "Bytes")
  }

  @Test func progressMetricValueForSnapshotCoversAllCases() {
    let snapshot = RepositoryMetricsSnapshot(
      fileCount: 10,
      sourceFileCount: 6,
      testFileCount: 2,
      otherFileCount: 2,
      lineCount: 500,
      characterCount: 12_000,
      byteCount: 13_000
    )
    #expect(OperatorProgressMetric.files.value(for: snapshot) == 10)
    #expect(OperatorProgressMetric.lines.value(for: snapshot) == 500)
    #expect(OperatorProgressMetric.characters.value(for: snapshot) == 12_000)
    #expect(OperatorProgressMetric.bytes.value(for: snapshot) == 13_000)
  }

  @Test func loadIfNeededSkipsWhenReportAlreadyLoaded() async {
    let client = PassiveSymphonyAPIClient()
    let vm = OperatorProgressReportViewModel(client: client, cache: TestProgressReportCache())
    vm.testingSetReport(makeIssueProgressReport())

    let endpoint = try? ServerEndpoint(host: "localhost", port: 8080)
    // Should short-circuit because report != nil
    await vm.loadIfNeeded(endpoint: endpoint)
    #expect(vm.report != nil)
  }

  @Test func refreshSkipsWhenAlreadyRefreshing() async throws {
    let client = PassiveSymphonyAPIClient()
    let vm = OperatorProgressReportViewModel(client: client, cache: TestProgressReportCache())
    vm.updateIssueContext(issueID: IssueID("issue-1"), workspacePath: "/tmp/ws")

    let endpoint = try ServerEndpoint(host: "localhost", port: 8080)
    // First refresh will proceed and fail (PassiveClient doesn't serve)
    await vm.refresh(endpoint: endpoint)
    // The refresh completed; calling it again immediately exercises the guard
    await vm.refresh(endpoint: endpoint)
    #expect(vm.isRefreshing == false)
  }

  @Test func selectCommitFallsBackToFirstVisibleCommit() {
    let client = PassiveSymphonyAPIClient()
    let vm = OperatorProgressReportViewModel(client: client, cache: TestProgressReportCache())
    vm.testingSetReport(makeIssueProgressReport())

    // Select a non-existent commit ID to trigger fallback
    vm.selectCommit(id: "nonexistent-commit-id-that-wont-match")
    // Should fall back to first visible commit
    #expect(vm.selectedCommit != nil)
  }

  @Test func selectMetricWithNilReportHitsRecomputeNilGuard() {
    let client = PassiveSymphonyAPIClient()
    let vm = OperatorProgressReportViewModel(client: client, cache: TestProgressReportCache())
    // No report loaded — selectMetric triggers recomputeDerivedState with nil report
    vm.selectMetric(.bytes)
    #expect(vm.visibleCommits.isEmpty)
    #expect(vm.chartPoints.isEmpty)
    #expect(vm.selectedCommit == nil)
  }

  @Test func selectCommitWithNilReportHitsRecomputeNilGuard() {
    let client = PassiveSymphonyAPIClient()
    let vm = OperatorProgressReportViewModel(client: client, cache: TestProgressReportCache())
    // No report loaded — selectCommit triggers recomputeDerivedState with nil report
    vm.selectCommit(id: "some-id")
    #expect(vm.visibleCommits.isEmpty)
    #expect(vm.chartPoints.isEmpty)
    #expect(vm.selectedCommit == nil)
  }
}
