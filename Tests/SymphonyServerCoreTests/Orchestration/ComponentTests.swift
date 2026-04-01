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
