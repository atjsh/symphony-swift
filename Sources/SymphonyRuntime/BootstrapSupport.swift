import Foundation
import SymphonyShared

enum BootstrapRuntimeHooks {
  private final class Storage: @unchecked Sendable {
    private static func defaultRunLoopAction() {
      RunLoop.main.run()
    }

    private let lock = NSLock()
    private var output: ((String) -> Void)?
    private var keepAlive: (() -> Void)?
    private var runLoopOverride: (() -> Void)?
    private var defaultRunLoopOverride: (() -> Void)?

    var outputOverride: ((String) -> Void)? {
      get {
        lock.lock()
        defer { lock.unlock() }
        return output
      }
      set {
        lock.lock()
        output = newValue
        lock.unlock()
      }
    }

    var keepAliveOverride: (() -> Void)? {
      get {
        lock.lock()
        defer { lock.unlock() }
        return keepAlive
      }
      set {
        lock.lock()
        keepAlive = newValue
        lock.unlock()
      }
    }

    var runLoopRunnerOverride: (() -> Void)? {
      get {
        lock.lock()
        defer { lock.unlock() }
        return runLoopOverride
      }
      set {
        lock.lock()
        runLoopOverride = newValue
        lock.unlock()
      }
    }

    func setDefaultRunLoopActionOverride(_ action: (() -> Void)?) {
      lock.lock()
      defaultRunLoopOverride = action
      lock.unlock()
    }

    func runDefaultRunLoopAction() {
      let override: (() -> Void)?
      lock.lock()
      override = defaultRunLoopOverride
      lock.unlock()
      if let override {
        override()
      } else {
        Storage.defaultRunLoopAction()
      }
    }
  }

  private static let storage = Storage()

  static var outputOverride: ((String) -> Void)? {
    get { storage.outputOverride }
    set { storage.outputOverride = newValue }
  }

  static var keepAliveOverride: (() -> Void)? {
    get { storage.keepAliveOverride }
    set { storage.keepAliveOverride = newValue }
  }

  static var runLoopRunnerOverride: (() -> Void)? {
    get { storage.runLoopRunnerOverride }
    set { storage.runLoopRunnerOverride = newValue }
  }

  static func withDefaultRunLoopAction(_ action: @escaping () -> Void) {
    storage.setDefaultRunLoopActionOverride(action)
  }

  static func resetDefaultRunLoopAction() {
    storage.setDefaultRunLoopActionOverride(nil)
  }

  static func defaultOutput(_ line: String) {
    if let outputOverride {
      outputOverride(line)
    } else {
      print(line)
    }
  }

  @inline(never)
  static func keepAlive() {
    if let keepAliveOverride {
      keepAliveOverride()
    } else if let runLoopRunnerOverride {
      runLoopRunnerOverride()
    } else {
      storage.runDefaultRunLoopAction()
    }
  }
}

public enum BootstrapEnvironment {
  public static let serverSchemeKey = "SYMPHONY_SERVER_SCHEME"
  public static let serverHostKey = "SYMPHONY_SERVER_HOST"
  public static let serverPortKey = "SYMPHONY_SERVER_PORT"
  public static let serverSQLitePathKey = "SYMPHONY_STORAGE_SQLITE_PATH"
  public static let workflowPathKey = "SYMPHONY_WORKFLOW_PATH"

  public static func effectiveServerEndpoint(
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> BootstrapServerEndpoint {
    BootstrapServerEndpoint.resolved(from: environment)
  }

  public static func effectiveSQLitePath(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    fileManager: FileManager = .default
  ) -> URL {
    if let rawValue = environment[serverSQLitePathKey]?.trimmingCharacters(
      in: .whitespacesAndNewlines),
      !rawValue.isEmpty
    {
      return URL(fileURLWithPath: NSString(string: rawValue).expandingTildeInPath)
    }

    let applicationSupport =
      fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent(
        "Library/Application Support", isDirectory: true)
    return
      applicationSupport
      .appendingPathComponent("symphony", isDirectory: true)
      .appendingPathComponent("symphony.sqlite3", isDirectory: false)
  }

  public static func effectiveWorkflowURL(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    workingDirectory: String = FileManager.default.currentDirectoryPath
  ) -> URL? {
    if let explicitPath = environment[workflowPathKey]?.trimmingCharacters(
      in: .whitespacesAndNewlines),
      !explicitPath.isEmpty
    {
      let expanded = NSString(string: explicitPath).expandingTildeInPath
      return URL(fileURLWithPath: expanded)
    }

    return WorkflowParser.discover(workingDirectory: workingDirectory)
  }

  public static func requiredWorkflowURL(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    workingDirectory: String = FileManager.default.currentDirectoryPath
  ) throws -> URL {
    if let workflowURL = effectiveWorkflowURL(
      environment: environment,
      workingDirectory: workingDirectory
    ) {
      return workflowURL
    }

    throw WorkflowConfigError.missingWorkflowFile(
      URL(fileURLWithPath: workingDirectory)
        .appendingPathComponent("WORKFLOW.md", isDirectory: false)
        .path
    )
  }
}

public protocol BootstrapEngineRunning: Sendable {
  func start() throws
  func stop()
}

extension OrchestratorEngine: BootstrapEngineRunning {}

public struct BootstrapTrackerFactory: Sendable {
  public let environment: [String: String]

  public init(environment: [String: String]) {
    self.environment = environment
  }

  public func make(_ tracker: TrackerConfig) throws -> any TrackerAdapting {
    guard let endpoint = URL(string: tracker.endpoint) else {
      throw GitHubTrackerError.invalidEndpoint(tracker.endpoint)
    }

    let apiKey =
      try ConfigResolver.resolveAPIKey(tracker.apiKey, environment: environment)
      ?? environment["GITHUB_TOKEN"]
    guard let apiKey, !apiKey.isEmpty else {
      throw GitHubTrackerError.missingAPIKey
    }

    let transport = URLSessionGraphQLTransport(endpoint: endpoint, apiKey: apiKey)
    return GitHubTrackerAdapter(transport: transport, config: tracker)
  }
}

public struct BootstrapAgentRunnerFactory: Sendable {
  public let store: SQLiteServerStateStore

  public init(store: SQLiteServerStateStore) {
    self.store = store
  }

  public func make(_ workspaceManager: any WorkspaceManaging) -> any AgentRunning {
    AgentRunner(
      workspaceManager: workspaceManager,
      processLauncher: DefaultProcessLauncher(),
      eventSink: SQLiteAgentRunEventSink(store: store)
    )
  }
}

public struct BootstrapServerEndpoint: Equatable, Sendable, CustomStringConvertible {
  public var scheme: String
  public var host: String
  public var port: Int

  public init(scheme: String, host: String, port: Int) {
    self.scheme = Self.normalizedScheme(scheme) ?? Self.defaultEndpoint.scheme
    self.host = Self.normalizedHost(host) ?? Self.defaultEndpoint.host
    self.port = Self.normalizedPort(port) ?? Self.defaultEndpoint.port
  }

  public static let defaultEndpoint = BootstrapServerEndpoint(
    scheme: "http",
    host: "127.0.0.1",
    port: 8080
  )

  public var url: URL? {
    var components = URLComponents()
    components.scheme = scheme
    components.host = host
    components.port = port
    return components.url
  }

  public var displayString: String {
    url?.absoluteString ?? "\(scheme)://\(host):\(port)"
  }

  public var description: String {
    displayString
  }

  public static func resolved(from environment: [String: String]) -> Self {
    var endpoint = defaultEndpoint

    if let scheme = normalizedScheme(environment[BootstrapEnvironment.serverSchemeKey]) {
      endpoint.scheme = scheme
    }

    if let host = normalizedHost(environment[BootstrapEnvironment.serverHostKey]) {
      endpoint.host = host
    }

    if let port = normalizedPort(environment[BootstrapEnvironment.serverPortKey]) {
      endpoint.port = port
    }

    return endpoint
  }

  private static func normalizedScheme(_ value: String?) -> String? {
    guard let value else {
      return nil
    }

    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return nil
    }

    return trimmed.lowercased()
  }

  private static func normalizedHost(_ value: String?) -> String? {
    guard let value else {
      return nil
    }

    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private static func normalizedPort(_ value: Int) -> Int? {
    (1...65535).contains(value) ? value : nil
  }

  private static func normalizedPort(_ value: String?) -> Int? {
    guard let value else {
      return nil
    }

    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let port = Int(trimmed) else {
      return nil
    }

    return normalizedPort(port)
  }
}

public struct BootstrapStartupState: Sendable, CustomStringConvertible {
  public let componentName: String
  public let processIdentifier: Int32
  public let launchArguments: [String]
  public let startedAt: Date
  public let endpoint: BootstrapServerEndpoint

  public init(
    componentName: String,
    processIdentifier: Int32,
    launchArguments: [String],
    startedAt: Date = Date(),
    endpoint: BootstrapServerEndpoint
  ) {
    self.componentName = componentName
    self.processIdentifier = processIdentifier
    self.launchArguments = launchArguments
    self.startedAt = startedAt
    self.endpoint = endpoint
  }

  public static func current(
    componentName: String,
    environment: [String: String] = ProcessInfo.processInfo.environment,
    processIdentifier: Int32 = getpid(),
    launchArguments: [String] = ProcessInfo.processInfo.arguments,
    startedAt: Date = Date()
  ) -> Self {
    Self(
      componentName: componentName,
      processIdentifier: processIdentifier,
      launchArguments: launchArguments,
      startedAt: startedAt,
      endpoint: BootstrapEnvironment.effectiveServerEndpoint(environment: environment)
    )
  }

  public var startupLogLines: [String] {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    return [
      "[\(componentName)] starting",
      "[\(componentName)] pid=\(processIdentifier)",
      "[\(componentName)] started_at=\(formatter.string(from: startedAt))",
      "[\(componentName)] endpoint=\(endpoint.displayString)",
      "[\(componentName)] arguments=\(launchArguments.joined(separator: " "))",
    ]
  }

  public var description: String {
    startupLogLines.joined(separator: "\n")
  }
}

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

    var serverTask: Task<Void, Error>?
    var orchestratorEngine: (any BootstrapEngineRunning)?
    var startupSignal: ServerStartupSignal?
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
          let engine = try engineFactory(workflow, environment, store)
          try engine.start()
          orchestratorEngine = engine
        }
      }

      if startServer {
        let api = SymphonyHTTPAPI(store: store, version: "1.0.0", trackerKind: "github")
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
      keepAlive: keepAlive,
      orchestratorEngine: orchestratorEngine,
      serverTask: serverTask,
      startupSignal: startupSignal
    )
  }

  private static func cleanupRuntime(_ runtime: PreparedBootstrapRuntime) {
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
      observer: observer
    )
  }
}

private struct PreparedBootstrapRuntime {
  let keepAlive: () -> Void
  let orchestratorEngine: (any BootstrapEngineRunning)?
  let serverTask: Task<Void, Error>?
  let startupSignal: ServerStartupSignal?
}

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

public enum BootstrapKeepAlivePolicy {
  public static let exitAfterStartupKey = "SYMPHONY_EXIT_AFTER_STARTUP"

  public static func shouldExitAfterStartup(
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> Bool {
    environment[exitAfterStartupKey] == "1"
  }

  public static func makeKeepAlive(
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> () -> Void {
    shouldExitAfterStartup(environment: environment) ? {} : { BootstrapRuntimeHooks.keepAlive() }
  }
}
