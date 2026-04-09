// Batch40MutationHardeningTests.swift
// -----------------------------------------------------------------
// Mutation targets:
//
// Orchestrator.swift — evaluateReconciliation uncached-issue guard branches:
//   Three separate `guard let cachedIssue else { continue }` / `guard cachedIssue != nil`
//   in the reconciliation loop — one per action type (cancelAndCleanup,
//   cancelWithoutCleanup, refreshSnapshot). When an issue is marked running
//   via markRunning(issueID:state:) (without caching the Issue), the
//   reconciliation must skip the delegate call for each action type.
//   Existing tests only cover the "issue not in snapshot" guard, not these three.
//
// -----------------------------------------------------------------

import Foundation
import SymphonyShared
import Testing

@testable import SymphonyServerCore

private func makeIssue(
  id: String = "issue-1",
  owner: String = "org",
  repo: String = "repo",
  number: Int = 1,
  state: String = "In Progress",
  issueState: String = "OPEN"
) throws -> SymphonyShared.Issue {
  SymphonyShared.Issue(
    id: IssueID(id),
    identifier: try IssueIdentifier(validating: "\(owner)/\(repo)#\(number)"),
    repository: "\(owner)/\(repo)",
    number: number,
    title: "Issue \(number)",
    description: nil,
    priority: nil,
    state: state,
    issueState: issueState,
    projectItemID: nil,
    url: nil,
    labels: [],
    blockedBy: [],
    createdAt: nil,
    updatedAt: nil
  )
}

// MARK: - Reconciliation Uncached Issue Guard Tests

@Suite("Reconciliation uncached-issue guard branches")
struct ReconciliationUncachedIssueGuardTests {

  /// When a running issue has no cached Issue and the latest snapshot shows it
  /// CLOSED (→ cancelAndCleanup), the guard must skip the delegate cancel.
  /// Kills mutant that removes `guard let cachedIssue else { continue }` in the
  /// cancelAndCleanup branch of evaluateReconciliation.
  @Test func uncachedIssueCancelAndCleanupSkipsDelegate() async throws {
    let tracker = StubTracker()
    let delegate = StubOrchestratorDelegate()
    let orchestrator = Orchestrator(tracker: tracker, config: .defaults, delegate: delegate)

    // markRunning with id-only (no Issue cache)
    orchestrator.markRunning(issueID: IssueID("r1"), state: "In Progress")

    // Provide the issue in the snapshot with CLOSED state → triggers cancelAndCleanup
    tracker.setAllIssues([
      try makeIssue(id: "r1", number: 1, issueState: "CLOSED"),
    ])

    let result = try await orchestrator.tick()
    #expect(result.reconciled == 1)
    #expect(
      delegate.canceled.isEmpty,
      "cancelAndCleanup guard must skip when cachedIssue is nil"
    )
  }

  /// When a running issue has no cached Issue and the latest snapshot shows a
  /// non-active, non-terminal state (→ cancelWithoutCleanup), the guard must skip.
  /// Kills mutant that removes `guard let cachedIssue else { continue }` in the
  /// cancelWithoutCleanup branch of evaluateReconciliation.
  @Test func uncachedIssueCancelWithoutCleanupSkipsDelegate() async throws {
    let tracker = StubTracker()
    let delegate = StubOrchestratorDelegate()
    let orchestrator = Orchestrator(tracker: tracker, config: .defaults, delegate: delegate)

    orchestrator.markRunning(issueID: IssueID("r2"), state: "In Progress")

    // "Review" is not in activeStates ["Todo", "In Progress"] nor terminalStates ["Done"]
    tracker.setAllIssues([
      try makeIssue(id: "r2", number: 2, state: "Review", issueState: "OPEN"),
    ])

    let result = try await orchestrator.tick()
    #expect(result.reconciled == 1)
    #expect(
      delegate.canceled.isEmpty,
      "cancelWithoutCleanup guard must skip when cachedIssue is nil"
    )
  }

  /// When a running issue has no cached Issue and the latest snapshot shows an
  /// active state (→ refreshSnapshot), the guard must skip.
  /// Kills mutant that removes `guard cachedIssue != nil else { continue }` in the
  /// refreshSnapshot branch of evaluateReconciliation.
  @Test func uncachedIssueRefreshSnapshotSkipsDelegate() async throws {
    let tracker = StubTracker()
    let delegate = StubOrchestratorDelegate()
    let orchestrator = Orchestrator(tracker: tracker, config: .defaults, delegate: delegate)

    orchestrator.markRunning(issueID: IssueID("r3"), state: "In Progress")

    // "In Progress" is an activeState → triggers refreshSnapshot
    tracker.setAllIssues([
      try makeIssue(id: "r3", number: 3, state: "In Progress", issueState: "OPEN"),
    ])

    let result = try await orchestrator.tick()
    #expect(result.reconciled == 1)
    #expect(
      delegate.refreshed.isEmpty,
      "refreshSnapshot guard must skip when cachedIssue is nil"
    )
  }
}
