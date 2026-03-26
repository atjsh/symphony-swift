import Foundation
import Synchronization
import Testing

@testable import SymphonyRuntime
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
    // Give time for the engine to start and complete at least one tick
    try await Task.sleep(nanoseconds: 200_000_000)

    #expect(engine.state == .running)
    #expect(observer.stateChanges.contains(.starting))
    #expect(observer.stateChanges.contains(.running))

    engine.stop()
    try await Task.sleep(nanoseconds: 100_000_000)
    #expect(engine.state == .stopped)
  }

  @Test func engineCannotStartTwice() async throws {
    let config = makeConfig(pollingIntervalMS: 50)
    let engine = OrchestratorEngine(
      config: config,
      trackerFactory: { _ in StubTracker() }
    )

    try engine.start()
    try await Task.sleep(nanoseconds: 100_000_000)

    #expect(throws: OrchestratorEngineError.self) {
      try engine.start()
    }

    engine.stop()
    try await Task.sleep(nanoseconds: 100_000_000)
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
    try await Task.sleep(nanoseconds: 300_000_000)
    engine.stop()
    try await Task.sleep(nanoseconds: 100_000_000)

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

    let didStart = try await waitUntil {
      engine.state == .running
    }
    #expect(didStart)

    let baselineTickCount = observer.tickResults.count
    engine.requestRefresh()

    let didRefresh = try await waitUntil {
      observer.tickResults.count > baselineTickCount
    }
    #expect(didRefresh)
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

    let didStart = try await waitUntil {
      engine.state == .running
    }

    #expect(didStart)
    #expect(stubRunner.executeRunCount == 0)

    engine.reloadWorkflow(updatedWorkflow)

    let didDispatch = try await waitUntil {
      stubRunner.executeRunCount == 1
    }

    #expect(didDispatch)
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

    let didStart = try await waitUntil {
      engine.state == .running
    }
    #expect(didStart)

    engine.reloadWorkflow(
      makeWorkflow(
        pollingIntervalMS: 75,
        activeStates: ["Queued"],
        promptTemplate: "Broken prompt"
      ))

    let didReportReloadError = try await waitUntil {
      observer.errors.contains { $0.context == "reload" }
    }

    #expect(didReportReloadError)
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

      let didStart = try await waitUntil {
        engine.state == .running
      }
      #expect(didStart)

      engine.reloadWorkflow(
        makeWorkflow(
          pollingIntervalMS: 75,
          activeStates: ["Queued"],
          promptTemplate: "Broken prompt"
        ))

      let didReportReloadError = try await waitUntil {
        observer.errors.contains { $0.context == "reload" }
      }
      #expect(didReportReloadError)
    }

    let reloadLog = try #require(
      logs.first { $0.json["event"] as? String == "workflow_reload_failed" })
    #expect((reloadLog.json["error"] as? String)?.contains("ghp_reload_secret") == false)
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
    try await Task.sleep(nanoseconds: 300_000_000)
    engine.stop()
    try await Task.sleep(nanoseconds: 100_000_000)

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
    try await Task.sleep(nanoseconds: 200_000_000)

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
    try await Task.sleep(nanoseconds: 150_000_000)
    engine.stop()
    try await Task.sleep(nanoseconds: 150_000_000)
    #expect(engine.state == .stopped)

    try engine.start()
    try await Task.sleep(nanoseconds: 150_000_000)
    #expect(engine.state == .running)
    engine.stop()
    try await Task.sleep(nanoseconds: 150_000_000)
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
    try await Task.sleep(nanoseconds: 300_000_000)
    engine.stop()
    try await Task.sleep(nanoseconds: 100_000_000)

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
    try await Task.sleep(nanoseconds: 250_000_000)
    engine.stop()
    try await Task.sleep(nanoseconds: 100_000_000)

    #expect(!observer.dispatches.isEmpty)
    #expect(!observer.completions.isEmpty)
    #expect(stubRunner.executeRunCount > 0)
  }
}

// MARK: - OrchestratorEngineState Tests

@Suite("OrchestratorEngineState")
struct OrchestratorEngineStateTests {
  @Test func rawValues() {
    #expect(OrchestratorEngineState.idle.rawValue == "idle")
    #expect(OrchestratorEngineState.starting.rawValue == "starting")
    #expect(OrchestratorEngineState.running.rawValue == "running")
    #expect(OrchestratorEngineState.stopping.rawValue == "stopping")
    #expect(OrchestratorEngineState.stopped.rawValue == "stopped")
  }
}

// MARK: - OrchestratorEngineError Tests

@Suite("OrchestratorEngineError")
struct OrchestratorEngineErrorTests {
  @Test func errorsAreEquatable() {
    #expect(
      OrchestratorEngineError.workflowLoadFailed("a")
        == OrchestratorEngineError.workflowLoadFailed("a"))
    #expect(
      OrchestratorEngineError.trackerCreationFailed("a")
        == OrchestratorEngineError.trackerCreationFailed("a"))
    #expect(OrchestratorEngineError.alreadyRunning == OrchestratorEngineError.alreadyRunning)
    #expect(OrchestratorEngineError.notRunning == OrchestratorEngineError.notRunning)
  }
}

// MARK: - RunContext Tests

@Suite("RunContext")
struct RunContextTests {
  @Test func initAndEquality() throws {
    let ctx1 = RunContext(
      issueID: IssueID("I_1"),
      issueIdentifier: try IssueIdentifier(validating: "owner/repo#1"),
      runID: RunID("R_1"),
      attempt: 1
    )
    let ctx2 = RunContext(
      issueID: IssueID("I_1"),
      issueIdentifier: try IssueIdentifier(validating: "owner/repo#1"),
      runID: RunID("R_1"),
      attempt: 1
    )
    #expect(ctx1 == ctx2)
  }
}

// MARK: - NoOpEngineEventObserver Tests

@Suite("NoOpEngineEventObserver")
struct NoOpEngineEventObserverTests {
  @Test func noOpDoesNotCrash() async {
    let observer = NoOpEngineEventObserver()
    await observer.engineStateChanged(.running)
    await observer.engineTickCompleted(
      TickResult(reconciled: 0, candidatesFetched: 0, dispatched: 0, retriesProcessed: 0))
    await observer.engineDispatchStarted(
      RunContext(
        issueID: IssueID("I_1"),
        issueIdentifier: try! IssueIdentifier(validating: "o/r#1"),
        runID: RunID("R_1"),
        attempt: 1
      ))
    await observer.engineRunCompleted(
      RunContext(
        issueID: IssueID("I_1"),
        issueIdentifier: try! IssueIdentifier(validating: "o/r#1"),
        runID: RunID("R_1"),
        attempt: 1
      ), success: true)
    await observer.engineError(OrchestratorEngineError.notRunning, context: "test")
  }
}

// MARK: - CollectingEngineObserver Tests

@Suite("CollectingEngineObserver")
struct CollectingEngineObserverTests {
  @Test func collectsAllEventTypes() async {
    let observer = CollectingEngineObserver()

    await observer.engineStateChanged(.running)
    await observer.engineTickCompleted(
      TickResult(reconciled: 1, candidatesFetched: 2, dispatched: 3, retriesProcessed: 0))
    await observer.engineDispatchStarted(
      RunContext(
        issueID: IssueID("I_1"),
        issueIdentifier: try! IssueIdentifier(validating: "o/r#1"),
        runID: RunID("R_1"),
        attempt: 1
      ))
    await observer.engineRunCompleted(
      RunContext(
        issueID: IssueID("I_1"),
        issueIdentifier: try! IssueIdentifier(validating: "o/r#1"),
        runID: RunID("R_1"),
        attempt: 1
      ), success: false)
    await observer.engineError(OrchestratorEngineError.notRunning, context: "ctx")

    #expect(observer.stateChanges == [.running])
    #expect(observer.tickResults.count == 1)
    #expect(observer.dispatches.count == 1)
    #expect(observer.completions.count == 1)
    #expect(observer.errors.count == 1)
    #expect(observer.errors[0].context == "ctx")
  }
}

// MARK: - WorkflowReloader Tests

@Suite("WorkflowReloader")
struct WorkflowReloaderTests {
  @Test func startWatchingOnNonExistentPathThrows() {
    let reloader = WorkflowReloader(workflowPath: "/nonexistent/WORKFLOW.md") { _ in }
    #expect(throws: OrchestratorEngineError.self) {
      try reloader.startWatching()
    }
    #expect(!reloader.isWatching)
  }

  @Test func startAndStopWatching() throws {
    let tmpFile = NSTemporaryDirectory() + "reloader_test_\(UUID().uuidString).md"
    FileManager.default.createFile(atPath: tmpFile, contents: Data("---\n---\nHello".utf8))
    defer { try? FileManager.default.removeItem(atPath: tmpFile) }

    let reloader = WorkflowReloader(workflowPath: tmpFile) { _ in }
    try reloader.startWatching()
    #expect(reloader.isWatching)

    reloader.stopWatching()
    #expect(!reloader.isWatching)
  }

  @Test func fileChangeTriggersCallback() async throws {
    let tmpFile = NSTemporaryDirectory() + "reloader_callback_\(UUID().uuidString).md"
    FileManager.default.createFile(
      atPath: tmpFile, contents: Data("---\npolling:\n  interval_ms: 1000\n---\nPrompt".utf8))
    defer { try? FileManager.default.removeItem(atPath: tmpFile) }

    let reloadedDefinition = Mutex<WorkflowDefinition?>(nil)

    let reloader = WorkflowReloader(workflowPath: tmpFile) { definition in
      reloadedDefinition.withLock { $0 = definition }
    }
    try reloader.startWatching()

    try "---\npolling:\n  interval_ms: 2000\n---\nUpdated prompt".write(
      toFile: tmpFile, atomically: true, encoding: .utf8)
    reloader.processFileChange()

    reloader.stopWatching()

    let definition = try #require(reloadedDefinition.withLock { $0 })
    #expect(definition.config.polling.intervalMS == 2000)
    #expect(definition.promptTemplate == "Updated prompt")
  }

  @Test func invalidFileChangeKeepsLastGoodConfig() async throws {
    let tmpFile = NSTemporaryDirectory() + "reloader_invalid_\(UUID().uuidString).md"
    FileManager.default.createFile(
      atPath: tmpFile,
      contents: Data("---\npolling:\n  interval_ms: 1000\n---\nPrompt".utf8))
    defer { try? FileManager.default.removeItem(atPath: tmpFile) }

    let reloadCount = Mutex(0)

    let reloader = WorkflowReloader(workflowPath: tmpFile) { _ in
      reloadCount.withLock { $0 += 1 }
    }

    // Write invalid content that will cause parse error
    try Data([0xFF, 0xFE]).write(to: URL(fileURLWithPath: tmpFile))

    // Call processFileChange directly to exercise the catch block
    reloader.processFileChange()

    // The invalid change should not trigger callback
    let count = reloadCount.withLock { $0 }
    #expect(count == 0)
  }

  @Test func stopWatchingTwiceDoesNotCrash() throws {
    let tmpFile = NSTemporaryDirectory() + "reloader_double_stop_\(UUID().uuidString).md"
    FileManager.default.createFile(atPath: tmpFile, contents: Data("---\n---\nTest".utf8))
    defer { try? FileManager.default.removeItem(atPath: tmpFile) }

    let reloader = WorkflowReloader(workflowPath: tmpFile) { _ in }
    try reloader.startWatching()
    reloader.stopWatching()
    reloader.stopWatching()
    #expect(!reloader.isWatching)
  }
}

// MARK: - EngineOrchestratorDelegate Tests

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

private final class StubAgentRunner: AgentRunning, @unchecked Sendable {
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

private func waitUntil(
  timeoutMS: Int = 1_000,
  pollIntervalMS: Int = 25,
  condition: @escaping @Sendable () -> Bool
) async throws -> Bool {
  let deadline = Date().addingTimeInterval(Double(timeoutMS) / 1000)
  while Date() <= deadline {
    if condition() {
      return true
    }
    try await Task.sleep(nanoseconds: UInt64(pollIntervalMS) * 1_000_000)
  }
  return condition()
}
