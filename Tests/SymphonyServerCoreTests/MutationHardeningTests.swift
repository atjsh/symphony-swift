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

// MARK: - Orchestrator State Count Tests

/// Verifies that markCompleted decrements per-state count when multiple issues share a state,
/// rather than removing the state entirely. Kills mutants on _runningStateCount decrement path.
@Test func markCompletedDecrementsStateCountWhenMultipleIssuesShareState() async throws {
  let config = WorkflowConfig(
    agent: AgentConfig(
      maxConcurrentAgents: 10,
      maxConcurrentAgentsByState: ["In Progress": 2]
    )
  )
  let tracker = StubTracker()
  let delegate = StubOrchestratorDelegate()
  let orchestrator = Orchestrator(tracker: tracker, config: config, delegate: delegate)

  // Two running issues in same state → state count = 2
  let r1 = try makeIssue(id: "1", number: 1, state: "In Progress")
  let r2 = try makeIssue(id: "2", number: 2, state: "In Progress")
  orchestrator.markRunning(issue: r1)
  orchestrator.markRunning(issue: r2)

  // Complete one → state count should become 1, leaving one slot open
  orchestrator.markCompleted(issueID: IssueID("1"), state: "In Progress")

  // A new candidate should be dispatchable since state limit is 2 and count is now 1
  let candidate = try makeIssue(id: "3", number: 3, state: "In Progress")
  // Include r2 in allIssues to prevent reconciliation from removing it
  tracker.setAllIssues([r2, candidate])

  let result = try await orchestrator.tick()
  #expect(result.dispatched == 1, "State count must have been decremented to allow dispatch")
}

/// Verifies that markCompleted removes the state key entirely when the last issue in that
/// state is completed. Kills mutant on _runningStateCount.removeValue(forKey:).
@Test func markCompletedRemovesStateKeyWhenLastIssueCompleted() async throws {
  let config = WorkflowConfig(
    agent: AgentConfig(
      maxConcurrentAgents: 10,
      maxConcurrentAgentsByState: ["In Progress": 1]
    )
  )
  let tracker = StubTracker()
  let delegate = StubOrchestratorDelegate()
  let orchestrator = Orchestrator(tracker: tracker, config: config, delegate: delegate)

  let running = try makeIssue(id: "1", number: 1, state: "In Progress")
  orchestrator.markRunning(issue: running)
  orchestrator.markCompleted(issueID: IssueID("1"), state: "In Progress")

  // After completing the only running issue, state count should be 0 (key removed).
  // A new candidate in the same state should be dispatchable.
  let candidate = try makeIssue(id: "2", number: 2, state: "In Progress")
  tracker.setAllIssues([candidate])

  let result = try await orchestrator.tick()
  #expect(result.dispatched == 1, "State key must have been removed to allow dispatch")
}

/// Verifies markCompleted's count > 1 branch boundary. With 2 running issues at state limit 2,
/// no more can dispatch. After completing one (count 2→1), dispatch becomes possible.
/// Kills RelationalOperatorReplacement on `count > 1`.
@Test func markCompletedStateCountBoundary() async throws {
  let config = WorkflowConfig(
    tracker: TrackerConfig(activeStates: ["A"], terminalStates: ["Done"]),
    agent: AgentConfig(
      maxConcurrentAgents: 10,
      maxConcurrentAgentsByState: ["A": 2]
    )
  )
  let tracker = StubTracker()
  let delegate = StubOrchestratorDelegate()
  let orchestrator = Orchestrator(tracker: tracker, config: config, delegate: delegate)

  let r1 = try makeIssue(id: "1", number: 1, state: "A")
  let r2 = try makeIssue(id: "2", number: 2, state: "A")
  orchestrator.markRunning(issue: r1)
  orchestrator.markRunning(issue: r2)

  // At state limit (2 running, limit 2) → no dispatch possible
  let candidate = try makeIssue(id: "3", number: 3, state: "A")
  tracker.setAllIssues([r1, r2, candidate])

  let atLimit = try await orchestrator.tick()
  #expect(atLimit.dispatched == 0, "Dispatch blocked when state count equals limit")

  // Complete one → count 2→1, now dispatch possible
  orchestrator.markCompleted(issueID: IssueID("1"), state: "A")
  tracker.setAllIssues([r2, candidate])

  let afterDecrement = try await orchestrator.tick()
  #expect(afterDecrement.dispatched >= 1, "State count decrement must re-enable dispatch")
}

// MARK: - Orchestrator Cache and Cleanup Tests

/// Verifies markRunning(issue:) caches the issue so reconciliation can find it.
/// Kills mutant on `_runningIssues[issue.id] = issue`.
@Test func markRunningWithIssueCachesForReconciliation() async throws {
  let tracker = StubTracker()
  let delegate = StubOrchestratorDelegate()
  let orchestrator = Orchestrator(tracker: tracker, config: .defaults, delegate: delegate)

  let issue = try makeIssue(id: "cached-1", state: "In Progress", issueState: "OPEN")
  orchestrator.markRunning(issue: issue)

  // Reconcile with a closed version → should cancel (only possible if cached)
  let closedIssue = try makeIssue(id: "cached-1", state: "In Progress", issueState: "CLOSED")
  tracker.setAllIssues([closedIssue])

  let result = try await orchestrator.tick()
  #expect(result.reconciled == 1)
  #expect(delegate.canceled.count == 1, "Cached issue should enable cancellation on close")
  #expect(delegate.canceled[0].0 == IssueID("cached-1"))
}

/// Verifies markCompleted removes the issue from _runningIssues cache so reconciliation
/// cannot act on it afterward. Kills mutant on `_runningIssues.removeValue(forKey:)`.
@Test func markCompletedRemovesCachedIssue() async throws {
  let tracker = StubTracker()
  let delegate = StubOrchestratorDelegate()
  let orchestrator = Orchestrator(tracker: tracker, config: .defaults, delegate: delegate)

  let issue = try makeIssue(id: "cleanup-1", state: "In Progress", issueState: "OPEN")
  orchestrator.markRunning(issue: issue)
  orchestrator.markCompleted(issueID: IssueID("cleanup-1"), state: "In Progress")

  // Re-mark as running WITHOUT issue (simulating id-only re-entry)
  orchestrator.markRunning(issueID: IssueID("cleanup-1"), state: "In Progress")

  // Reconcile with the issue absent from snapshot — without cached issue, no cancel delegate call
  tracker.setAllIssues([])
  let result = try await orchestrator.tick()
  #expect(result.reconciled == 1)
  #expect(
    delegate.canceled.isEmpty,
    "After markCompleted, cached issue must be gone — reconciliation should skip uncached issue"
  )
}

/// Verifies markCompleted removes the issue from _retryIssues so processRetries cannot
/// find the snapshot. Kills mutant on `_retryIssues.removeValue(forKey:)`.
@Test func markCompletedRemovesRetryIssueSnapshot() async throws {
  let tracker = StubTracker()
  let delegate = StubOrchestratorDelegate()
  let retryQueue = RetryQueue()
  let orchestrator = Orchestrator(
    tracker: tracker, config: .defaults, retryQueue: retryQueue, delegate: delegate
  )

  let issue = try makeIssue(id: "retry-clean-1", number: 1, state: "In Progress")
  // Enqueue retry (stores snapshot in _retryIssues)
  _ = orchestrator.enqueueRetry(issue: issue, attempt: 2, delayMS: 0, error: "err")

  // Complete the issue (should clear _retryIssues entry AND dequeue from retryQueue claimed set)
  orchestrator.markCompleted(issueID: IssueID("retry-clean-1"), state: "In Progress")

  // Re-enqueue a retry for the same issue but without snapshot
  retryQueue.enqueue(
    RetryRecord(
      issueID: IssueID("retry-clean-1"),
      issueIdentifier: try IssueIdentifier(validating: "org/repo#1"),
      attempt: 3,
      dueAt: Date(timeIntervalSinceNow: -10),
      error: "timeout"
    )
  )

  let result = try await orchestrator.tick()
  #expect(result.retriesProcessed == 1)
  // Because _retryIssues was cleared, processRetries should NOT find a snapshot → no delegate call
  #expect(
    delegate.retried.isEmpty,
    "Retry snapshot must have been removed by markCompleted"
  )
}

/// Verifies markCompleted removes the issue from _claimedIssueIDs.
/// Kills mutant on `_claimedIssueIDs.remove(issueID)` inside markCompleted.
@Test func markCompletedRemovesFromClaimedSet() async throws {
  let tracker = StubTracker()
  let delegate = StubOrchestratorDelegate()
  let orchestrator = Orchestrator(tracker: tracker, config: .defaults, delegate: delegate)

  orchestrator.markClaimed(issueID: IssueID("claimed-1"))
  #expect(orchestrator.claimedIssueIDs.contains(IssueID("claimed-1")))

  orchestrator.markCompleted(issueID: IssueID("claimed-1"), state: "In Progress")
  #expect(
    !orchestrator.claimedIssueIDs.contains(IssueID("claimed-1")),
    "markCompleted must remove from claimed set"
  )
}

/// Verifies cacheRunningIssue updates the cached snapshot during reconciliation refresh.
/// Kills mutant on `_runningIssues[issueID] = issue` in cacheRunningIssue.
@Test func reconciliationRefreshUpdatesCachedIssue() async throws {
  let tracker = StubTracker()
  let delegate = StubOrchestratorDelegate()
  let orchestrator = Orchestrator(tracker: tracker, config: .defaults, delegate: delegate)

  let original = try makeIssue(id: "refresh-1", state: "In Progress", issueState: "OPEN")
  orchestrator.markRunning(issue: original)

  // Reconcile with a refreshed version (still active, same state)
  let refreshed = SymphonyShared.Issue(
    id: IssueID("refresh-1"),
    identifier: try IssueIdentifier(validating: "org/repo#1"),
    repository: "org/repo",
    number: 1,
    title: "Updated Title",
    description: "new description",
    priority: nil,
    state: "In Progress",
    issueState: "OPEN",
    projectItemID: nil,
    url: nil,
    labels: [],
    blockedBy: [],
    createdAt: nil,
    updatedAt: nil
  )
  tracker.setAllIssues([refreshed])

  _ = try await orchestrator.tick()
  #expect(delegate.refreshed.count == 1)
  #expect(delegate.refreshed[0].title == "Updated Title")

  // Now change it to closed — reconciliation must see the UPDATED cache
  let closed = SymphonyShared.Issue(
    id: IssueID("refresh-1"),
    identifier: try IssueIdentifier(validating: "org/repo#1"),
    repository: "org/repo",
    number: 1,
    title: "Updated Title",
    description: "new description",
    priority: nil,
    state: "In Progress",
    issueState: "CLOSED",
    projectItemID: nil,
    url: nil,
    labels: [],
    blockedBy: [],
    createdAt: nil,
    updatedAt: nil
  )
  tracker.setAllIssues([closed])

  _ = try await orchestrator.tick()
  // The cached issue must have been updated by cacheRunningIssue on the first refresh,
  // so the cancel delegate should fire with the cached identifier.
  #expect(delegate.canceled.count == 1, "Cache must be updated for subsequent reconciliation")
  #expect(delegate.canceled[0].0 == IssueID("refresh-1"))
}

/// Verifies markRunning(issueID:state:) increments state count for per-state slot tracking.
/// Kills mutant on `_runningStateCount[state, default: 0] += 1` in markRunning(issueID:state:).
@Test func markRunningIDIncrementsStateCount() async throws {
  let config = WorkflowConfig(
    agent: AgentConfig(
      maxConcurrentAgents: 10,
      maxConcurrentAgentsByState: ["In Progress": 1]
    )
  )
  let tracker = StubTracker()
  let delegate = StubOrchestratorDelegate()
  let orchestrator = Orchestrator(tracker: tracker, config: config, delegate: delegate)

  let issue = try makeIssue(id: "1", number: 1, state: "In Progress")
  orchestrator.markRunning(issue: issue)

  // With limit 1 and one already running, no more should dispatch
  let candidate = try makeIssue(id: "2", number: 2, state: "In Progress")
  // Include running issue in allIssues to prevent reconciliation removal
  tracker.setAllIssues([issue, candidate])

  let result = try await orchestrator.tick()
  #expect(result.dispatched == 0, "State count must be incremented to block dispatch at limit")
}

/// Verifies markRunning(issue:) increments state count for per-state slot tracking.
/// Kills mutant on `_runningStateCount[issue.state, default: 0] += 1` in markRunning(issue:).
@Test func markRunningIssueIncrementsStateCount() async throws {
  let config = WorkflowConfig(
    agent: AgentConfig(
      maxConcurrentAgents: 10,
      maxConcurrentAgentsByState: ["In Progress": 1]
    )
  )
  let tracker = StubTracker()
  let delegate = StubOrchestratorDelegate()
  let orchestrator = Orchestrator(tracker: tracker, config: config, delegate: delegate)

  let issue = try makeIssue(id: "1", number: 1, state: "In Progress")
  orchestrator.markRunning(issue: issue)

  let candidate = try makeIssue(id: "2", number: 2, state: "In Progress")
  // Include issue in allIssues to prevent reconciliation removal
  tracker.setAllIssues([issue, candidate])

  let result = try await orchestrator.tick()
  #expect(result.dispatched == 0, "State count must be incremented to block dispatch at limit")
}

// MARK: - Candidate Sort Tiebreaker Tests

/// Verifies sort tiebreaker: same priority, different createdAt → oldest first.
/// Kills RelationalOperatorReplacement on `aCreated != bCreated`.
@Test func sortCandidatesTiebreakByCreatedAt() throws {
  let newer = try makeIssue(id: "new", number: 1, priority: 1, createdAt: "2024-06-02T00:00:00Z")
  let older = try makeIssue(id: "old", number: 2, priority: 1, createdAt: "2024-06-01T00:00:00Z")

  let sorted = CandidateEligibility.sortCandidates([newer, older])
  #expect(sorted[0].id == IssueID("old"), "Same priority → older createdAt should come first")
  #expect(sorted[1].id == IssueID("new"))
}

/// Verifies sort tiebreaker: same priority, same createdAt → identifier lexicographic.
/// Kills RelationalOperatorReplacement on `aPriority != bPriority`.
@Test func sortCandidatesTiebreakByIdentifier() throws {
  let b = try makeIssue(
    id: "b", owner: "org", repo: "repo", number: 2, priority: 1, createdAt: "2024-06-01T00:00:00Z"
  )
  let a = try makeIssue(
    id: "a", owner: "org", repo: "repo", number: 1, priority: 1, createdAt: "2024-06-01T00:00:00Z"
  )

  let sorted = CandidateEligibility.sortCandidates([b, a])
  #expect(
    sorted[0].id == IssueID("a"),
    "Same priority + createdAt → lower identifier should come first"
  )
  #expect(sorted[1].id == IssueID("b"))
}

/// Verifies primary sort: different priorities → lower priority value first.
/// Also exercises the `aPriority != bPriority` guard returning early.
@Test func sortCandidatesPrimaryByPriority() throws {
  let low = try makeIssue(id: "low", number: 1, priority: 3)
  let high = try makeIssue(id: "high", number: 2, priority: 1)

  let sorted = CandidateEligibility.sortCandidates([low, high])
  #expect(sorted[0].id == IssueID("high"))
  #expect(sorted[1].id == IssueID("low"))
}

// MARK: - WorkflowParser.discover Tests

/// Verifies that discover with an explicit readable path returns the actual URL (not nil).
/// Kills SwapTernary on `isReadableFile ? url : nil`.
@Test func discoverExplicitPathReturnsCorrectURL() throws {
  let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: dir) }

  let file = dir.appendingPathComponent("test-workflow.md")
  try "content".write(to: file, atomically: true, encoding: .utf8)

  let result = WorkflowParser.discover(explicitPath: file.path)
  #expect(result == file, "Readable explicit path must return the file URL, not nil")
}

/// Also verify nil is returned for non-readable explicit path (inverse of ternary swap).
@Test func discoverExplicitPathNonReadableReturnsNil() {
  let result = WorkflowParser.discover(
    explicitPath: "/tmp/nonexistent_\(UUID().uuidString)/workflow.md"
  )
  #expect(result == nil, "Non-readable explicit path must return nil, not the URL")
}

// MARK: - Orchestrator enqueueRetry dueAt Calculation

@Test func enqueueRetryWithNonZeroDelayComputesDueAtCorrectly() throws {
  let tracker = StubTracker()
  let delegate = StubOrchestratorDelegate()
  let orchestrator = Orchestrator(
    tracker: tracker, config: .defaults, delegate: delegate)

  let issue = try makeIssue(id: "delay-1", number: 1, state: "In Progress")
  let now = Date(timeIntervalSince1970: 1_000_000)

  let record = orchestrator.enqueueRetry(
    issue: issue, attempt: 2, delayMS: 5000, error: "timeout", now: now)

  // 5000ms = 5.0 seconds
  #expect(record.dueAt.timeIntervalSince1970 == 1_000_005)
}

@Test func enqueueRetryWithSmallDelayConvertsMillisecondsCorrectly() throws {
  let tracker = StubTracker()
  let delegate = StubOrchestratorDelegate()
  let orchestrator = Orchestrator(
    tracker: tracker, config: .defaults, delegate: delegate)

  let issue = try makeIssue(id: "delay-2", number: 2, state: "In Progress")
  let now = Date(timeIntervalSince1970: 0)

  let record = orchestrator.enqueueRetry(
    issue: issue, attempt: 1, delayMS: 1500, error: nil, now: now)

  // 1500ms = 1.5 seconds
  #expect(record.dueAt.timeIntervalSince1970 == 1.5)
}

// MARK: - Helpers
