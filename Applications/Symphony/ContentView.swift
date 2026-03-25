import SwiftUI
import SymphonyClientUI
import SymphonyShared

struct ContentView: View {
    @ObservedObject var model: SymphonyOperatorModel

    init(model: SymphonyOperatorModel) {
        self.model = model
    }

    init(endpoint: BootstrapServerEndpoint) {
        let sharedEndpoint = try! ServerEndpoint(scheme: endpoint.scheme, host: endpoint.host, port: endpoint.port)
        self.model = SymphonyOperatorModel(initialEndpoint: sharedEndpoint)
    }

    var body: some View {
        SymphonyOperatorRootView(model: model)
    }
}

#if DEBUG
#Preview {
    ContentView(endpoint: .defaultEndpoint)
}
#endif
