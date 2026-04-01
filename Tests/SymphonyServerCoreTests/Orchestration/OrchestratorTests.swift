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

// MARK: - Orchestrator State Management Tests

@Test func orchestratorMarkRunning() async throws {
  let tracker = StubTracker()
  let delegate = StubOrchestratorDelegate()
  let orchestrator = Orchestrator(tracker: tracker, config: .defaults, delegate: delegate)

  orchestrator.markClaimed(issueID: IssueID("1"))
  #expect(orchestrator.claimedIssueIDs.contains(IssueID("1")))

  orchestrator.markRunning(issueID: IssueID("1"), state: "In Progress")
  #expect(orchestrator.runningIssueIDs.contains(IssueID("1")))
  #expect(!orchestrator.claimedIssueIDs.contains(IssueID("1")))
}

@Test func orchestratorMarkCompleted() async throws {
  let tracker = StubTracker()
  let delegate = StubOrchestratorDelegate()
  let orchestrator = Orchestrator(tracker: tracker, config: .defaults, delegate: delegate)

  orchestrator.markRunning(issueID: IssueID("1"), state: "In Progress")
  orchestrator.markCompleted(issueID: IssueID("1"), state: "In Progress")
  #expect(!orchestrator.runningIssueIDs.contains(IssueID("1")))
}

@Test func orchestratorMarkCompletedMultipleStates() async throws {
  let tracker = StubTracker()
  let delegate = StubOrchestratorDelegate()
  let orchestrator = Orchestrator(tracker: tracker, config: .defaults, delegate: delegate)

  orchestrator.markRunning(issueID: IssueID("1"), state: "In Progress")
  orchestrator.markRunning(issueID: IssueID("2"), state: "In Progress")
  orchestrator.markCompleted(issueID: IssueID("1"), state: "In Progress")
  // Second issue should still be tracked
  #expect(orchestrator.runningIssueIDs.contains(IssueID("2")))
}

@Test func orchestratorReloadAppliesUpdatedConfigOnFutureTicks() async throws {
  let tracker = StubTracker()
  let delegate = StubOrchestratorDelegate()
  let initialConfig = WorkflowConfig(
    tracker: TrackerConfig(activeStates: ["In Progress"], terminalStates: ["Done"])
  )
  let updatedConfig = WorkflowConfig(
    tracker: TrackerConfig(activeStates: ["Queued"], terminalStates: ["Done"])
  )
  let orchestrator = Orchestrator(tracker: tracker, config: initialConfig, delegate: delegate)

  let issue = try makeIssue(id: "reload-1", number: 1, state: "Queued")
  tracker.setAllIssues([issue])

  let initialResult = try await orchestrator.tick()
  #expect(initialResult.dispatched == 0)

  orchestrator.reload(tracker: tracker, config: updatedConfig)

  let updatedResult = try await orchestrator.tick()
  #expect(updatedResult.dispatched == 1)
  #expect(delegate.dispatched.count == 1)
  #expect(orchestrator.config.tracker.activeStates == ["Queued"])
}

// MARK: - Orchestrator Tick Tests

@Test func orchestratorTickDispatchesCandidates() async throws {
  let tracker = StubTracker()
  let delegate = StubOrchestratorDelegate()
  let orchestrator = Orchestrator(tracker: tracker, config: .defaults, delegate: delegate)

  let issue = try makeIssue(id: "1", number: 1, state: "In Progress")
  tracker.setAllIssues([issue])

  let result = try await orchestrator.tick()
  #expect(result.dispatched == 1)
  #expect(result.candidatesFetched == 1)
  #expect(delegate.dispatched.count == 1)
  #expect(delegate.dispatched[0].id == IssueID("1"))
}

@Test func orchestratorTickRespectsSlotLimit() async throws {
  let config = WorkflowConfig(agent: AgentConfig(maxConcurrentAgents: 1))
  let tracker = StubTracker()
  let delegate = StubOrchestratorDelegate()
  let orchestrator = Orchestrator(tracker: tracker, config: config, delegate: delegate)

  let issues = [
    try makeIssue(id: "1", number: 1),
    try makeIssue(id: "2", number: 2),
  ]
  tracker.setAllIssues(issues)

  let result = try await orchestrator.tick()
  #expect(result.dispatched == 1)
}

@Test func orchestratorTickFetchError() async throws {
  let tracker = StubTracker()
  let delegate = StubOrchestratorDelegate()
  let orchestrator = Orchestrator(tracker: tracker, config: .defaults, delegate: delegate)

  tracker.setFetchError(OrchestratorError.noTrackerConfigured)

  let result = try await orchestrator.tick()
  #expect(result.candidatesFetched == 0)
  #expect(result.dispatched == 0)
}

@Test func orchestratorTickProcessesRetries() async throws {
  let tracker = StubTracker()
  let delegate = StubOrchestratorDelegate()
  let retryQueue = RetryQueue()
  let orchestrator = Orchestrator(
    tracker: tracker, config: .defaults, retryQueue: retryQueue, delegate: delegate)

  let issue = try makeIssue(id: "retry-1", number: 1, state: "In Progress")
  let record = orchestrator.enqueueRetry(issue: issue, attempt: 2, delayMS: 0, error: "timeout")

  let result = try await orchestrator.tick()
  #expect(result.retriesProcessed == 1)
  #expect(delegate.retried.count == 1)
  #expect(delegate.retried[0].0.id == issue.id)
  #expect(delegate.retried[0].1 == record)
  #expect(orchestrator.queuedRetryRecord(issueID: issue.id) == nil)
}

@Test func orchestratorTickSkipsRetryWithoutIssueSnapshot() async throws {
  let tracker = StubTracker()
  let delegate = StubOrchestratorDelegate()
  let retryQueue = RetryQueue()
  let orchestrator = Orchestrator(
    tracker: tracker, config: .defaults, retryQueue: retryQueue, delegate: delegate)

  retryQueue.enqueue(
    RetryRecord(
      issueID: IssueID("retry-missing"),
      issueIdentifier: try IssueIdentifier(validating: "org/repo#3"),
      attempt: 2,
      dueAt: Date(timeIntervalSinceNow: -10),
      error: "timeout"
    )
  )

  let result = try await orchestrator.tick()
  #expect(result.retriesProcessed == 1)
  #expect(delegate.retried.isEmpty)
  #expect(retryQueue.count == 0)
}

@Test func orchestratorTickEmptyTracker() async throws {
  let tracker = StubTracker()
  let delegate = StubOrchestratorDelegate()
  let orchestrator = Orchestrator(tracker: tracker, config: .defaults, delegate: delegate)

  let result = try await orchestrator.tick()
  #expect(result.dispatched == 0)
  #expect(result.candidatesFetched == 0)
  #expect(result.reconciled == 0)
  #expect(result.retriesProcessed == 0)
}

@Test func orchestratorTickSynchronizesAllIssuesBeforeFilteringCandidates() async throws {
  let tracker = StubTracker()
  let delegate = StubOrchestratorDelegate()
  let orchestrator = Orchestrator(tracker: tracker, config: .defaults, delegate: delegate)

  let active = try makeIssue(id: "active-1", number: 1, state: "In Progress")
  let backlog = try makeIssue(id: "backlog-1", number: 2, state: "Backlog")
  tracker.setAllIssues([active, backlog])

  let result = try await orchestrator.tick()
  #expect(result.candidatesFetched == 2)
  #expect(result.dispatched == 1)
  #expect(delegate.synced.count == 2)
  #expect(delegate.synced.map { $0.state } == ["In Progress", "Backlog"])
}

@Test func orchestratorTickReconciliation() async throws {
  let tracker = StubTracker()
  let delegate = StubOrchestratorDelegate()
  let orchestrator = Orchestrator(tracker: tracker, config: .defaults, delegate: delegate)

  let issue = try makeIssue(id: "running-1", state: "In Progress", issueState: "OPEN")
  orchestrator.markRunning(issue: issue)
  tracker.setAllIssues([issue])

  let result = try await orchestrator.tick()
  #expect(result.reconciled == 1)
  #expect(delegate.refreshed.count == 1)
}

@Test func orchestratorTickReconcileErrorReturnsZero() async throws {
  let tracker = StubTracker()
  let delegate = StubOrchestratorDelegate()
  let orchestrator = Orchestrator(tracker: tracker, config: .defaults, delegate: delegate)

  orchestrator.markRunning(issueID: IssueID("running-1"), state: "In Progress")
  tracker.setFetchError(OrchestratorError.noTrackerConfigured)

  let result = try await orchestrator.tick()
  // Reconcile catches the error and returns 0; candidate fetch also fails
  #expect(result.reconciled == 0)
  #expect(result.candidatesFetched == 0)
}

private struct ReconcileOnlyErrorTracker: TrackerAdapting {
  func fetchAllIssues() async throws -> [SymphonyShared.Issue] {
    throw OrchestratorError.noTrackerConfigured
  }
  func fetchCandidateIssues() async throws -> [SymphonyShared.Issue] { [] }
  func fetchIssuesByStates(_ stateNames: [String]) async throws -> [SymphonyShared.Issue] { [] }
  func fetchIssueStatesByIDs(_ issueIDs: [IssueID]) async throws -> [IssueID: String] {
    throw OrchestratorError.noTrackerConfigured
  }
}

@Test func orchestratorTickReconcileErrorStillReturnsCandidates() async throws {
  let tracker = ReconcileOnlyErrorTracker()
  let delegate = StubOrchestratorDelegate()
  let orchestrator = Orchestrator(tracker: tracker, config: .defaults, delegate: delegate)

  orchestrator.markRunning(issueID: IssueID("running-1"), state: "In Progress")

  let result = try await orchestrator.tick()
  #expect(result.reconciled == 0)
  #expect(result.candidatesFetched == 0)
  #expect(result.dispatched == 0)
}

@Test func orchestratorTickReconciliationWithNoReturnedStates() async throws {
  let tracker = StubTracker()
  let delegate = StubOrchestratorDelegate()
  let orchestrator = Orchestrator(tracker: tracker, config: .defaults, delegate: delegate)

  orchestrator.markRunning(issueID: IssueID("running-1"), state: "In Progress")
  tracker.setAllIssues([])

  let result = try await orchestrator.tick()
  #expect(result.reconciled == 1)
  #expect(delegate.canceled.isEmpty)
  #expect(result.candidatesFetched == 0)
}

@Test func reconcileCancelsCachedIssueMissingFromLatestSnapshot() async throws {
  let tracker = StubTracker()
  let delegate = StubOrchestratorDelegate()
  let orchestrator = Orchestrator(tracker: tracker, config: .defaults, delegate: delegate)

  let issue = try makeIssue(id: "missing-1", state: "In Progress", issueState: "OPEN")
  orchestrator.markRunning(issue: issue)
  tracker.setAllIssues([])

  let result = try await orchestrator.tick()
  #expect(result.reconciled == 1)
  #expect(delegate.canceled.count == 1)
  #expect(delegate.canceled[0].0 == IssueID("missing-1"))
  #expect(delegate.canceled[0].2 == "Issue no longer present in project snapshot")
  #expect(delegate.canceled[0].3 == false)
  #expect(orchestrator.runningIssueIDs.isEmpty)
}

// MARK: - Reconciliation Delegation Tests

@Test func reconcileCancelsClosedIssue() async throws {
  let tracker = StubTracker()
  let delegate = StubOrchestratorDelegate()
  let orchestrator = Orchestrator(tracker: tracker, config: .defaults, delegate: delegate)

  let issue = try makeIssue(id: "r1", state: "In Progress", issueState: "OPEN")
  orchestrator.markRunning(issue: issue)
  tracker.setAllIssues([try makeIssue(id: "r1", state: "In Progress", issueState: "CLOSED")])

  let result = try await orchestrator.tick()
  #expect(result.reconciled == 1)
  #expect(delegate.canceled.count == 1)
  #expect(delegate.canceled[0].0 == IssueID("r1"))
  #expect(delegate.canceled[0].2 == "Issue closed")
  #expect(delegate.canceled[0].3 == true)
  #expect(orchestrator.runningIssueIDs.isEmpty)
}

@Test func reconcileCancelsTerminalProjectState() async throws {
  let tracker = StubTracker()
  let delegate = StubOrchestratorDelegate()
  let config = WorkflowConfig(
    tracker: TrackerConfig(activeStates: ["In Progress"], terminalStates: ["Done"]))
  let orchestrator = Orchestrator(tracker: tracker, config: config, delegate: delegate)

  let issue = try makeIssue(id: "r2", state: "Done", issueState: "OPEN")
  orchestrator.markRunning(issue: issue)
  tracker.setAllIssues([try makeIssue(id: "r2", state: "Done", issueState: "OPEN")])

  let result = try await orchestrator.tick()
  #expect(result.reconciled == 1)
  #expect(delegate.canceled.count == 1)
  #expect(delegate.canceled[0].2 == "Terminal project state: Done")
  #expect(delegate.canceled[0].3 == true)
  #expect(orchestrator.runningIssueIDs.isEmpty)
}

@Test func reconcileCancelsWhenLatestProjectStateBecomesNonActive() async throws {
  let tracker = StubTracker()
  let delegate = StubOrchestratorDelegate()
  let orchestrator = Orchestrator(tracker: tracker, config: .defaults, delegate: delegate)

  let issue = try makeIssue(id: "r3", state: "In Progress", issueState: "OPEN")
  orchestrator.markRunning(issue: issue)
  tracker.setAllIssues([try makeIssue(id: "r3", state: "Backlog", issueState: "OPEN")])

  let result = try await orchestrator.tick()
  #expect(result.reconciled == 1)
  #expect(delegate.canceled.count == 1)
  #expect(delegate.canceled[0].2 == "Non-active project state: Backlog")
  #expect(delegate.canceled[0].3 == false)
  #expect(orchestrator.runningIssueIDs.isEmpty)
}

@Test func reconcileRefreshesActiveIssue() async throws {
  let tracker = StubTracker()
  let delegate = StubOrchestratorDelegate()
  let orchestrator = Orchestrator(tracker: tracker, config: .defaults, delegate: delegate)

  let issue = try makeIssue(id: "r4", state: "In Progress", issueState: "OPEN")
  orchestrator.markRunning(issue: issue)
  tracker.setAllIssues([issue])

  let result = try await orchestrator.tick()
  #expect(result.reconciled == 1)
  #expect(delegate.refreshed.count == 1)
  #expect(delegate.refreshed[0].id == IssueID("r4"))
  #expect(orchestrator.runningIssueIDs.contains(IssueID("r4")))
}

@Test func reconcileSkipsUncachedIssues() async throws {
  let tracker = StubTracker()
  let delegate = StubOrchestratorDelegate()
  let orchestrator = Orchestrator(tracker: tracker, config: .defaults, delegate: delegate)

  // Use old markRunning without issue cache
  orchestrator.markRunning(issueID: IssueID("r5"), state: "In Progress")
  tracker.setStatesByIDs([IssueID("r5"): "CLOSED"])

  let result = try await orchestrator.tick()
  #expect(result.reconciled == 1)
  // No delegate action since issue is not cached
  #expect(delegate.canceled.isEmpty)
  #expect(delegate.refreshed.isEmpty)
}

@Test func reconcileMultipleIssuesMixedActions() async throws {
  let tracker = StubTracker()
  let delegate = StubOrchestratorDelegate()
  let orchestrator = Orchestrator(tracker: tracker, config: .defaults, delegate: delegate)

  let active = try makeIssue(id: "a1", number: 1, state: "In Progress", issueState: "OPEN")
  let closed = try makeIssue(id: "c1", number: 2, state: "In Progress", issueState: "OPEN")
  orchestrator.markRunning(issue: active)
  orchestrator.markRunning(issue: closed)
  tracker.setAllIssues([
    active,
    try makeIssue(id: "c1", number: 2, state: "In Progress", issueState: "CLOSED"),
  ])

  let result = try await orchestrator.tick()
  #expect(result.reconciled == 2)
  #expect(delegate.canceled.count == 1)
  #expect(delegate.refreshed.count == 1)
  #expect(orchestrator.runningIssueIDs.count == 1)
  #expect(orchestrator.runningIssueIDs.contains(IssueID("a1")))
}

@Test func reconcilerEvaluateWithStateStrings() {
  let config = TrackerConfig.defaults
  #expect(
    Reconciler.evaluate(issueState: "CLOSED", projectState: "In Progress", config: config)
      == .cancelAndCleanup(reason: "Issue closed"))
  #expect(
    Reconciler.evaluate(issueState: "OPEN", projectState: "Done", config: config)
      == .cancelAndCleanup(reason: "Terminal project state: Done"))
  #expect(
    Reconciler.evaluate(issueState: "OPEN", projectState: "Backlog", config: config)
      == .cancelWithoutCleanup(reason: "Non-active project state: Backlog"))
  #expect(
    Reconciler.evaluate(issueState: "OPEN", projectState: "In Progress", config: config)
      == .refreshSnapshot)
}

@Test func markRunningWithIssue() async throws {
  let tracker = StubTracker()
  let delegate = StubOrchestratorDelegate()
  let orchestrator = Orchestrator(tracker: tracker, config: .defaults, delegate: delegate)

  let issue = try makeIssue(id: "i1", state: "Todo")
  orchestrator.markRunning(issue: issue)
  #expect(orchestrator.runningIssueIDs.contains(IssueID("i1")))

  orchestrator.markCompleted(issueID: IssueID("i1"), state: "Todo")
  #expect(!orchestrator.runningIssueIDs.contains(IssueID("i1")))
}
