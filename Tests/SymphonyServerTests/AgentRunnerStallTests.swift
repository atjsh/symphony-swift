import Foundation
import SymphonyShared
import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore


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
