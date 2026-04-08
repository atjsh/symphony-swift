import Foundation
import SymphonyShared
import Testing

@testable import SymphonyServerCore

// MARK: - RetryQueue Boundary Tests

@Test func retryQueueDueEntryAtExactlyNow() throws {
  let queue = RetryQueue()
  let now = Date()
  queue.enqueue(
    RetryRecord(
      issueID: IssueID("exact"),
      issueIdentifier: try IssueIdentifier(validating: "org/repo#1"),
      attempt: 1,
      dueAt: now,
      error: nil
    ))

  // dueAt <= now: entry with dueAt exactly equal to now must be returned
  let due = queue.dueEntries(asOf: now)
  #expect(due.count == 1, "Entry with dueAt==now must be due (tests <= vs <)")
  #expect(due[0].issueID == IssueID("exact"))
}

@Test func retryQueueDueEntryJustAfterNow() throws {
  let queue = RetryQueue()
  let now = Date()
  // 1ms in the future
  let future = now.addingTimeInterval(0.001)
  queue.enqueue(
    RetryRecord(
      issueID: IssueID("future"),
      issueIdentifier: try IssueIdentifier(validating: "org/repo#1"),
      attempt: 1,
      dueAt: future,
      error: nil
    ))

  let due = queue.dueEntries(asOf: now)
  #expect(due.isEmpty, "Entry with dueAt just after now must not be due")
}

@Test func retryQueueEnqueueOverwritesSameIssue() throws {
  let queue = RetryQueue()
  let id = IssueID("overwrite")
  let ident = try IssueIdentifier(validating: "org/repo#1")

  queue.enqueue(RetryRecord(issueID: id, issueIdentifier: ident, attempt: 1, dueAt: Date(), error: "first"))
  queue.enqueue(RetryRecord(issueID: id, issueIdentifier: ident, attempt: 2, dueAt: Date(), error: "second"))

  #expect(queue.count == 1, "Enqueue with same issueID must overwrite")
  let entry = queue.entries[id]
  #expect(entry?.attempt == 2, "Latest enqueue must win")
}

// MARK: - StallDetector Boundary Tests

@Test func stallDetectorExactlyAtThreshold() {
  let detector = StallDetector(stallTimeoutMS: 5_000)
  let now = Date()
  // elapsed == stallTimeoutMS: should be stalled (tests >= vs >)
  let exactThreshold = now.addingTimeInterval(-5.0)
  #expect(
    detector.isStalled(lastEventAt: exactThreshold, now: now),
    "Exactly at threshold must be stalled (tests >= boundary)"
  )
}

@Test func stallDetectorJustBeforeThreshold() {
  let detector = StallDetector(stallTimeoutMS: 5_000)
  let now = Date()
  // 1ms before threshold: should NOT be stalled
  let justBefore = now.addingTimeInterval(-4.999)
  #expect(
    !detector.isStalled(lastEventAt: justBefore, now: now),
    "Just before threshold must not be stalled"
  )
}

// MARK: - ConcurrencySlotManager Boundary Tests

@Test func canDispatchGlobalSlotsAvailableButStateBlocked() {
  let config = AgentConfig(
    maxConcurrentAgents: 10,
    maxConcurrentAgentsByState: ["Todo": 1]
  )
  let manager = ConcurrencySlotManager(config: config)
  #expect(
    !manager.canDispatch(currentRunning: 0, state: "Todo", currentInState: 1),
    "Must be false when state slots exhausted even if global slots available (tests && vs ||)"
  )
}

@Test func canDispatchStateSlotsAvailableButGlobalBlocked() {
  let config = AgentConfig(
    maxConcurrentAgents: 1,
    maxConcurrentAgentsByState: ["Todo": 10]
  )
  let manager = ConcurrencySlotManager(config: config)
  #expect(
    !manager.canDispatch(currentRunning: 1, state: "Todo", currentInState: 0),
    "Must be false when global slots exhausted even if state slots available (tests && vs ||)"
  )
}

@Test func canDispatchBothAtExactLimit() {
  let config = AgentConfig(
    maxConcurrentAgents: 2,
    maxConcurrentAgentsByState: ["Todo": 1]
  )
  let manager = ConcurrencySlotManager(config: config)
  #expect(
    !manager.canDispatch(currentRunning: 2, state: "Todo", currentInState: 1),
    "Both at limit must block (tests > 0 boundary)"
  )
}

@Test func canDispatchBothJustBelowLimit() {
  let config = AgentConfig(
    maxConcurrentAgents: 2,
    maxConcurrentAgentsByState: ["Todo": 2]
  )
  let manager = ConcurrencySlotManager(config: config)
  #expect(
    manager.canDispatch(currentRunning: 1, state: "Todo", currentInState: 1),
    "Both below limit must allow dispatch"
  )
}

// MARK: - Reconciler Boundary Tests

@Test func reconcilerSequentialPrecedence() throws {
  // An active state that is ALSO terminal should be treated as terminal (cleanup)
  let config = TrackerConfig(activeStates: ["Done"], terminalStates: ["Done"])
  let action = Reconciler.evaluate(issueState: "OPEN", projectState: "Done", config: config)
  #expect(
    action == .cancelAndCleanup(reason: "Terminal project state: Done"),
    "Terminal check must precede active check"
  )
}

@Test func reconcilerClosedOverridesTerminal() throws {
  // Even if project state is terminal, CLOSED takes precedence
  let action = Reconciler.evaluate(issueState: "CLOSED", projectState: "Done", config: .defaults)
  #expect(
    action == .cancelAndCleanup(reason: "Issue closed"),
    "CLOSED must override terminal state check"
  )
}

// MARK: - Backoff Delay Boundary Tests

@Test func backoffDelayAttemptOneIsBase() {
  let delay = RetryQueue.backoffDelay(attempt: 1, maxRetryBackoffMS: 1_000_000)
  #expect(delay == 10_000, "Attempt 1 must return base delay (10s)")
}

@Test func backoffDelayClampedAtMax() {
  // attempt=6 → base * 2^5 = 10000 * 32 = 320000 → clamped to 50000
  let delay = RetryQueue.backoffDelay(attempt: 6, maxRetryBackoffMS: 50_000)
  #expect(delay == 50_000, "Must be clamped to max")
}

// MARK: - Helpers
