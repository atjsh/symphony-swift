import Foundation
import SwiftData
import SymphonyShared
import Testing

@testable import SymphonySwiftUIApp

@Suite("Progress Report – Coverage Refinement", .tags(.model))
struct ProgressReportCoverageRefinementTests {

  // MARK: - ProgressReportCache

  @Test func makeDefaultFallsBackToInMemoryCacheOnContainerError() async throws {
    struct ContainerError: Error {}
    let cache = DefaultOperatorProgressReportCache.makeDefault(containerFactory: { throw ContainerError() })

    let issueID = IssueID("fallback-test")
    let workspacePath = "/tmp/fallback"
    let snapshot = CachedOperatorProgressReportSnapshot(
      response: makeIssueProgressReport(issueID: issueID),
      selectedMetric: .bytes,
      selectedCommitID: nil,
      lastRefreshDate: Date()
    )

    try await cache.store(snapshot: snapshot, issueID: issueID, workspacePath: workspacePath)
    let loaded = try await cache.loadLatest(issueID: issueID, workspacePath: workspacePath)
    #expect(loaded?.selectedMetric == .bytes)
  }

  @Test func cacheStoreDecodesUnknownMetricRawValueAsLines() async throws {
    let container = try ModelContainer(
      for: OperatorProgressReportCacheRecord.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )

    let report = makeIssueProgressReport()
    let encodedResponse = try JSONEncoder().encode(report)
    let record = OperatorProgressReportCacheRecord(
      cacheKey: "issue-42|/tmp/ws|abcdef1234567890",
      issueID: "issue-42",
      workspacePath: "/tmp/ws",
      headCommitID: "abcdef1234567890",
      selectedMetricRawValue: "nonexistent_metric",
      selectedCommitID: nil,
      lastRefreshDate: Date(),
      encodedResponse: encodedResponse
    )

    let context = ModelContext(container)
    context.insert(record)
    try context.save()

    let store = OperatorProgressReportCacheStore(modelContainer: container)
    let loaded = try await store.loadLatest(issueID: "issue-42", workspacePath: "/tmp/ws")
    #expect(loaded != nil)
    #expect(loaded?.selectedMetric == .lines)
  }

  // MARK: - ProgressReportViewModel

  @MainActor
  @Test func recomputeDerivedStateFiltersUnparseableDateBuckets() async throws {
    let vm = OperatorProgressReportViewModel(
      client: PassiveSymphonyAPIClient(),
      cache: TestProgressReportCache()
    )

    let metrics = RepositoryMetricsSnapshot(
      fileCount: 1, sourceFileCount: 1, testFileCount: 0, otherFileCount: 0,
      lineCount: 10, characterCount: 100, byteCount: 100
    )
    let activity = RepositoryGitActivitySummary(changedFileCount: 1, additions: 5, deletions: 0)
    let report = IssueProgressReportResponse(
      issueID: IssueID("issue-1"),
      generatedAt: "2026-01-01T00:00:00Z",
      report: RepositoryHistoryReport(
        headCommitID: "abc123",
        summary: metrics,
        commits: [
          RepositoryHistoryCommit(
            commitID: "abc123", shortID: "abc1234", subject: "First",
            authorName: "A", committedAt: "2026-01-02T00:00:00Z",
            metrics: metrics, activity: activity
          ),
          RepositoryHistoryCommit(
            commitID: "def456", shortID: "def4567", subject: "Second",
            authorName: "B", committedAt: "2026-01-01T00:00:00Z",
            metrics: metrics, activity: activity
          ),
        ],
        buckets: [
          RepositoryMetricsBucket(
            bucketID: "bad-bucket",
            label: "Bad",
            rangeStart: "not-a-date",
            rangeEnd: "also-not-a-date",
            metrics: metrics
          ),
          RepositoryMetricsBucket(
            bucketID: "good-bucket",
            label: "Good",
            rangeStart: "2026-01-01T00:00:00Z",
            rangeEnd: "2026-01-07T23:59:59Z",
            metrics: metrics
          ),
        ]
      ),
      syntaxHealth: RepositorySyntaxHealth(
        status: .configured,
        checkedFileCount: 0,
        diagnosticCount: 0,
        diagnostics: []
      )
    )

    vm.testingSetReport(report)

    #expect(vm.chartPoints.count == 1)
    #expect(vm.chartPoints.first?.id == "good-bucket")
    #expect(vm.visibleCommits.count == 2)
    #expect(vm.visibleCommits.first?.commitID == "abc123", "Sorted descending by committedAt")
  }
}
