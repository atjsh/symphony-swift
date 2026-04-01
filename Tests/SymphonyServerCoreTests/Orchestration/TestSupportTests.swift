import Foundation
import SymphonyShared
import Testing

@testable import SymphonyServerCore

// MARK: - Test Issue Helper

private func makeIssue(
  id: String = "issue-1",
  owner: String = "org",
  repo: String = "repo",
  number: Int = 1,
  state: String = "In Progress",
  issueState: String = "OPEN",
  priority: Int? = nil,
  createdAt: String? = nil,
  blockedBy: [BlockerReference] = []
) throws -> SymphonyShared.Issue {
  SymphonyShared.Issue(
    id: IssueID(id),
    identifier: try IssueIdentifier(validating: "\(owner)/\(repo)#\(number)"),
    repository: "\(owner)/\(repo)",
    number: number,
    title: "Issue \(number)",
    description: nil,
    priority: priority,
    state: state,
    issueState: issueState,
    projectItemID: nil,
    url: nil,
    labels: [],
    blockedBy: blockedBy,
    createdAt: createdAt,
    updatedAt: nil
  )
}

// MARK: - StubTracker Tests

@Test func stubTrackerSetAndFetch() async throws {
  let tracker = StubTracker()
  let issue = try makeIssue()
  tracker.setAllIssues([issue])

  let candidates = try await tracker.fetchCandidateIssues()
  #expect(candidates.count == 1)
}

@Test func stubTrackerSetCandidatesOverridesFetchedCandidateList() async throws {
  let tracker = StubTracker()
  let allIssue = try makeIssue(id: "all-1", number: 1, state: "In Progress")
  let candidate = try makeIssue(id: "candidate-1", number: 2, state: "Todo")
  tracker.setAllIssues([allIssue])
  tracker.setCandidates([candidate])

  let candidates = try await tracker.fetchCandidateIssues()
  #expect(candidates == [candidate])
}

@Test func stubTrackerFetchByStates() async throws {
  let tracker = StubTracker()
  let issues = [
    try makeIssue(id: "1", number: 1, state: "Active"),
    try makeIssue(id: "2", number: 2, state: "Done"),
  ]
  tracker.setAllIssues(issues)

  let result = try await tracker.fetchIssuesByStates(["Active"])
  #expect(result.count == 1)
  #expect(result[0].state == "Active")
}

@Test func stubTrackerSetIssuesByStatesOverridesStateFilteredResults() async throws {
  let tracker = StubTracker()
  let allIssue = try makeIssue(id: "all-1", number: 1, state: "Backlog")
  let filteredIssue = try makeIssue(id: "filtered-1", number: 2, state: "Active")
  tracker.setAllIssues([allIssue])
  tracker.setIssuesByStates([filteredIssue])

  let result = try await tracker.fetchIssuesByStates(["Active"])
  #expect(result == [filteredIssue])
}

@Test func stubTrackerFetchAllIssues() async throws {
  let tracker = StubTracker()
  let issues = [
    try makeIssue(id: "1", number: 1, state: "Active"),
    try makeIssue(id: "2", number: 2, state: "Backlog"),
  ]
  tracker.setAllIssues(issues)

  let result = try await tracker.fetchAllIssues()
  #expect(result == issues)
}

@Test func stubTrackerFetchStatesByIDs() async throws {
  let tracker = StubTracker()
  tracker.setStatesByIDs([IssueID("1"): "Active", IssueID("2"): "Done"])

  let result = try await tracker.fetchIssueStatesByIDs([IssueID("1")])
  #expect(result.count == 1)
  #expect(result[IssueID("1")] == "Active")
}

@Test func stubTrackerFetchError() async throws {
  let tracker = StubTracker()
  tracker.setFetchError(OrchestratorError.noTrackerConfigured)

  do {
    _ = try await tracker.fetchCandidateIssues()
    #expect(Bool(false), "Should have thrown")
  } catch {
    // Expected
  }
}

@Test func stubTrackerClearError() async throws {
  let tracker = StubTracker()
  tracker.setFetchError(OrchestratorError.noTrackerConfigured)
  tracker.setFetchError(nil as Error?)

  let result = try await tracker.fetchCandidateIssues()
  #expect(result.isEmpty)
}

// MARK: - StubOrchestratorDelegate Tests

@Test func stubOrchestratorDelegateRecords() async throws {
  let delegate = StubOrchestratorDelegate()

  let dispatchIssue = try makeIssue(id: "1", number: 1)
  await delegate.orchestratorDidDispatch(issue: dispatchIssue)
  #expect(delegate.dispatched.count == 1)

  await delegate.orchestratorDidCancel(
    issueID: IssueID("2"),
    issueIdentifier: try IssueIdentifier(validating: "org/repo#2"),
    reason: "canceled",
    cleanup: true
  )
  #expect(delegate.canceled.count == 1)

  let issue = try makeIssue()
  await delegate.orchestratorDidRefreshSnapshot(issue: issue)
  #expect(delegate.refreshed.count == 1)

  await delegate.orchestratorDidSyncIssues([issue])
  #expect(delegate.synced.count == 1)

  let record = RetryRecord(
    issueID: IssueID("3"),
    issueIdentifier: try IssueIdentifier(validating: "org/repo#3"),
    attempt: 1,
    dueAt: Date(),
    error: nil
  )
  await delegate.orchestratorDidRetry(issue: issue, record: record)
  #expect(delegate.retried.count == 1)
}

// MARK: - ReconciliationAction Tests

@Test func reconciliationActionEquatable() {
  #expect(ReconciliationAction.continueRunning == .continueRunning)
  #expect(ReconciliationAction.cancelAndCleanup(reason: "A") == .cancelAndCleanup(reason: "A"))
  #expect(ReconciliationAction.cancelAndCleanup(reason: "A") != .cancelAndCleanup(reason: "B"))
  #expect(
    ReconciliationAction.cancelWithoutCleanup(reason: "X") == .cancelWithoutCleanup(reason: "X"))
  #expect(ReconciliationAction.refreshSnapshot == .refreshSnapshot)
  #expect(ReconciliationAction.continueRunning != .refreshSnapshot)
}

// MARK: - OrchestratorError Tests

@Test func orchestratorErrorEquatable() {
  #expect(OrchestratorError.noTrackerConfigured == .noTrackerConfigured)
  #expect(OrchestratorError.configurationInvalid("x") == .configurationInvalid("x"))
  #expect(OrchestratorError.configurationInvalid("x") != .configurationInvalid("y"))
  #expect(OrchestratorError.dispatchFailed("d") == .dispatchFailed("d"))
  #expect(OrchestratorError.reconciliationFailed("r") == .reconciliationFailed("r"))
}
