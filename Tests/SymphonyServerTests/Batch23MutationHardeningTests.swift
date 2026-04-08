// Batch 23 — mutation hardening for EngineOrchestratorDelegate constant values
// (success: false in cancel, attempt: 1 in dispatch/cancel).

import Foundation
import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore
@testable import SymphonyShared

// MARK: - EngineOrchestratorDelegate Cancel Completion Values

@Suite("EngineOrchestratorDelegate Cancel Completion")
struct EngineDelegateCancelCompletionTests {

  @Test func cancelReportsSuccessFalse() async throws {
    let observer = CollectingEngineObserver()
    let wsRoot = NSTemporaryDirectory() + "cancel_false_\(UUID().uuidString)"
    let wsManager = WorkspaceManager(root: wsRoot)
    let delegate = EngineOrchestratorDelegate(
      workspaceManager: wsManager, observer: observer)

    await delegate.orchestratorDidCancel(
      issueID: IssueID("I_1"),
      issueIdentifier: try IssueIdentifier(validating: "o/r#1"),
      reason: "closed", cleanup: false)

    let completion = try #require(observer.completions.first)
    #expect(completion.1 == false)
  }

  @Test func cancelContextHasAttemptOne() async throws {
    let observer = CollectingEngineObserver()
    let wsRoot = NSTemporaryDirectory() + "cancel_attempt_\(UUID().uuidString)"
    let wsManager = WorkspaceManager(root: wsRoot)
    let delegate = EngineOrchestratorDelegate(
      workspaceManager: wsManager, observer: observer)

    await delegate.orchestratorDidCancel(
      issueID: IssueID("I_1"),
      issueIdentifier: try IssueIdentifier(validating: "o/r#1"),
      reason: "closed", cleanup: false)

    let context = try #require(observer.completions.first?.0)
    #expect(context.attempt == 1)
  }

  @Test func cancelContextPreservesIssueIdentity() async throws {
    let observer = CollectingEngineObserver()
    let wsRoot = NSTemporaryDirectory() + "cancel_id_\(UUID().uuidString)"
    let wsManager = WorkspaceManager(root: wsRoot)
    let delegate = EngineOrchestratorDelegate(
      workspaceManager: wsManager, observer: observer)

    let expectedID = IssueID("I_42")
    let expectedIdent = try IssueIdentifier(validating: "org/repo#42")

    await delegate.orchestratorDidCancel(
      issueID: expectedID,
      issueIdentifier: expectedIdent,
      reason: "reassigned", cleanup: false)

    let context = try #require(observer.completions.first?.0)
    #expect(context.issueID == expectedID)
    #expect(context.issueIdentifier == expectedIdent)
  }
}

// MARK: - EngineOrchestratorDelegate Dispatch Attempt Value

@Suite("EngineOrchestratorDelegate Dispatch Attempt")
struct EngineDelegateDispatchAttemptTests {

  @Test func dispatchPassesAttemptOneToAgentRunner() async throws {
    let observer = CollectingEngineObserver()
    let wsRoot = NSTemporaryDirectory() + "dispatch_attempt_\(UUID().uuidString)"
    let wsManager = WorkspaceManager(root: wsRoot)

    let stubRunner = StubAgentRunner(finalState: .succeeded)
    let delegate = EngineOrchestratorDelegate(
      workspaceManager: wsManager, observer: observer,
      agentRunner: stubRunner, config: .defaults, promptTemplate: "")
    let orchestrator = Orchestrator(
      tracker: StubTracker(),
      config: .defaults,
      delegate: delegate
    )
    delegate.attach(orchestrator: orchestrator)

    let issue = Issue(
      id: IssueID("I_1"),
      identifier: try IssueIdentifier(validating: "o/r#1"),
      repository: "o/r", number: 1, title: "Test", description: nil,
      priority: nil, state: "In Progress", issueState: "OPEN",
      projectItemID: nil, url: nil, labels: [], blockedBy: [],
      createdAt: nil, updatedAt: nil
    )

    await delegate.orchestratorDidDispatch(issue: issue)

    let dispatchContext = try #require(observer.dispatches.first)
    #expect(dispatchContext.attempt == 1)
  }
}
