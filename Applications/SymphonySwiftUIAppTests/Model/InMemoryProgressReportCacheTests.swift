import Foundation
import SymphonyShared
import Testing

@testable import SymphonySwiftUIApp

@Suite("InMemoryOperatorProgressReportCache", .tags(.model))
struct InMemoryProgressReportCacheTests {

  @Test func loadLatestReturnsNilWhenEmpty() async throws {
    let cache = InMemoryOperatorProgressReportCache()
    let result = try await cache.loadLatest(
      issueID: IssueID("issue-1"),
      workspacePath: "/tmp/workspace"
    )
    #expect(result == nil)
  }

  @Test func storeAndLoadRoundTrip() async throws {
    let cache = InMemoryOperatorProgressReportCache()
    let issueID = IssueID("issue-1")
    let workspacePath = "/tmp/workspace"
    let report = makeIssueProgressReport(issueID: issueID)
    let snapshot = CachedOperatorProgressReportSnapshot(
      response: report,
      selectedMetric: .lines,
      selectedCommitID: report.report.commits.first?.commitID,
      lastRefreshDate: Date()
    )

    try await cache.store(snapshot: snapshot, issueID: issueID, workspacePath: workspacePath)
    let loaded = try await cache.loadLatest(issueID: issueID, workspacePath: workspacePath)
    #expect(loaded != nil)
    #expect(loaded?.response.report.headCommitID == report.report.headCommitID)
    #expect(loaded?.selectedMetric == .lines)
  }

  @Test func loadLatestReturnsMostRecent() async throws {
    let cache = InMemoryOperatorProgressReportCache()
    let issueID = IssueID("issue-1")
    let workspacePath = "/tmp/workspace"

    let older = CachedOperatorProgressReportSnapshot(
      response: makeIssueProgressReport(issueID: issueID, headCommitID: "old111"),
      selectedMetric: .files,
      selectedCommitID: "old111",
      lastRefreshDate: Date(timeIntervalSince1970: 100)
    )
    try await cache.store(snapshot: older, issueID: issueID, workspacePath: workspacePath)

    let newer = CachedOperatorProgressReportSnapshot(
      response: makeIssueProgressReport(issueID: issueID, headCommitID: "new222"),
      selectedMetric: .bytes,
      selectedCommitID: "new222",
      lastRefreshDate: Date(timeIntervalSince1970: 200)
    )
    try await cache.store(snapshot: newer, issueID: issueID, workspacePath: workspacePath)

    let loaded = try await cache.loadLatest(issueID: issueID, workspacePath: workspacePath)
    #expect(loaded?.response.report.headCommitID == "new222")
    #expect(loaded?.selectedMetric == .bytes)
  }

  @Test func loadLatestFiltersByIssueIDAndWorkspacePath() async throws {
    let cache = InMemoryOperatorProgressReportCache()
    let issueA = IssueID("issue-A")
    let issueB = IssueID("issue-B")
    let path = "/tmp/workspace"

    let snapshotA = CachedOperatorProgressReportSnapshot(
      response: makeIssueProgressReport(issueID: issueA),
      selectedMetric: .lines,
      selectedCommitID: nil,
      lastRefreshDate: Date()
    )
    try await cache.store(snapshot: snapshotA, issueID: issueA, workspacePath: path)

    let loaded = try await cache.loadLatest(issueID: issueB, workspacePath: path)
    #expect(loaded == nil)
  }

  @Test func storeOverwritesSameHeadCommit() async throws {
    let cache = InMemoryOperatorProgressReportCache()
    let issueID = IssueID("issue-1")
    let workspacePath = "/tmp/workspace"

    let snapshot1 = CachedOperatorProgressReportSnapshot(
      response: makeIssueProgressReport(issueID: issueID, headCommitID: "same"),
      selectedMetric: .lines,
      selectedCommitID: nil,
      lastRefreshDate: Date(timeIntervalSince1970: 100)
    )
    try await cache.store(snapshot: snapshot1, issueID: issueID, workspacePath: workspacePath)

    let snapshot2 = CachedOperatorProgressReportSnapshot(
      response: makeIssueProgressReport(issueID: issueID, headCommitID: "same"),
      selectedMetric: .bytes,
      selectedCommitID: nil,
      lastRefreshDate: Date(timeIntervalSince1970: 200)
    )
    try await cache.store(snapshot: snapshot2, issueID: issueID, workspacePath: workspacePath)

    let loaded = try await cache.loadLatest(issueID: issueID, workspacePath: workspacePath)
    #expect(loaded?.selectedMetric == .bytes)
  }
}
