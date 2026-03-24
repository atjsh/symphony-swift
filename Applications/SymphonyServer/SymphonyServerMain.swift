import Foundation
import XcodeSupport

@main
struct SymphonyServerMain {
    static func main() {
        let environment = ProcessInfo.processInfo.environment
        BootstrapServerRunner.run(
            environment: environment,
            output: { print($0) },
            keepAlive: BootstrapKeepAlivePolicy.makeKeepAlive(environment: environment)
        )
    }
}
