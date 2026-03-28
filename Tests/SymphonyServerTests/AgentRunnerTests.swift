import Foundation
import SymphonyShared
import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore

// MARK: - Test Helpers

private func makeIssue(
  id: String = "I_1",
  owner: String = "org",
  repo: String = "repo",
  number: Int = 1,
  title: String = "Fix bug",
  description: String? = "Description",
  state: String = "In Progress",
  issueState: String = "OPEN"
) throws -> SymphonyShared.Issue {
  SymphonyShared.Issue(
    id: IssueID(id),
    identifier: try IssueIdentifier(validating: "\(owner)/\(repo)#\(number)"),
    repository: "\(owner)/\(repo)",
    number: number,
    title: title,
    description: description,
    priority: nil,
    state: state,
    issueState: issueState,
    projectItemID: nil,
    url: "https://github.com/\(owner)/\(repo)/issues/\(number)",
    labels: [],
    blockedBy: [],
    createdAt: nil,
    updatedAt: nil
  )
}

private func makeRunContext(
  issueID: String = "I_1",
  runID: String = "R_1",
  attempt: Int = 1
) throws -> RunContext {
  RunContext(
    issueID: IssueID(issueID),
    issueIdentifier: try IssueIdentifier(validating: "org/repo#1"),
    runID: RunID(runID),
    attempt: attempt
  )
}

// MARK: - Stub Workspace Manager

private final class StubWorkspaceManager: WorkspaceManaging, @unchecked Sendable {
  private let lock = NSLock()
  private var _ensuredKeys: [WorkspaceKey] = []
  private var _removedKeys: [WorkspaceKey] = []
  private var _ensureError: Error?
  let root: String

  init(root: String = "/tmp/test_workspaces") {
    self.root = root
  }

  var ensuredKeys: [WorkspaceKey] {
    lock.withLock { _ensuredKeys }
  }

  var removedKeys: [WorkspaceKey] {
    lock.withLock { _removedKeys }
  }

  func setEnsureError(_ error: Error?) {
    lock.withLock { _ensureError = error }
  }

  func workspacePath(for key: WorkspaceKey) -> String {
    "\(root)/\(key.rawValue)"
  }

  func ensureWorkspace(for key: WorkspaceKey, hooks: HooksConfig) throws -> String {
    let error = lock.withLock {
      _ensuredKeys.append(key)
      return _ensureError
    }
    if let error { throw error }
    return workspacePath(for: key)
  }

  func removeWorkspace(for key: WorkspaceKey, hooks: HooksConfig) throws {
    lock.withLock { _removedKeys.append(key) }
  }

  func validateContainment(path: String) throws {
    guard path.hasPrefix(root) else {
      throw WorkspaceError.rootContainmentViolation(path: path, root: root)
    }
  }
}

// MARK: - Collecting Event Sink

private final class CollectingEventSink: AgentRunEventSink, @unchecked Sendable {
  private let lock = NSLock()
  private var _starts: [AgentRunStartInfo] = []
  private var _transitions: [(RunContext, RunLifecycleState)] = []
  private var _events: [AgentRawEvent] = []
  private var _completions: [AgentRunResult] = []

  var starts: [AgentRunStartInfo] {
    lock.withLock { _starts }
  }

  var transitions: [(RunContext, RunLifecycleState)] {
    lock.withLock { _transitions }
  }

  var transitionStates: [RunLifecycleState] {
    lock.withLock { _transitions.map(\.1) }
  }

  var events: [AgentRawEvent] {
    lock.withLock { _events }
  }

  var completions: [AgentRunResult] {
    lock.withLock { _completions }
  }

  func runDidStart(_ startInfo: AgentRunStartInfo) {
    lock.withLock { _starts.append(startInfo) }
  }

  func runDidTransition(_ context: RunContext, to state: RunLifecycleState) {
    lock.withLock { _transitions.append((context, state)) }
  }

  func runDidReceiveEvent(_ event: AgentRawEvent) {
    lock.withLock { _events.append(event) }
  }

  func runDidComplete(_ result: AgentRunResult) {
    lock.withLock { _completions.append(result) }
  }
}

// MARK: - AgentRunResult Tests

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
        $0.json["event"] as? String == "agent_run_failed"
          && $0.json["run_id"] as? String == ctx.runID.rawValue
          && $0.json["state"] as? String == RunLifecycleState.preparingWorkspace.rawValue
      })
    #expect(failureLog.json["issue_id"] as? String == ctx.issueID.rawValue)
    #expect(failureLog.json["issue_identifier"] as? String == ctx.issueIdentifier.rawValue)
    #expect(failureLog.json["run_id"] as? String == ctx.runID.rawValue)
    #expect(failureLog.json["provider"] as? String == ProviderName.codex.rawValue)
    #expect((failureLog.json["error"] as? String)?.contains("[REDACTED]") == true)
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

@Suite("AgentRunner Cancel")
struct AgentRunnerCancelTests {
  @Test func cancelNonExistentRunThrows() async throws {
    let wsManager = StubWorkspaceManager()
    let launcher = StubProcessLauncher()
    let sink = CollectingEventSink()
    let runner = AgentRunner(
      workspaceManager: wsManager, processLauncher: launcher, eventSink: sink)

    await #expect(throws: AgentRunnerError.self) {
      try await runner.cancelRun(runID: RunID("nonexistent"))
    }
  }

  @Test func cancelActiveRunSucceeds() async throws {
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

    // Wait for the run to become active
    while runner.activeRunCount == 0 {
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    #expect(runner.activeRunCount == 1)

    // Cancel the active run — should not throw
    try await runner.cancelRun(runID: ctx.runID)

    // Simulate process termination so executeRun completes
    stubProcess.simulateTermination(exitCode: 9)

    let result = await task.value
    #expect(result.context == ctx)
  }

  @Test func cancelActiveCodexRunUsesNativeInterruptWhenTurnIsKnown() async throws {
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

    while runner.activeRunCount == 0 {
      try await Task.sleep(nanoseconds: 10_000_000)
    }

    stubProcess.simulateOutput(
      #"{"method":"thread/started","params":{"thread":{"id":"thread-interrupt"}}}"# + "\n")
    stubProcess.simulateOutput(
      #"{"method":"turn/started","params":{"threadId":"thread-interrupt","turn":{"id":"turn-interrupt"}}}"#
        + "\n")

    try await Task.sleep(nanoseconds: 50_000_000)
    try await runner.cancelRun(runID: ctx.runID)
    #expect(stubProcess.interruptCount == 1)
    #expect(stubProcess.terminationCount == 0)

    stubProcess.simulateOutput(
      #"{"method":"turn/interrupted","params":{"turn_id":"turn-interrupt"}}"# + "\n")
    stubProcess.simulateTermination(exitCode: 0)

    let result = await task.value
    #expect(result.finalState == RunLifecycleState.failed)
    #expect(result.error?.contains("interrupted") == true)
  }

  @Test func cancelActiveCodexRunFallsBackToTerminateBeforeTurnIsKnown() async throws {
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

    while runner.activeRunCount == 0 {
      try await Task.sleep(nanoseconds: 10_000_000)
    }

    try await runner.cancelRun(runID: ctx.runID)
    #expect(stubProcess.interruptCount == 0)
    #expect(stubProcess.terminationCount == 1)

    let result = await task.value
    #expect(result.finalState == RunLifecycleState.failed)
  }
}

// MARK: - AgentRunner Provider Selection Tests

@Suite("AgentRunner Provider Selection")
struct AgentRunnerProviderSelectionTests {
  @Test func defaultProviderIsUsed() async throws {
    let wsManager = StubWorkspaceManager()
    let launcher = StubProcessLauncher()
    let sink = CollectingEventSink()
    let runner = AgentRunner(
      workspaceManager: wsManager, processLauncher: launcher, eventSink: sink)

    let stubProcess = StubLaunchedProcess()
    launcher.setStubProcess(stubProcess)

    let issue = try makeIssue()
    let ctx = try makeRunContext()

    // Default config uses .codex as default provider
    let task = Task {
      await runner.executeRun(
        context: ctx, issue: issue, config: .defaults, promptTemplate: "")
    }

    try await Task.sleep(nanoseconds: 50_000_000)
    stubProcess.simulateTermination(exitCode: 0)

    let result = await task.value
    #expect(result.finalState == RunLifecycleState.succeeded)
    // Verify the process was launched (provider adapter used the launcher)
    #expect(!launcher.invocations.isEmpty)
  }

  @Test func claudeCodeProviderIsUsed() async throws {
    let wsManager = StubWorkspaceManager()
    let launcher = StubProcessLauncher()
    let sink = CollectingEventSink()
    let runner = AgentRunner(
      workspaceManager: wsManager, processLauncher: launcher, eventSink: sink)

    let stubProcess = StubLaunchedProcess()
    launcher.setStubProcess(stubProcess)

    let issue = try makeIssue()
    let ctx = try makeRunContext()

    let config = WorkflowConfig(agent: AgentConfig(defaultProvider: .claudeCode))

    let task = Task {
      await runner.executeRun(
        context: ctx, issue: issue, config: config, promptTemplate: "")
    }

    try await Task.sleep(nanoseconds: 50_000_000)
    stubProcess.simulateTermination(exitCode: 0)

    let result = await task.value
    #expect(result.finalState == RunLifecycleState.succeeded)

    // Claude code adapter adds specific flags
    let invocation = launcher.invocations.first
    #expect(invocation?.command.contains("stream-json") == true)
  }
}

// MARK: - AgentRunner Prompt Rendering Tests

@Suite("AgentRunner Prompt Rendering")
struct AgentRunnerPromptRenderingTests {
  @Test func promptTemplateIsRenderedWithIssueData() async throws {
    let wsManager = StubWorkspaceManager()
    let launcher = StubProcessLauncher()
    let sink = CollectingEventSink()
    let runner = AgentRunner(
      workspaceManager: wsManager, processLauncher: launcher, eventSink: sink)

    let stubProcess = StubLaunchedProcess()
    launcher.setStubProcess(stubProcess)

    let issue = try makeIssue(title: "Fix login bug")
    let ctx = try makeRunContext()

    let task = Task {
      await runner.executeRun(
        context: ctx, issue: issue, config: .defaults,
        promptTemplate: "Please fix: {{issue.title}}")
    }

    try await Task.sleep(nanoseconds: 50_000_000)
    stubProcess.simulateTermination(exitCode: 0)

    let result = await task.value
    #expect(result.finalState == RunLifecycleState.succeeded)

    // The prompt was rendered (we verify it didn't fail)
    #expect(sink.transitionStates.contains(.buildingPrompt))
    #expect(sink.transitionStates.contains(.launchingAgentProcess))
  }

  @Test func emptyPromptUsesDefaultFallback() async throws {
    let wsManager = StubWorkspaceManager()
    let launcher = StubProcessLauncher()
    let sink = CollectingEventSink()
    let runner = AgentRunner(
      workspaceManager: wsManager, processLauncher: launcher, eventSink: sink)

    let stubProcess = StubLaunchedProcess()
    launcher.setStubProcess(stubProcess)

    let issue = try makeIssue(title: "Fix it")
    let ctx = try makeRunContext()

    let task = Task {
      await runner.executeRun(
        context: ctx, issue: issue, config: .defaults, promptTemplate: "")
    }

    try await Task.sleep(nanoseconds: 50_000_000)
    stubProcess.simulateTermination(exitCode: 0)

    let result = await task.value
    #expect(result.finalState == RunLifecycleState.succeeded)
    #expect(sink.transitionStates.contains(.buildingPrompt))
  }
}

// MARK: - AgentRunner Event Sink Tests

@Suite("AgentRunner Event Sink")
struct AgentRunnerEventSinkTests {
  @Test func eventsAreForwardedToSink() async throws {
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
    stubProcess.simulateOutput("{\"type\":\"tool_call\"}\n")
    stubProcess.simulateOutput("{\"type\":\"status\"}\n")
    try await Task.sleep(nanoseconds: 50_000_000)
    stubProcess.simulateTermination(exitCode: 0)

    let result = await task.value
    #expect(result.eventCount == 3)
    #expect(sink.events.count == 3)
  }

  @Test func completionCallbackReceivedOnSuccess() async throws {
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

    _ = await task.value
    #expect(sink.completions.count == 1)
    #expect(sink.completions[0].finalState == RunLifecycleState.succeeded)
    #expect(sink.completions[0].error == nil)
  }

  @Test func completionCallbackReceivedOnFailure() async throws {
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
    stubProcess.simulateTermination(exitCode: 1)

    _ = await task.value
    #expect(sink.completions.count == 1)
    #expect(sink.completions[0].finalState == RunLifecycleState.failed)
    #expect(sink.completions[0].error != nil)
  }
}

// MARK: - AgentRunner Workspace Tests

@Suite("AgentRunner Workspace")
struct AgentRunnerWorkspaceTests {
  @Test func workspaceKeyMatchesIssueIdentifier() async throws {
    let wsManager = StubWorkspaceManager()
    let launcher = StubProcessLauncher()
    let sink = CollectingEventSink()
    let runner = AgentRunner(
      workspaceManager: wsManager, processLauncher: launcher, eventSink: sink)

    let stubProcess = StubLaunchedProcess()
    launcher.setStubProcess(stubProcess)

    let issue = try makeIssue(owner: "myorg", repo: "myrepo", number: 42)
    let ctx = try makeRunContext()

    let task = Task {
      await runner.executeRun(
        context: ctx, issue: issue, config: .defaults, promptTemplate: "")
    }

    try await Task.sleep(nanoseconds: 50_000_000)
    stubProcess.simulateTermination(exitCode: 0)

    _ = await task.value
    #expect(wsManager.ensuredKeys.count == 1)
    let expectedKey = issue.identifier.workspaceKey
    #expect(wsManager.ensuredKeys[0] == expectedKey)
  }
}

// MARK: - AgentRunning Protocol Conformance Tests

@Suite("AgentRunning Protocol")
struct AgentRunningProtocolTests {
  @Test func agentRunnerConformsToProtocol() throws {
    let wsManager = StubWorkspaceManager()
    let launcher = StubProcessLauncher()
    let sink = NoOpAgentRunEventSink()
    let runner: any AgentRunning = AgentRunner(
      workspaceManager: wsManager, processLauncher: launcher, eventSink: sink)
    // Verify it can be used as the protocol type
    _ = runner
  }
}

// MARK: - AgentRunner Stall Detection Tests

@Suite("AgentRunner Stall Detection")
struct AgentRunnerStallDetectionTests {
  @Test func stallDetectionDisabledWithZeroTimeout() async throws {
    let wsManager = StubWorkspaceManager()
    let launcher = StubProcessLauncher()
    let sink = CollectingEventSink()
    let runner = AgentRunner(
      workspaceManager: wsManager, processLauncher: launcher, eventSink: sink)

    let stubProcess = StubLaunchedProcess()
    launcher.setStubProcess(stubProcess)

    let issue = try makeIssue()
    let ctx = try makeRunContext()

    // Config with stall detection disabled (0ms)
    let config = WorkflowConfig(
      agent: AgentConfig(defaultProvider: .codex),
      providers: ProvidersConfig(
        codex: CodexProviderConfig(stallTimeoutMS: 0)))

    let task = Task {
      await runner.executeRun(
        context: ctx, issue: issue, config: config, promptTemplate: "")
    }

    try await Task.sleep(nanoseconds: 50_000_000)
    stubProcess.simulateTermination(exitCode: 0)

    let result = await task.value
    #expect(result.finalState == RunLifecycleState.succeeded)
  }

  @Test func stallDetectedProducesStallState() async throws {
    let wsManager = StubWorkspaceManager()
    let launcher = StubProcessLauncher()
    let sink = CollectingEventSink()
    let runner = AgentRunner(
      workspaceManager: wsManager, processLauncher: launcher, eventSink: sink)

    let stubProcess = StubLaunchedProcess()
    launcher.setStubProcess(stubProcess)

    let issue = try makeIssue()
    let ctx = try makeRunContext()

    // Use a short stall timeout and wait for the first event before going idle.
    let config = WorkflowConfig(
      providers: ProvidersConfig(
        codex: CodexProviderConfig(stallTimeoutMS: 120)))

    let task = Task {
      await runner.executeRun(
        context: ctx, issue: issue, config: config, promptTemplate: "")
    }

    // Wait for streaming to begin, send one event, then go silent to trigger stall.
    try await Task.sleep(nanoseconds: 50_000_000)
    stubProcess.simulateOutput("{\"type\":\"message\"}\n")

    while sink.events.isEmpty {
      try await Task.sleep(nanoseconds: 10_000_000)
    }

    try await Task.sleep(nanoseconds: 250_000_000)

    let result = await task.value
    #expect(result.finalState == RunLifecycleState.stalled)
    #expect(result.error?.contains("Stall detected") == true)
    #expect(result.eventCount == 1)
  }

  @Test func noStallWhenEventsArriveRegularly() async throws {
    let wsManager = StubWorkspaceManager()
    let launcher = StubProcessLauncher()
    let sink = CollectingEventSink()
    let runner = AgentRunner(
      workspaceManager: wsManager, processLauncher: launcher, eventSink: sink)

    let stubProcess = StubLaunchedProcess()
    launcher.setStubProcess(stubProcess)

    let issue = try makeIssue()
    let ctx = try makeRunContext()

    // Stall timeout 500ms - events arrive within that window
    let config = WorkflowConfig(
      providers: ProvidersConfig(
        codex: CodexProviderConfig(stallTimeoutMS: 500)))

    let task = Task {
      await runner.executeRun(
        context: ctx, issue: issue, config: config, promptTemplate: "")
    }

    try await Task.sleep(nanoseconds: 50_000_000)
    stubProcess.simulateOutput("{\"type\":\"message\"}\n")
    try await Task.sleep(nanoseconds: 20_000_000)
    stubProcess.simulateOutput("{\"type\":\"tool_call\"}\n")
    try await Task.sleep(nanoseconds: 20_000_000)
    stubProcess.simulateTermination(exitCode: 0)

    let result = await task.value
    #expect(result.finalState == RunLifecycleState.succeeded)
    #expect(result.eventCount == 2)
    #expect(result.error == nil)
  }

  @Test func stallTimeoutResolvedForClaudeCode() async throws {
    let wsManager = StubWorkspaceManager()
    let launcher = StubProcessLauncher()
    let sink = CollectingEventSink()
    let runner = AgentRunner(
      workspaceManager: wsManager, processLauncher: launcher, eventSink: sink)

    let stubProcess = StubLaunchedProcess()
    launcher.setStubProcess(stubProcess)

    let issue = try makeIssue()
    let ctx = try makeRunContext()

    // Claude code provider with short stall timeout.
    let config = WorkflowConfig(
      agent: AgentConfig(defaultProvider: .claudeCode),
      providers: ProvidersConfig(
        claudeCode: ClaudeCodeProviderConfig(stallTimeoutMS: 120)))

    let task = Task {
      await runner.executeRun(
        context: ctx, issue: issue, config: config, promptTemplate: "")
    }

    try await Task.sleep(nanoseconds: 50_000_000)
    stubProcess.simulateOutput("{\"type\":\"message\"}\n")

    while sink.events.isEmpty {
      try await Task.sleep(nanoseconds: 10_000_000)
    }

    try await Task.sleep(nanoseconds: 250_000_000)

    let result = await task.value
    #expect(result.finalState == RunLifecycleState.stalled)
  }
}

// MARK: - ProvidersConfig stallTimeoutMS Tests

@Suite("ProvidersConfig StallTimeout")
struct ProvidersConfigStallTimeoutTests {
  @Test func resolvesCodexStallTimeout() {
    let config = ProvidersConfig(codex: CodexProviderConfig(stallTimeoutMS: 100))
    #expect(config.stallTimeoutMS(for: .codex) == 100)
  }

  @Test func resolvesClaudeCodeStallTimeout() {
    let config = ProvidersConfig(claudeCode: ClaudeCodeProviderConfig(stallTimeoutMS: 200))
    #expect(config.stallTimeoutMS(for: .claudeCode) == 200)
  }

  @Test func resolvesCopilotCLIStallTimeout() {
    let config = ProvidersConfig(copilotCLI: CopilotCLIProviderConfig(stallTimeoutMS: 300))
    #expect(config.stallTimeoutMS(for: .copilotCLI) == 300)
  }

  @Test func defaultStallTimeout() {
    let config = ProvidersConfig.defaults
    #expect(config.stallTimeoutMS(for: .codex) == 300_000)
    #expect(config.stallTimeoutMS(for: .claudeCode) == 300_000)
    #expect(config.stallTimeoutMS(for: .copilotCLI) == 300_000)
  }
}

// MARK: - Collecting Event Sink Tests

@Suite("CollectingEventSink")
struct CollectingEventSinkDirectTests {
  @Test func collectsStarts() async throws {
    let sink = CollectingEventSink()
    let ctx = try makeRunContext()
    let startInfo = AgentRunStartInfo(
      context: ctx,
      issue: try makeIssue(),
      provider: "codex",
      sessionID: SessionID("S_1"),
      workspacePath: "/tmp/ws"
    )

    sink.runDidStart(startInfo)

    #expect(sink.starts == [startInfo])
  }

  @Test func collectsTransitions() async throws {
    let sink = CollectingEventSink()
    let ctx = try makeRunContext()

    sink.runDidTransition(ctx, to: .preparingWorkspace)
    sink.runDidTransition(ctx, to: .streamingTurn)

    #expect(sink.transitions.count == 2)
    #expect(sink.transitionStates == [.preparingWorkspace, .streamingTurn])
  }

  @Test func collectsEvents() async {
    let sink = CollectingEventSink()
    let event = AgentRawEvent(
      sessionID: SessionID("S_1"), provider: "codex",
      sequence: EventSequence(0), timestamp: "2026-01-01T00:00:00Z",
      rawJSON: "{}", providerEventType: "test", normalizedEventKind: "message")
    sink.runDidReceiveEvent(event)
    #expect(sink.events.count == 1)
  }

  @Test func collectsCompletions() async throws {
    let sink = CollectingEventSink()
    let ctx = try makeRunContext()
    let result = AgentRunResult(
      context: ctx, sessionID: SessionID("S_1"), finalState: .succeeded,
      eventCount: 0, error: nil)
    sink.runDidComplete(result)
    #expect(sink.completions.count == 1)
  }
}
