import Foundation
import SymphonyServerCore
import SymphonyShared

// MARK: - Bootstrap Server Runner

public enum BootstrapServerRunner {
  public static func run(
    componentName: String = "SymphonyServer",
    environment: [String: String] = ProcessInfo.processInfo.environment,
    workingDirectory: String = FileManager.default.currentDirectoryPath,
    processIdentifier: Int32 = getpid(),
    launchArguments: [String] = ProcessInfo.processInfo.arguments,
    startedAt: Date = Date(),
    output: ((String) -> Void)? = nil,
    keepAlive: (() -> Void)? = nil,
    startServer: Bool = true,
    startOrchestrator: Bool? = nil,
    workflowLoader: (URL) throws -> WorkflowDefinition = {
      try WorkflowParser.parse(contentsOf: $0)
    },
    engineFactory: (WorkflowDefinition, [String: String], SQLiteServerStateStore) throws ->
      any BootstrapEngineRunning = {
        try makeOrchestratorEngine(workflow: $0, environment: $1, store: $2)
      }
  ) throws {
    let runtime = try prepareRuntime(
      componentName: componentName,
      environment: environment,
      workingDirectory: workingDirectory,
      processIdentifier: processIdentifier,
      launchArguments: launchArguments,
      startedAt: startedAt,
      output: output,
      keepAlive: keepAlive,
      startServer: startServer,
      startOrchestrator: startOrchestrator,
      workflowLoader: workflowLoader,
      engineFactory: engineFactory
    )
    defer { cleanupRuntime(runtime) }

    try runtime.startupSignal?.wait()
    runtime.keepAlive()
  }

  public static func runAsync(
    componentName: String = "SymphonyServer",
    environment: [String: String] = ProcessInfo.processInfo.environment,
    workingDirectory: String = FileManager.default.currentDirectoryPath,
    processIdentifier: Int32 = getpid(),
    launchArguments: [String] = ProcessInfo.processInfo.arguments,
    startedAt: Date = Date(),
    output: ((String) -> Void)? = nil,
    keepAlive: (() -> Void)? = nil,
    startServer: Bool = true,
    startOrchestrator: Bool? = nil,
    workflowLoader: (URL) throws -> WorkflowDefinition = {
      try WorkflowParser.parse(contentsOf: $0)
    },
    engineFactory: (WorkflowDefinition, [String: String], SQLiteServerStateStore) throws ->
      any BootstrapEngineRunning = {
        try makeOrchestratorEngine(workflow: $0, environment: $1, store: $2)
      }
  ) async throws {
    let runtime = try prepareRuntime(
      componentName: componentName,
      environment: environment,
      workingDirectory: workingDirectory,
      processIdentifier: processIdentifier,
      launchArguments: launchArguments,
      startedAt: startedAt,
      output: output,
      keepAlive: keepAlive,
      startServer: startServer,
      startOrchestrator: startOrchestrator,
      workflowLoader: workflowLoader,
      engineFactory: engineFactory
    )
    defer { cleanupRuntime(runtime) }

    try await runtime.startupSignal?.waitUntilReady()
    runtime.keepAlive()
  }

  private static func prepareRuntime(
    componentName: String,
    environment: [String: String],
    workingDirectory: String,
    processIdentifier: Int32,
    launchArguments: [String],
    startedAt: Date,
    output: ((String) -> Void)?,
    keepAlive: (() -> Void)?,
    startServer: Bool,
    startOrchestrator: Bool?,
    workflowLoader: (URL) throws -> WorkflowDefinition,
    engineFactory: (WorkflowDefinition, [String: String], SQLiteServerStateStore) throws ->
      any BootstrapEngineRunning
  ) throws -> PreparedBootstrapRuntime {
    let output = output ?? BootstrapRuntimeHooks.defaultOutput
    let keepAlive = keepAlive ?? BootstrapRuntimeHooks.keepAlive
    let shouldStartOrchestrator = startOrchestrator ?? startServer
    let state = BootstrapStartupState.current(
      componentName: componentName,
      environment: environment,
      processIdentifier: processIdentifier,
      launchArguments: launchArguments,
      startedAt: startedAt
    )

    state.startupLogLines.forEach(output)
    RuntimeLogger.log(
      level: .info,
      event: "bootstrap_starting",
      context: RuntimeLogContext(
        metadata: [
          "component": componentName,
          "endpoint": state.endpoint.displayString,
          "pid": String(processIdentifier),
        ]
      )
    )

    var serverTask: Task<Void, Error>?
    var orchestratorEngine: (any BootstrapEngineRunning)?
    var workflowReloader: WorkflowReloader?
    var startupSignal: ServerStartupSignal?
    let analysisConfigStore = WorkflowAnalysisConfigStore(config: .defaults)
    if startServer || shouldStartOrchestrator {
      let databaseURL = BootstrapEnvironment.effectiveSQLitePath(environment: environment)
      let liveLogHub = LiveLogHub()
      let store = try SQLiteServerStateStore(
        databaseURL: databaseURL,
        eventObserver: makeEventObserver(liveLogHub: liveLogHub)
      )

      if shouldStartOrchestrator {
        let workflowURL: URL?
        if startOrchestrator == true {
          workflowURL = try BootstrapEnvironment.requiredWorkflowURL(
            environment: environment,
            workingDirectory: workingDirectory
          )
        } else {
          workflowURL = BootstrapEnvironment.effectiveWorkflowURL(
            environment: environment,
            workingDirectory: workingDirectory
          )
        }

        if let workflowURL {
          let workflow = try workflowLoader(workflowURL)
          analysisConfigStore.update(workflow.config.analysis)
          let engine = try engineFactory(workflow, environment, store)
          try engine.start()
          orchestratorEngine = engine

          if let reloadingEngine = engine as? any BootstrapWorkflowReloading {
            let reloader = WorkflowReloader(workflowPath: workflowURL.path) { workflow in
              analysisConfigStore.update(workflow.config.analysis)
              reloadingEngine.reloadWorkflow(workflow)
            }
            try reloader.startWatching()
            workflowReloader = reloader
          }
        }
      }

      if startServer {
        let refresh = (orchestratorEngine as? any OrchestratorEngineRefreshing)?.requestRefresh
        let progressReports = CachedIssueProgressReportGenerator(
          cacheDirectoryURL: databaseURL
            .deletingLastPathComponent()
            .appendingPathComponent("progress-report-cache", isDirectory: true),
          analysisConfigProvider: { analysisConfigStore.current }
        )
        let api = SymphonyHTTPAPI(
          store: store,
          version: "1.0.0",
          trackerKind: "github",
          progressReports: progressReports,
          refresh: refresh
        )
        let server = SymphonyHTTPServer(
          endpoint: state.endpoint,
          store: store,
          api: api,
          liveLogHub: liveLogHub
        )
        let startup = ServerStartupSignal()
        serverTask = Task.detached {
          do {
            try await server.run {
              startup.ready()
            }
          } catch {
            startup.fail(error)
            throw error
          }
        }
        startupSignal = startup
      }
    }

    return PreparedBootstrapRuntime(
      componentName: componentName,
      endpoint: state.endpoint.displayString,
      keepAlive: keepAlive,
      orchestratorEngine: orchestratorEngine,
      workflowReloader: workflowReloader,
      serverTask: serverTask,
      startupSignal: startupSignal
    )
  }

  private static func cleanupRuntime(_ runtime: PreparedBootstrapRuntime) {
    RuntimeLogger.log(
      level: .info,
      event: "bootstrap_stopping",
      context: RuntimeLogContext(
        metadata: [
          "component": runtime.componentName,
          "endpoint": runtime.endpoint,
        ]
      )
    )
    runtime.workflowReloader?.stopWatching()
    runtime.orchestratorEngine?.stop()
    runtime.serverTask?.cancel()
  }

  public static func startupState(
    componentName: String = "SymphonyServer",
    environment: [String: String] = ProcessInfo.processInfo.environment,
    processIdentifier: Int32 = getpid(),
    launchArguments: [String] = ProcessInfo.processInfo.arguments,
    startedAt: Date = Date()
  ) -> BootstrapStartupState {
    BootstrapStartupState.current(
      componentName: componentName,
      environment: environment,
      processIdentifier: processIdentifier,
      launchArguments: launchArguments,
      startedAt: startedAt
    )
  }

  static func makeEventObserver(liveLogHub: LiveLogHub) -> @Sendable (AgentRawEvent) -> Void {
    { event in
      Task {
        await liveLogHub.publish(event)
      }
    }
  }

  public static func makeOrchestratorEngine(
    workflow: WorkflowDefinition,
    environment: [String: String],
    store: SQLiteServerStateStore,
    observer: any EngineEventObserving = NoOpEngineEventObserver()
  ) throws -> any BootstrapEngineRunning {
    let trackerFactory = BootstrapTrackerFactory(environment: environment)
    let agentRunnerFactory = BootstrapAgentRunnerFactory(store: store)

    return OrchestratorEngine(
      config: workflow.config,
      trackerFactory: trackerFactory.make,
      agentRunnerFactory: agentRunnerFactory.make,
      promptTemplate: workflow.promptTemplate,
      observer: observer,
      stateStore: store
    )
  }
}

private struct PreparedBootstrapRuntime {
  let componentName: String
  let endpoint: String
  let keepAlive: () -> Void
  let orchestratorEngine: (any BootstrapEngineRunning)?
  let workflowReloader: WorkflowReloader?
  let serverTask: Task<Void, Error>?
  let startupSignal: ServerStartupSignal?
}

// MARK: - Server Startup Signal

final class ServerStartupSignal: @unchecked Sendable {
  private let lock = NSLock()
  private var result: Result<Void, any Error>?
  private var syncWaiters = [DispatchSemaphore]()
  private var asyncWaiters = [CheckedContinuation<Void, any Error>]()

  func ready() {
    signal(.success(()))
  }

  func fail(_ error: Error) {
    signal(.failure(error))
  }

  func wait() throws {
    let semaphore: DispatchSemaphore
    lock.lock()
    if let result {
      lock.unlock()
      return try result.get()
    }
    semaphore = DispatchSemaphore(value: 0)
    syncWaiters.append(semaphore)
    lock.unlock()

    semaphore.wait()

    lock.lock()
    let result = self.result
    lock.unlock()
    try result?.get()
  }

  func waitUntilReady() async throws {
    try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<Void, any Error>) in
      lock.lock()
      if let currentResult = result {
        lock.unlock()
        continuation.resume(with: currentResult)
      } else {
        asyncWaiters.append(continuation)
        lock.unlock()
      }
    }
  }

  private func signal(_ result: Result<Void, any Error>) {
    lock.lock()
    guard self.result == nil else {
      lock.unlock()
      return
    }
    self.result = result
    let syncWaiters = self.syncWaiters
    self.syncWaiters.removeAll(keepingCapacity: false)
    let asyncWaiters = self.asyncWaiters
    self.asyncWaiters.removeAll(keepingCapacity: false)
    lock.unlock()

    syncWaiters.forEach { $0.signal() }
    asyncWaiters.forEach { $0.resume(with: result) }
  }
}
