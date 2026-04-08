import Foundation
import Synchronization
import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore
@testable import SymphonyShared

// MARK: - OrchestratorEngine Restart After Stop

@Suite("OrchestratorEngine Restart")
struct OrchestratorEngineRestartTests {

  private func makeConfig(pollingIntervalMS: Int = 50) -> WorkflowConfig {
    WorkflowConfig(
      tracker: TrackerConfig(
        activeStates: ["Todo"],
        terminalStates: ["Done"]
      ),
      polling: PollingConfig(intervalMS: pollingIntervalMS)
    )
  }

  @Test func restartAfterStopSucceeds() async throws {
    let observer = CollectingEngineObserver()
    let config = makeConfig()
    let engine = OrchestratorEngine(
      config: config,
      trackerFactory: { _ in StubTracker() },
      observer: observer
    )

    try engine.start()
    try await bootstrapWaitUntil("engine starts") { engine.state == .running }
    engine.stop()
    try await bootstrapWaitUntil("engine stops") { engine.state == .stopped }
    #expect(engine.state == .stopped)

    // Restart — tests the `|| _state == .stopped` guard branch
    try engine.start()
    try await bootstrapWaitUntil("engine restarts") { engine.state == .running }
    #expect(engine.state == .running)

    engine.stop()
    try await bootstrapWaitUntil("engine stops again") { engine.state == .stopped }

    let stateChanges = observer.stateChanges
    #expect(stateChanges.contains(.running))
    #expect(stateChanges.contains(.stopped))
  }

  @Test func stopWhileIdleIsNoOp() {
    let engine = OrchestratorEngine(
      config: makeConfig(),
      trackerFactory: { _ in StubTracker() }
    )
    #expect(engine.state == .idle)
    engine.stop()
    #expect(engine.state == .idle)
  }

  @Test func stopWhileAlreadyStoppedIsNoOp() async throws {
    let engine = OrchestratorEngine(
      config: makeConfig(),
      trackerFactory: { _ in StubTracker() }
    )
    try engine.start()
    try await bootstrapWaitUntil("engine starts") { engine.state == .running }
    engine.stop()
    try await bootstrapWaitUntil("engine stops") { engine.state == .stopped }
    engine.stop()
    #expect(engine.state == .stopped)
  }
}

// MARK: - OrchestratorEngine Polling Interval Edge Cases

@Suite("OrchestratorEngine Polling Interval")
struct OrchestratorEnginePollingIntervalTests {

  @Test func zeroIntervalDoesNotCrash() async throws {
    let observer = CollectingEngineObserver()
    let config = WorkflowConfig(
      tracker: TrackerConfig(activeStates: ["Todo"], terminalStates: ["Done"]),
      polling: PollingConfig(intervalMS: 0)
    )
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

  @Test func negativeIntervalClampedToZero() async throws {
    let observer = CollectingEngineObserver()
    let config = WorkflowConfig(
      tracker: TrackerConfig(activeStates: ["Todo"], terminalStates: ["Done"]),
      polling: PollingConfig(intervalMS: -100)
    )
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
}

// MARK: - OrchestratorEngine Config Reload

@Suite("OrchestratorEngine Config Reload")
struct OrchestratorEngineConfigReloadTests {

  @Test func reloadConfigUpdatesPollingInterval() async throws {
    let config = WorkflowConfig(
      tracker: TrackerConfig(activeStates: ["Todo"], terminalStates: ["Done"]),
      polling: PollingConfig(intervalMS: 50)
    )
    let engine = OrchestratorEngine(
      config: config,
      trackerFactory: { _ in StubTracker() }
    )
    try engine.start()
    try await bootstrapWaitUntil("engine starts") { engine.state == .running }

    let newConfig = WorkflowConfig(
      tracker: TrackerConfig(activeStates: ["Todo"], terminalStates: ["Done"]),
      polling: PollingConfig(intervalMS: 200)
    )
    engine.reloadConfig(newConfig)
    #expect(engine.config.polling.intervalMS == 200)

    engine.stop()
    try await bootstrapWaitUntil("engine stops") { engine.state == .stopped }
  }

  @Test func reloadWorkflowWhileNotRunningNoOps() {
    let config = WorkflowConfig(
      tracker: TrackerConfig(activeStates: ["Todo"], terminalStates: ["Done"]),
      polling: PollingConfig(intervalMS: 50)
    )
    let engine = OrchestratorEngine(
      config: config,
      trackerFactory: { _ in StubTracker() }
    )

    let newWorkflow = WorkflowDefinition(
      config: WorkflowConfig(
        tracker: TrackerConfig(activeStates: ["Open"], terminalStates: ["Closed"]),
        polling: PollingConfig(intervalMS: 500)
      ),
      promptTemplate: "New prompt"
    )
    engine.reloadWorkflow(newWorkflow)
    #expect(engine.config.polling.intervalMS == 500)
  }
}

// MARK: - CopilotCLIAdapter Request IDs

@Suite("CopilotCLI Request IDs")
struct CopilotCLIRequestIDTests {

  @Test func startupPromptIDStartsAt3() async throws {
    let stubLauncher = StubProcessLauncher()
    let stubProcess = StubLaunchedProcess()
    stubLauncher.setStubProcess(stubProcess)

    let adapter = CopilotCLIAdapter(config: .defaults, processLauncher: stubLauncher)
    let stream = try await adapter.startSession(
      sessionID: SessionID("s-id"),
      workspacePath: "/tmp/ws",
      prompt: "fix",
      environment: [:]
    )

    stubProcess.simulateOutput(
      #"{"id":2,"result":{"sessionId":"copilot-session-1"}}"# + "\n")
    stubProcess.simulateOutput(
      #"{"id":3,"result":{"stopReason":"end_turn"}}"# + "\n")

    for try await _ in stream {}

    let messages = try stubProcess.recordedInputStrings.map(parseJSONObject)
    #expect(messages.count == 3)

    // initialize = id 1, newSession = id 2
    #expect(messages[0]["id"] as? Int == 1)
    #expect(messages[1]["id"] as? Int == 2)
    // startup prompt = id 3 (from nextRequestID starting at 3)
    #expect(messages[2]["id"] as? Int == 3)
  }

  @Test func continuationPromptIDIncrements() async throws {
    let stubLauncher = StubProcessLauncher()
    let stubProcess = StubLaunchedProcess()
    stubLauncher.setStubProcess(stubProcess)

    let adapter = CopilotCLIAdapter(config: .defaults, processLauncher: stubLauncher)
    let initialStream = try await adapter.startSession(
      sessionID: SessionID("s-id-inc"),
      workspacePath: "/tmp/ws",
      prompt: "fix",
      environment: [:]
    )

    stubProcess.simulateOutput(
      #"{"id":2,"result":{"sessionId":"copilot-session-1"}}"# + "\n")
    stubProcess.simulateOutput(
      #"{"id":3,"result":{"stopReason":"end_turn"}}"# + "\n")

    for try await _ in initialStream {}

    _ = try await adapter.continueSession(
      sessionID: SessionID("s-id-inc"), guidance: "keep going")

    let messages = try stubProcess.recordedInputStrings.map(parseJSONObject)
    // [initialize(1), newSession(2), prompt(3), prompt(4)]
    #expect(messages.count == 4)
    #expect(messages[2]["id"] as? Int == 3)
    #expect(messages[3]["id"] as? Int == 4)
  }
}

// MARK: - CopilotCLIAdapter Exit Code

@Suite("CopilotCLI Exit Code")
struct CopilotCLIExitCodeTests {

  @Test func nonZeroExitCodeThrowsProcessExitedUnexpectedly() async throws {
    let stubProcess = StubLaunchedProcess()
    let adapter = CopilotCLIAdapter(config: .defaults)

    let stream = adapter.makeEventStream(
      from: stubProcess, sessionID: SessionID("s-exit"))
    stubProcess.simulateOutput("{\"event\": \"update\"}\n")
    stubProcess.simulateTermination(exitCode: 1)

    var caughtError: Error?
    do {
      for try await _ in stream {}
    } catch {
      caughtError = error
    }

    let adapterError = try #require(caughtError as? ProviderAdapterError)
    guard case .processExitedUnexpectedly(let exitCode) = adapterError else {
      Issue.record("Expected processExitedUnexpectedly, got \(adapterError)")
      return
    }
    #expect(exitCode == 1)
  }

  @Test func negativeExitCodeAlsoThrows() async throws {
    let stubProcess = StubLaunchedProcess()
    let adapter = CopilotCLIAdapter(config: .defaults)

    let stream = adapter.makeEventStream(
      from: stubProcess, sessionID: SessionID("s-exit-neg"))
    stubProcess.simulateTermination(exitCode: -1)

    var caughtError: Error?
    do {
      for try await _ in stream {}
    } catch {
      caughtError = error
    }

    let adapterError = try #require(caughtError as? ProviderAdapterError)
    guard case .processExitedUnexpectedly(let exitCode) = adapterError else {
      Issue.record("Expected processExitedUnexpectedly for negative exit code")
      return
    }
    #expect(exitCode == -1)
  }

  @Test func zeroExitCodeFinishesCleanly() async throws {
    let stubProcess = StubLaunchedProcess()
    let adapter = CopilotCLIAdapter(config: .defaults)

    let stream = adapter.makeEventStream(
      from: stubProcess, sessionID: SessionID("s-exit-ok"))
    stubProcess.simulateTermination(exitCode: 0)

    var events: [AgentRawEvent] = []
    for try await event in stream {
      events.append(event)
    }
    #expect(events.isEmpty)
  }
}

// MARK: - WorkflowReloader File Descriptor Reset

@Suite("WorkflowReloader FD Reset")
struct WorkflowReloaderFDResetTests {

  @Test func stopWatchingSetsFileDescriptorToNegativeOne() throws {
    let tmpFile = NSTemporaryDirectory() + "reloader_fd_\(UUID().uuidString).md"
    FileManager.default.createFile(
      atPath: tmpFile, contents: Data("---\n---\nTest".utf8))
    defer { try? FileManager.default.removeItem(atPath: tmpFile) }

    let reloader = WorkflowReloader(workflowPath: tmpFile) { _ in }
    try reloader.startWatching()
    #expect(reloader.isWatching)

    reloader.stopWatching()
    #expect(!reloader.isWatching)

    // Start again — if FD was NOT reset to -1 the dispatch source might be stale
    try reloader.startWatching()
    #expect(reloader.isWatching)
    reloader.stopWatching()
    #expect(!reloader.isWatching)
  }

  @Test func processFileChangeOnDeletedFileDoesNotCrash() throws {
    let tmpFile = NSTemporaryDirectory() + "reloader_deleted_\(UUID().uuidString).md"
    FileManager.default.createFile(
      atPath: tmpFile,
      contents: Data("---\npolling:\n  interval_ms: 100\n---\nPrompt".utf8))

    let reloadCount = Mutex(0)
    let reloader = WorkflowReloader(workflowPath: tmpFile) { _ in
      reloadCount.withLock { $0 += 1 }
    }
    try reloader.startWatching()

    // Delete the file, then trigger a change
    try FileManager.default.removeItem(atPath: tmpFile)
    reloader.processFileChange()

    // Parse failure should NOT crash, callback should NOT fire
    #expect(reloadCount.withLock { $0 } == 0)
    reloader.stopWatching()
  }
}

// MARK: - ProviderSessionSnapshot Merging Edge Cases

@Suite("ProviderSessionSnapshot Merging")
struct ProviderSessionSnapshotMergingTests {

  @Test func mergingNilUpdatePreservesAllBaseFields() throws {
    let base = ProviderSessionSnapshot(
      providerSessionID: "sess-1",
      providerThreadID: "t-1",
      providerTurnID: "turn-1",
      providerRunID: "run-1",
      tokenUsage: try TokenUsage(inputTokens: 10, outputTokens: 20),
      latestRateLimitPayload: "{\"remaining\":50}",
      lastAgentMessage: "hello",
      latestSequence: EventSequence(5)
    )
    let emptyUpdate = ProviderSessionSnapshotUpdate()
    let merged = base.merging(emptyUpdate)

    #expect(merged.providerSessionID == "sess-1")
    #expect(merged.providerThreadID == "t-1")
    #expect(merged.providerTurnID == "turn-1")
    #expect(merged.providerRunID == "run-1")
    #expect(merged.tokenUsage.inputTokens == 10)
    #expect(merged.tokenUsage.outputTokens == 20)
    #expect(merged.latestRateLimitPayload == "{\"remaining\":50}")
    #expect(merged.lastAgentMessage == "hello")
    #expect(merged.latestSequence == EventSequence(5))
  }

  @Test func mergingReplacesAllFieldsWhenAllNonNil() throws {
    let base = ProviderSessionSnapshot(
      providerSessionID: "old-sess",
      providerThreadID: "old-thread",
      providerTurnID: "old-turn",
      providerRunID: "old-run",
      tokenUsage: try TokenUsage(inputTokens: 1, outputTokens: 2),
      latestRateLimitPayload: "old",
      lastAgentMessage: "old msg",
      latestSequence: EventSequence(1)
    )
    let fullUpdate = ProviderSessionSnapshotUpdate(
      providerSessionID: "new-sess",
      providerThreadID: "new-thread",
      providerTurnID: "new-turn",
      providerRunID: "new-run",
      tokenUsage: try TokenUsage(inputTokens: 100, outputTokens: 200),
      latestRateLimitPayload: "new",
      lastAgentMessage: "new msg",
      latestSequence: EventSequence(99)
    )
    let merged = base.merging(fullUpdate)

    #expect(merged.providerSessionID == "new-sess")
    #expect(merged.providerThreadID == "new-thread")
    #expect(merged.providerTurnID == "new-turn")
    #expect(merged.providerRunID == "new-run")
    #expect(merged.tokenUsage.inputTokens == 100)
    #expect(merged.tokenUsage.outputTokens == 200)
    #expect(merged.latestRateLimitPayload == "new")
    #expect(merged.lastAgentMessage == "new msg")
    #expect(merged.latestSequence == EventSequence(99))
  }
}
