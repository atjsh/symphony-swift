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
}
