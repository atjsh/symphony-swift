import SwiftUI
import SymphonyClientUI
import SymphonyShared
#if canImport(AppKit)
import AppKit
#endif

@main
struct SymphonyApp: App {
    @StateObject private var model: SymphonyOperatorModel

    init() {
        let environment = ProcessInfo.processInfo.environment
        let endpoint = BootstrapEnvironment.effectiveServerEndpoint(environment: environment)
        let sharedEndpoint = try! ServerEndpoint(scheme: endpoint.scheme, host: endpoint.host, port: endpoint.port)
        _model = StateObject(wrappedValue: SymphonyOperatorModel(initialEndpoint: sharedEndpoint))

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

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
        }
    }
}
