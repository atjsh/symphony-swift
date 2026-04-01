import Foundation
import Synchronization
import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore
@testable import SymphonyShared


@Suite("EngineOrchestratorDelegate")
struct EngineOrchestratorDelegateTests {
  @Test func delegateDispatchNotifiesObserver() async throws {
    let observer = CollectingEngineObserver()
    let wsRoot = NSTemporaryDirectory() + "delegate_test_\(UUID().uuidString)"
    let wsManager = WorkspaceManager(root: wsRoot)
    let delegate = EngineOrchestratorDelegate(
      workspaceManager: wsManager, observer: observer)

    let issue = Issue(
      id: IssueID("I_1"),
      identifier: try IssueIdentifier(validating: "o/r#1"),
      repository: "o/r", number: 1, title: "Test", description: nil,
      priority: nil, state: "In Progress", issueState: "OPEN",
      projectItemID: nil, url: nil, labels: [], blockedBy: [],
      createdAt: nil, updatedAt: nil
    )
    await delegate.orchestratorDidDispatch(issue: issue)

    #expect(observer.dispatches.count == 1)
    #expect(observer.dispatches[0].issueID == IssueID("I_1"))
  }

  @Test func delegateCancelWithCleanup() async throws {
    let observer = CollectingEngineObserver()
    let wsRoot = NSTemporaryDirectory() + "delegate_cancel_\(UUID().uuidString)"
    let wsManager = WorkspaceManager(root: wsRoot)
    let delegate = EngineOrchestratorDelegate(
      workspaceManager: wsManager, observer: observer)

    await delegate.orchestratorDidCancel(
      issueID: IssueID("I_1"),
      issueIdentifier: try IssueIdentifier(validating: "o/r#1"),
      reason: "closed", cleanup: true)
    // Should not crash even though workspace doesn't exist
    #expect(observer.completions.count == 1)
  }

  @Test func delegateCancelWithoutCleanup() async throws {
    let observer = CollectingEngineObserver()
    let wsRoot = NSTemporaryDirectory() + "delegate_noclean_\(UUID().uuidString)"
    let wsManager = WorkspaceManager(root: wsRoot)
    let delegate = EngineOrchestratorDelegate(
      workspaceManager: wsManager, observer: observer)

    await delegate.orchestratorDidCancel(
      issueID: IssueID("I_1"),
      issueIdentifier: try IssueIdentifier(validating: "o/r#1"),
      reason: "paused", cleanup: false)
    // No cleanup attempted
    #expect(observer.completions.count == 1)
  }

  @Test func delegateRefreshSnapshotDoesNotEmitFakeDispatch() async throws {
    let observer = CollectingEngineObserver()
    let wsRoot = NSTemporaryDirectory() + "delegate_refresh_\(UUID().uuidString)"
    let wsManager = WorkspaceManager(root: wsRoot)
    let delegate = EngineOrchestratorDelegate(
      workspaceManager: wsManager, observer: observer)

    let issue = Issue(
      id: IssueID("I_1"),
      identifier: try IssueIdentifier(validating: "o/r#1"),
      repository: "o/r",
      number: 1,
      title: "Test",
      description: nil,
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

    await delegate.orchestratorDidRefreshSnapshot(issue: issue)
    #expect(observer.dispatches.isEmpty)
  }

  @Test func delegateSyncIssuesPersistsSnapshotsToStore() async throws {
    let observer = CollectingEngineObserver()
    let wsRoot = NSTemporaryDirectory() + "delegate_sync_\(UUID().uuidString)"
    let wsManager = WorkspaceManager(root: wsRoot)
    let databaseURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      .appendingPathComponent("delegate_sync_\(UUID().uuidString).sqlite3")
    let store = try SQLiteServerStateStore(databaseURL: databaseURL)
    let delegate = EngineOrchestratorDelegate(
      workspaceManager: wsManager,
      observer: observer,
      stateStore: store
    )

    let issue = Issue(
      id: IssueID("I_1"),
      identifier: try IssueIdentifier(validating: "o/r#1"),
      repository: "o/r",
      number: 1,
      title: "Test",
      description: nil,
      priority: nil,
      state: "Backlog",
      issueState: "OPEN",
      projectItemID: nil,
      url: nil,
      labels: [],
      blockedBy: [],
      createdAt: nil,
      updatedAt: "2026-03-27T00:00:00Z"
    )

    await delegate.orchestratorDidSyncIssues([issue])
    let issues = try store.issues()
    #expect(issues.count == 1)
    #expect(issues[0].state == "Backlog")
  }

  @Test func delegateSyncIssuesWithoutStateStoreReturnsEarly() async throws {
    let observer = CollectingEngineObserver()
    let wsRoot = NSTemporaryDirectory() + "delegate_sync_no_store_\(UUID().uuidString)"
    let wsManager = WorkspaceManager(root: wsRoot)
    let delegate = EngineOrchestratorDelegate(
      workspaceManager: wsManager,
      observer: observer
    )

    let issue = Issue(
      id: IssueID("I_NO_STORE"),
      identifier: try IssueIdentifier(validating: "o/r#2"),
      repository: "o/r",
      number: 2,
      title: "No store",
      description: nil,
      priority: nil,
      state: "Backlog",
      issueState: "OPEN",
      projectItemID: nil,
      url: nil,
      labels: [],
      blockedBy: [],
      createdAt: nil,
      updatedAt: nil
    )

    await delegate.orchestratorDidSyncIssues([issue])
    #expect(observer.dispatches.isEmpty)
    #expect(observer.completions.isEmpty)
  }

  @Test func delegateSyncIssuesWithEmptySnapshotsLeavesStoreUnchanged() async throws {
    let observer = CollectingEngineObserver()
    let wsRoot = NSTemporaryDirectory() + "delegate_sync_empty_\(UUID().uuidString)"
    let wsManager = WorkspaceManager(root: wsRoot)
    let databaseURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      .appendingPathComponent("delegate_sync_empty_\(UUID().uuidString).sqlite3")
    let store = try SQLiteServerStateStore(databaseURL: databaseURL)
    let delegate = EngineOrchestratorDelegate(
      workspaceManager: wsManager,
      observer: observer,
      stateStore: store
    )

    await delegate.orchestratorDidSyncIssues([])

    let issues = try store.issues()
    #expect(issues.isEmpty)
    #expect(observer.dispatches.isEmpty)
    #expect(observer.completions.isEmpty)
  }

  @Test func delegateRetryWithAgentRunnerExecutesRecordedAttempt() async throws {
    let observer = CollectingEngineObserver()
    let wsRoot = NSTemporaryDirectory() + "delegate_retry_\(UUID().uuidString)"
    let wsManager = WorkspaceManager(root: wsRoot)
    let stubRunner = StubAgentRunner()
    let delegate = EngineOrchestratorDelegate(
      workspaceManager: wsManager,
      observer: observer,
      agentRunner: stubRunner,
      config: .defaults,
      promptTemplate: "Retry prompt"
    )
    let orchestrator = Orchestrator(
      tracker: StubTracker(),
      config: .defaults,
      delegate: delegate
    )
    delegate.attach(orchestrator: orchestrator)

    let issue = Issue(
      id: IssueID("I_1"),
      identifier: try IssueIdentifier(validating: "o/r#1"),
      repository: "o/r",
      number: 1,
      title: "Retry me",
      description: nil,
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

    let record = RetryRecord(
      issueID: IssueID("I_1"),
      issueIdentifier: try IssueIdentifier(validating: "o/r#1"),
      attempt: 2,
      dueAt: Date(),
      error: "timeout"
    )

    await delegate.orchestratorDidRetry(issue: issue, record: record)
    #expect(observer.dispatches.count == 1)
    #expect(observer.dispatches[0].attempt == 2)
    #expect(observer.completions.count == 1)
    #expect(stubRunner.executeRunCount == 1)
    #expect(stubRunner.lastContext?.attempt == 2)
  }

  @Test func delegateDispatchWithAgentRunnerExecutesRun() async throws {
    let observer = CollectingEngineObserver()
    let wsRoot = NSTemporaryDirectory() + "delegate_runner_\(UUID().uuidString)"
    let wsManager = WorkspaceManager(root: wsRoot)

    let stubRunner = StubAgentRunner()
    let delegate = EngineOrchestratorDelegate(
      workspaceManager: wsManager, observer: observer,
      agentRunner: stubRunner, config: .defaults, promptTemplate: "Test prompt")
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

    // Both dispatch and completion should be observed
    #expect(observer.dispatches.count == 1)
    #expect(observer.completions.count == 1)
    #expect(observer.completions[0].1 == true)

    // AgentRunner should have been called
    #expect(stubRunner.executeRunCount == 1)
    #expect(stubRunner.lastPromptTemplate == "Test prompt")
    #expect(orchestrator.runningIssueIDs.isEmpty)
    #expect(orchestrator.queuedRetryRecord(issueID: issue.id) == nil)
  }

  @Test func delegateDispatchFailureSchedulesRetryOnAttachedOrchestrator() async throws {
    let observer = CollectingEngineObserver()
    let wsRoot = NSTemporaryDirectory() + "delegate_fail_\(UUID().uuidString)"
    let wsManager = WorkspaceManager(root: wsRoot)

    let stubRunner = StubAgentRunner(finalState: .failed)
    let config = WorkflowConfig(agent: AgentConfig(maxRetryBackoffMS: 60_000))
    let delegate = EngineOrchestratorDelegate(
      workspaceManager: wsManager, observer: observer,
      agentRunner: stubRunner, config: config, promptTemplate: "")
    let orchestrator = Orchestrator(
      tracker: StubTracker(),
      config: config,
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

    #expect(observer.completions.count == 1)
    #expect(observer.completions[0].1 == false)
    #expect(orchestrator.runningIssueIDs.isEmpty)
    #expect(orchestrator.claimedIssueIDs.contains(issue.id))

    let retryRecord = try #require(orchestrator.queuedRetryRecord(issueID: issue.id))
    #expect(retryRecord.attempt == 2)
    #expect(retryRecord.error == "stub error")
  }

  @Test func delegateDispatchWithoutAgentRunnerDoesNotComplete() async throws {
    let observer = CollectingEngineObserver()
    let wsRoot = NSTemporaryDirectory() + "delegate_norunner_\(UUID().uuidString)"
    let wsManager = WorkspaceManager(root: wsRoot)

    // No agent runner provided
    let delegate = EngineOrchestratorDelegate(
      workspaceManager: wsManager, observer: observer)

    let issue = Issue(
      id: IssueID("I_1"),
      identifier: try IssueIdentifier(validating: "o/r#1"),
      repository: "o/r", number: 1, title: "Test", description: nil,
      priority: nil, state: "In Progress", issueState: "OPEN",
      projectItemID: nil, url: nil, labels: [], blockedBy: [],
      createdAt: nil, updatedAt: nil
    )

    await delegate.orchestratorDidDispatch(issue: issue)

    // Dispatch event should fire but no completion (no runner)
    #expect(observer.dispatches.count == 1)
    #expect(observer.completions.isEmpty)
  }
}

// MARK: - Stub Agent Runner for Engine Tests

final class StubAgentRunner: AgentRunning, @unchecked Sendable {
  private let lock = NSLock()
  private var _executeRunCount = 0
  private var _lastContext: RunContext?
  private var _lastConfig: WorkflowConfig?
  private var _lastPromptTemplate: String?
  private let finalState: RunLifecycleState

  init(finalState: RunLifecycleState = .succeeded) {
    self.finalState = finalState
  }

  var executeRunCount: Int {
    lock.withLock { _executeRunCount }
  }

  var lastContext: RunContext? {
    lock.withLock { _lastContext }
  }

  var lastConfig: WorkflowConfig? {
    lock.withLock { _lastConfig }
  }

  var lastPromptTemplate: String? {
    lock.withLock { _lastPromptTemplate }
  }

  func executeRun(
    context: RunContext, issue: SymphonyShared.Issue, config: WorkflowConfig,
    promptTemplate: String
  ) async -> AgentRunResult {
    lock.withLock {
      _executeRunCount += 1
      _lastContext = context
      _lastConfig = config
      _lastPromptTemplate = promptTemplate
    }
    return AgentRunResult(
      context: context, sessionID: SessionID("stub_session"),
      finalState: finalState, eventCount: 0, error: finalState == .failed ? "stub error" : nil)
  }

  func cancelRun(runID: RunID) async throws {}
}
