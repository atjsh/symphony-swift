import Foundation
import SymphonyServerCore
import SymphonyShared

// MARK: - Bootstrap Environment

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

// MARK: - Bootstrap Protocols & Factories

public protocol BootstrapEngineRunning: Sendable {
  func start() throws
  func stop()
}

extension OrchestratorEngine: BootstrapEngineRunning {}

public protocol BootstrapWorkflowReloading: Sendable {
  func reloadWorkflow(_ workflow: WorkflowDefinition)
}

extension OrchestratorEngine: BootstrapWorkflowReloading {}

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

// MARK: - Bootstrap Server Endpoint

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

// MARK: - Bootstrap Startup State

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

// MARK: - Bootstrap Keep-Alive Policy

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
