import Foundation

enum BootstrapRuntimeHooks {
  private final class Storage: @unchecked Sendable {
    private let lock = NSLock()
    private var output: ((String) -> Void)?
    private var keepAlive: (() -> Void)?
    private var runLoop: () -> Void = RunLoop.main.run

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

    var runLoopRunner: () -> Void {
      get {
        lock.lock()
        defer { lock.unlock() }
        return runLoop
      }
      set {
        lock.lock()
        runLoop = newValue
        lock.unlock()
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

  static var runLoopRunner: () -> Void {
    get { storage.runLoopRunner }
    set { storage.runLoopRunner = newValue }
  }

  static func defaultOutput(_ line: String) {
    if let outputOverride {
      outputOverride(line)
    } else {
      print(line)
    }
  }

  static func keepAlive() {
    if let keepAliveOverride {
      keepAliveOverride()
    } else {
      runLoopRunner()
    }
  }
}

enum BootstrapEnvironment {
  static let serverSchemeKey = "SYMPHONY_SERVER_SCHEME"
  static let serverHostKey = "SYMPHONY_SERVER_HOST"
  static let serverPortKey = "SYMPHONY_SERVER_PORT"

  static func effectiveServerEndpoint(
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> BootstrapServerEndpoint {
    BootstrapServerEndpoint.resolved(from: environment)
  }
}

struct BootstrapServerEndpoint: Equatable, Sendable, CustomStringConvertible {
  var scheme: String
  var host: String
  var port: Int

  init(scheme: String, host: String, port: Int) {
    self.scheme = Self.normalizedScheme(scheme) ?? Self.defaultEndpoint.scheme
    self.host = Self.normalizedHost(host) ?? Self.defaultEndpoint.host
    self.port = Self.normalizedPort(port) ?? Self.defaultEndpoint.port
  }

  static let defaultEndpoint = BootstrapServerEndpoint(
    scheme: "http",
    host: "localhost",
    port: 8080
  )

  var url: URL? {
    var components = URLComponents()
    components.scheme = scheme
    components.host = host
    components.port = port
    return components.url
  }

  var displayString: String {
    url?.absoluteString ?? "\(scheme)://\(host):\(port)"
  }

  var description: String {
    displayString
  }

  static func resolved(from environment: [String: String]) -> Self {
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

struct BootstrapStartupState: Sendable, CustomStringConvertible {
  let componentName: String
  let processIdentifier: Int32
  let launchArguments: [String]
  let startedAt: Date
  let endpoint: BootstrapServerEndpoint

  init(
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

  static func current(
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

  var startupLogLines: [String] {
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

  var description: String {
    startupLogLines.joined(separator: "\n")
  }
}

enum BootstrapServerRunner {
  static func run(
    componentName: String = "SymphonyServer",
    environment: [String: String] = ProcessInfo.processInfo.environment,
    processIdentifier: Int32 = getpid(),
    launchArguments: [String] = ProcessInfo.processInfo.arguments,
    startedAt: Date = Date(),
    output: ((String) -> Void)? = nil,
    keepAlive: (() -> Void)? = nil
  ) {
    let output = output ?? BootstrapRuntimeHooks.defaultOutput
    let keepAlive = keepAlive ?? BootstrapRuntimeHooks.keepAlive
    let state = BootstrapStartupState.current(
      componentName: componentName,
      environment: environment,
      processIdentifier: processIdentifier,
      launchArguments: launchArguments,
      startedAt: startedAt
    )

    state.startupLogLines.forEach(output)
    keepAlive()
  }

  static func startupState(
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
}

enum BootstrapKeepAlivePolicy {
  static let exitAfterStartupKey = "SYMPHONY_EXIT_AFTER_STARTUP"

  static func shouldExitAfterStartup(
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> Bool {
    environment[exitAfterStartupKey] == "1"
  }

  static func makeKeepAlive(environment: [String: String] = ProcessInfo.processInfo.environment)
    -> () -> Void
  {
    shouldExitAfterStartup(environment: environment) ? {} : { BootstrapRuntimeHooks.keepAlive() }
  }
}
