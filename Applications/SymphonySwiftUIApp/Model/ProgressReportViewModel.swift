import Foundation
import SymphonyShared

@MainActor
@Observable
final class OperatorProgressReportViewModel {
  private(set) var status: OperatorProgressReportStatus = .idle
  private(set) var report: IssueProgressReportResponse?
  private(set) var visibleCommits = [RepositoryHistoryCommit]()
  private(set) var chartPoints = [OperatorProgressBucketPoint]()
  private(set) var selectedCommit: RepositoryHistoryCommit?
  private(set) var refreshErrorMessage: String?
  private(set) var isLoading = false
  private(set) var isRefreshing = false
  private(set) var isShowingCachedReport = false
  private(set) var lastRefreshDate: Date?
  private(set) var selectedMetric: OperatorProgressMetric = .lines
  private(set) var selectedCommitID: String?

  @ObservationIgnored private let client: any SymphonyAPIClientProtocol
  @ObservationIgnored private let cache: any OperatorProgressReportCaching
  @ObservationIgnored private var currentIssueID: IssueID?
  @ObservationIgnored private var currentWorkspacePath: String?
  @ObservationIgnored private var selectionPersistenceTask: Task<Void, Never>?

  init(client: any SymphonyAPIClientProtocol, cache: any OperatorProgressReportCaching) {
    self.client = client
    self.cache = cache
  }

  func prepareForIssueSelection(issueID: IssueID) {
    currentIssueID = issueID
    currentWorkspacePath = nil
    resetLoadedState()
  }

  func updateIssueContext(issueID: IssueID, workspacePath: String?) {
    currentIssueID = issueID
    let normalizedWorkspacePath = workspacePath?.trimmingCharacters(in: .whitespacesAndNewlines)
    let resolvedWorkspacePath = normalizedWorkspacePath?.isEmpty == false ? normalizedWorkspacePath : nil

    if currentWorkspacePath != resolvedWorkspacePath {
      resetLoadedState()
    }

    currentWorkspacePath = resolvedWorkspacePath
    if resolvedWorkspacePath == nil {
      status = .noWorkspace
    } else if report == nil {
      status = .idle
    }
  }

  func loadIfNeeded(endpoint: ServerEndpoint?) async {
    guard report == nil, isLoading == false, isRefreshing == false else {
      return
    }
    await load(endpoint: endpoint, forceRefresh: false)
  }

  func refresh(endpoint: ServerEndpoint?) async {
    guard isLoading == false, isRefreshing == false else {
      return
    }
    await load(endpoint: endpoint, forceRefresh: true)
  }

  func selectMetric(_ metric: OperatorProgressMetric) {
    guard selectedMetric != metric else {
      return
    }
    selectedMetric = metric
    recomputeDerivedState()
    persistSelectionIfPossible()
  }

  func selectCommit(id: String) {
    guard selectedCommitID != id else {
      return
    }
    selectedCommitID = id
    recomputeDerivedState()
    persistSelectionIfPossible()
  }

  func testingSetReport(_ report: IssueProgressReportResponse) {
    applySnapshot(
      CachedOperatorProgressReportSnapshot(
        response: report,
        selectedMetric: .lines,
        selectedCommitID: report.report.commits.last?.commitID,
        lastRefreshDate: Date()
      ),
      cached: false
    )
  }

  func testingSetStatus(_ newStatus: OperatorProgressReportStatus) {
    status = newStatus
  }

  func testingSetRefreshErrorMessage(_ message: String?) {
    refreshErrorMessage = message
  }

  private func load(endpoint: ServerEndpoint?, forceRefresh: Bool) async {
    guard let issueID = currentIssueID else {
      status = .idle
      return
    }
    guard let workspacePath = currentWorkspacePath else {
      status = .noWorkspace
      return
    }
    guard let endpoint else {
      status = .failed(SymphonyClientError.invalidEndpoint.localizedDescription)
      return
    }

    if forceRefresh {
      isRefreshing = true
    } else {
      isLoading = true
      status = .loading
      if let cachedSnapshot = try? await cache.loadLatest(issueID: issueID, workspacePath: workspacePath) {
        applySnapshot(cachedSnapshot, cached: true)
      }
    }

    defer {
      isLoading = false
      isRefreshing = false
    }

    do {
      let response = try await client.issueProgressReport(endpoint: endpoint, issueID: issueID)
      let snapshot = CachedOperatorProgressReportSnapshot(
        response: response,
        selectedMetric: selectedMetric,
        selectedCommitID: selectedCommitID ?? response.report.commits.last?.commitID,
        lastRefreshDate: Date()
      )
      applySnapshot(snapshot, cached: false)
      try? await cache.store(snapshot: snapshot, issueID: issueID, workspacePath: workspacePath)
    } catch {
      refreshErrorMessage = error.localizedDescription
      if report == nil {
        status = .failed(error.localizedDescription)
      } else {
        status = .loaded
      }
    }
  }

  private func applySnapshot(_ snapshot: CachedOperatorProgressReportSnapshot, cached: Bool) {
    report = snapshot.response
    isShowingCachedReport = cached
    lastRefreshDate = snapshot.lastRefreshDate
    refreshErrorMessage = nil
    selectedMetric = snapshot.selectedMetric
    selectedCommitID = snapshot.selectedCommitID
    status = .loaded
    recomputeDerivedState()
  }

  private func recomputeDerivedState() {
    guard let report else {
      visibleCommits = []
      chartPoints = []
      selectedCommit = nil
      return
    }

    visibleCommits = report.report.commits.sorted { $0.committedAt > $1.committedAt }

    if let selectedCommitID,
      let matchedCommit = visibleCommits.first(where: { $0.commitID == selectedCommitID })
    {
      selectedCommit = matchedCommit
    } else {
      let fallback = visibleCommits.first
      selectedCommitID = fallback?.commitID
      selectedCommit = fallback
    }

    chartPoints = report.report.buckets.compactMap { bucket in
      guard let date = Self.iso8601.date(from: bucket.rangeEnd) ?? Self.iso8601.date(from: bucket.rangeStart) else {
        return nil
      }
      return OperatorProgressBucketPoint(
        id: bucket.bucketID,
        label: bucket.label,
        date: date,
        value: selectedMetric.value(for: bucket.metrics)
      )
    }
  }

  private func persistSelectionIfPossible() {
    guard
      let report,
      let issueID = currentIssueID,
      let workspacePath = currentWorkspacePath
    else {
      return
    }

    // applySnapshot always sets lastRefreshDate before report becomes non-nil.
    let snapshot = CachedOperatorProgressReportSnapshot(
      response: report,
      selectedMetric: selectedMetric,
      selectedCommitID: selectedCommitID,
      lastRefreshDate: lastRefreshDate!
    )
    selectionPersistenceTask?.cancel()
    selectionPersistenceTask = Task { [cache] in
      try? await cache.store(snapshot: snapshot, issueID: issueID, workspacePath: workspacePath)
    }
  }

  private func resetLoadedState() {
    selectionPersistenceTask?.cancel()
    selectionPersistenceTask = nil
    status = .idle
    report = nil
    visibleCommits = []
    chartPoints = []
    selectedCommit = nil
    selectedCommitID = nil
    selectedMetric = .lines
    lastRefreshDate = nil
    refreshErrorMessage = nil
    isLoading = false
    isRefreshing = false
    isShowingCachedReport = false
  }

  private static let iso8601: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
  }()
}
