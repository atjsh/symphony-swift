import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

@main
struct SymphonyApp: App {
    private let endpoint: BootstrapServerEndpoint

    init() {
        let environment = ProcessInfo.processInfo.environment
        self.endpoint = BootstrapEnvironment.effectiveServerEndpoint(environment: environment)
        if BootstrapKeepAlivePolicy.shouldExitAfterStartup(environment: environment) {
            let state = BootstrapStartupState.current(componentName: "Symphony", environment: environment)
            state.startupLogLines.forEach { print($0) }
#if canImport(AppKit)
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
#endif
        }
    }

    init(testEndpoint: BootstrapServerEndpoint) {
        self.endpoint = testEndpoint
    }

    var body: some Scene {
        WindowGroup {
            ContentView(endpoint: endpoint)
        }
    }
}
