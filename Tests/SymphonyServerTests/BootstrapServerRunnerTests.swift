import CoreFoundation
import Darwin
import Foundation
import SymphonyShared
import Testing

@testable import SymphonyRuntime

@Test func bootstrapServerRunnerEventObserverPublishesToLiveLogHub() async throws {
  let hub = LiveLogHub()
  let event = AgentRawEvent(
    sessionID: SessionID("session-42"),
    provider: "claude_code",
    sequence: EventSequence(1),
    timestamp: "2026-03-24T03:00:01Z",
    rawJSON: #"{"type":"status","payload":{"message":"starting"}}"#,
    providerEventType: "status",
    normalizedEventKind: "status"
  )
  let stream = await hub.subscribe(to: event.sessionID)
  let observer = BootstrapServerRunner.makeEventObserver(liveLogHub: hub)

  let receiveTask = Task {
    var iterator = stream.makeAsyncIterator()
    return await iterator.next()
  }
  observer(event)

  let received = try #require(await receiveTask.value)
  #expect(received == event)
}

@Test func bootstrapServerRunnerRunStartsServerAndReturnsAfterKeepAlive() async throws {
  let root = try makeTemporaryDirectory()
  let databaseURL = root.appendingPathComponent("bootstrap.sqlite3")
  let port = try availableLoopbackPort()
  let keepAliveEntered = LockedFlag()
  let allowReturn = DispatchSemaphore(value: 0)

  let runTask = Task {
    try await BootstrapServerRunner.runAsync(
      componentName: "InProcessServer",
      environment: [
        BootstrapEnvironment.serverHostKey: "127.0.0.1",
        BootstrapEnvironment.serverPortKey: String(port),
        BootstrapEnvironment.serverSQLitePathKey: databaseURL.path,
      ],
      output: { _ in },
      keepAlive: {
        keepAliveEntered.setTrue()
        allowReturn.wait()
      }
    )
  }
  defer { allowReturn.signal() }

  try await waitUntil("bootstrap runner enters keepAlive", timeout: .seconds(5)) {
    keepAliveEntered.value
  }

  let url = try #require(URL(string: "http://127.0.0.1:\(port)/api/v1/health"))
  let (data, response) = try await URLSession(configuration: .ephemeral).data(from: url)
  let httpResponse = try #require(response as? HTTPURLResponse)
  let health = try JSONDecoder().decode(HealthResponse.self, from: data)
  #expect(httpResponse.statusCode == 200)
  #expect(health.status == "ok")

  allowReturn.signal()
  try await runTask.value
}

@Test func bootstrapServerRunnerRunPropagatesStartupFailuresAndSignalOnlyFiresOnce() async throws {
  let firstSignal = ServerStartupSignal()
  Task.detached {
    firstSignal.ready()
    firstSignal.fail(POSIXError(.EIO))
  }
  try await firstSignal.waitUntilReady()

  let secondSignal = ServerStartupSignal()
  let expectedError = POSIXError(.EADDRINUSE)
  Task.detached {
    secondSignal.fail(expectedError)
    secondSignal.ready()
  }

  do {
    try await secondSignal.waitUntilReady()
    Issue.record("Expected startup failure to be reported.")
  } catch let error as POSIXError {
    #expect(error.code == expectedError.code)
  }

  let occupiedSocket = try makeListeningSocket(port: try availableLoopbackPort())
  defer { close(occupiedSocket) }
  let occupiedPort = try listeningPort(for: occupiedSocket)
  let root = try makeTemporaryDirectory()
  let databaseURL = root.appendingPathComponent("bind-failure.sqlite3")

  do {
    try await BootstrapServerRunner.runAsync(
      componentName: "BindFailureServer",
      environment: [
        BootstrapEnvironment.serverHostKey: "127.0.0.1",
        BootstrapEnvironment.serverPortKey: String(occupiedPort),
        BootstrapEnvironment.serverSQLitePathKey: databaseURL.path,
      ],
      output: { _ in },
      keepAlive: {}
    )
    Issue.record("Expected startup on an occupied port to fail.")
  } catch {}
}

@Test func serverStartupSignalAsyncWaitSupportsSuccessFailureAndConcurrentWaiters() async throws {
  let readySignal = ServerStartupSignal()
  let waiterA = Task { try await readySignal.waitUntilReady() }
  let waiterB = Task { try await readySignal.waitUntilReady() }
  Task.detached {
    readySignal.ready()
    readySignal.fail(POSIXError(.EIO))
  }
  try await waiterA.value
  try await waiterB.value

  let failedSignal = ServerStartupSignal()
  let expectedError = POSIXError(.ECONNREFUSED)
  Task.detached {
    failedSignal.fail(expectedError)
    failedSignal.ready()
  }

  do {
    try await failedSignal.waitUntilReady()
    Issue.record("Expected the first startup failure to be preserved for async waiters.")
  } catch let error as POSIXError {
    #expect(error.code == expectedError.code)
  }
}

@Test func serverStartupSignalSyncWaitCoversBlockingAndImmediateBranches() throws {
  let syncSignal = ServerStartupSignal()
  let syncWaitStarted = DispatchSemaphore(value: 0)
  let syncWaitFinished = DispatchSemaphore(value: 0)
  let syncWaitError = LockedErrorBox()
  DispatchQueue.global().async {
    syncWaitStarted.signal()
    do {
      try syncSignal.wait()
    } catch {
      syncWaitError.error = error
    }
    syncWaitFinished.signal()
  }
  #expect(syncWaitStarted.wait(timeout: .now() + 1) == .success)
  Thread.sleep(forTimeInterval: 0.05)
  #expect(syncWaitFinished.wait(timeout: .now() + 0.05) == .timedOut)
  syncSignal.ready()
  #expect(syncWaitFinished.wait(timeout: .now() + 1) == .success)
  #expect(syncWaitError.error == nil)
  try syncSignal.wait()

  let syncFailure = ServerStartupSignal()
  let expectedSyncError = POSIXError(.ETIMEDOUT)
  syncFailure.fail(expectedSyncError)
  do {
    try syncFailure.wait()
    Issue.record("Expected synchronous waiters to surface pre-signaled failures.")
  } catch let error as POSIXError {
    #expect(error.code == expectedSyncError.code)
  }
}

@Test func serverStartupSignalAsyncWaitCoversImmediateResultBranches() async throws {
  let asyncReady = ServerStartupSignal()
  asyncReady.ready()
  try await asyncReady.waitUntilReady()

  let asyncFailure = ServerStartupSignal()
  let expectedAsyncError = POSIXError(.ECONNABORTED)
  asyncFailure.fail(expectedAsyncError)
  do {
    try await asyncFailure.waitUntilReady()
    Issue.record("Expected async waiters to surface pre-signaled failures.")
  } catch let error as POSIXError {
    #expect(error.code == expectedAsyncError.code)
  }
}

@Test func startupStateUsesProvidedLaunchArguments() {
  let state = BootstrapServerRunner.startupState(
    componentName: "SymphonyServer",
    environment: [:],
    processIdentifier: 4321,
    launchArguments: ["server", "--port", "8080"],
    startedAt: Date(timeIntervalSince1970: 1_700_000_123)
  )

  #expect(state.launchArguments == ["server", "--port", "8080"])
  #expect(state.description.contains("[SymphonyServer] starting"))
  #expect(state.description.contains("[SymphonyServer] arguments=server --port 8080"))
}

@Test func startupStateUsesEnvironmentOverridesAndDescription() {
  let state = BootstrapServerRunner.startupState(
    componentName: "WorkerServer",
    environment: [
      BootstrapEnvironment.serverSchemeKey: "https",
      BootstrapEnvironment.serverHostKey: "worker.example.com",
      BootstrapEnvironment.serverPortKey: "8443",
    ],
    processIdentifier: 777,
    launchArguments: ["server"],
    startedAt: Date(timeIntervalSince1970: 1_700_000_222)
  )

  #expect(state.endpoint.displayString == "https://worker.example.com:8443")
  #expect(state.description.contains("[WorkerServer] endpoint=https://worker.example.com:8443"))
}

@Test func bootstrapEnvironmentWorkflowURLPrefersExplicitPath() throws {
  let explicitWorkflow = try makeTemporaryDirectory().appendingPathComponent("custom-workflow.md")
  try "---\nagent:\n  default_provider: codex\n---\nResolve it".write(
    to: explicitWorkflow,
    atomically: true,
    encoding: .utf8
  )

  let resolved = BootstrapEnvironment.effectiveWorkflowURL(
    environment: [BootstrapEnvironment.workflowPathKey: explicitWorkflow.path],
    workingDirectory: "/tmp/does-not-matter"
  )

  #expect(resolved == explicitWorkflow)
}

@Test func bootstrapServerRunnerStartsInjectedOrchestratorWhenWorkflowPresent() throws {
  let root = try makeTemporaryDirectory()
  let databaseURL = root.appendingPathComponent("bootstrap-orchestrator.sqlite3")
  let workflowURL = root.appendingPathComponent("WORKFLOW.md")
  try "---\npolling:\n  interval_ms: 50\n---\nResolve {{issue.title}}".write(
    to: workflowURL,
    atomically: true,
    encoding: .utf8
  )

  let engine = RecordingBootstrapEngine()
  var loadedWorkflow: WorkflowDefinition?

  try BootstrapServerRunner.run(
    componentName: "BootstrapOrchestrator",
    environment: [
      BootstrapEnvironment.serverSQLitePathKey: databaseURL.path,
      BootstrapEnvironment.workflowPathKey: workflowURL.path,
    ],
    output: { _ in },
    keepAlive: {},
    startServer: false,
    startOrchestrator: true,
    workflowLoader: { url in
      let workflow = try WorkflowParser.parse(contentsOf: url)
      loadedWorkflow = workflow
      return workflow
    },
    engineFactory: { workflow, _, _ in
      #expect(workflow.promptTemplate == "Resolve {{issue.title}}")
      return engine
    }
  )

  #expect(engine.started)
  #expect(engine.stopped)
  #expect(loadedWorkflow?.config.polling.intervalMS == 50)
}

@Test func bootstrapServerRunnerEmitsStructuredStartupAndShutdownLogs() async throws {
  let (_, logs) = try await withCapturedRuntimeLogs {
    try BootstrapServerRunner.run(
      componentName: "StructuredBootstrap",
      environment: [
        BootstrapEnvironment.serverPortKey: "8089"
      ],
      output: { _ in },
      keepAlive: {},
      startServer: false
    )
  }

  let matchingLogs = logs.filter { $0.json["component"] as? String == "StructuredBootstrap" }
  let events = matchingLogs.map { $0.json["event"] as? String }
  #expect(events.contains("bootstrap_starting"))
  #expect(events.contains("bootstrap_stopping"))

  let startingLog = try #require(
    matchingLogs.first { $0.json["event"] as? String == "bootstrap_starting" })
  #expect(startingLog.json["component"] as? String == "StructuredBootstrap")
  #expect(startingLog.json["endpoint"] as? String == "http://127.0.0.1:8089")
}

@Test func bootstrapServerRunnerReloadsInjectedOrchestratorWhenWorkflowChanges() async throws {
  let root = try makeTemporaryDirectory()
  let databaseURL = root.appendingPathComponent("bootstrap-orchestrator-reload.sqlite3")
  let workflowURL = root.appendingPathComponent("WORKFLOW.md")
  try "---\npolling:\n  interval_ms: 50\n---\nResolve {{issue.title}}".write(
    to: workflowURL,
    atomically: true,
    encoding: .utf8
  )

  let engine = RecordingBootstrapEngine()
  let allowExit = LockedFlag()

  let runTask = Task {
    try await BootstrapServerRunner.runAsync(
      componentName: "BootstrapReloadingOrchestrator",
      environment: [
        BootstrapEnvironment.serverSQLitePathKey: databaseURL.path,
        BootstrapEnvironment.workflowPathKey: workflowURL.path,
      ],
      output: { _ in },
      keepAlive: {
        while !allowExit.value {
          Thread.sleep(forTimeInterval: 0.02)
        }
      },
      startServer: false,
      startOrchestrator: true,
      workflowLoader: { url in
        try WorkflowParser.parse(contentsOf: url)
      },
      engineFactory: { _, _, _ in
        engine
      }
    )
  }

  try await waitUntil("bootstrap engine starts") {
    engine.started
  }

  try "---\npolling:\n  interval_ms: 75\n---\nUpdated prompt".write(
    to: workflowURL,
    atomically: true,
    encoding: .utf8
  )

  try await waitUntil("bootstrap workflow reload") {
    !engine.reloadedWorkflows.isEmpty
  }

  allowExit.setTrue()
  try await runTask.value

  #expect(engine.reloadedWorkflows.count == 1)
  #expect(engine.reloadedWorkflows[0].config.polling.intervalMS == 75)
  #expect(engine.reloadedWorkflows[0].promptTemplate == "Updated prompt")
  #expect(engine.stopped)
}

@Test func bootstrapServerRunnerCanStartOrchestratorUsingDefaultFactories() throws {
  let root = try makeTemporaryDirectory()
  let databaseURL = root.appendingPathComponent("bootstrap-default-orchestrator.sqlite3")
  let workflowURL = root.appendingPathComponent("WORKFLOW.md")
  try """
  ---
  tracker:
    kind: github
    endpoint: https://api.github.com/graphql
    project_owner: owner
    project_owner_type: organization
    project_number: 1
  polling:
    interval_ms: 50
  ---
  Resolve {{issue.title}}
  """.write(to: workflowURL, atomically: true, encoding: .utf8)

  try BootstrapServerRunner.run(
    componentName: "BootstrapDefaultOrchestrator",
    environment: [
      BootstrapEnvironment.serverSQLitePathKey: databaseURL.path,
      BootstrapEnvironment.workflowPathKey: workflowURL.path,
      "GITHUB_TOKEN": "token",
    ],
    output: { _ in },
    keepAlive: {},
    startServer: false,
    startOrchestrator: true
  )
}

@Test func bootstrapServerRunnerRunAsyncCanStartOrchestratorUsingDefaultFactories() async throws {
  let root = try makeTemporaryDirectory()
  let databaseURL = root.appendingPathComponent("bootstrap-default-orchestrator-async.sqlite3")
  let workflowURL = root.appendingPathComponent("WORKFLOW.md")
  try """
  ---
  tracker:
    kind: github
    endpoint: https://api.github.com/graphql
    project_owner: owner
    project_owner_type: organization
    project_number: 1
  polling:
    interval_ms: 50
  ---
  Resolve {{issue.title}}
  """.write(to: workflowURL, atomically: true, encoding: .utf8)

  try await BootstrapServerRunner.runAsync(
    componentName: "BootstrapDefaultAsyncOrchestrator",
    environment: [
      BootstrapEnvironment.serverSQLitePathKey: databaseURL.path,
      BootstrapEnvironment.workflowPathKey: workflowURL.path,
      "GITHUB_TOKEN": "token",
    ],
    output: { _ in },
    keepAlive: {},
    startServer: false,
    startOrchestrator: true
  )
}

@Test func bootstrapServerRunnerPropagatesWorkflowParseFailure() throws {
  let root = try makeTemporaryDirectory()
  let databaseURL = root.appendingPathComponent("bootstrap-invalid.sqlite3")
  let workflowURL = root.appendingPathComponent("WORKFLOW.md")
  try "---\ntracker: [\n---\nBroken".write(to: workflowURL, atomically: true, encoding: .utf8)

  #expect(throws: WorkflowConfigError.self) {
    try BootstrapServerRunner.run(
      environment: [
        BootstrapEnvironment.serverSQLitePathKey: databaseURL.path,
        BootstrapEnvironment.workflowPathKey: workflowURL.path,
      ],
      output: { _ in },
      keepAlive: {},
      startServer: false,
      startOrchestrator: true
    )
  }
}

@Test func bootstrapServerRunnerRequiresWorkflowWhenStartingOrchestrator() throws {
  let root = try makeTemporaryDirectory()
  let databaseURL = root.appendingPathComponent("bootstrap-missing-workflow.sqlite3")
  let expectedWorkflowPath = root.resolvingSymlinksInPath().appendingPathComponent("WORKFLOW.md")
    .path

  #expect(throws: WorkflowConfigError.missingWorkflowFile(expectedWorkflowPath)) {
    try BootstrapServerRunner.run(
      environment: [
        BootstrapEnvironment.serverSQLitePathKey: databaseURL.path
      ],
      workingDirectory: root.path,
      output: { _ in },
      keepAlive: {},
      startServer: false,
      startOrchestrator: true
    )
  }
}

@Test func bootstrapTrackerFactoryBuildsGitHubTrackerAdapter() throws {
  let factory = BootstrapTrackerFactory(environment: ["GITHUB_TOKEN": "test-token"])
  let tracker = try factory.make(
    TrackerConfig(
      endpoint: "https://api.github.com/graphql",
      projectOwner: "owner",
      projectOwnerType: "organization",
      projectNumber: 1
    ))

  #expect(tracker is GitHubTrackerAdapter)
}

@Test func bootstrapTrackerFactoryRejectsInvalidEndpointAndMissingAPIKey() {
  let invalidEndpointFactory = BootstrapTrackerFactory(environment: ["GITHUB_TOKEN": "token"])
  #expect(throws: GitHubTrackerError.self) {
    _ = try invalidEndpointFactory.make(TrackerConfig(endpoint: "http://[invalid"))
  }

  let missingKeyFactory = BootstrapTrackerFactory(environment: [:])
  #expect(throws: GitHubTrackerError.self) {
    _ = try missingKeyFactory.make(TrackerConfig(endpoint: "https://api.github.com/graphql"))
  }
}

@Test func bootstrapAgentRunnerFactoryBuildsAgentRunner() throws {
  let databaseURL = try makeTemporaryDirectory().appendingPathComponent(
    "bootstrap-runner-factory.sqlite3")
  let store = try SQLiteServerStateStore(databaseURL: databaseURL)
  let factory = BootstrapAgentRunnerFactory(store: store)
  let workspaceManager = WorkspaceManager(root: NSTemporaryDirectory() + UUID().uuidString)

  let runner = factory.make(workspaceManager)

  #expect(runner is AgentRunner)
}

@Test func bootstrapMakeOrchestratorEngineReturnsEngine() throws {
  let root = try makeTemporaryDirectory()
  let databaseURL = root.appendingPathComponent("bootstrap-engine.sqlite3")
  let store = try SQLiteServerStateStore(databaseURL: databaseURL)
  let workflow = WorkflowDefinition(
    config: WorkflowConfig(
      tracker: TrackerConfig(
        endpoint: "https://api.github.com/graphql",
        projectOwner: "owner",
        projectOwnerType: "organization",
        projectNumber: 1
      )
    ),
    promptTemplate: "Resolve {{issue.title}}"
  )

  let engine = try BootstrapServerRunner.makeOrchestratorEngine(
    workflow: workflow,
    environment: ["GITHUB_TOKEN": "token"],
    store: store
  )

  #expect(engine is OrchestratorEngine)
}

@Test func bootstrapMakeOrchestratorEngineStartsRealEngine() async throws {
  let root = try makeTemporaryDirectory()
  let databaseURL = root.appendingPathComponent("bootstrap-engine-start.sqlite3")
  let store = try SQLiteServerStateStore(databaseURL: databaseURL)
  let workflow = WorkflowDefinition(
    config: WorkflowConfig(
      tracker: TrackerConfig(
        endpoint: "https://api.github.com/graphql",
        projectOwner: "owner",
        projectOwnerType: "organization",
        projectNumber: 1
      ),
      polling: PollingConfig(intervalMS: 10_000)
    ),
    promptTemplate: "Resolve {{issue.title}}"
  )

  let engine = try BootstrapServerRunner.makeOrchestratorEngine(
    workflow: workflow,
    environment: ["GITHUB_TOKEN": "token"],
    store: store
  )

  try engine.start()
  defer { engine.stop() }

  try await Task.sleep(for: .milliseconds(50))
}

@Suite(.serialized)
struct BootstrapRuntimeHooksIsolationTests {
  @Test func keepAlivePolicyCanExitImmediatelyForServerCoverageRuns() {
    withBootstrapRuntimeHooksLock {
      #expect(!BootstrapKeepAlivePolicy.shouldExitAfterStartup(environment: [:]))
      #expect(
        BootstrapKeepAlivePolicy.shouldExitAfterStartup(environment: [
          BootstrapKeepAlivePolicy.exitAfterStartupKey: "1"
        ]))

      let action = BootstrapKeepAlivePolicy.makeKeepAlive(environment: [
        BootstrapKeepAlivePolicy.exitAfterStartupKey: "1"
      ])
      action()

      var didKeepAlive = false
      let previousKeepAlive = BootstrapRuntimeHooks.keepAliveOverride
      BootstrapRuntimeHooks.keepAliveOverride = { didKeepAlive = true }
      defer { BootstrapRuntimeHooks.keepAliveOverride = previousKeepAlive }

      let blockingAction = BootstrapKeepAlivePolicy.makeKeepAlive(environment: [:])
      blockingAction()
      #expect(didKeepAlive)
    }
  }

  @Test func bootstrapServerRunnerRunUsesDefaultHooksAndFallsBackToDefaultPort() throws {
    try withBootstrapRuntimeHooksLock {
      var lines = [String]()
      var didKeepAlive = false
      let previousOutput = BootstrapRuntimeHooks.outputOverride
      let previousKeepAlive = BootstrapRuntimeHooks.keepAliveOverride
      BootstrapRuntimeHooks.outputOverride = { lines.append($0) }
      BootstrapRuntimeHooks.keepAliveOverride = { didKeepAlive = true }
      defer {
        BootstrapRuntimeHooks.outputOverride = previousOutput
        BootstrapRuntimeHooks.keepAliveOverride = previousKeepAlive
      }

      try BootstrapServerRunner.run(
        componentName: "DefaultHookServer",
        environment: [
          BootstrapEnvironment.serverPortKey: "abc"
        ],
        processIdentifier: 88,
        launchArguments: ["server"],
        startedAt: Date(timeIntervalSince1970: 1_700_000_400),
        startServer: false
      )

      #expect(didKeepAlive)
      #expect(lines.contains("[DefaultHookServer] endpoint=http://127.0.0.1:8080"))
      #expect(
        BootstrapEnvironment.effectiveServerEndpoint(environment: [:]).host == "127.0.0.1")
      #expect(
        BootstrapEnvironment.effectiveServerEndpoint(environment: [
          BootstrapEnvironment.serverPortKey: "abc"
        ]).port == 8080)
    }
  }

  @Test func bootstrapRuntimeHooksDefaultBranchesAndEndpointFallbacks() {
    withBootstrapRuntimeHooksLock {
      let previousOutput = BootstrapRuntimeHooks.outputOverride
      let previousKeepAliveOverride = BootstrapRuntimeHooks.keepAliveOverride
      let previousRunLoopRunner = BootstrapRuntimeHooks.runLoopRunnerOverride
      BootstrapRuntimeHooks.outputOverride = nil

      var didDefaultRunLoop = false
      var didCustomRunLoop = false
      BootstrapRuntimeHooks.keepAliveOverride = nil
      BootstrapRuntimeHooks.runLoopRunnerOverride = { didCustomRunLoop = true }
      BootstrapRuntimeHooks.withDefaultRunLoopAction { didDefaultRunLoop = true }
      defer {
        BootstrapRuntimeHooks.outputOverride = previousOutput
        BootstrapRuntimeHooks.keepAliveOverride = previousKeepAliveOverride
        BootstrapRuntimeHooks.runLoopRunnerOverride = previousRunLoopRunner
        BootstrapRuntimeHooks.resetDefaultRunLoopAction()
      }

      BootstrapRuntimeHooks.defaultOutput("[SymphonyServer] probe")
      BootstrapRuntimeHooks.keepAlive()
      #expect(didCustomRunLoop)

      BootstrapRuntimeHooks.runLoopRunnerOverride = nil
      BootstrapRuntimeHooks.keepAlive()
      #expect(didDefaultRunLoop)

      let normalized = BootstrapServerEndpoint(scheme: " ", host: " ", port: 0)
      #expect(normalized == .defaultEndpoint)
      #expect(normalized.description == "http://127.0.0.1:8080")
      #expect(BootstrapServerEndpoint.defaultEndpoint.host == "127.0.0.1")

      let fallbackEndpoint = BootstrapServerEndpoint(
        scheme: "http", host: "bad host", port: 8080)
      #expect(fallbackEndpoint.url == nil)
      #expect(fallbackEndpoint.displayString == "http://bad host:8080")
      #expect(fallbackEndpoint.description == "http://bad host:8080")
    }
  }

  @Test func bootstrapRuntimeHooksDefaultRunLoopFallbackCanBeExercisedDirectly() {
    withBootstrapRuntimeHooksLock {
      let previousKeepAliveOverride = BootstrapRuntimeHooks.keepAliveOverride
      let previousRunLoopRunner = BootstrapRuntimeHooks.runLoopRunnerOverride
      BootstrapRuntimeHooks.keepAliveOverride = nil
      BootstrapRuntimeHooks.runLoopRunnerOverride = nil
      defer {
        BootstrapRuntimeHooks.keepAliveOverride = previousKeepAliveOverride
        BootstrapRuntimeHooks.runLoopRunnerOverride = previousRunLoopRunner
      }

      var didReachStopBlock = false
      let runLoop = CFRunLoopGetCurrent()
      CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) {
        didReachStopBlock = true
        CFRunLoopStop(runLoop)
      }
      CFRunLoopWakeUp(runLoop)
      BootstrapRuntimeHooks.keepAlive()

      #expect(didReachStopBlock)
    }
  }

  @Test func bootstrapRuntimeHooksKeepAliveUsesExplicitOverrideFirst() {
    withBootstrapRuntimeHooksLock {
      let previousKeepAliveOverride = BootstrapRuntimeHooks.keepAliveOverride
      let previousRunLoopRunner = BootstrapRuntimeHooks.runLoopRunnerOverride
      var didKeepAlive = false
      var didRunLoop = false
      BootstrapRuntimeHooks.keepAliveOverride = { didKeepAlive = true }
      BootstrapRuntimeHooks.runLoopRunnerOverride = { didRunLoop = true }
      defer {
        BootstrapRuntimeHooks.keepAliveOverride = previousKeepAliveOverride
        BootstrapRuntimeHooks.runLoopRunnerOverride = previousRunLoopRunner
      }

      BootstrapRuntimeHooks.keepAlive()

      #expect(didKeepAlive)
      #expect(!didRunLoop)
    }
  }
}

@Test
func bootstrapEnvironmentSQLitePathFallsBackToHomeDirectoryWhenApplicationSupportIsUnavailable() {
  let fileManager = EmptyApplicationSupportFileManager(
    homeDirectory: URL(fileURLWithPath: "/tmp/bootstrap-home", isDirectory: true))

  let sqlitePath = BootstrapEnvironment.effectiveSQLitePath(
    environment: [:],
    fileManager: fileManager
  )

  #expect(
    sqlitePath.path == "/tmp/bootstrap-home/Library/Application Support/symphony/symphony.sqlite3")
}

@Test func builtServerExecutableStartsAndExitsWhenRequested() throws {
  let executable = builtProductsDirectory().appendingPathComponent("SymphonyServer")
  #expect(FileManager.default.isExecutableFile(atPath: executable.path))

  let process = Process()
  let output = Pipe()
  process.executableURL = executable
  var environment = ProcessInfo.processInfo.environment
  environment[BootstrapKeepAlivePolicy.exitAfterStartupKey] = "1"
  environment[BootstrapEnvironment.serverSchemeKey] = "https"
  environment[BootstrapEnvironment.serverHostKey] = "server.example.com"
  environment[BootstrapEnvironment.serverPortKey] = "9555"
  process.environment = environment
  process.standardOutput = output
  process.standardError = output
  try process.run()
  process.waitUntilExit()

  let transcript = String(
    decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
  #expect(process.terminationStatus == 0)
  #expect(transcript.contains("[SymphonyServer] starting"))
  #expect(transcript.contains("[SymphonyServer] endpoint=https://server.example.com:9555"))
}

@Test func builtServerExecutableServesHealthEndpointUntilTerminated() async throws {
  let executable = builtProductsDirectory().appendingPathComponent("SymphonyServer")
  #expect(FileManager.default.isExecutableFile(atPath: executable.path))
  let port = try availableLoopbackPort()

  let process = Process()
  let output = Pipe()
  process.executableURL = executable
  var environment = ProcessInfo.processInfo.environment
  environment[BootstrapEnvironment.serverHostKey] = "127.0.0.1"
  environment[BootstrapEnvironment.serverPortKey] = String(port)
  process.environment = environment
  process.standardOutput = output
  process.standardError = output
  try process.run()

  do {
    let url = try #require(URL(string: "http://127.0.0.1:\(port)/api/v1/health"))
    let session = URLSession(configuration: .ephemeral)
    var responseData: Data?

    for _ in 0..<30 {
      do {
        let (data, response) = try await session.data(from: url)
        let httpResponse = try #require(response as? HTTPURLResponse)
        if httpResponse.statusCode == 200 {
          responseData = data
          break
        }
      } catch {
        try await Task.sleep(for: .milliseconds(100))
      }
    }

    let data = try #require(responseData)
    let health = try JSONDecoder().decode(HealthResponse.self, from: data)
    #expect(health.status == "ok")
    #expect(health.trackerKind == "github")
  } catch {
    try await terminateProcessIfRunning(process)
    throw error
  }

  try await terminateProcessIfRunning(process)
}

@Test func builtServerExecutablePrintsFailureAndExitsForInvalidSQLitePath() throws {
  let executable = builtProductsDirectory().appendingPathComponent("SymphonyServer")
  #expect(FileManager.default.isExecutableFile(atPath: executable.path))

  let invalidDatabaseURL = FileManager.default.temporaryDirectory.appendingPathComponent(
    UUID().uuidString, isDirectory: true)
  try FileManager.default.createDirectory(at: invalidDatabaseURL, withIntermediateDirectories: true)

  let process = Process()
  let output = Pipe()
  process.executableURL = executable
  var environment = ProcessInfo.processInfo.environment
  environment[BootstrapEnvironment.serverSQLitePathKey] = invalidDatabaseURL.path
  process.environment = environment
  process.standardOutput = output
  process.standardError = output
  try process.run()
  process.waitUntilExit()

  let transcript = String(
    decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
  #expect(process.terminationStatus == 1)
  #expect(transcript.contains("[SymphonyServer] failed to start:"))
  #expect(transcript.contains(invalidDatabaseURL.path))
}

private func builtProductsDirectory() -> URL {
  Bundle(for: BundleLocator.self).bundleURL.deletingLastPathComponent()
}

private final class BundleLocator {}

private let bootstrapRuntimeHooksLock = NSLock()

private func withBootstrapRuntimeHooksLock(_ body: () throws -> Void) rethrows {
  bootstrapRuntimeHooksLock.lock()
  defer { bootstrapRuntimeHooksLock.unlock() }
  try body()
}

private final class EmptyApplicationSupportFileManager: FileManager, @unchecked Sendable {
  private let testHomeDirectory: URL

  init(homeDirectory: URL) {
    self.testHomeDirectory = homeDirectory
    super.init()
  }

  override func urls(
    for directory: FileManager.SearchPathDirectory, in domainMask: FileManager.SearchPathDomainMask
  ) -> [URL] {
    []
  }

  override var homeDirectoryForCurrentUser: URL {
    testHomeDirectory
  }
}

private final class LockedErrorBox: @unchecked Sendable {
  private let lock = NSLock()
  private var storage: Error?

  var error: Error? {
    get { lock.withLock { storage } }
    set { lock.withLock { storage = newValue } }
  }
}

private final class RecordingBootstrapEngine: BootstrapEngineRunning, BootstrapWorkflowReloading,
  @unchecked Sendable
{
  private let lock = NSLock()
  private var _started = false
  private var _stopped = false
  private var _reloadedWorkflows: [WorkflowDefinition] = []

  var started: Bool {
    lock.withLock { _started }
  }

  var stopped: Bool {
    lock.withLock { _stopped }
  }

  var reloadedWorkflows: [WorkflowDefinition] {
    lock.withLock { _reloadedWorkflows }
  }

  func start() throws {
    lock.withLock { _started = true }
  }

  func stop() {
    lock.withLock { _stopped = true }
  }

  func reloadWorkflow(_ workflow: WorkflowDefinition) {
    lock.withLock { _reloadedWorkflows.append(workflow) }
  }
}

private func makeTemporaryDirectory() throws -> URL {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    UUID().uuidString, isDirectory: true)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  return root
}

private func availableLoopbackPort() throws -> Int {
  let descriptor = socket(AF_INET, SOCK_STREAM, 0)
  guard descriptor >= 0 else {
    throw POSIXError(.EIO)
  }
  defer { close(descriptor) }

  var address = sockaddr_in()
  address.sin_len = UInt8(MemoryLayout<sockaddr_in>.stride)
  address.sin_family = sa_family_t(AF_INET)
  address.sin_port = in_port_t(0).bigEndian
  address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

  let bindResult = withUnsafePointer(to: &address) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
      Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.stride))
    }
  }
  guard bindResult == 0 else {
    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
  }

  var length = socklen_t(MemoryLayout<sockaddr_in>.stride)
  let nameResult = withUnsafeMutablePointer(to: &address) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
      getsockname(descriptor, $0, &length)
    }
  }
  guard nameResult == 0 else {
    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
  }

  return Int(UInt16(bigEndian: address.sin_port))
}

private func makeListeningSocket(port: Int) throws -> Int32 {
  let descriptor = socket(AF_INET, SOCK_STREAM, 0)
  guard descriptor >= 0 else {
    throw POSIXError(.EIO)
  }

  var reuseAddress = 1
  setsockopt(
    descriptor, SOL_SOCKET, SO_REUSEADDR, &reuseAddress, socklen_t(MemoryLayout<Int32>.size))

  var address = sockaddr_in()
  address.sin_len = UInt8(MemoryLayout<sockaddr_in>.stride)
  address.sin_family = sa_family_t(AF_INET)
  address.sin_port = in_port_t(UInt16(port).bigEndian)
  address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

  let bindResult = withUnsafePointer(to: &address) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
      Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.stride))
    }
  }
  guard bindResult == 0 else {
    close(descriptor)
    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
  }

  guard listen(descriptor, 1) == 0 else {
    close(descriptor)
    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
  }

  return descriptor
}

private func listeningPort(for descriptor: Int32) throws -> Int {
  var address = sockaddr_in()
  var length = socklen_t(MemoryLayout<sockaddr_in>.stride)
  let result = withUnsafeMutablePointer(to: &address) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
      getsockname(descriptor, $0, &length)
    }
  }
  guard result == 0 else {
    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
  }

  return Int(UInt16(bigEndian: address.sin_port))
}

private final class LockedFlag: @unchecked Sendable {
  private let lock = NSLock()
  private var storedValue = false

  var value: Bool {
    lock.lock()
    defer { lock.unlock() }
    return storedValue
  }

  func setTrue() {
    lock.lock()
    storedValue = true
    lock.unlock()
  }
}

private func waitUntil(
  _ description: String,
  timeout: Duration = .seconds(2),
  interval: Duration = .milliseconds(20),
  condition: @escaping @Sendable () async -> Bool
) async throws {
  let deadline = ContinuousClock.now + timeout
  while ContinuousClock.now < deadline {
    if await condition() {
      return
    }
    try await Task.sleep(for: interval)
  }

  Issue.record("Timed out waiting for \(description).")
  throw POSIXError(.ETIMEDOUT)
}

private func terminateProcessIfRunning(
  _ process: Process,
  timeout: Duration = .seconds(2)
) async throws {
  guard process.isRunning else { return }

  process.terminate()
  do {
    try await waitUntil(
      "process \(process.processIdentifier) exits after SIGTERM", timeout: timeout
    ) {
      !process.isRunning
    }
  } catch {
    guard process.isRunning else { return }
    kill(process.processIdentifier, SIGKILL)
    try await waitUntil(
      "process \(process.processIdentifier) exits after SIGKILL", timeout: timeout
    ) {
      !process.isRunning
    }
  }
}
