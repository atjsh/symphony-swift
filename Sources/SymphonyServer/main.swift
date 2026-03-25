import Foundation
import SymphonyRuntime

@main
struct SymphonyServerMain {
    static func main() {
        let environment = ProcessInfo.processInfo.environment
        do {
            try BootstrapServerRunner.run(
                environment: environment,
                output: { print($0) },
                keepAlive: BootstrapKeepAlivePolicy.makeKeepAlive(environment: environment)
            )
        } catch {
            fputs("[SymphonyServer] failed to start: \(error)\n", stderr)
            exit(1)
        }
    }
}
