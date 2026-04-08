// Batch 32 — Orchestrator reconciliation mutation hardening from SymphonyServerTests.
//
// These tests cover reconciliation paths in Orchestrator.tick() that are only
// exercised by SymphonyServerCoreTests. Without them, reconciliation mutations
// survive the `--filter SymphonyServer` muter run.
//
// Targets:
//   Orchestrator.swift — reconcile() guard removal, cancelAndCleanup delegate call,
//     cancelWithoutCleanup delegate call, refreshSnapshot delegate call,
//     missing-issue-in-snapshot cancel path, dispatch markClaimed + delegate call,
//     tick() error path early return, synced delegate call

import Foundation
import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore
@testable import SymphonyShared

// MARK: - Orchestrator Reconciliation

@Suite("Orchestrator Reconciliation")
struct OrchestratorReconciliationTests {

  private func issueWith(
    id: String, state: String, issueState: String = "OPEN"
  ) throws -> SymphonyShared.Issue {
    SymphonyShared.Issue(
      id: IssueID(id), identifier: try IssueIdentifier(validating: "org/repo#1"),
      repository: "org/repo", number: 1, title: "T", description: nil, priority: nil,
      state: state, issueState: issueState, projectItemID: nil, url: nil, labels: [],
      blockedBy: [], createdAt: nil, updatedAt: nil
    )
  }

  @Test func tickWithNoRunningIssuesSkipsReconciliation() async throws {
    let tracker = StubTracker()
    let delegate = StubOrchestratorDelegate()
    let orchestrator = Orchestrator(tracker: tracker, config: .defaults, delegate: delegate)

    let issue = try issueWith(id: "no-recon", state: "Todo")
    tracker.setAllIssues([issue])

    let result = try await orchestrator.tick()
    #expect(result.reconciled == 0, "No running issues means reconcile returns 0")
  }

  @Test func tickReconcilesCancelAndCleanupForTerminalIssue() async throws {
    let tracker = StubTracker()
    let delegate = StubOrchestratorDelegate()
    let config = WorkflowConfig(
      tracker: TrackerConfig(activeStates: ["In Progress"], terminalStates: ["Done"])
    )
    let orchestrator = Orchestrator(tracker: tracker, config: config, delegate: delegate)

    // Mark an issue as running with a cached snapshot
    let issue = try issueWith(id: "term-recon", state: "In Progress")
    orchestrator.markRunning(issue: issue)

    // Tracker now returns the issue in terminal state
    let terminalIssue = try issueWith(id: "term-recon", state: "Done")
    tracker.setAllIssues([terminalIssue])

    let result = try await orchestrator.tick()
    #expect(result.reconciled == 1)
    #expect(delegate.canceled.count == 1)
    #expect(delegate.canceled[0].3 == true, "Terminal state must trigger cleanup: true")
  }

  @Test func tickReconcilesCancelWithoutCleanupForNonActiveIssue() async throws {
    let tracker = StubTracker()
    let delegate = StubOrchestratorDelegate()
    let config = WorkflowConfig(
      tracker: TrackerConfig(activeStates: ["In Progress"], terminalStates: ["Done"])
    )
    let orchestrator = Orchestrator(tracker: tracker, config: config, delegate: delegate)

    let issue = try issueWith(id: "noactive-recon", state: "In Progress")
    orchestrator.markRunning(issue: issue)

    // Tracker returns issue in a non-active, non-terminal state
    let backlogIssue = try issueWith(id: "noactive-recon", state: "Backlog")
    tracker.setAllIssues([backlogIssue])

    let result = try await orchestrator.tick()
    #expect(result.reconciled == 1)
    #expect(delegate.canceled.count == 1)
    #expect(delegate.canceled[0].3 == false, "Non-active state must trigger cleanup: false")
  }

  @Test func tickReconcileRefreshesSnapshotForActiveIssue() async throws {
    let tracker = StubTracker()
    let delegate = StubOrchestratorDelegate()
    let config = WorkflowConfig(
      tracker: TrackerConfig(activeStates: ["In Progress"], terminalStates: ["Done"])
    )
    let orchestrator = Orchestrator(tracker: tracker, config: config, delegate: delegate)

    let issue = try issueWith(id: "refresh-recon", state: "In Progress")
    orchestrator.markRunning(issue: issue)

    // Tracker returns same issue still in active state
    tracker.setAllIssues([issue])

    let result = try await orchestrator.tick()
    #expect(result.reconciled == 1)
    #expect(delegate.refreshed.count == 1)
    #expect(delegate.refreshed[0].id == issue.id)
  }

  @Test func tickReconcilesMissingIssueAsCancelWithoutCleanup() async throws {
    let tracker = StubTracker()
    let delegate = StubOrchestratorDelegate()
    let orchestrator = Orchestrator(tracker: tracker, config: .defaults, delegate: delegate)

    let issue = try issueWith(id: "missing-recon", state: "In Progress")
    orchestrator.markRunning(issue: issue)

    // Tracker returns empty — issue is missing from snapshot
    tracker.setAllIssues([])

    let result = try await orchestrator.tick()
    #expect(result.reconciled == 1)
    #expect(delegate.canceled.count == 1)
    #expect(delegate.canceled[0].3 == false, "Missing issue uses cleanup: false")
    #expect(delegate.canceled[0].2.contains("no longer present"))
  }

  @Test func tickReconcileClosedIssueOverridesProjectState() async throws {
    let tracker = StubTracker()
    let delegate = StubOrchestratorDelegate()
    let config = WorkflowConfig(
      tracker: TrackerConfig(activeStates: ["In Progress"], terminalStates: ["Done"])
    )
    let orchestrator = Orchestrator(tracker: tracker, config: config, delegate: delegate)

    let issue = try issueWith(id: "closed-recon", state: "In Progress")
    orchestrator.markRunning(issue: issue)

    // Tracker returns issue that is CLOSED but still in active project state
    let closedIssue = try issueWith(id: "closed-recon", state: "In Progress", issueState: "CLOSED")
    tracker.setAllIssues([closedIssue])

    let result = try await orchestrator.tick()
    #expect(delegate.canceled.count == 1)
    #expect(delegate.canceled[0].3 == true, "CLOSED issueState triggers cleanup: true")
  }
}

// MARK: - Orchestrator Tick Dispatch

@Suite("Orchestrator Tick Dispatch")
struct OrchestratorTickDispatchTests {

  @Test func tickDispatchesCandidateAndMarksClaimed() async throws {
    let tracker = StubTracker()
    let delegate = StubOrchestratorDelegate()
    let orchestrator = Orchestrator(tracker: tracker, config: .defaults, delegate: delegate)

    let issue = try makeIssue(id: "dispatch-1", number: 1)
    tracker.setAllIssues([issue])

    let result = try await orchestrator.tick()
    #expect(result.dispatched == 1)
    #expect(delegate.dispatched.count == 1)
    #expect(delegate.dispatched[0].id == issue.id)
    #expect(orchestrator.claimedIssueIDs.contains(issue.id))
  }

  @Test func tickSyncsIssuesViaDelegate() async throws {
    let tracker = StubTracker()
    let delegate = StubOrchestratorDelegate()
    let orchestrator = Orchestrator(tracker: tracker, config: .defaults, delegate: delegate)

    let issue = try makeIssue(id: "sync-1", number: 1)
    tracker.setAllIssues([issue])

    _ = try await orchestrator.tick()
    #expect(delegate.synced.count == 1)
    #expect(delegate.synced[0].id == issue.id)
  }

  @Test func tickWithFetchErrorReturnsEarlyResult() async throws {
    let tracker = StubTracker()
    let delegate = StubOrchestratorDelegate()
    let orchestrator = Orchestrator(tracker: tracker, config: .defaults, delegate: delegate)

    struct FetchFailed: Error {}
    tracker.setFetchError(FetchFailed())

    let result = try await orchestrator.tick()
    #expect(result.candidatesFetched == 0)
    #expect(result.dispatched == 0)
    #expect(result.reconciled == 0)
    #expect(delegate.synced.isEmpty, "No sync when fetch fails")
  }
}

// MARK: - ConcurrencySlotManager

@Suite("ConcurrencySlotManager")
struct ConcurrencySlotManagerTests {

  @Test func canDispatchRespectsGlobalLimit() {
    let config = AgentConfig(maxConcurrentAgents: 2)
    let manager = ConcurrencySlotManager(config: config)

    #expect(manager.canDispatch(currentRunning: 0, state: "Todo", currentInState: 0))
    #expect(manager.canDispatch(currentRunning: 1, state: "Todo", currentInState: 0))
    #expect(!manager.canDispatch(currentRunning: 2, state: "Todo", currentInState: 0))
  }
}
