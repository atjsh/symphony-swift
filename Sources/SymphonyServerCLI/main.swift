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

  static func main() {
    main(
      environment: ProcessInfo.processInfo.environment,
      output: { print($0) },
      errorOutput: { fputs($0, stderr) },
      exit: { Foundation.exit($0) },
      runner: { environment, output, keepAlive, startServer in
        try BootstrapServerRunner.run(
          environment: environment,
          output: output,
          keepAlive: keepAlive,
          startServer: startServer
        )
      }
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
