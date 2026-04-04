import Foundation
import SymphonyShared
import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore

@Suite("AgentRunResult")
struct AgentRunResultTests {
  @Test func initAndEquality() throws {
    let ctx = try makeRunContext(runID: "R_REDACTED")
    let result1 = AgentRunResult(
      context: ctx, sessionID: SessionID("S_1"), finalState: .succeeded,
      eventCount: 5, error: nil)
    let result2 = AgentRunResult(
      context: ctx, sessionID: SessionID("S_1"), finalState: .succeeded,
      eventCount: 5, error: nil)
    #expect(result1 == result2)
  }

  @Test func inequalityOnDifferentState() throws {
    let ctx = try makeRunContext()
    let result1 = AgentRunResult(
      context: ctx, sessionID: SessionID("S_1"), finalState: .succeeded,
      eventCount: 5, error: nil)
    let result2 = AgentRunResult(
      context: ctx, sessionID: SessionID("S_1"), finalState: .failed,
      eventCount: 5, error: "oops")
    #expect(result1 != result2)
  }

  @Test func inequalityOnDifferentEventCount() throws {
    let ctx = try makeRunContext()
    let result1 = AgentRunResult(
      context: ctx, sessionID: SessionID("S_1"), finalState: .succeeded,
      eventCount: 5, error: nil)
    let result2 = AgentRunResult(
      context: ctx, sessionID: SessionID("S_1"), finalState: .succeeded,
      eventCount: 10, error: nil)
    #expect(result1 != result2)
  }
}

// MARK: - AgentRunnerError Tests

@Suite("AgentRunnerError")
struct AgentRunnerErrorTests {
  @Test func errorsAreEquatable() {
    #expect(
      AgentRunnerError.workspacePreparationFailed("a")
        == AgentRunnerError.workspacePreparationFailed("a"))
    #expect(
      AgentRunnerError.promptRenderFailed("a")
        == AgentRunnerError.promptRenderFailed("a"))
    #expect(
      AgentRunnerError.hookFailed(hook: "before_run", reason: "exit 1")
        == AgentRunnerError.hookFailed(hook: "before_run", reason: "exit 1"))
    #expect(
      AgentRunnerError.runAlreadyActive(RunID("R_1"))
        == AgentRunnerError.runAlreadyActive(RunID("R_1")))
    #expect(
      AgentRunnerError.runNotFound(RunID("R_1"))
        == AgentRunnerError.runNotFound(RunID("R_1")))
  }

  @Test func differentErrorsAreNotEqual() {
    #expect(
      AgentRunnerError.workspacePreparationFailed("a")
        != AgentRunnerError.workspacePreparationFailed("b"))
    #expect(
      AgentRunnerError.runNotFound(RunID("R_1"))
        != AgentRunnerError.runNotFound(RunID("R_2")))
  }
}

// MARK: - NoOpAgentRunEventSink Tests

@Suite("NoOpAgentRunEventSink")
struct NoOpAgentRunEventSinkTests {
  @Test func noOpDoesNotCrash() async throws {
    let sink = NoOpAgentRunEventSink()
    let ctx = try makeRunContext()
    sink.runDidStart(
      AgentRunStartInfo(
        context: ctx,
        issue: try makeIssue(),
        provider: "codex",
        sessionID: SessionID("S_1"),
        workspacePath: "/tmp/ws"
      ))
    sink.runDidTransition(ctx, to: .preparingWorkspace)
    sink.runDidReceiveEvent(
      AgentRawEvent(
        sessionID: SessionID("S_1"), provider: "codex",
        sequence: EventSequence(0), timestamp: "2026-01-01T00:00:00Z",
        rawJSON: "{}", providerEventType: "test", normalizedEventKind: "message"))
    sink.runDidComplete(
      AgentRunResult(
        context: ctx, sessionID: SessionID("S_1"), finalState: .succeeded,
        eventCount: 1, error: nil))
  }
}

// MARK: - AgentRunner Lifecycle Tests

@Suite("AgentRunner Lifecycle")
struct AgentRunnerLifecycleTests {
  @Test func successfulRunGoesFullLifecycle() async throws {
    let wsManager = StubWorkspaceManager()
    let launcher = StubProcessLauncher()
    let sink = CollectingEventSink()
    let runner = AgentRunner(
      workspaceManager: wsManager, processLauncher: launcher, eventSink: sink)

    let stubProcess = StubLaunchedProcess()
    launcher.setStubProcess(stubProcess)

    let issue = try makeIssue()
    let ctx = try makeRunContext(runID: "R_REDACTED")

    let task = Task {
      await runner.executeRun(
        context: ctx, issue: issue, config: .defaults,
        promptTemplate: "Fix: {{issue.title}}")
    }

    // Give time for adapter to call startSession and set up stream
    try await Task.sleep(nanoseconds: 50_000_000)

    // Emit some events
    stubProcess.simulateOutput("{\"type\":\"message\"}\n")
    stubProcess.simulateOutput("{\"type\":\"tool_call\"}\n")
    try await Task.sleep(nanoseconds: 50_000_000)

    // Complete the process
    stubProcess.simulateTermination(exitCode: 0)

    let result = await task.value

    #expect(result.finalState == RunLifecycleState.succeeded)
    #expect(result.eventCount == 2)
    #expect(result.error == nil)
    #expect(result.context == ctx)

    // Verify lifecycle transitions
    let states = sink.transitionStates
    #expect(states.contains(.preparingWorkspace))
    #expect(states.contains(.buildingPrompt))
    #expect(states.contains(.launchingAgentProcess))
    #expect(states.contains(.initializingSession))
    #expect(states.contains(.streamingTurn))
    #expect(states.contains(.finishing))

    // Verify workspace was ensured
    #expect(wsManager.ensuredKeys.count == 1)

    // Verify completion sink was called
    #expect(sink.completions.count == 1)
    #expect(sink.completions[0].finalState == RunLifecycleState.succeeded)

    // Start info is emitted after session initialization.
    #expect(sink.starts.count == 1)
    #expect(sink.starts[0].sessionID == result.sessionID)
    #expect(sink.starts[0].provider == "codex")

    // Events received by sink
    #expect(sink.events.count == 2)

    // Active run count should be 0 after completion
    #expect(runner.activeRunCount == 0)
  }

  @Test func failedProcessExitProducesFailedResult() async throws {
    let wsManager = StubWorkspaceManager()
    let launcher = StubProcessLauncher()
    let sink = CollectingEventSink()
    let runner = AgentRunner(
      workspaceManager: wsManager, processLauncher: launcher, eventSink: sink)

    let stubProcess = StubLaunchedProcess()
    launcher.setStubProcess(stubProcess)

    let issue = try makeIssue()
    let ctx = try makeRunContext()

    let task = Task {
      await runner.executeRun(
        context: ctx, issue: issue, config: .defaults, promptTemplate: "")
    }

    try await Task.sleep(nanoseconds: 50_000_000)
    stubProcess.simulateOutput("{\"type\":\"message\"}\n")
    try await Task.sleep(nanoseconds: 50_000_000)
    stubProcess.simulateTermination(exitCode: 1)

    let result = await task.value

    #expect(result.finalState == RunLifecycleState.failed)
    #expect(result.eventCount == 1)
    #expect(result.error != nil)
    #expect(runner.activeRunCount == 0)
  }

  @Test func codexFailedTerminalOutcomeDoesNotBecomeSucceeded() async throws {
    let wsManager = StubWorkspaceManager()
    let launcher = StubProcessLauncher()
    let sink = CollectingEventSink()
    let runner = AgentRunner(
      workspaceManager: wsManager, processLauncher: launcher, eventSink: sink)

    let stubProcess = StubLaunchedProcess()
    launcher.setStubProcess(stubProcess)

    let issue = try makeIssue()
    let ctx = try makeRunContext()

    let task = Task {
      await runner.executeRun(
        context: ctx, issue: issue, config: .defaults, promptTemplate: "")
    }

    try await Task.sleep(nanoseconds: 50_000_000)
    stubProcess.simulateOutput(
      #"{"method":"thread/started","params":{"thread":{"id":"thread-failed"}}}"# + "\n")
    stubProcess.simulateOutput(
      #"{"method":"turn/started","params":{"threadId":"thread-failed","turn":{"id":"turn-failed"}}}"#
        + "\n")
    stubProcess.simulateOutput(#"{"method":"turn/failed","params":{"turn_id":"turn-failed"}}"# + "\n")
    stubProcess.simulateTermination(exitCode: 0)

    let result = await task.value
    #expect(result.finalState == RunLifecycleState.failed)
    #expect(result.error?.contains("failed") == true)
    #expect(result.eventCount >= 1)
  }

  @Test func codexInterruptedTerminalOutcomeDoesNotBecomeSucceeded() async throws {
    let wsManager = StubWorkspaceManager()
    let launcher = StubProcessLauncher()
    let sink = CollectingEventSink()
    let runner = AgentRunner(
      workspaceManager: wsManager, processLauncher: launcher, eventSink: sink)

    let stubProcess = StubLaunchedProcess()
    launcher.setStubProcess(stubProcess)

    let issue = try makeIssue()
    let ctx = try makeRunContext()

    let task = Task {
      await runner.executeRun(
        context: ctx, issue: issue, config: .defaults, promptTemplate: "")
    }

    try await Task.sleep(nanoseconds: 50_000_000)
    stubProcess.simulateOutput(
      #"{"method":"thread/started","params":{"thread":{"id":"thread-interrupted"}}}"# + "\n")
    stubProcess.simulateOutput(
      #"{"method":"turn/started","params":{"threadId":"thread-interrupted","turn":{"id":"turn-interrupted"}}}"#
        + "\n")
    stubProcess.simulateOutput(
      #"{"method":"turn/interrupted","params":{"turn_id":"turn-interrupted"}}"# + "\n")
    stubProcess.simulateTermination(exitCode: 0)

    let result = await task.value
    #expect(result.finalState == RunLifecycleState.failed)
    #expect(result.error?.contains("interrupted") == true)
    #expect(result.eventCount >= 1)
  }

  @Test func codexCompletedTerminalOutcomeKeepsRunSucceeded() async throws {
    let wsManager = StubWorkspaceManager()
    let launcher = StubProcessLauncher()
    let sink = CollectingEventSink()
    let runner = AgentRunner(
      workspaceManager: wsManager, processLauncher: launcher, eventSink: sink)

    let stubProcess = StubLaunchedProcess()
    launcher.setStubProcess(stubProcess)

    let issue = try makeIssue()
    let ctx = try makeRunContext()

    let task = Task {
      await runner.executeRun(
        context: ctx, issue: issue, config: .defaults, promptTemplate: "")
    }

    try await Task.sleep(nanoseconds: 50_000_000)
    stubProcess.simulateOutput(
      #"{"method":"thread/started","params":{"thread":{"id":"thread-completed"}}}"# + "\n")
    stubProcess.simulateOutput(
      #"{"method":"turn/started","params":{"threadId":"thread-completed","turn":{"id":"turn-completed"}}}"#
        + "\n")
    stubProcess.simulateOutput(
      #"{"method":"turn/completed","params":{"turn_id":"turn-completed","outcome":"completed"}}"#
        + "\n")
    stubProcess.simulateTermination(exitCode: 0)

    let result = await task.value
    #expect(result.finalState == RunLifecycleState.succeeded)
    #expect(result.error == nil)
    #expect(result.eventCount >= 1)
  }

  @Test func codexReadTimeoutProducesTimedOutState() async throws {
    let wsManager = StubWorkspaceManager()
    let launcher = StubProcessLauncher()
    let sink = CollectingEventSink()
    let runner = AgentRunner(
      workspaceManager: wsManager, processLauncher: launcher, eventSink: sink)

    let stubProcess = StubLaunchedProcess()
    launcher.setStubProcess(stubProcess)

    let issue = try makeIssue()
    let ctx = try makeRunContext()
    let config = WorkflowConfig(
      providers: ProvidersConfig(
        codex: CodexProviderConfig(turnTimeoutMS: 5_000, readTimeoutMS: 50, stallTimeoutMS: 0)))

    let result = await runner.executeRun(
      context: ctx, issue: issue, config: config, promptTemplate: "")

    #expect(result.finalState == RunLifecycleState.timedOut)
    #expect(result.error?.contains("readTimeout") == true)
  }

  @Test func codexTurnTimeoutProducesTimedOutState() async throws {
    let wsManager = StubWorkspaceManager()
    let launcher = StubProcessLauncher()
    let sink = CollectingEventSink()
    let runner = AgentRunner(
      workspaceManager: wsManager, processLauncher: launcher, eventSink: sink)

    let stubProcess = StubLaunchedProcess()
    launcher.setStubProcess(stubProcess)

    let issue = try makeIssue()
    let ctx = try makeRunContext()
    let config = WorkflowConfig(
      providers: ProvidersConfig(
        codex: CodexProviderConfig(turnTimeoutMS: 50, readTimeoutMS: 5_000, stallTimeoutMS: 0)))

    let task = Task {
      await runner.executeRun(
        context: ctx, issue: issue, config: config, promptTemplate: "")
    }

    try await Task.sleep(nanoseconds: 50_000_000)
    stubProcess.simulateOutput(
      #"{"method":"thread/started","params":{"thread":{"id":"thread-timeout"}}}"# + "\n")

    let result = await task.value
    #expect(result.finalState == RunLifecycleState.timedOut)
    #expect(result.error?.contains("turnTimeout") == true)
  }

  @Test func workspaceFailureReturnsEarlyWithFailed() async throws {
    let wsManager = StubWorkspaceManager()
    wsManager.setEnsureError(
      WorkspaceError.workspaceCreationFailed("disk full"))

    let launcher = StubProcessLauncher()
    let sink = CollectingEventSink()
    let runner = AgentRunner(
      workspaceManager: wsManager, processLauncher: launcher, eventSink: sink)

    let issue = try makeIssue()
    let ctx = try makeRunContext()

    let result = await runner.executeRun(
      context: ctx, issue: issue, config: .defaults, promptTemplate: "")

    #expect(result.finalState == RunLifecycleState.failed)
    #expect(result.eventCount == 0)
    #expect(result.error?.contains("Workspace preparation failed") == true)

    // Only one transition (preparingWorkspace) before failure
    #expect(sink.transitionStates.first == RunLifecycleState.preparingWorkspace)
    #expect(sink.completions.count == 1)

    // No process should have been launched
    #expect(launcher.invocations.isEmpty)
  }

  @Test func workspaceFailureEmitsRedactedStructuredFailureLog() async throws {
    let wsManager = StubWorkspaceManager()
    wsManager.setEnsureError(
      WorkspaceError.workspaceCreationFailed("Authorization: Bearer ghp_workspace_secret"))

    let launcher = StubProcessLauncher()
    let sink = CollectingEventSink()
    let runner = AgentRunner(
      workspaceManager: wsManager, processLauncher: launcher, eventSink: sink)

    let issue = try makeIssue()
    let ctx = try makeRunContext()

    let (result, logs) = try await withCapturedRuntimeLogs {
      await runner.executeRun(
        context: ctx, issue: issue, config: .defaults, promptTemplate: "")
    }

    #expect(result.finalState == .failed)
    let failureLog = try #require(
      logs.first {
        $0.entry.event == "agent_run_failed"
          && $0.entry.runID == ctx.runID.rawValue
          && $0.entry.state == RunLifecycleState.preparingWorkspace.rawValue
      })
    #expect(failureLog.entry.issueID == ctx.issueID.rawValue)
    #expect(failureLog.entry.issueIdentifier == ctx.issueIdentifier.rawValue)
    #expect(failureLog.entry.runID == ctx.runID.rawValue)
    #expect(failureLog.entry.provider == ProviderName.codex.rawValue)
    #expect(failureLog.entry.error?.contains("[REDACTED]") == true)
    #expect(!failureLog.line.contains("ghp_workspace_secret"))
  }

  @Test func promptRenderFailureReturnsEarlyWithFailed() async throws {
    let wsManager = StubWorkspaceManager()
    let launcher = StubProcessLauncher()
    let sink = CollectingEventSink()
    let runner = AgentRunner(
      workspaceManager: wsManager, processLauncher: launcher, eventSink: sink)

    let issue = try makeIssue()
    let ctx = try makeRunContext()

    // Template with unknown variable causes render failure
    let result = await runner.executeRun(
      context: ctx, issue: issue, config: .defaults,
      promptTemplate: "{{unknown.variable}}")

    #expect(result.finalState == RunLifecycleState.failed)
    #expect(result.eventCount == 0)
    #expect(result.error?.contains("Prompt render failed") == true)

    #expect(sink.transitionStates.contains(.buildingPrompt))
    #expect(sink.completions.count == 1)
    #expect(launcher.invocations.isEmpty)
  }

  @Test func processLaunchFailureReturnsEarlyWithFailed() async throws {
    let wsManager = StubWorkspaceManager()
    let launcher = StubProcessLauncher()
    launcher.setLaunchError(
      ProviderAdapterError.processLaunchFailed("command not found"))

    let sink = CollectingEventSink()
    let runner = AgentRunner(
      workspaceManager: wsManager, processLauncher: launcher, eventSink: sink)

    let issue = try makeIssue()
    let ctx = try makeRunContext()

    let result = await runner.executeRun(
      context: ctx, issue: issue, config: .defaults, promptTemplate: "")

    #expect(result.finalState == RunLifecycleState.failed)
    #expect(result.eventCount == 0)
    #expect(result.error?.contains("Session start failed") == true)
    #expect(runner.activeRunCount == 0)
  }

  @Test func noEventsStillSucceeds() async throws {
    let wsManager = StubWorkspaceManager()
    let launcher = StubProcessLauncher()
    let sink = CollectingEventSink()
    let runner = AgentRunner(
      workspaceManager: wsManager, processLauncher: launcher, eventSink: sink)

    let stubProcess = StubLaunchedProcess()
    launcher.setStubProcess(stubProcess)

    let issue = try makeIssue()
    let ctx = try makeRunContext()

    let task = Task {
      await runner.executeRun(
        context: ctx, issue: issue, config: .defaults, promptTemplate: "")
    }

    try await Task.sleep(nanoseconds: 50_000_000)
    stubProcess.simulateTermination(exitCode: 0)

    let result = await task.value

    #expect(result.finalState == RunLifecycleState.succeeded)
    #expect(result.eventCount == 0)
    #expect(result.error == nil)
    #expect(sink.events.isEmpty)
  }
}

// MARK: - AgentRunner Cancel Tests
