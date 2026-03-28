import Foundation
import SymphonyServer

@main
struct SymphonyServerMain {
  typealias Runner = (
    _ environment: [String: String],
    _ output: @escaping (String) -> Void,
    _ keepAlive: @escaping () -> Void,
    _ startServer: Bool
  ) throws -> Void

  struct RuntimeHooks {
    var environment: () -> [String: String]
    var output: (String) -> Void
    var errorOutput: (String) -> Void
    var exit: (Int32) -> Void
    var runner: Runner
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
    environment: [String: String],
    output: @escaping (String) -> Void,
    keepAlive: @escaping () -> Void,
    startServer: Bool
  ) throws {
    try BootstrapServerRunner.run(
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

  static var runtimeHooks: RuntimeHooks {
    get { runtimeHooksStore.load() }
    set { runtimeHooksStore.store(newValue) }
  }

  static func main() {
    let hooks = runtimeHooks
    main(
      environment: hooks.environment(),
      output: hooks.output,
      errorOutput: hooks.errorOutput,
      exit: hooks.exit,
      runner: hooks.runner
    )
  }

  static func main(
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
        environment,
        output,
        BootstrapKeepAlivePolicy.makeKeepAlive(environment: environment),
        !shouldExitAfterStartup
      )
    } catch {
      errorOutput("[SymphonyServer] failed to start: \(error)\n")
      exit(1)
    }
  }
}
