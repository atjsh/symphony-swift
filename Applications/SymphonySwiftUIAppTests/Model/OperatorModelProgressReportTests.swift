import Foundation
import SwiftData
import SymphonyShared
import Testing

@testable import SymphonySwiftUIApp

@MainActor
@Suite("OperatorModel – Progress Report", .tags(.model))
struct OperatorModelProgressReportTests {
  @Test func SelectingIssueDoesNotLoadProgressReportUntilRequested() async throws {
    let client = MockSymphonyAPIClient()
    let issueSummary = makeIssueSummary()
    client.issueDetailResponse = makeIssueDetail()
    client.runDetailResponse = makeRunDetail()
    client.logsResponse = LogEntriesResponse(
      sessionID: SessionID("session-42"),
      provider: "claude_code",
      items: [],
      nextCursor: nil,
      hasMore: false
    )

    let model = SymphonyOperatorModel(client: client, progressReportCache: TestProgressReportCache())

    await model.selectIssue(issueSummary)

    #expect(client.issueProgressReportRequests.isEmpty)
    #expect(model.progressReportModel.status == .idle)

    await model.progressReportModel.loadIfNeeded(endpoint: try ServerEndpoint(host: "localhost", port: 8080))

    #expect(client.issueProgressReportRequests == [issueSummary.issueID])
    #expect(model.progressReportModel.report?.issueID == issueSummary.issueID)
    #expect(model.progressReportModel.isShowingCachedReport == false)
  }

  @Test func ProgressReportViewModelShowsCachedSnapshotBeforeRefreshing() async throws {
    let client = MockSymphonyAPIClient()
    let issueID = IssueID("issue-42")
    let cachedReport = makeIssueProgressReport(issueID: issueID)
    let refreshedReport = makeIssueProgressReport(
      issueID: issueID,
      headCommitID: "fedcba9876543210",
      lineCount: 960
    )
    client.issueProgressReportResponse = refreshedReport
    client.suspendIssueProgressReport = true
    let cache = TestProgressReportCache(
      snapshots: [
        .init(
          response: cachedReport,
          selectedMetric: .bytes,
          selectedCommitID: cachedReport.report.commits.first?.commitID,
          lastRefreshDate: Date(timeIntervalSince1970: 10)
        )
      ]
    )
    let viewModel = OperatorProgressReportViewModel(client: client, cache: cache)
    let endpoint = try ServerEndpoint(host: "localhost", port: 8080)

    viewModel.prepareForIssueSelection(issueID: issueID)
    viewModel.updateIssueContext(issueID: issueID, workspacePath: "/tmp/symphony/atjsh_example_42")

    let loadTask = Task { await viewModel.loadIfNeeded(endpoint: endpoint) }
    let requestedIssueID = await client.nextIssueProgressReportRequest()

    #expect(requestedIssueID == issueID)
    #expect(viewModel.report?.report.headCommitID == cachedReport.report.headCommitID)
    #expect(viewModel.isShowingCachedReport)
    #expect(viewModel.selectedMetric == .bytes)
    let loadRequests = await cache.loadRequests
    #expect(loadRequests.count == 1)
    #expect(loadRequests.first?.0 == issueID)
    #expect(loadRequests.first?.1 == "/tmp/symphony/atjsh_example_42")

    client.resumeIssueProgressReport()
    await loadTask.value

    #expect(viewModel.report?.report.headCommitID == refreshedReport.report.headCommitID)
    #expect(viewModel.isShowingCachedReport == false)
    let storedSnapshots = await cache.storedSnapshots
    #expect(storedSnapshots.last?.response.report.headCommitID == refreshedReport.report.headCommitID)
  }

  @Test func ProgressMetricTitlesExcludeFunctionsAndSymbols() {
    #expect(OperatorProgressMetric.allCases.map(\.title) == ["Files", "Lines", "Characters", "Bytes"])
    #expect(OperatorProgressMetric.allCases.map(\.title).contains("Functions") == false)
    #expect(OperatorProgressMetric.allCases.map(\.title).contains("Symbols") == false)
  }

  @Test func ProgressReportRefreshIgnoresOverlappingRequests() async throws {
    let client = MockSymphonyAPIClient()
    let issueID = IssueID("issue-42")
    client.suspendIssueProgressReport = true
    let viewModel = OperatorProgressReportViewModel(client: client, cache: TestProgressReportCache())
    let endpoint = try ServerEndpoint(host: "localhost", port: 8080)

    viewModel.prepareForIssueSelection(issueID: issueID)
    viewModel.updateIssueContext(issueID: issueID, workspacePath: "/tmp/symphony/atjsh_example_42")
    viewModel.testingSetReport(makeIssueProgressReport(issueID: issueID))

    let firstRefresh = Task { await viewModel.refresh(endpoint: endpoint) }
    let firstRequestedIssueID = await client.nextIssueProgressReportRequest()

    let secondRefresh = Task { await viewModel.refresh(endpoint: endpoint) }
    await Task.yield()

    #expect(firstRequestedIssueID == issueID)
    #expect(client.issueProgressReportRequests == [issueID])

    client.resumeIssueProgressReport()
    await firstRefresh.value
    await secondRefresh.value

    #expect(client.issueProgressReportRequests == [issueID])
  }

  @Test func ProgressReportCacheStoreRoundTripsSnapshots() async throws {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
      for: OperatorProgressReportCacheRecord.self,
      configurations: configuration
    )
    let store = OperatorProgressReportCacheStore(modelContainer: container)
    let issueID = IssueID("issue-42")
    let workspacePath = "/tmp/symphony/workspace"

    let initial = CachedOperatorProgressReportSnapshot(
      response: makeIssueProgressReport(issueID: issueID),
      selectedMetric: .lines,
      selectedCommitID: "abcdef1234567890",
      lastRefreshDate: Date(timeIntervalSince1970: 10)
    )
    try await store.store(
      snapshot: initial,
      issueID: issueID.rawValue,
      workspacePath: workspacePath
    )

    let loadedInitial = try await store.loadLatest(
      issueID: issueID.rawValue,
      workspacePath: workspacePath
    )
    #expect(loadedInitial == initial)

    let updated = CachedOperatorProgressReportSnapshot(
      response: makeIssueProgressReport(
        issueID: issueID,
        headCommitID: "fedcba9876543210",
        lineCount: 960
      ),
      selectedMetric: .bytes,
      selectedCommitID: "fedcba9876543210",
      lastRefreshDate: Date(timeIntervalSince1970: 20)
    )
    try await store.store(
      snapshot: updated,
      issueID: issueID.rawValue,
      workspacePath: workspacePath
    )

    let loadedUpdated = try await store.loadLatest(
      issueID: issueID.rawValue,
      workspacePath: workspacePath
    )
    #expect(loadedUpdated == updated)
  }

  @Test func ProgressReportLoadWithNilEndpointFails() async throws {
    let client = MockSymphonyAPIClient()
    let viewModel = OperatorProgressReportViewModel(client: client, cache: TestProgressReportCache())
    let issueID = IssueID("issue-42")

    viewModel.prepareForIssueSelection(issueID: issueID)
    viewModel.updateIssueContext(issueID: issueID, workspacePath: "/tmp/workspace")

    await viewModel.loadIfNeeded(endpoint: nil)

    #expect(viewModel.status == .failed(SymphonyClientError.invalidEndpoint.localizedDescription))
    #expect(viewModel.report == nil)
  }

  @Test func ProgressReportLoadWithNilWorkspaceShowsNoWorkspace() async throws {
    let client = MockSymphonyAPIClient()
    let viewModel = OperatorProgressReportViewModel(client: client, cache: TestProgressReportCache())
    let issueID = IssueID("issue-42")

    viewModel.prepareForIssueSelection(issueID: issueID)
    viewModel.updateIssueContext(issueID: issueID, workspacePath: nil)

    #expect(viewModel.status == .noWorkspace)

    await viewModel.loadIfNeeded(endpoint: try ServerEndpoint(host: "localhost", port: 8080))

    #expect(viewModel.status == .noWorkspace)
  }

  @Test func ProgressReportLoadWithEmptyWorkspaceShowsNoWorkspace() async throws {
    let client = MockSymphonyAPIClient()
    let viewModel = OperatorProgressReportViewModel(client: client, cache: TestProgressReportCache())
    let issueID = IssueID("issue-42")

    viewModel.prepareForIssueSelection(issueID: issueID)
    viewModel.updateIssueContext(issueID: issueID, workspacePath: "   ")

    #expect(viewModel.status == .noWorkspace)
  }

  @Test func ProgressReportNetworkErrorSetsFailedStatus() async throws {
    let client = MockSymphonyAPIClient()
    client.issueDetailError = TestModelFailure.failed("Network error")
    let viewModel = OperatorProgressReportViewModel(client: client, cache: TestProgressReportCache())
    let issueID = IssueID("issue-42")
    let endpoint = try ServerEndpoint(host: "localhost", port: 8080)

    viewModel.prepareForIssueSelection(issueID: issueID)
    viewModel.updateIssueContext(issueID: issueID, workspacePath: "/tmp/workspace")

    await viewModel.loadIfNeeded(endpoint: endpoint)

    #expect(viewModel.status == .failed("Network error"))
    #expect(viewModel.refreshErrorMessage == "Network error")
  }

  @Test func ProgressReportRefreshErrorKeepsExistingReport() async throws {
    let client = MockSymphonyAPIClient()
    let issueID = IssueID("issue-42")
    let viewModel = OperatorProgressReportViewModel(client: client, cache: TestProgressReportCache())
    let endpoint = try ServerEndpoint(host: "localhost", port: 8080)

    viewModel.prepareForIssueSelection(issueID: issueID)
    viewModel.updateIssueContext(issueID: issueID, workspacePath: "/tmp/workspace")
    viewModel.testingSetReport(makeIssueProgressReport(issueID: issueID))

    #expect(viewModel.status == .loaded)

    client.issueDetailError = TestModelFailure.failed("Refresh failed")
    await viewModel.refresh(endpoint: endpoint)

    #expect(viewModel.status == .loaded)
    #expect(viewModel.refreshErrorMessage == "Refresh failed")
    #expect(viewModel.report != nil)
  }

  @Test func ProgressReportSelectMetricRecomputesState() async throws {
    let client = MockSymphonyAPIClient()
    let cache = TestProgressReportCache()
    let viewModel = OperatorProgressReportViewModel(client: client, cache: cache)
    let issueID = IssueID("issue-42")

    viewModel.prepareForIssueSelection(issueID: issueID)
    viewModel.updateIssueContext(issueID: issueID, workspacePath: "/tmp/workspace")
    viewModel.testingSetReport(makeIssueProgressReport(issueID: issueID))

    #expect(viewModel.selectedMetric == .lines)

    viewModel.selectMetric(.bytes)

    #expect(viewModel.selectedMetric == .bytes)
    #expect(viewModel.chartPoints.isEmpty == false)

    try await Task.sleep(for: .milliseconds(50))
    let storedSnapshots = await cache.storedSnapshots
    #expect(storedSnapshots.last?.selectedMetric == .bytes)
  }

  @Test func ProgressReportSelectCommitUpdatesState() async throws {
    let client = MockSymphonyAPIClient()
    let cache = TestProgressReportCache()
    let viewModel = OperatorProgressReportViewModel(client: client, cache: cache)
    let issueID = IssueID("issue-42")
    let report = makeIssueProgressReport(issueID: issueID)

    viewModel.prepareForIssueSelection(issueID: issueID)
    viewModel.updateIssueContext(issueID: issueID, workspacePath: "/tmp/workspace")
    viewModel.testingSetReport(report)

    // testingSetReport selects the last (only) commit.
    let commitID = report.report.commits.first!.commitID
    #expect(viewModel.selectedCommitID == commitID)
    #expect(viewModel.selectedCommit?.commitID == commitID)

    // Selecting an unknown commit falls back to the first visible commit.
    viewModel.selectCommit(id: "nonexistent")
    #expect(viewModel.selectedCommitID == commitID)
    #expect(viewModel.selectedCommit?.commitID == commitID)
  }

  @Test func ProgressReportPrepareForNewIssueResetsState() async throws {
    let client = MockSymphonyAPIClient()
    let viewModel = OperatorProgressReportViewModel(client: client, cache: TestProgressReportCache())
    let issueID = IssueID("issue-42")

    viewModel.prepareForIssueSelection(issueID: issueID)
    viewModel.updateIssueContext(issueID: issueID, workspacePath: "/tmp/workspace")
    viewModel.testingSetReport(makeIssueProgressReport(issueID: issueID))

    #expect(viewModel.report != nil)

    viewModel.prepareForIssueSelection(issueID: IssueID("issue-99"))

    #expect(viewModel.report == nil)
    #expect(viewModel.status == .idle)
    #expect(viewModel.visibleCommits.isEmpty)
    #expect(viewModel.chartPoints.isEmpty)
    #expect(viewModel.selectedCommit == nil)
  }

  @Test func ProgressReportUpdateContextWithDifferentWorkspaceResetsState() async throws {
    let client = MockSymphonyAPIClient()
    let viewModel = OperatorProgressReportViewModel(client: client, cache: TestProgressReportCache())
    let issueID = IssueID("issue-42")

    viewModel.prepareForIssueSelection(issueID: issueID)
    viewModel.updateIssueContext(issueID: issueID, workspacePath: "/tmp/workspace-a")
    viewModel.testingSetReport(makeIssueProgressReport(issueID: issueID))

    #expect(viewModel.report != nil)

    viewModel.updateIssueContext(issueID: issueID, workspacePath: "/tmp/workspace-b")

    #expect(viewModel.report == nil)
    #expect(viewModel.status == .idle)
  }

  @Test func ProgressReportCacheStoreUpdatesExistingRecord() async throws {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
      for: OperatorProgressReportCacheRecord.self,
      configurations: configuration
    )
    let store = OperatorProgressReportCacheStore(modelContainer: container)
    let issueID = IssueID("issue-42")
    let workspacePath = "/tmp/workspace"
    let headCommitID = "abcdef1234567890"

    let initial = CachedOperatorProgressReportSnapshot(
      response: makeIssueProgressReport(issueID: issueID, headCommitID: headCommitID),
      selectedMetric: .lines,
      selectedCommitID: headCommitID,
      lastRefreshDate: Date(timeIntervalSince1970: 10)
    )
    try await store.store(snapshot: initial, issueID: issueID.rawValue, workspacePath: workspacePath)

    let updatedSnapshot = CachedOperatorProgressReportSnapshot(
      response: makeIssueProgressReport(issueID: issueID, headCommitID: headCommitID, lineCount: 999),
      selectedMetric: .bytes,
      selectedCommitID: headCommitID,
      lastRefreshDate: Date(timeIntervalSince1970: 20)
    )
    try await store.store(snapshot: updatedSnapshot, issueID: issueID.rawValue, workspacePath: workspacePath)

    let loaded = try await store.loadLatest(issueID: issueID.rawValue, workspacePath: workspacePath)
    #expect(loaded?.selectedMetric == .bytes)
    #expect(loaded?.lastRefreshDate == Date(timeIntervalSince1970: 20))
  }

  @Test func ProgressReportCacheLoadLatestReturnsMostRecent() async throws {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
      for: OperatorProgressReportCacheRecord.self,
      configurations: configuration
    )
    let store = OperatorProgressReportCacheStore(modelContainer: container)
    let issueID = IssueID("issue-42")
    let workspacePath = "/tmp/workspace"

    let older = CachedOperatorProgressReportSnapshot(
      response: makeIssueProgressReport(issueID: issueID, headCommitID: "aaa"),
      selectedMetric: .lines,
      selectedCommitID: "aaa",
      lastRefreshDate: Date(timeIntervalSince1970: 10)
    )
    try await store.store(snapshot: older, issueID: issueID.rawValue, workspacePath: workspacePath)

    let newer = CachedOperatorProgressReportSnapshot(
      response: makeIssueProgressReport(issueID: issueID, headCommitID: "bbb"),
      selectedMetric: .bytes,
      selectedCommitID: "bbb",
      lastRefreshDate: Date(timeIntervalSince1970: 20)
    )
    try await store.store(snapshot: newer, issueID: issueID.rawValue, workspacePath: workspacePath)

    let loaded = try await store.loadLatest(issueID: issueID.rawValue, workspacePath: workspacePath)
    #expect(loaded?.response.report.headCommitID == "bbb")
    #expect(loaded?.selectedMetric == .bytes)
  }

  @Test func ProgressReportCacheMissReturnsNil() async throws {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
      for: OperatorProgressReportCacheRecord.self,
      configurations: configuration
    )
    let store = OperatorProgressReportCacheStore(modelContainer: container)

    let loaded = try await store.loadLatest(issueID: "nonexistent", workspacePath: "/tmp")
    #expect(loaded == nil)
  }

  // MARK: - ViewModel Guard Paths

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

    // Wait briefly for async persist
    try await Task.sleep(for: .milliseconds(50))
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
