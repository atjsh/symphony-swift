import SwiftUI
import SymphonyShared

struct ContentView: View {
  var model: SymphonyOperatorModel

  init(model: SymphonyOperatorModel) {
    self.model = model
  }

  init(endpoint: BootstrapServerEndpoint) {
    let sharedEndpoint = endpoint.serverEndpoint
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
