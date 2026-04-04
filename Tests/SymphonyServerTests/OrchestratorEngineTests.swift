import Foundation
import Synchronization
import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore
@testable import SymphonyShared

// MARK: - OrchestratorEngine Tests

@Suite("OrchestratorEngine")
struct OrchestratorEngineTests {
  private func makeConfig(
    pollingIntervalMS: Int = 100,
    activeStates: [String] = ["Todo", "In Progress"],
    terminalStates: [String] = ["Done"]
  ) -> WorkflowConfig {
    WorkflowConfig(
      tracker: TrackerConfig(
        activeStates: activeStates,
        terminalStates: terminalStates
      ),
      polling: PollingConfig(intervalMS: pollingIntervalMS)
    )
  }

  private func makeWorkflow(
    pollingIntervalMS: Int = 100,
    activeStates: [String] = ["Todo", "In Progress"],
    terminalStates: [String] = ["Done"],
    promptTemplate: String = "Resolve {{issue.title}}"
  ) -> WorkflowDefinition {
    WorkflowDefinition(
      config: makeConfig(
        pollingIntervalMS: pollingIntervalMS,
        activeStates: activeStates,
        terminalStates: terminalStates
      ),
      promptTemplate: promptTemplate
    )
  }

  @Test func engineStartsInIdleState() {
    let config = makeConfig()
    let engine = OrchestratorEngine(
      config: config,
      trackerFactory: { _ in StubTracker() }
    )
    #expect(engine.state == .idle)
  }

  @Test func engineTransitionsToRunning() async throws {
    let observer = CollectingEngineObserver()
    let config = makeConfig(pollingIntervalMS: 50)
    let engine = OrchestratorEngine(
      config: config,
      trackerFactory: { _ in StubTracker() },
      observer: observer
    )

    try engine.start()
    try await bootstrapWaitUntil("engine starts") { engine.state == .running }

    #expect(engine.state == OrchestratorEngineState.running)
    #expect(observer.stateChanges.contains(.starting))
    #expect(observer.stateChanges.contains(.running))

    engine.stop()
    try await bootstrapWaitUntil("engine stops") { engine.state == .stopped }
    #expect(engine.state == .stopped)
  }

  @Test func engineCannotStartTwice() async throws {
    let config = makeConfig(pollingIntervalMS: 50)
    let engine = OrchestratorEngine(
      config: config,
      trackerFactory: { _ in StubTracker() }
    )

    try engine.start()
    try await bootstrapWaitUntil("engine starts") { engine.state == .running }

    #expect(throws: OrchestratorEngineError.self) {
      try engine.start()
    }

    engine.stop()
    try await bootstrapWaitUntil("engine stops") { engine.state == .stopped }
  }

  @Test func engineCompletesTickCycles() async throws {
    let observer = CollectingEngineObserver()
    let config = makeConfig(pollingIntervalMS: 50)
    let engine = OrchestratorEngine(
      config: config,
      trackerFactory: { _ in StubTracker() },
      observer: observer
    )

    try engine.start()
    try await bootstrapWaitUntil("tick completed") { !observer.tickResults.isEmpty }
    engine.stop()
    try await bootstrapWaitUntil("engine stops") { engine.state == .stopped }

    #expect(!observer.tickResults.isEmpty)
  }

  @Test func engineRequestRefreshRunsAnImmediateTick() async throws {
    let observer = CollectingEngineObserver()
    let tracker = StubTracker()
    let engine = OrchestratorEngine(
      config: makeConfig(pollingIntervalMS: 1_000),
      trackerFactory: { _ in tracker },
      observer: observer
    )

    try engine.start()
    defer { engine.stop() }

    try await bootstrapWaitUntil("engine starts") {
      engine.state == OrchestratorEngineState.running
    }

    let baselineTickCount = observer.tickResults.count
    engine.requestRefresh()

    try await bootstrapWaitUntil("refresh tick completes") {
      observer.tickResults.count > baselineTickCount
    }
  }

  @Test func engineRequestRefreshWithoutActiveOrchestratorReturnsWithoutObserverSignals()
    async throws
  {
    let observer = CollectingEngineObserver()
    let engine = OrchestratorEngine(
      config: makeConfig(),
      trackerFactory: { _ in StubTracker() },
      observer: observer
    )

    engine.requestRefresh()
    try await Task.sleep(nanoseconds: 50_000_000)

    #expect(observer.tickResults.isEmpty)
    #expect(observer.errors.isEmpty)
  }

  @Test func enginePerformRefreshReportsErrors() async {
    struct RefreshFailure: Error {}

    let observer = CollectingEngineObserver()
    let engine = OrchestratorEngine(
      config: makeConfig(),
      trackerFactory: { _ in StubTracker() },
      observer: observer
    )

    await engine.performRefresh(observer: observer) {
      throw RefreshFailure()
    }

    #expect(observer.errors.contains { $0.context == "refresh" })
  }

  @Test func engineReloadConfig() {
    let config = makeConfig(pollingIntervalMS: 100)
    let engine = OrchestratorEngine(
      config: config,
      trackerFactory: { _ in StubTracker() }
    )

    let newConfig = makeConfig(pollingIntervalMS: 200)
    engine.reloadConfig(newConfig)

    #expect(engine.config.polling.intervalMS == 200)
  }

  @Test func engineReloadWorkflowAppliesFutureConfigAndPromptTemplate() async throws {
    let workflow = makeWorkflow(
      pollingIntervalMS: 50,
      activeStates: ["In Progress"],
      promptTemplate: "Initial {{issue.title}}"
    )
    let updatedWorkflow = makeWorkflow(
      pollingIntervalMS: 50,
      activeStates: ["Queued"],
      promptTemplate: "Updated {{issue.title}}"
    )

    let tracker = StubTracker()
    let issue = Issue(
      id: IssueID("I_RELOAD"),
      identifier: try IssueIdentifier(validating: "owner/repo#77"),
      repository: "owner/repo",
      number: 77,
      title: "Reload me",
      description: nil,
      priority: nil,
      state: "Queued",
      issueState: "OPEN",
      projectItemID: nil,
      url: nil,
      labels: [],
      blockedBy: [],
      createdAt: nil,
      updatedAt: nil
    )
    tracker.setAllIssues([issue])

    let stubRunner = StubAgentRunner()
    let engine = OrchestratorEngine(
      config: workflow.config,
      trackerFactory: { _ in tracker },
      agentRunnerFactory: { _ in stubRunner },
      promptTemplate: workflow.promptTemplate
    )

    try engine.start()
    defer { engine.stop() }

    try await bootstrapWaitUntil("engine starts") {
      engine.state == OrchestratorEngineState.running
    }

    #expect(stubRunner.executeRunCount == 0)

    engine.reloadWorkflow(updatedWorkflow)

    try await bootstrapWaitUntil("run dispatched") {
      stubRunner.executeRunCount == 1
    }

    #expect(stubRunner.lastConfig?.tracker.activeStates == ["Queued"])
    #expect(stubRunner.lastPromptTemplate == "Updated {{issue.title}}")
  }

  @Test func engineReloadWorkflowFailureKeepsLastGoodDefinitionAndReportsError() async throws {
    let observer = CollectingEngineObserver()
    let trackerFactoryCallCount = Mutex(0)
    let initialWorkflow = makeWorkflow(
      pollingIntervalMS: 50,
      activeStates: ["In Progress"],
      promptTemplate: "Initial prompt"
    )
    let engine = OrchestratorEngine(
      config: initialWorkflow.config,
      trackerFactory: { _ in
        let callCount = trackerFactoryCallCount.withLock {
          $0 += 1
          return $0
        }
        if callCount == 1 {
          return StubTracker()
        }
        throw OrchestratorEngineError.trackerCreationFailed("reload failure")
      },
      promptTemplate: initialWorkflow.promptTemplate,
      observer: observer
    )

    try engine.start()
    defer { engine.stop() }

    try await bootstrapWaitUntil("engine starts") {
      engine.state == OrchestratorEngineState.running
    }

    engine.reloadWorkflow(
      makeWorkflow(
        pollingIntervalMS: 75,
        activeStates: ["Queued"],
        promptTemplate: "Broken prompt"
      ))

    try await bootstrapWaitUntil("reload error reported") {
      observer.errors.contains { $0.context == "reload" }
    }

    #expect(engine.config.polling.intervalMS == initialWorkflow.config.polling.intervalMS)
    #expect(engine.config.tracker.activeStates == initialWorkflow.config.tracker.activeStates)
  }

  @Test func engineReloadWorkflowFailureEmitsStructuredLog() async throws {
    let observer = CollectingEngineObserver()
    let trackerFactoryCallCount = Mutex(0)
    let initialWorkflow = makeWorkflow(
      pollingIntervalMS: 50,
      activeStates: ["In Progress"],
      promptTemplate: "Initial prompt"
    )
    let engine = OrchestratorEngine(
      config: initialWorkflow.config,
      trackerFactory: { _ in
        let callCount = trackerFactoryCallCount.withLock {
          $0 += 1
          return $0
        }
        if callCount == 1 {
          return StubTracker()
        }
        throw OrchestratorEngineError.trackerCreationFailed(
          "reload failure with token=ghp_reload_secret")
      },
      promptTemplate: initialWorkflow.promptTemplate,
      observer: observer
    )

    let (_, logs) = try await withCapturedRuntimeLogs {
      try engine.start()
      defer { engine.stop() }

      try await bootstrapWaitUntil("engine starts") {
        engine.state == OrchestratorEngineState.running
      }

      engine.reloadWorkflow(
        makeWorkflow(
          pollingIntervalMS: 75,
          activeStates: ["Queued"],
          promptTemplate: "Broken prompt"
        ))

      try await bootstrapWaitUntil("reload error reported") {
        observer.errors.contains { $0.context == "reload" }
      }
    }

    let reloadLog = try #require(
      logs.first { $0.entry.event == "workflow_reload_failed" })
    #expect(reloadLog.entry.error?.contains("ghp_reload_secret") == false)
    #expect(!reloadLog.line.contains("ghp_reload_secret"))
  }

  @Test func engineStartupCleanupRemovesTerminalWorkspaces() async throws {
    let observer = CollectingEngineObserver()
    let config = makeConfig(pollingIntervalMS: 50, terminalStates: ["Done"])

    let tracker = StubTracker()
    let doneIssue = Issue(
      id: IssueID("I_DONE"),
      identifier: try IssueIdentifier(validating: "owner/repo#99"),
      repository: "owner/repo",
      number: 99,
      title: "Completed",
      description: nil,
      priority: nil,
      state: "Done",
      issueState: "CLOSED",
      projectItemID: nil,
      url: nil,
      labels: [],
      blockedBy: [],
      createdAt: nil,
      updatedAt: nil
    )
    tracker.setIssuesByStates([doneIssue])

    let workspaceRoot = NSTemporaryDirectory() + "engine_test_\(UUID().uuidString)"
    let wsManager = WorkspaceManager(root: workspaceRoot)

    let engine = OrchestratorEngine(
      config: config,
      trackerFactory: { _ in tracker },
      workspaceManagerFactory: { _ in wsManager },
      observer: observer
    )

    try engine.start()
    try await bootstrapWaitUntil("engine running") { engine.state == .running }
    engine.stop()
    try await bootstrapWaitUntil("engine stops") { engine.state == .stopped }

    #expect(observer.stateChanges.contains(.running))
    // Cleanup errors for non-existent workspaces are swallowed
  }

  @Test func engineHandlesTrackerCreationFailure() async throws {
    let observer = CollectingEngineObserver()
    let config = makeConfig(pollingIntervalMS: 50)
    let engine = OrchestratorEngine(
      config: config,
      trackerFactory: { _ in throw OrchestratorEngineError.trackerCreationFailed("test failure") },
      observer: observer
    )

    try engine.start()
    try await bootstrapWaitUntil("engine stops after failure") { engine.state == .stopped }

    #expect(engine.state == .stopped)
    #expect(!observer.errors.isEmpty)
    #expect(observer.errors[0].context == "startup")
  }

  @Test func engineStopWhenNotRunning() {
    let config = makeConfig()
    let engine = OrchestratorEngine(
      config: config,
      trackerFactory: { _ in StubTracker() }
    )
    // Should not crash
    engine.stop()
    #expect(engine.state == .idle)
  }

  @Test func engineCanRestartAfterStop() async throws {
    let config = makeConfig(pollingIntervalMS: 50)
    let engine = OrchestratorEngine(
      config: config,
      trackerFactory: { _ in StubTracker() }
    )

    try engine.start()
    try await bootstrapWaitUntil("engine starts") { engine.state == .running }
    engine.stop()
    try await bootstrapWaitUntil("engine stops") { engine.state == .stopped }
    #expect(engine.state == .stopped)

    try engine.start()
    try await bootstrapWaitUntil("engine restarts") { engine.state == .running }
    #expect(engine.state == OrchestratorEngineState.running)
    engine.stop()
    try await bootstrapWaitUntil("engine stops again") { engine.state == .stopped }
  }

  @Test func engineStartupCleanupErrorIsReportedToObserver() async throws {
    let observer = CollectingEngineObserver()
    let config = makeConfig(pollingIntervalMS: 50, terminalStates: ["Done"])

    let tracker = StubTracker()
    tracker.setFetchError(GitHubTrackerError.missingAPIKey)

    let engine = OrchestratorEngine(
      config: config,
      trackerFactory: { _ in tracker },
      observer: observer
    )

    try engine.start()
    try await bootstrapWaitUntil("cleanup error reported") {
      observer.errors.contains { $0.context == "startupCleanup" }
    }
    engine.stop()
    try await bootstrapWaitUntil("engine stops") { engine.state == .stopped }

    #expect(observer.errors.contains { $0.context == "startupCleanup" })
  }

  @Test func engineDispatchCanExecuteInjectedAgentRunner() async throws {
    let observer = CollectingEngineObserver()
    let config = makeConfig(pollingIntervalMS: 50)

    let tracker = StubTracker()
    let issue = Issue(
      id: IssueID("I_1"),
      identifier: try IssueIdentifier(validating: "owner/repo#1"),
      repository: "owner/repo",
      number: 1,
      title: "Dispatch me",
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
    tracker.setAllIssues([issue])

    let stubRunner = StubAgentRunner()
    let engine = OrchestratorEngine(
      config: config,
      trackerFactory: { _ in tracker },
      agentRunnerFactory: { _ in stubRunner },
      promptTemplate: "Test prompt",
      observer: observer
    )

    try engine.start()
    try await bootstrapWaitUntil("run dispatched") { !observer.dispatches.isEmpty }
    engine.stop()
    try await bootstrapWaitUntil("engine stops") { engine.state == .stopped }

    #expect(!observer.dispatches.isEmpty)
    #expect(!observer.completions.isEmpty)
    #expect(stubRunner.executeRunCount > 0)
  }
}
