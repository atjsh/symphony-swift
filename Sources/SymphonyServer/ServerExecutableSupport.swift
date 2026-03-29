import Foundation

public enum SymphonyServerExecutable {
  public typealias Runner = (
    _ componentName: String,
    _ environment: [String: String],
    _ output: @escaping (String) -> Void,
    _ keepAlive: @escaping () -> Void,
    _ startServer: Bool
  ) throws -> Void

  public struct RuntimeHooks {
    public var environment: () -> [String: String]
    public var output: (String) -> Void
    public var errorOutput: (String) -> Void
    public var exit: (Int32) -> Void
    public var runner: Runner

    public init(
      environment: @escaping () -> [String: String],
      output: @escaping (String) -> Void,
      errorOutput: @escaping (String) -> Void,
      exit: @escaping (Int32) -> Void,
      runner: @escaping Runner
    ) {
      self.environment = environment
      self.output = output
      self.errorOutput = errorOutput
      self.exit = exit
      self.runner = runner
    }
  }

  private final class RuntimeHooksStore: @unchecked Sendable {
    private let lock = NSLock()
    private var hooks: RuntimeHooks

    init(hooks: RuntimeHooks) {
      self.hooks = hooks
    }

    func load() -> RuntimeHooks {
      lock.withLock { hooks }
    }

    func store(_ hooks: RuntimeHooks) {
      lock.withLock {
        self.hooks = hooks
      }
    }
  }

  private static func defaultEnvironment() -> [String: String] {
    ProcessInfo.processInfo.environment
  }

  private static func defaultOutput(_ value: String) {
    print(value)
  }

  private static func defaultErrorOutput(_ value: String) {
    fputs(value, stderr)
  }

  private static func defaultExit(_ code: Int32) {
    Foundation.exit(code)
  }

  private static func defaultRunner(
    componentName: String,
    environment: [String: String],
    output: @escaping (String) -> Void,
    keepAlive: @escaping () -> Void,
    startServer: Bool
  ) throws {
    try BootstrapServerRunner.run(
      componentName: componentName,
      environment: environment,
      output: output,
      keepAlive: keepAlive,
      startServer: startServer
    )
  }

  private static let runtimeHooksStore = RuntimeHooksStore(hooks: .init(
    environment: defaultEnvironment,
    output: defaultOutput,
    errorOutput: defaultErrorOutput,
    exit: defaultExit,
    runner: defaultRunner
  ))

  public static var runtimeHooks: RuntimeHooks {
    get { runtimeHooksStore.load() }
    set { runtimeHooksStore.store(newValue) }
  }

  public static func main(componentName: String = "SymphonyServer") {
    let hooks = runtimeHooks
    main(
      componentName: componentName,
      environment: hooks.environment(),
      output: hooks.output,
      errorOutput: hooks.errorOutput,
      exit: hooks.exit,
      runner: hooks.runner
    )
  }

  public static func main(
    componentName: String = "SymphonyServer",
    environment: [String: String],
    output: @escaping (String) -> Void,
    errorOutput: (String) -> Void,
    exit: (Int32) -> Void,
    runner: Runner
  ) {
    let shouldExitAfterStartup = BootstrapKeepAlivePolicy.shouldExitAfterStartup(
      environment: environment
    )
    do {
      try runner(
        componentName,
        environment,
        output,
        BootstrapKeepAlivePolicy.makeKeepAlive(environment: environment),
        !shouldExitAfterStartup
      )
    } catch {
      errorOutput("[\(componentName)] failed to start: \(error)\n")
      exit(1)
    }
  }
}
