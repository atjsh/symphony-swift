import SwiftUI
import XcodeSupport

@main
struct SymphonyApp: App {
    private let endpoint = BootstrapEnvironment.effectiveServerEndpoint()

    var body: some Scene {
        WindowGroup {
            ContentView(endpoint: endpoint)
        }
    }
}
