import Foundation
import SymphonyServer

@main
struct SymphonyServerMain {
  typealias Runner = SymphonyServerExecutable.Runner
  typealias RuntimeHooks = SymphonyServerExecutable.RuntimeHooks

  static var runtimeHooks: RuntimeHooks {
    get { SymphonyServerExecutable.runtimeHooks }
    set { SymphonyServerExecutable.runtimeHooks = newValue }
  }

  static func main() {
    SymphonyServerExecutable.main()
  }

  static func main(
    environment: [String: String],
    output: @escaping (String) -> Void,
    errorOutput: (String) -> Void,
    exit: (Int32) -> Void,
    runner: Runner
  ) {
    SymphonyServerExecutable.main(
      environment: environment,
      output: output,
      errorOutput: errorOutput,
      exit: exit,
      runner: runner
    )
  }
}
