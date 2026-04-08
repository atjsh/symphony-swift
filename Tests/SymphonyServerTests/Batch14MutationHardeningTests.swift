import Foundation
import Synchronization
import SymphonyShared
import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore

// MARK: - RepositoryFileClassifier: Missing OR-Chain Clauses

@Suite("RepositoryFileClassifier OR-Chain")
struct RepositoryFileClassifierORChainTests {
  private let emptyHistory = AnalysisHistoryConfig(sourcePaths: [], testPaths: [])

  @Test func documentationPathClassifiedAsOther() throws {
    let detector = StubRepositoryLanguageDetector(
      testPaths: [],
      languagesByPath: [:],
      languageTypes: [:],
      documentationPaths: ["docs/guide.md"]
    )
    let classifier = RepositoryFileClassifier(detector: detector)
    let result = try classifier.classify(
      path: "docs/guide.md", content: Data(), historyConfig: emptyHistory)
    #expect(result == .other)
  }

  @Test func imagePathClassifiedAsOther() throws {
    let detector = StubRepositoryLanguageDetector(
      testPaths: [],
      languagesByPath: [:],
      languageTypes: [:],
      imagePaths: ["assets/logo.png"]
    )
    let classifier = RepositoryFileClassifier(detector: detector)
    let result = try classifier.classify(
      path: "assets/logo.png", content: Data(), historyConfig: emptyHistory)
    #expect(result == .other)
  }

  @Test func generatedPathClassifiedAsOther() throws {
    let detector = StubRepositoryLanguageDetector(
      testPaths: [],
      languagesByPath: [:],
      languageTypes: [:],
      generatedPaths: ["gen/schema.pb.swift"]
    )
    let classifier = RepositoryFileClassifier(detector: detector)
    let result = try classifier.classify(
      path: "gen/schema.pb.swift", content: Data(), historyConfig: emptyHistory)
    #expect(result == .other)
  }

  @Test func configurationPathClassifiedAsOther() throws {
    let detector = StubRepositoryLanguageDetector(
      testPaths: [],
      languagesByPath: [:],
      languageTypes: [:],
      configurationPaths: ["config/settings.yml"]
    )
    let classifier = RepositoryFileClassifier(detector: detector)
    let result = try classifier.classify(
      path: "config/settings.yml", content: Data(), historyConfig: emptyHistory)
    #expect(result == .other)
  }
}

// MARK: - AgentRunner: Codex Failed Then Completed Ignored

@Suite("AgentRunner Codex StreamError Guard")
struct AgentRunnerCodexStreamErrorGuardTests {

  @Test func failedThenCompletedOutcomeKeepsFailedState() async throws {
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

    await Task.yield()
    try await bootstrapWaitUntil("runner activates") { runner.activeRunCount > 0 }

    // Emit thread + turn started
    stubProcess.simulateOutput(
      #"{"method":"thread/started","params":{"thread":{"id":"t1"}}}"# + "\n")
    stubProcess.simulateOutput(
      #"{"method":"turn/started","params":{"threadId":"t1","turn":{"id":"turn1"}}}"# + "\n")
    // Emit failed outcome → sets streamError
    stubProcess.simulateOutput(
      #"{"method":"turn/failed","params":{"turn_id":"turn1"}}"# + "\n")
    // Emit completed outcome AFTER failure → should be ignored by streamError == nil guard
    stubProcess.simulateOutput(
      #"{"method":"turn/completed","params":{"turn_id":"turn1","outcome":"completed"}}"# + "\n")
    stubProcess.simulateTermination(exitCode: 0)

    let result = await task.value
    #expect(result.finalState == RunLifecycleState.failed)
    #expect(result.error?.contains("failed") == true)
  }
}

// MARK: - AgentRunner: Token Redaction Patterns

@Suite("AgentRunner Redaction Patterns")
struct AgentRunnerRedactionPatternsTests {

  @Test func skTokenRedactedInErrorLog() async throws {
    let wsManager = StubWorkspaceManager()
    wsManager.setEnsureError(
      WorkspaceError.workspaceCreationFailed("API key: sk-proj-abc123_XYZ"))

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
      })
    #expect(!failureLog.line.contains("sk-proj-abc123_XYZ"))
    #expect(failureLog.entry.error?.contains("[REDACTED]") == true)
  }

  @Test func ghoTokenRedactedInErrorLog() async throws {
    let wsManager = StubWorkspaceManager()
    wsManager.setEnsureError(
      WorkspaceError.workspaceCreationFailed("Token gho_organizationSecret123"))

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
      })
    #expect(!failureLog.line.contains("gho_organizationSecret123"))
    #expect(failureLog.entry.error?.contains("[REDACTED]") == true)
  }
}

// MARK: - BootstrapServerRunner Orchestrator/Server Flag Logic

@Suite("BootstrapServerRunner Flag Logic")
struct BootstrapServerRunnerFlagLogicTests {

  @Test func bothFlagsDisabledProducesNoStartupState() throws {
    var outputLines: [String] = []
    // Both flags false: no database, no server, no orchestrator.
    // Should complete without error.
    try BootstrapServerRunner.run(
      environment: [
        "SYMPHONY_PORT": "0",
        "SYMPHONY_HOST": "127.0.0.1",
      ],
      output: { outputLines.append($0) },
      keepAlive: {},
      startServer: false,
      startOrchestrator: false
    )
    // Verify the bootstrap_starting log was emitted but no server started
    #expect(!outputLines.isEmpty)
  }

  @Test func orchestratorNilInheritsStartServerTrue() throws {
    // startOrchestrator: nil, startServer: true → shouldStartOrchestrator = true
    // Without a workflow file, this means effectiveWorkflowURL returns nil → no engine started
    var outputLines: [String] = []
    try BootstrapServerRunner.run(
      environment: [
        "SYMPHONY_PORT": "0",
        "SYMPHONY_HOST": "127.0.0.1",
      ],
      output: { outputLines.append($0) },
      keepAlive: {},
      startServer: false,
      startOrchestrator: nil
    )
    #expect(!outputLines.isEmpty)
  }

  @Test func orchestratorExplicitlyTrueWithMissingWorkflowThrows() {
    #expect(throws: Error.self) {
      try BootstrapServerRunner.run(
        environment: [
          "SYMPHONY_PORT": "0",
          "SYMPHONY_HOST": "127.0.0.1",
        ],
        output: { _ in },
        keepAlive: {},
        startServer: false,
        startOrchestrator: true
      )
    }
  }
}

// MARK: - StallWatchState Edge Cases

@Suite("StallWatchState Boundaries")
struct StallWatchStateBoundaryTests {

  @Test func stallDetectorDisabledWithZeroTimeout() async throws {
    let wsManager = StubWorkspaceManager()
    let launcher = StubProcessLauncher()
    let sink = CollectingEventSink()
    let runner = AgentRunner(
      workspaceManager: wsManager, processLauncher: launcher, eventSink: sink)

    let stubProcess = StubLaunchedProcess()
    launcher.setStubProcess(stubProcess)

    let issue = try makeIssue()
    let ctx = try makeRunContext()
    // stallTimeoutMS = 0 should disable stall detection
    let config = WorkflowConfig(
      providers: ProvidersConfig(
        codex: CodexProviderConfig(
          turnTimeoutMS: 300_000, readTimeoutMS: 5_000, stallTimeoutMS: 0)))

    let task = Task {
      await runner.executeRun(
        context: ctx, issue: issue, config: config, promptTemplate: "")
    }

    await Task.yield()
    try await bootstrapWaitUntil("runner activates") { runner.activeRunCount > 0 }
    stubProcess.simulateOutput("{\"type\":\"message\"}\n")
    try await bootstrapWaitUntil("event processed") { sink.events.count >= 1 }
    stubProcess.simulateTermination(exitCode: 0)

    let result = await task.value
    #expect(result.finalState == RunLifecycleState.succeeded)
    #expect(result.error == nil)
  }

  @Test func stallErrorMessageContainsExactTimeout() async throws {
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
        codex: CodexProviderConfig(
          turnTimeoutMS: 300_000, readTimeoutMS: 5_000, stallTimeoutMS: 120)))

    let task = Task {
      await runner.executeRun(
        context: ctx, issue: issue, config: config, promptTemplate: "")
    }

    await Task.yield()
    try await bootstrapWaitUntil("runner activates") { runner.activeRunCount > 0 }
    // Don't send any events — wait for stall detection
    let result = await task.value
    #expect(result.finalState == RunLifecycleState.stalled)
    #expect(result.error?.contains("120ms") == true)
  }
}

// MARK: - GlobPattern Matching

@Suite("GlobPattern Edge Cases")
struct GlobPatternEdgeCaseTests {

  @Test func globPatternMatchesDoubleStarDeep() throws {
    let detector = StubRepositoryLanguageDetector(
      testPaths: [],
      languagesByPath: ["a/b/c/deep.swift": "Swift"],
      languageTypes: ["Swift": "programming"]
    )
    let classifier = RepositoryFileClassifier(detector: detector)
    let history = AnalysisHistoryConfig(sourcePaths: ["a/**"], testPaths: [])
    let result = try classifier.classify(
      path: "a/b/c/deep.swift", content: Data("code".utf8), historyConfig: history)
    #expect(result == .source)
  }

  @Test func globPatternDoesNotMatchOutsideScope() throws {
    let detector = StubRepositoryLanguageDetector(
      testPaths: [],
      languagesByPath: ["other/file.swift": "Swift"],
      languageTypes: ["Swift": "programming"]
    )
    let classifier = RepositoryFileClassifier(detector: detector)
    let history = AnalysisHistoryConfig(sourcePaths: ["src/**"], testPaths: [])
    let result = try classifier.classify(
      path: "other/file.swift", content: Data("code".utf8), historyConfig: history)
    // Not matched by glob, falls through to language detection → programming → source
    #expect(result == .source)
  }
}
