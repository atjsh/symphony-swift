import Foundation
import SymphonyShared
import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore

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

    try await bootstrapWaitUntil("events processed") { sink.events.count >= 2 }
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

    try await bootstrapWaitUntil("runner activates") { runner.activeRunCount > 0 }
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

    try await bootstrapWaitUntil("runner activates") { runner.activeRunCount > 0 }
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

    try await bootstrapWaitUntil("runner activates") { runner.activeRunCount > 0 }
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

    try await bootstrapWaitUntil("runner activates") { runner.activeRunCount > 0 }
    stubProcess.simulateTermination(exitCode: 0)

    let result = await task.value
    #expect(result.finalState == RunLifecycleState.succeeded)
    #expect(sink.transitionStates.contains(.buildingPrompt))
  }
}

// MARK: - AgentRunner Event Sink Tests
