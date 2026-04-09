// Batch 43 – Mutation hardening for Orchestrator reconciliation with
// uncached issues and SQLiteAgentRunEventSink completion/restart guards.
//
// Targets:
//   Orchestrator.swift – evaluateReconciliation guard-let-cachedIssue
//     else { continue } for cancelAndCleanup, cancelWithoutCleanup,
//     and refreshSnapshot actions when markRunning(issueID:state:)
//     was used instead of markRunning(issue:).
//   SQLiteAgentRunEventSink.swift – persistCompletion guard when
//     runDidComplete arrives without prior runDidStart, and double
//     runDidStart preserving existing eventCount/providerSnapshot.

import Foundation
import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore
@testable import SymphonyShared

// MARK: - Orchestrator Reconciliation with Uncached Issues

@Suite("Orchestrator Reconciliation Uncached Issues")
struct OrchestratorReconciliationUncachedTests {

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

  @Test func cancelAndCleanupSkippedWhenIssueNotCached() async throws {
    let tracker = StubTracker()
    let delegate = StubOrchestratorDelegate()
    let config = WorkflowConfig(
      tracker: TrackerConfig(activeStates: ["In Progress"], terminalStates: ["Done"])
    )
    let orchestrator = Orchestrator(tracker: tracker, config: config, delegate: delegate)

    // Use markRunning(issueID:state:) — does NOT cache the issue.
    orchestrator.markRunning(issueID: IssueID("uncached-term"), state: "In Progress")

    // Tracker returns the issue in a terminal state → Reconciler → .cancelAndCleanup
    let terminalIssue = try issueWith(id: "uncached-term", state: "Done")
    tracker.setAllIssues([terminalIssue])

    let result = try await orchestrator.tick()
    #expect(result.reconciled == 1)
    // guard let cachedIssue else { continue } skips the delegate call
    #expect(delegate.canceled.isEmpty, "Cancel must be skipped when cachedIssue is nil")
    // Issue stays in running set because markCompleted was not called
    #expect(orchestrator.runningIssueIDs.contains(IssueID("uncached-term")))
  }

  @Test func cancelWithoutCleanupSkippedWhenIssueNotCached() async throws {
    let tracker = StubTracker()
    let delegate = StubOrchestratorDelegate()
    let config = WorkflowConfig(
      tracker: TrackerConfig(activeStates: ["In Progress"], terminalStates: ["Done"])
    )
    let orchestrator = Orchestrator(tracker: tracker, config: config, delegate: delegate)

    orchestrator.markRunning(issueID: IssueID("uncached-backlog"), state: "In Progress")

    // Non-active, non-terminal state → Reconciler → .cancelWithoutCleanup
    let backlogIssue = try issueWith(id: "uncached-backlog", state: "Backlog")
    tracker.setAllIssues([backlogIssue])

    let result = try await orchestrator.tick()
    #expect(result.reconciled == 1)
    #expect(delegate.canceled.isEmpty, "Cancel must be skipped when cachedIssue is nil")
    #expect(orchestrator.runningIssueIDs.contains(IssueID("uncached-backlog")))
  }

  @Test func refreshSnapshotSkippedWhenIssueNotCached() async throws {
    let tracker = StubTracker()
    let delegate = StubOrchestratorDelegate()
    let config = WorkflowConfig(
      tracker: TrackerConfig(activeStates: ["In Progress"], terminalStates: ["Done"])
    )
    let orchestrator = Orchestrator(tracker: tracker, config: config, delegate: delegate)

    orchestrator.markRunning(issueID: IssueID("uncached-active"), state: "In Progress")

    // Active state → Reconciler → .refreshSnapshot
    let activeIssue = try issueWith(id: "uncached-active", state: "In Progress")
    tracker.setAllIssues([activeIssue])

    let result = try await orchestrator.tick()
    #expect(result.reconciled == 1)
    #expect(delegate.refreshed.isEmpty, "Refresh must be skipped when cachedIssue is nil")
    #expect(orchestrator.runningIssueIDs.contains(IssueID("uncached-active")))
  }

  @Test func missingIssueInSnapshotSkippedWhenIssueNotCached() async throws {
    let tracker = StubTracker()
    let delegate = StubOrchestratorDelegate()
    let orchestrator = Orchestrator(tracker: tracker, config: .defaults, delegate: delegate)

    orchestrator.markRunning(issueID: IssueID("uncached-missing"), state: "In Progress")

    // Issue not in snapshot at all → first guard let cachedIssue else { continue }
    tracker.setAllIssues([])

    let result = try await orchestrator.tick()
    #expect(result.reconciled == 1)
    #expect(delegate.canceled.isEmpty, "Cancel must be skipped when cachedIssue is nil")
    #expect(orchestrator.runningIssueIDs.contains(IssueID("uncached-missing")))
  }
}

// MARK: - SQLiteAgentRunEventSink Completion Without Start

@Suite("EventSink Completion Without Start")
struct EventSinkCompletionWithoutStartTests {

  @Test func runDidCompleteWithoutPriorStartIsNoOp() throws {
    let dir = try makeAgentRunSinkTemporaryDirectory()
    let store = try SQLiteServerStateStore(
      databaseURL: dir.appendingPathComponent("no-start.sqlite3"))
    let sink = SQLiteAgentRunEventSink(store: store)

    let context = try makeAgentRunSinkContext(runID: "orphan-complete")
    let result = AgentRunResult(
      context: context,
      sessionID: SessionID("orphan-session"),
      finalState: .succeeded,
      eventCount: 0,
      error: nil
    )

    // guard let startInfo = startInfo(for:) else { return } — early return
    sink.runDidComplete(result)

    // No run detail should have been created
    let runDetail = try store.runDetail(id: context.runID)
    #expect(runDetail == nil, "Completion without start must not create a run detail")
  }
}

// MARK: - SQLiteAgentRunEventSink Double Start

@Suite("EventSink Double Start Preserves State")
struct EventSinkDoubleStartTests {

  @Test func doubleStartPreservesEventCountAndProviderSnapshot() throws {
    let dir = try makeAgentRunSinkTemporaryDirectory()
    let store = try SQLiteServerStateStore(
      databaseURL: dir.appendingPathComponent("double-start.sqlite3"))
    let sink = SQLiteAgentRunEventSink(store: store)

    let issue = try makeAgentRunSinkIssue(id: "I_double", number: 42)
    let context = try makeAgentRunSinkContext(
      issueID: IssueID("I_double"), number: 42, runID: "R_double")
    let startInfo = AgentRunStartInfo(
      context: context,
      issue: issue,
      provider: "codex",
      sessionID: SessionID("s-double"),
      workspacePath: "/tmp/ws"
    )

    // First start — initializes eventCount and providerSnapshot
    sink.runDidStart(startInfo)

    // Fire an event to increment eventCount
    sink.runDidTransition(context, to: .streamingTurn)
    sink.runDidReceiveEvent(AgentRawEvent(
      sessionID: startInfo.sessionID,
      provider: "codex",
      sequence: EventSequence(0),
      timestamp: "2026-06-01T00:00:01Z",
      rawJSON: #"{"type":"message"}"#,
      providerEventType: "message",
      normalizedEventKind: "message"
    ))

    let snapshotBefore = sink.testingSnapshot(for: context.runID)
    #expect(snapshotBefore.count == 1)

    // Second start — should NOT reset eventCount or providerSnapshot
    sink.runDidStart(startInfo)

    let snapshotAfter = sink.testingSnapshot(for: context.runID)
    #expect(snapshotAfter.count == 1, "Double start must preserve existing event count")
  }
}
