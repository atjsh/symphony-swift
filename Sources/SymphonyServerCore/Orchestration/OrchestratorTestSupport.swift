import Foundation
import SymphonyShared

// MARK: - Stub Tracker (for testing)

// SAFETY: @unchecked Sendable — all mutable state is exclusively accessed through `lock`.
public final class StubTracker: TrackerAdapting, @unchecked Sendable {
  private let lock = NSLock()
  private var _allIssues: [Issue] = []
  private var _candidates: [Issue] = []
  private var _issuesByStates: [Issue] = []
  private var _statesByIDs: [IssueID: String] = [:]
  private var _fetchError: Error?

  public init() {}

  public func setAllIssues(_ issues: [Issue]) {
    lock.lock()
    _allIssues = issues
    lock.unlock()
  }

  public func setCandidates(_ issues: [Issue]) {
    lock.lock()
    _candidates = issues
    lock.unlock()
  }

  public func setIssuesByStates(_ issues: [Issue]) {
    lock.lock()
    _issuesByStates = issues
    lock.unlock()
  }

  public func setStatesByIDs(_ states: [IssueID: String]) {
    lock.lock()
    _statesByIDs = states
    lock.unlock()
  }

  public func setFetchError(_ error: Error?) {
    lock.lock()
    _fetchError = error
    lock.unlock()
  }

  public nonisolated func fetchAllIssues() async throws -> [Issue] {
    let (error, issues) = lock.withLock { (_fetchError, _allIssues) }
    if let error { throw error }
    return issues
  }

  public nonisolated func fetchCandidateIssues() async throws -> [Issue] {
    let (error, issues, candidates) = lock.withLock { (_fetchError, _allIssues, _candidates) }
    if let error { throw error }
    return candidates.isEmpty ? issues : candidates
  }

  public nonisolated func fetchIssuesByStates(_ stateNames: [String]) async throws -> [Issue] {
    let (error, issues, issuesByStates) = lock.withLock {
      (_fetchError, _allIssues, _issuesByStates)
    }
    if let error { throw error }
    let source = issuesByStates.isEmpty ? issues : issuesByStates
    return source.filter { stateNames.contains($0.state) }
  }

  public nonisolated func fetchIssueStatesByIDs(_ issueIDs: [IssueID]) async throws -> [IssueID:
    String]
  {
    let (error, states) = lock.withLock { (_fetchError, _statesByIDs) }
    if let error { throw error }
    return states.filter { issueIDs.contains($0.key) }
  }
}

// MARK: - Stub Orchestrator Delegate (for testing)

// SAFETY: @unchecked Sendable — all mutable state is exclusively accessed through `lock`.
public final class StubOrchestratorDelegate: OrchestratorDelegate, @unchecked Sendable {
  private let lock = NSLock()
  private var _synced: [Issue] = []
  private var _dispatched: [Issue] = []
  private var _canceled: [(IssueID, IssueIdentifier, String, Bool)] = []
  private var _refreshed: [Issue] = []
  private var _retried: [(Issue, RetryRecord)] = []

  public init() {}

  public var synced: [Issue] {
    lock.lock()
    defer { lock.unlock() }
    return _synced
  }

  public var dispatched: [Issue] {
    lock.lock()
    defer { lock.unlock() }
    return _dispatched
  }

  public var canceled: [(IssueID, IssueIdentifier, String, Bool)] {
    lock.lock()
    defer { lock.unlock() }
    return _canceled
  }

  public var refreshed: [Issue] {
    lock.lock()
    defer { lock.unlock() }
    return _refreshed
  }

  public var retried: [(Issue, RetryRecord)] {
    lock.lock()
    defer { lock.unlock() }
    return _retried
  }

  public nonisolated func orchestratorDidSyncIssues(_ issues: [Issue]) async {
    lock.withLock { _synced = issues }
  }

  public nonisolated func orchestratorDidDispatch(issue: Issue) async {
    lock.withLock { _dispatched.append(issue) }
  }

  public nonisolated func orchestratorDidCancel(
    issueID: IssueID, issueIdentifier: IssueIdentifier, reason: String, cleanup: Bool
  ) async {
    lock.withLock { _canceled.append((issueID, issueIdentifier, reason, cleanup)) }
  }

  public nonisolated func orchestratorDidRefreshSnapshot(issue: Issue) async {
    lock.withLock { _refreshed.append(issue) }
  }

  public nonisolated func orchestratorDidRetry(issue: Issue, record: RetryRecord) async {
    lock.withLock { _retried.append((issue, record)) }
  }
}
