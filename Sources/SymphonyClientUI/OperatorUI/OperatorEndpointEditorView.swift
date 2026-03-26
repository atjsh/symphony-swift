import SwiftUI

struct OperatorEndpointEditorView: View {
  @ObservedObject private var model: SymphonyOperatorModel
  @Environment(\.dismiss) private var dismiss

  @State private var draftHost: String
  @State private var draftPort: String

  init(model: SymphonyOperatorModel) {
    self._model = ObservedObject(wrappedValue: model)
    self._draftHost = State(initialValue: model.host)
    self._draftPort = State(initialValue: model.portText)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Server") {
          TextField("Host", text: $draftHost)
            .accessibilityIdentifier("server-editor-host")
          TextField("Port", text: $draftPort)
            .accessibilityIdentifier("server-editor-port")
        }

        if let connectionError = model.connectionError {
          Section("Last Error") {
            Text(connectionError)
              .foregroundStyle(.red)
          }
        }

        Section {
          Button(
            "Connect",
            systemImage: "bolt.horizontal.circle",
            action: makeEndpointConnectAction(
              model: model,
              draftHost: draftHost,
              draftPort: draftPort,
              dismiss: dismiss.callAsFunction
            )
          )
          .buttonStyle(.glassProminent)
          .frame(maxWidth: .infinity, alignment: .center)
          .accessibilityIdentifier("server-editor-connect-button")
        }
      }
      .navigationTitle("Server")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", action: makeEndpointDismissAction(dismiss.callAsFunction))
        }
      }
    }
    .accessibilityIdentifier("server-editor-sheet")
  }
}

@MainActor
func operatorEndpointDismiss(_ dismiss: @escaping @MainActor () -> Void) {
  dismiss()
}

@MainActor
func operatorEndpointConnect(
  model: SymphonyOperatorModel,
  draftHost: String,
  draftPort: String,
  dismiss: @escaping @MainActor () -> Void
) {
  model.host = draftHost.trimmingCharacters(in: .whitespacesAndNewlines)
  model.portText = draftPort.trimmingCharacters(in: .whitespacesAndNewlines)

  Task { @MainActor in
    await model.connect()
    if model.connectionError == nil {
      dismiss()
    }
  }
}

@MainActor
func makeEndpointDismissAction(_ dismiss: @escaping @MainActor () -> Void) -> () -> Void {
  { operatorEndpointDismiss(dismiss) }
}

@MainActor
func makeEndpointConnectAction(
  model: SymphonyOperatorModel,
  draftHost: String,
  draftPort: String,
  dismiss: @escaping @MainActor () -> Void
) -> () -> Void {
  {
    operatorEndpointConnect(
      model: model, draftHost: draftHost, draftPort: draftPort, dismiss: dismiss)
  }
}
