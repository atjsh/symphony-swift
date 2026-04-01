import CoreFoundation
import Darwin
import Foundation
import SymphonyShared
import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore

@Test func bootstrapServerRunnerReloadsInjectedOrchestratorWhenWorkflowChanges() async throws {
  let root = try bootstrapMakeTemporaryDirectory()
  let databaseURL = root.appendingPathComponent("bootstrap-orchestrator-reload.sqlite3")
  let workflowURL = root.appendingPathComponent("WORKFLOW.md")
  try "---\npolling:\n  interval_ms: 50\n---\nResolve {{issue.title}}".write(
    to: workflowURL,
    atomically: true,
    encoding: .utf8
  )

  let engine = RecordingBootstrapEngine()
  let allowExit = BootstrapLockedFlag()

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

  try await bootstrapWaitUntil("bootstrap engine starts") {
    engine.started
  }

  try "---\npolling:\n  interval_ms: 75\n---\nUpdated prompt".write(
    to: workflowURL,
    atomically: true,
    encoding: .utf8
  )

  try await bootstrapWaitUntil("bootstrap workflow reload") {
    !engine.reloadedWorkflows.isEmpty
  }

  allowExit.setTrue()
  try await runTask.value

  #expect(engine.reloadedWorkflows.count == 1)
  #expect(engine.reloadedWorkflows[0].config.polling.intervalMS == 75)
  #expect(engine.reloadedWorkflows[0].promptTemplate == "Updated prompt")
  #expect(engine.stopped)
}

@Test func bootstrapServerRunnerWiresRefreshEndpointForRefreshableInjectedOrchestrator()
  async throws
{
  let root = try bootstrapMakeTemporaryDirectory()
  let databaseURL = root.appendingPathComponent("bootstrap-refreshable.sqlite3")
  let workflowURL = root.appendingPathComponent("WORKFLOW.md")
  try "---\npolling:\n  interval_ms: 50\n---\nResolve {{issue.title}}".write(
    to: workflowURL,
    atomically: true,
    encoding: .utf8
  )

  let engine = RefreshableRecordingBootstrapEngine()
  let port = try bootstrapAvailableLoopbackPort()
  let keepAliveEntered = BootstrapLockedFlag()
  let allowReturn = DispatchSemaphore(value: 0)

  let runTask = Task {
    try await BootstrapServerRunner.runAsync(
      componentName: "BootstrapRefreshableOrchestrator",
      environment: [
        BootstrapEnvironment.serverHostKey: "127.0.0.1",
        BootstrapEnvironment.serverPortKey: String(port),
        BootstrapEnvironment.serverSQLitePathKey: databaseURL.path,
        BootstrapEnvironment.workflowPathKey: workflowURL.path,
      ],
      output: { _ in },
      keepAlive: {
        keepAliveEntered.setTrue()
        allowReturn.wait()
      },
      startServer: true,
      startOrchestrator: true,
      workflowLoader: { url in
        try WorkflowParser.parse(contentsOf: url)
      },
      engineFactory: { _, _, _ in
        engine
      }
    )
  }
  defer { allowReturn.signal() }

  try await bootstrapWaitUntil("bootstrap refreshable server enters keepAlive", timeout: .seconds(5)) {
    keepAliveEntered.value
  }

  let refreshURL = try #require(URL(string: "http://127.0.0.1:\(port)/api/v1/refresh"))
  var request = URLRequest(url: refreshURL)
  request.httpMethod = "POST"
  let (_, response) = try await URLSession(configuration: .ephemeral).data(for: request)
  let httpResponse = try #require(response as? HTTPURLResponse)
  #expect(httpResponse.statusCode == 202)

  try await bootstrapWaitUntil("bootstrap refresh callback invoked") {
    engine.refreshRequests == 1
  }

  allowReturn.signal()
  try await runTask.value

  #expect(engine.started)
  #expect(engine.stopped)
}

@Test func bootstrapServerRunnerCanStartOrchestratorUsingDefaultFactories() throws {
  let root = try bootstrapMakeTemporaryDirectory()
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
  let root = try bootstrapMakeTemporaryDirectory()
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
  let root = try bootstrapMakeTemporaryDirectory()
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
  let root = try bootstrapMakeTemporaryDirectory()
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
  let databaseURL = try bootstrapMakeTemporaryDirectory().appendingPathComponent(
    "bootstrap-runner-factory.sqlite3")
  let store = try SQLiteServerStateStore(databaseURL: databaseURL)
  let factory = BootstrapAgentRunnerFactory(store: store)
  let workspaceManager = WorkspaceManager(root: NSTemporaryDirectory() + UUID().uuidString)

  let runner = factory.make(workspaceManager)

  #expect(runner is AgentRunner)
}

@Test func bootstrapMakeOrchestratorEngineReturnsEngine() throws {
  let root = try bootstrapMakeTemporaryDirectory()
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
  let root = try bootstrapMakeTemporaryDirectory()
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

