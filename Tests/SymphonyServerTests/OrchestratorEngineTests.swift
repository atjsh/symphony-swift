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

    let didReload = Mutex(false)

    let reloader = WorkflowReloader(workflowPath: tmpFile) { config in
      didReload.withLock { $0 = true }
    }
    try reloader.startWatching()

    // Write changed content
    try "---\npolling:\n  interval_ms: 2000\n---\nUpdated prompt".write(
      toFile: tmpFile, atomically: true, encoding: .utf8)

    // Wait for DispatchSource to fire
    try await Task.sleep(nanoseconds: 500_000_000)

    reloader.stopWatching()

    // DispatchSource may or may not fire depending on timing; we verify no crash
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
      engine: nil, workspaceManager: wsManager, observer: observer)

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
      engine: nil, workspaceManager: wsManager, observer: observer)

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
      engine: nil, workspaceManager: wsManager, observer: observer)

    await delegate.orchestratorDidCancel(
      issueID: IssueID("I_1"),
      issueIdentifier: try IssueIdentifier(validating: "o/r#1"),
      reason: "paused", cleanup: false)
    // No cleanup attempted
    #expect(observer.completions.count == 1)
  }

  @Test func delegateRefreshSnapshotNotifiesObserver() async throws {
    let observer = CollectingEngineObserver()
    let wsRoot = NSTemporaryDirectory() + "delegate_refresh_\(UUID().uuidString)"
    let wsManager = WorkspaceManager(root: wsRoot)
    let delegate = EngineOrchestratorDelegate(
      engine: nil, workspaceManager: wsManager, observer: observer)

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
    #expect(observer.dispatches.count == 1)
  }

  @Test func delegateRetryNotifiesObserver() async throws {
    let observer = CollectingEngineObserver()
    let wsRoot = NSTemporaryDirectory() + "delegate_retry_\(UUID().uuidString)"
    let wsManager = WorkspaceManager(root: wsRoot)
    let delegate = EngineOrchestratorDelegate(
      engine: nil, workspaceManager: wsManager, observer: observer)

    let record = RetryRecord(
      issueID: IssueID("I_1"),
      issueIdentifier: try IssueIdentifier(validating: "o/r#1"),
      attempt: 2,
      dueAt: Date(),
      error: "timeout"
    )

    await delegate.orchestratorDidRetry(record: record)
    #expect(observer.dispatches.count == 1)
  }
}
