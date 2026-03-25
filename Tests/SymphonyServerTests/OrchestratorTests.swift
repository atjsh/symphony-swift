import Foundation
import SymphonyShared
import Testing

@testable import SymphonyRuntime

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

// MARK: - CandidateEligibility Tests

@Test func candidateEligibilityBasicEligible() throws {
  let issue = try makeIssue(state: "In Progress", issueState: "OPEN")
  let config = TrackerConfig.defaults

  let eligible = CandidateEligibility.isEligible(
    issue: issue,
    config: config,
    runningIssueIDs: [],
    claimedIssueIDs: []
  )
  #expect(eligible)
}

@Test func candidateEligibilityClosedIssueNotEligible() throws {
  let issue = try makeIssue(issueState: "CLOSED")
  let config = TrackerConfig.defaults

  let eligible = CandidateEligibility.isEligible(
    issue: issue,
    config: config,
    runningIssueIDs: [],
    claimedIssueIDs: []
  )
  #expect(!eligible)
}

@Test func candidateEligibilityNonActiveStateNotEligible() throws {
  let issue = try makeIssue(state: "Backlog")
  let config = TrackerConfig.defaults

  let eligible = CandidateEligibility.isEligible(
    issue: issue,
    config: config,
    runningIssueIDs: [],
    claimedIssueIDs: []
  )
  #expect(!eligible)
}

@Test func candidateEligibilityTerminalStateNotEligible() throws {
  let config = TrackerConfig(activeStates: ["Done"], terminalStates: ["Done"])
  let issue = try makeIssue(state: "Done")

  let eligible = CandidateEligibility.isEligible(
    issue: issue,
    config: config,
    runningIssueIDs: [],
    claimedIssueIDs: []
  )
  #expect(!eligible)
}

@Test func candidateEligibilityAlreadyRunningNotEligible() throws {
  let issue = try makeIssue(id: "running-1")

  let eligible = CandidateEligibility.isEligible(
    issue: issue,
    config: .defaults,
    runningIssueIDs: [IssueID("running-1")],
    claimedIssueIDs: []
  )
  #expect(!eligible)
}

@Test func candidateEligibilityAlreadyClaimedNotEligible() throws {
  let issue = try makeIssue(id: "claimed-1")

  let eligible = CandidateEligibility.isEligible(
    issue: issue,
    config: .defaults,
    runningIssueIDs: [],
    claimedIssueIDs: [IssueID("claimed-1")]
  )
  #expect(!eligible)
}

@Test func candidateEligibilityBlockedNotEligible() throws {
  let blocker = BlockerReference(
    issueID: IssueID("blocker-1"),
    identifier: try IssueIdentifier(validating: "org/repo#99"),
    state: "Todo",
    issueState: "OPEN",
    url: nil
  )
  let issue = try makeIssue(blockedBy: [blocker])

  let eligible = CandidateEligibility.isEligible(
    issue: issue,
    config: .defaults,
    runningIssueIDs: [],
    claimedIssueIDs: []
  )
  #expect(!eligible)
}

@Test func candidateEligibilityClosedBlockerDoesNotBlock() throws {
  let blocker = BlockerReference(
    issueID: IssueID("blocker-1"),
    identifier: try IssueIdentifier(validating: "org/repo#99"),
    state: "Todo",
    issueState: "CLOSED",
    url: nil
  )
  let issue = try makeIssue(blockedBy: [blocker])

  let eligible = CandidateEligibility.isEligible(
    issue: issue,
    config: .defaults,
    runningIssueIDs: [],
    claimedIssueIDs: []
  )
  #expect(eligible)
}

@Test func candidateEligibilityBlockerNotInProjectBlocks() throws {
  let blocker = BlockerReference(
    issueID: IssueID("blocker-1"),
    identifier: try IssueIdentifier(validating: "org/repo#99"),
    state: "UnknownState",
    issueState: "OPEN",
    url: nil
  )
  let issue = try makeIssue(blockedBy: [blocker])

  let eligible = CandidateEligibility.isEligible(
    issue: issue,
    config: .defaults,
    runningIssueIDs: [],
    claimedIssueIDs: []
  )
  #expect(!eligible)
}

@Test func candidateEligibilityFilterEligible() throws {
  let issues = [
    try makeIssue(id: "1", number: 1, state: "In Progress"),
    try makeIssue(id: "2", number: 2, issueState: "CLOSED"),
    try makeIssue(id: "3", number: 3, state: "In Progress"),
  ]

  let eligible = CandidateEligibility.filterEligible(
    candidates: issues,
    config: .defaults,
    runningIssueIDs: [],
    claimedIssueIDs: []
  )
  #expect(eligible.count == 2)
}

// MARK: - Candidate Sorting Tests

@Test func candidateSortByPriorityAscending() throws {
  let issues = [
    try makeIssue(id: "3", number: 3, priority: 3),
    try makeIssue(id: "1", number: 1, priority: 1),
    try makeIssue(id: "2", number: 2, priority: 2),
  ]

  let sorted = CandidateEligibility.sortCandidates(issues)
  #expect(sorted[0].number == 1)
  #expect(sorted[1].number == 2)
  #expect(sorted[2].number == 3)
}

@Test func candidateSortNullPriorityLast() throws {
  let issues = [
    try makeIssue(id: "n", number: 1, priority: nil),
    try makeIssue(id: "p", number: 2, priority: 1),
  ]

  let sorted = CandidateEligibility.sortCandidates(issues)
  #expect(sorted[0].number == 2)
  #expect(sorted[1].number == 1)
}

@Test func candidateSortByCreatedAt() throws {
  let issues = [
    try makeIssue(id: "2", number: 2, priority: 1, createdAt: "2024-02-01T00:00:00Z"),
    try makeIssue(id: "1", number: 1, priority: 1, createdAt: "2024-01-01T00:00:00Z"),
  ]

  let sorted = CandidateEligibility.sortCandidates(issues)
  #expect(sorted[0].number == 1)
  #expect(sorted[1].number == 2)
}

@Test func candidateSortByIdentifier() throws {
  let issues = [
    try makeIssue(
      id: "b", owner: "org", repo: "b", number: 1, priority: 1, createdAt: "2024-01-01T00:00:00Z"),
    try makeIssue(
      id: "a", owner: "org", repo: "a", number: 1, priority: 1, createdAt: "2024-01-01T00:00:00Z"),
  ]

  let sorted = CandidateEligibility.sortCandidates(issues)
  #expect(sorted[0].identifier.rawValue == "org/a#1")
  #expect(sorted[1].identifier.rawValue == "org/b#1")
}

// MARK: - Blocker Semantics Tests

@Test func isBlockedNoBlockers() throws {
  let issue = try makeIssue()
  #expect(!CandidateEligibility.isBlocked(issue: issue, config: .defaults))
}

@Test func isBlockedOpenBlockerInBlockedStates() throws {
  let blocker = BlockerReference(
    issueID: IssueID("b1"),
    identifier: try IssueIdentifier(validating: "org/repo#2"),
    state: "Todo",
    issueState: "OPEN",
    url: nil
  )
  let issue = try makeIssue(blockedBy: [blocker])
  #expect(CandidateEligibility.isBlocked(issue: issue, config: .defaults))
}

@Test func isBlockedOpenBlockerNotInAnyConfiguredState() throws {
  let blocker = BlockerReference(
    issueID: IssueID("b1"),
    identifier: try IssueIdentifier(validating: "org/repo#2"),
    state: "NotConfigured",
    issueState: "OPEN",
    url: nil
  )
  let issue = try makeIssue(blockedBy: [blocker])
  #expect(CandidateEligibility.isBlocked(issue: issue, config: .defaults))
}

@Test func isBlockedOpenBlockerInActiveStateNotBlocked() throws {
  let blocker = BlockerReference(
    issueID: IssueID("b1"),
    identifier: try IssueIdentifier(validating: "org/repo#2"),
    state: "In Progress",
    issueState: "OPEN",
    url: nil
  )
  let issue = try makeIssue(blockedBy: [blocker])
  // "In Progress" is in activeStates and not in blockedStates
  #expect(!CandidateEligibility.isBlocked(issue: issue, config: .defaults))
}

// MARK: - RetryQueue Tests

@Test func retryQueueEnqueueAndDequeue() throws {
  let queue = RetryQueue()
  let record = RetryRecord(
    issueID: IssueID("issue-1"),
    issueIdentifier: try IssueIdentifier(validating: "org/repo#1"),
    attempt: 1,
    dueAt: Date(),
    error: nil
  )

  queue.enqueue(record)
  #expect(queue.count == 1)

  let dequeued = queue.dequeue(issueID: IssueID("issue-1"))
  #expect(dequeued != nil)
  #expect(queue.count == 0)
}

@Test func retryQueueDequeueNonexistent() {
  let queue = RetryQueue()
  let result = queue.dequeue(issueID: IssueID("missing"))
  #expect(result == nil)
}

@Test func retryQueueDueEntries() throws {
  let queue = RetryQueue()
  let past = Date(timeIntervalSinceNow: -100)
  let future = Date(timeIntervalSinceNow: 100)

  queue.enqueue(
    RetryRecord(
      issueID: IssueID("past"),
      issueIdentifier: try IssueIdentifier(validating: "org/repo#1"),
      attempt: 1,
      dueAt: past,
      error: nil
    ))
  queue.enqueue(
    RetryRecord(
      issueID: IssueID("future"),
      issueIdentifier: try IssueIdentifier(validating: "org/repo#2"),
      attempt: 1,
      dueAt: future,
      error: nil
    ))

  let due = queue.dueEntries()
  #expect(due.count == 1)
  #expect(due[0].issueID == IssueID("past"))
}

@Test func retryQueueRemoveAll() throws {
  let queue = RetryQueue()
  queue.enqueue(
    RetryRecord(
      issueID: IssueID("1"),
      issueIdentifier: try IssueIdentifier(validating: "org/repo#1"),
      attempt: 1,
      dueAt: Date(),
      error: nil
    ))
  queue.enqueue(
    RetryRecord(
      issueID: IssueID("2"),
      issueIdentifier: try IssueIdentifier(validating: "org/repo#2"),
      attempt: 1,
      dueAt: Date(),
      error: nil
    ))

  #expect(queue.count == 2)
  queue.removeAll()
  #expect(queue.count == 0)
}

@Test func retryQueueEntries() throws {
  let queue = RetryQueue()
  queue.enqueue(
    RetryRecord(
      issueID: IssueID("1"),
      issueIdentifier: try IssueIdentifier(validating: "org/repo#1"),
      attempt: 1,
      dueAt: Date(),
      error: nil
    ))

  let entries = queue.entries
  #expect(entries.count == 1)
  #expect(entries[IssueID("1")] != nil)
}

@Test func retryQueueBackoffDelay() {
  #expect(RetryQueue.backoffDelay(attempt: 1, maxRetryBackoffMS: 300_000) == 10_000)
  #expect(RetryQueue.backoffDelay(attempt: 2, maxRetryBackoffMS: 300_000) == 20_000)
  #expect(RetryQueue.backoffDelay(attempt: 3, maxRetryBackoffMS: 300_000) == 40_000)
  #expect(RetryQueue.backoffDelay(attempt: 4, maxRetryBackoffMS: 300_000) == 80_000)
  #expect(RetryQueue.backoffDelay(attempt: 5, maxRetryBackoffMS: 300_000) == 160_000)
  // Capped at max
  #expect(RetryQueue.backoffDelay(attempt: 10, maxRetryBackoffMS: 300_000) == 300_000)
}

@Test func retryQueueContinuationDelay() {
  #expect(RetryQueue.continuationDelay() == 1_000)
}

// MARK: - StallDetector Tests

@Test func stallDetectorEnabled() {
  let detector = StallDetector(stallTimeoutMS: 60_000)
  #expect(detector.isEnabled)
}

@Test func stallDetectorDisabledWithZero() {
  let detector = StallDetector(stallTimeoutMS: 0)
  #expect(!detector.isEnabled)
}

@Test func stallDetectorDisabledWithNegative() {
  let detector = StallDetector(stallTimeoutMS: -1)
  #expect(!detector.isEnabled)
}

@Test func stallDetectorNotStalled() {
  let detector = StallDetector(stallTimeoutMS: 60_000)
  let recent = Date()
  #expect(!detector.isStalled(lastEventAt: recent))
}

@Test func stallDetectorStalled() {
  let detector = StallDetector(stallTimeoutMS: 1_000)
  let old = Date(timeIntervalSinceNow: -2)
  #expect(detector.isStalled(lastEventAt: old))
}

@Test func stallDetectorDisabledNeverStalls() {
  let detector = StallDetector(stallTimeoutMS: 0)
  let old = Date(timeIntervalSinceNow: -1000)
  #expect(!detector.isStalled(lastEventAt: old))
}

// MARK: - ConcurrencySlotManager Tests

@Test func concurrencySlotManagerAvailableSlots() {
  let config = AgentConfig(maxConcurrentAgents: 5)
  let manager = ConcurrencySlotManager(config: config)
  #expect(manager.availableSlots(currentRunning: 0) == 5)
  #expect(manager.availableSlots(currentRunning: 3) == 2)
  #expect(manager.availableSlots(currentRunning: 5) == 0)
  #expect(manager.availableSlots(currentRunning: 10) == 0)
}

@Test func concurrencySlotManagerAvailableSlotsForState() {
  let config = AgentConfig(maxConcurrentAgentsByState: ["Todo": 2, "In Progress": 3])
  let manager = ConcurrencySlotManager(config: config)
  #expect(manager.availableSlots(forState: "Todo", currentInState: 0) == 2)
  #expect(manager.availableSlots(forState: "Todo", currentInState: 1) == 1)
  #expect(manager.availableSlots(forState: "Todo", currentInState: 2) == 0)
  #expect(manager.availableSlots(forState: "Unknown", currentInState: 0) == Int.max)
}

@Test func concurrencySlotManagerCanDispatch() {
  let config = AgentConfig(maxConcurrentAgents: 5, maxConcurrentAgentsByState: ["Todo": 2])
  let manager = ConcurrencySlotManager(config: config)
  #expect(manager.canDispatch(currentRunning: 0, state: "Todo", currentInState: 0))
  #expect(manager.canDispatch(currentRunning: 4, state: "Todo", currentInState: 1))
  #expect(!manager.canDispatch(currentRunning: 5, state: "Todo", currentInState: 0))
  #expect(!manager.canDispatch(currentRunning: 0, state: "Todo", currentInState: 2))
}

// MARK: - Reconciliation Tests

@Test func reconcilerClosedIssue() throws {
  let issue = try makeIssue(issueState: "CLOSED")
  let action = Reconciler.evaluate(issue: issue, config: .defaults)
  #expect(action == .cancelAndCleanup(reason: "Issue closed"))
}

@Test func reconcilerTerminalState() throws {
  let issue = try makeIssue(state: "Done")
  let action = Reconciler.evaluate(issue: issue, config: .defaults)
  #expect(action == .cancelAndCleanup(reason: "Terminal project state: Done"))
}

@Test func reconcilerNonActiveState() throws {
  let issue = try makeIssue(state: "Backlog")
  let action = Reconciler.evaluate(issue: issue, config: .defaults)
  #expect(action == .cancelWithoutCleanup(reason: "Non-active project state: Backlog"))
}

@Test func reconcilerActiveState() throws {
  let issue = try makeIssue(state: "In Progress")
  let action = Reconciler.evaluate(issue: issue, config: .defaults)
  #expect(action == .refreshSnapshot)
}

// MARK: - TickResult Tests

@Test func tickResultInit() {
  let result = TickResult(reconciled: 1, candidatesFetched: 5, dispatched: 2, retriesProcessed: 0)
  #expect(result.reconciled == 1)
  #expect(result.candidatesFetched == 5)
  #expect(result.dispatched == 2)
  #expect(result.retriesProcessed == 0)
}

@Test func tickResultEquatable() {
  let a = TickResult(reconciled: 1, candidatesFetched: 5, dispatched: 2, retriesProcessed: 0)
  let b = TickResult(reconciled: 1, candidatesFetched: 5, dispatched: 2, retriesProcessed: 0)
  let c = TickResult(reconciled: 0, candidatesFetched: 5, dispatched: 2, retriesProcessed: 0)
  #expect(a == b)
  #expect(a != c)
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

// MARK: - Orchestrator Tick Tests

@Test func orchestratorTickDispatchesCandidates() async throws {
  let tracker = StubTracker()
  let delegate = StubOrchestratorDelegate()
  let orchestrator = Orchestrator(tracker: tracker, config: .defaults, delegate: delegate)

  let issue = try makeIssue(id: "1", number: 1, state: "In Progress")
  tracker.setCandidates([issue])

  let result = try await orchestrator.tick()
  #expect(result.dispatched == 1)
  #expect(result.candidatesFetched == 1)
  #expect(delegate.dispatched.count == 1)
  #expect(delegate.dispatched[0].0 == IssueID("1"))
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
  tracker.setCandidates(issues)

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

  let record = RetryRecord(
    issueID: IssueID("retry-1"),
    issueIdentifier: try IssueIdentifier(validating: "org/repo#1"),
    attempt: 1,
    dueAt: Date(timeIntervalSinceNow: -10),
    error: nil
  )
  retryQueue.enqueue(record)

  let result = try await orchestrator.tick()
  #expect(result.retriesProcessed == 1)
  #expect(delegate.retried.count == 1)
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

@Test func orchestratorTickReconciliation() async throws {
  let tracker = StubTracker()
  let delegate = StubOrchestratorDelegate()
  let orchestrator = Orchestrator(tracker: tracker, config: .defaults, delegate: delegate)

  orchestrator.markRunning(issueID: IssueID("running-1"), state: "In Progress")
  tracker.setStatesByIDs([IssueID("running-1"): "Done"])

  let result = try await orchestrator.tick()
  #expect(result.reconciled == 1)
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

// MARK: - StubTracker Tests

@Test func stubTrackerSetAndFetch() async throws {
  let tracker = StubTracker()
  let issue = try makeIssue()
  tracker.setCandidates([issue])

  let candidates = try await tracker.fetchCandidateIssues()
  #expect(candidates.count == 1)
}

@Test func stubTrackerFetchByStates() async throws {
  let tracker = StubTracker()
  let issues = [
    try makeIssue(id: "1", number: 1, state: "Active"),
    try makeIssue(id: "2", number: 2, state: "Done"),
  ]
  tracker.setIssuesByStates(issues)

  let result = try await tracker.fetchIssuesByStates(["Active"])
  #expect(result.count == 1)
  #expect(result[0].state == "Active")
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

  await delegate.orchestratorDidDispatch(
    issueID: IssueID("1"),
    issueIdentifier: try IssueIdentifier(validating: "org/repo#1")
  )
  #expect(delegate.dispatched.count == 1)

  await delegate.orchestratorDidCancel(
    issueID: IssueID("2"),
    reason: "canceled",
    cleanup: true
  )
  #expect(delegate.canceled.count == 1)

  let issue = try makeIssue()
  await delegate.orchestratorDidRefreshSnapshot(issue: issue)
  #expect(delegate.refreshed.count == 1)

  let record = RetryRecord(
    issueID: IssueID("3"),
    issueIdentifier: try IssueIdentifier(validating: "org/repo#3"),
    attempt: 1,
    dueAt: Date(),
    error: nil
  )
  await delegate.orchestratorDidRetry(record: record)
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
