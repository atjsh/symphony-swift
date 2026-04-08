// Batch 31 — SymphonyServerCore mutation hardening from SymphonyServerTests.
//
// These tests duplicate core Orchestrator/Contracts/Components coverage that
// exists in SymphonyServerCoreTests but is NOT exercised when muter runs with
// `--filter SymphonyServer`. Without them, mutations in SymphonyServerCore
// survive the muter run.
//
// Targets:
//   Orchestrator.swift — reload() body, retryQueue.enqueue(), processRetries loop,
//     markCompleted _retryIssues.removeValue
//   OrchestratorContracts.swift — Reconciler.evaluate guards and return values,
//     CandidateEligibility.isEligible guards, filterEligible, sortCandidates,
//     isBlocked loop body
//   OrchestratorComponents.swift — RetryQueue enqueue/dequeue/dueEntries/removeAll,
//     backoffDelay exponential growth and capping, continuationDelay

import Foundation
import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore
@testable import SymphonyShared

// MARK: - Orchestrator reload

@Suite("Orchestrator Reload Config")
struct OrchestratorReloadConfigTests {

  @Test func reloadUpdatesConfigImmediately() throws {
    let tracker = StubTracker()
    let delegate = StubOrchestratorDelegate()
    let initial = WorkflowConfig(
      tracker: TrackerConfig(activeStates: ["In Progress"], terminalStates: ["Done"])
    )
    let orchestrator = Orchestrator(tracker: tracker, config: initial, delegate: delegate)

    let updated = WorkflowConfig(
      tracker: TrackerConfig(activeStates: ["Queued", "In Progress"], terminalStates: ["Done"])
    )
    orchestrator.reload(tracker: tracker, config: updated)

    #expect(orchestrator.config.tracker.activeStates == ["Queued", "In Progress"])
  }

  @Test func reloadWithNewTrackerAffectsNextTick() async throws {
    let tracker1 = StubTracker()
    let tracker2 = StubTracker()
    let delegate = StubOrchestratorDelegate()
    let orchestrator = Orchestrator(tracker: tracker1, config: .defaults, delegate: delegate)

    let issue = try makeIssue(id: "reload-issue", number: 1)
    tracker2.setAllIssues([issue])

    orchestrator.reload(tracker: tracker2, config: .defaults)
    let result = try await orchestrator.tick()

    #expect(result.candidatesFetched == 1)
    #expect(result.dispatched == 1)
  }
}

// MARK: - Orchestrator enqueueRetry + processRetries

@Suite("Orchestrator Retry Path")
struct OrchestratorRetryPathTests {

  @Test func enqueueRetryAddsRecordToQueue() throws {
    let tracker = StubTracker()
    let delegate = StubOrchestratorDelegate()
    let orchestrator = Orchestrator(tracker: tracker, config: .defaults, delegate: delegate)

    let issue = try makeIssue(id: "retry-q", number: 1)
    let record = orchestrator.enqueueRetry(
      issue: issue, attempt: 1, delayMS: 0, error: "test-error"
    )

    let queued = orchestrator.queuedRetryRecord(issueID: issue.id)
    #expect(queued != nil)
    #expect(queued == record)
  }

  @Test func tickProcessesRetriesAndNotifiesDelegate() async throws {
    let tracker = StubTracker()
    let delegate = StubOrchestratorDelegate()
    let orchestrator = Orchestrator(tracker: tracker, config: .defaults, delegate: delegate)

    let issue = try makeIssue(id: "retry-notify", number: 1)
    let record = orchestrator.enqueueRetry(
      issue: issue, attempt: 2, delayMS: 0, error: "timeout"
    )

    let result = try await orchestrator.tick()
    #expect(result.retriesProcessed == 1)
    #expect(delegate.retried.count == 1)
    #expect(delegate.retried[0].0.id == issue.id)
    #expect(delegate.retried[0].1 == record)
    #expect(orchestrator.queuedRetryRecord(issueID: issue.id) == nil)
  }

  @Test func tickSkipsRetryWithoutCachedIssue() async throws {
    let tracker = StubTracker()
    let delegate = StubOrchestratorDelegate()
    let retryQueue = RetryQueue()
    let orchestrator = Orchestrator(
      tracker: tracker, config: .defaults, retryQueue: retryQueue, delegate: delegate
    )

    // Enqueue directly into the queue without a cached issue
    retryQueue.enqueue(
      RetryRecord(
        issueID: IssueID("orphan"),
        issueIdentifier: try IssueIdentifier(validating: "org/repo#99"),
        attempt: 1,
        dueAt: Date(timeIntervalSinceNow: -1),
        error: nil
      )
    )

    let result = try await orchestrator.tick()
    #expect(result.retriesProcessed == 1)
    #expect(delegate.retried.isEmpty, "No issue snapshot → delegate must NOT be notified")
  }
}

// MARK: - Orchestrator markCompleted clears retry issue cache

@Suite("Orchestrator markCompleted Retry Cleanup")
struct OrchestratorMarkCompletedRetryCleanupTests {

  @Test func markCompletedClearsRetryIssueCache() async throws {
    let tracker = StubTracker()
    let delegate = StubOrchestratorDelegate()
    let orchestrator = Orchestrator(tracker: tracker, config: .defaults, delegate: delegate)

    let issue = try makeIssue(id: "complete-retry", number: 1)
    orchestrator.enqueueRetry(issue: issue, attempt: 1, delayMS: 60_000, error: "slow")

    orchestrator.markCompleted(issueID: issue.id, state: "In Progress")

    // After completion, the retry issue should be cleared from internal cache.
    // A subsequent tick should NOT process the queued retry because the cached
    // issue was removed by markCompleted.
    let result = try await orchestrator.tick()
    #expect(delegate.retried.isEmpty, "Cleared retry cache must prevent delegate notification")
  }
}

// MARK: - Reconciler.evaluate mutations

@Suite("Reconciler.evaluate")
struct ReconcilerEvaluateTests {

  @Test func closedIssueStateReturnsCancelAndCleanup() {
    let config = TrackerConfig(activeStates: ["In Progress"], terminalStates: ["Done"])
    let action = Reconciler.evaluate(issueState: "CLOSED", projectState: "In Progress", config: config)
    #expect(action == .cancelAndCleanup(reason: "Issue closed"))
  }

  @Test func terminalProjectStateReturnsCancelAndCleanup() {
    let config = TrackerConfig(activeStates: ["In Progress"], terminalStates: ["Done"])
    let action = Reconciler.evaluate(issueState: "OPEN", projectState: "Done", config: config)
    #expect(action == .cancelAndCleanup(reason: "Terminal project state: Done"))
  }

  @Test func nonActiveNonTerminalReturnsCancelWithoutCleanup() {
    let config = TrackerConfig(activeStates: ["In Progress"], terminalStates: ["Done"])
    let action = Reconciler.evaluate(issueState: "OPEN", projectState: "Backlog", config: config)
    #expect(action == .cancelWithoutCleanup(reason: "Non-active project state: Backlog"))
  }

  @Test func activeProjectStateReturnsRefreshSnapshot() {
    let config = TrackerConfig(activeStates: ["In Progress"], terminalStates: ["Done"])
    let action = Reconciler.evaluate(issueState: "OPEN", projectState: "In Progress", config: config)
    #expect(action == .refreshSnapshot)
  }

  @Test func closedOverridesTerminalState() {
    let config = TrackerConfig(activeStates: ["In Progress"], terminalStates: ["Done"])
    let action = Reconciler.evaluate(issueState: "CLOSED", projectState: "Done", config: config)
    #expect(action == .cancelAndCleanup(reason: "Issue closed"),
            "CLOSED issueState must take priority over terminal projectState")
  }
}

// MARK: - CandidateEligibility mutations

@Suite("CandidateEligibility")
struct CandidateEligibilityTests {

  private func issueWith(
    id: String, state: String, issueState: String = "OPEN",
    blockedBy: [BlockerReference] = [], priority: Int? = nil, createdAt: String? = nil
  ) throws -> SymphonyShared.Issue {
    SymphonyShared.Issue(
      id: IssueID(id), identifier: try IssueIdentifier(validating: "org/repo#1"),
      repository: "org/repo", number: 1, title: "T", description: nil, priority: priority,
      state: state, issueState: issueState, projectItemID: nil, url: nil, labels: [],
      blockedBy: blockedBy, createdAt: createdAt, updatedAt: nil
    )
  }

  @Test func eligibleIssueIsAccepted() throws {
    let config = TrackerConfig(activeStates: ["Todo", "In Progress"], terminalStates: ["Done"])
    let issue = try issueWith(id: "e1", state: "Todo")
    let result = CandidateEligibility.isEligible(
      issue: issue, config: config, runningIssueIDs: [], claimedIssueIDs: [])
    #expect(result)
  }

  @Test func closedIssueIsNotEligible() throws {
    let config = TrackerConfig(activeStates: ["Todo"], terminalStates: ["Done"])
    let issue = try issueWith(id: "e2", state: "Todo", issueState: "CLOSED")
    let result = CandidateEligibility.isEligible(
      issue: issue, config: config, runningIssueIDs: [], claimedIssueIDs: [])
    #expect(!result)
  }

  @Test func nonActiveStateIsNotEligible() throws {
    let config = TrackerConfig(activeStates: ["In Progress"], terminalStates: ["Done"])
    let issue = try issueWith(id: "e3", state: "Backlog")
    let result = CandidateEligibility.isEligible(
      issue: issue, config: config, runningIssueIDs: [], claimedIssueIDs: [])
    #expect(!result)
  }

  @Test func terminalStateIsNotEligible() throws {
    let config = TrackerConfig(activeStates: ["Done"], terminalStates: ["Done"])
    let issue = try issueWith(id: "e4", state: "Done")
    let result = CandidateEligibility.isEligible(
      issue: issue, config: config, runningIssueIDs: [], claimedIssueIDs: [])
    #expect(!result)
  }

  @Test func runningIssueIsNotEligible() throws {
    let config = TrackerConfig(activeStates: ["Todo"], terminalStates: ["Done"])
    let issue = try issueWith(id: "e5", state: "Todo")
    let result = CandidateEligibility.isEligible(
      issue: issue, config: config, runningIssueIDs: [issue.id], claimedIssueIDs: [])
    #expect(!result)
  }

  @Test func claimedIssueIsNotEligible() throws {
    let config = TrackerConfig(activeStates: ["Todo"], terminalStates: ["Done"])
    let issue = try issueWith(id: "e6", state: "Todo")
    let result = CandidateEligibility.isEligible(
      issue: issue, config: config, runningIssueIDs: [], claimedIssueIDs: [issue.id])
    #expect(!result)
  }

  @Test func blockedByOpenIssueInBlockedStateIsNotEligible() throws {
    let config = TrackerConfig(
      activeStates: ["Todo"], terminalStates: ["Done"], blockedStates: ["Todo"])
    let blocker = BlockerReference(
      issueID: IssueID("blocker"), identifier: try IssueIdentifier(validating: "org/repo#2"),
      state: "Todo", issueState: "OPEN", url: nil)
    let issue = try issueWith(id: "e7", state: "Todo", blockedBy: [blocker])
    let result = CandidateEligibility.isEligible(
      issue: issue, config: config, runningIssueIDs: [], claimedIssueIDs: [])
    #expect(!result)
  }

  @Test func blockedByClosedBlockerIsEligible() throws {
    let config = TrackerConfig(
      activeStates: ["Todo"], terminalStates: ["Done"], blockedStates: ["Todo"])
    let blocker = BlockerReference(
      issueID: IssueID("blocker"), identifier: try IssueIdentifier(validating: "org/repo#2"),
      state: "Todo", issueState: "CLOSED", url: nil)
    let issue = try issueWith(id: "e8", state: "Todo", blockedBy: [blocker])
    let result = CandidateEligibility.isEligible(
      issue: issue, config: config, runningIssueIDs: [], claimedIssueIDs: [])
    #expect(result)
  }

  @Test func blockerInUnconfiguredStateBlocks() throws {
    let config = TrackerConfig(
      activeStates: ["Todo"], terminalStates: ["Done"], blockedStates: ["Blocked"])
    let blocker = BlockerReference(
      issueID: IssueID("blocker"), identifier: try IssueIdentifier(validating: "org/repo#2"),
      state: "Unknown", issueState: "OPEN", url: nil)
    let issue = try issueWith(id: "e9", state: "Todo", blockedBy: [blocker])
    let result = CandidateEligibility.isEligible(
      issue: issue, config: config, runningIssueIDs: [], claimedIssueIDs: [])
    #expect(!result)
  }

  @Test func filterEligibleReturnsMixedResults() throws {
    let config = TrackerConfig(activeStates: ["Todo"], terminalStates: ["Done"])
    let eligible = try issueWith(id: "f1", state: "Todo")
    let ineligible = try issueWith(id: "f2", state: "Backlog")
    let result = CandidateEligibility.filterEligible(
      candidates: [eligible, ineligible], config: config,
      runningIssueIDs: [], claimedIssueIDs: [])
    #expect(result.count == 1)
    #expect(result[0].id == eligible.id)
  }

  @Test func sortCandidatesByPriorityThenCreatedAt() throws {
    let a = try issueWith(id: "s1", state: "Todo", priority: 2, createdAt: "2024-01-01")
    let b = try issueWith(id: "s2", state: "Todo", priority: 1, createdAt: "2024-01-02")
    let c = try issueWith(id: "s3", state: "Todo", priority: nil, createdAt: "2024-01-01")
    let sorted = CandidateEligibility.sortCandidates([a, b, c])
    #expect(sorted[0].id == b.id, "Lower priority number first")
    #expect(sorted[1].id == a.id, "Higher priority number second")
    #expect(sorted[2].id == c.id, "Nil priority last")
  }
}

// MARK: - RetryQueue mutations

@Suite("RetryQueue")
struct RetryQueueTests {

  private func record(id: String, dueAt: Date = Date(timeIntervalSinceNow: -1)) throws -> RetryRecord {
    RetryRecord(
      issueID: IssueID(id),
      issueIdentifier: try IssueIdentifier(validating: "org/repo#1"),
      attempt: 1, dueAt: dueAt, error: String?.none
    )
  }

  @Test func enqueueAndDequeue() throws {
    let queue = RetryQueue()
    let r = try record(id: "rq1")
    queue.enqueue(r)
    #expect(queue.count == 1)
    let dequeued = queue.dequeue(issueID: IssueID("rq1"))
    #expect(dequeued == r)
    #expect(queue.count == 0)
  }

  @Test func dueEntriesFiltersCorrectly() throws {
    let queue = RetryQueue()
    let past = try record(id: "rq2", dueAt: Date(timeIntervalSinceNow: -10))
    let future = try record(id: "rq3", dueAt: Date(timeIntervalSinceNow: 3600))
    queue.enqueue(past)
    queue.enqueue(future)
    let due = queue.dueEntries()
    #expect(due.count == 1)
    #expect(due[0].issueID == IssueID("rq2"))
  }

  @Test func removeAllClearsQueue() throws {
    let queue = RetryQueue()
    queue.enqueue(try record(id: "rq4"))
    queue.enqueue(try record(id: "rq5"))
    queue.removeAll()
    #expect(queue.count == 0)
  }

  @Test func backoffDelayGrowsExponentially() {
    let d1 = RetryQueue.backoffDelay(attempt: 1, maxRetryBackoffMS: 300_000)
    let d2 = RetryQueue.backoffDelay(attempt: 2, maxRetryBackoffMS: 300_000)
    let d3 = RetryQueue.backoffDelay(attempt: 3, maxRetryBackoffMS: 300_000)
    #expect(d1 == 10_000)
    #expect(d2 == 20_000)
    #expect(d3 == 40_000)
  }

  @Test func backoffDelayCapsAtMax() {
    let d = RetryQueue.backoffDelay(attempt: 10, maxRetryBackoffMS: 60_000)
    #expect(d == 60_000)
  }

  @Test func continuationDelayIsOneSecond() {
    #expect(RetryQueue.continuationDelay() == 1_000)
  }
}
