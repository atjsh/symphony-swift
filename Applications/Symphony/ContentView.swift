import SwiftUI
import SymphonyRuntime

struct ContentView: View {
    let endpoint: BootstrapServerEndpoint

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Symphony")
                .font(.largeTitle.weight(.semibold))

            Text("Effective server endpoint")
                .font(.headline)

            Text(endpoint.displayString)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)

            Text("Configured from `SYMPHONY_SERVER_SCHEME`, `SYMPHONY_SERVER_HOST`, and `SYMPHONY_SERVER_PORT`.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(24)
    }
}

#if DEBUG
#Preview {
    ContentView(endpoint: .defaultEndpoint)
}
#endif
