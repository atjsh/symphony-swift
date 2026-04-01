import SwiftUI
import SymphonyShared

enum ServerEditorMode: String, CaseIterable, Identifiable {
  case localServer
  case existingServer

  var id: String { rawValue }

  var title: String {
    switch self {
    case .localServer:
      return "Local Server"
    case .existingServer:
      return "Existing Server"
    }
  }
}

struct OperatorEndpointEditorView: View {
  @Bindable private var model: SymphonyOperatorModel
  @Environment(\.dismiss) private var dismiss

  @State private var draftHost: String
  @State private var draftPort: String
  #if os(macOS)
    @State private var selectedMode: ServerEditorMode
  #endif

  #if os(macOS)
    init(
      model: SymphonyOperatorModel,
      initialMode: ServerEditorMode = .localServer
    ) {
      self.model = model
      self._draftHost = State(initialValue: model.host)
      self._draftPort = State(initialValue: model.portText)
      self._selectedMode = State(initialValue: initialMode)
    }
  #else
    init(model: SymphonyOperatorModel) {
      self.model = model
      self._draftHost = State(initialValue: model.host)
      self._draftPort = State(initialValue: model.portText)
    }
  #endif

  var body: some View {
    NavigationStack {
      contentView
      .navigationTitle("Server")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", action: Self.makeEndpointDismissAction(dismiss.callAsFunction))
        }
      }
    }
    .onAppear {
      refreshConnectionDrafts()
      #if os(macOS)
        if model.hasLocalServerSupport && selectedMode == .localServer {
          model.prepareLocalServerEditor(mode: selectedMode)
        }
      #endif
    }
    #if os(macOS)
      .onChange(of: selectedMode) { _, newValue in
        refreshConnectionDrafts()
        if model.hasLocalServerSupport && newValue == .localServer {
          model.prepareLocalServerEditor(mode: newValue)
        }
      }
    #endif
    .accessibilityIdentifier("server-editor-sheet")
  }

  @ViewBuilder
  private var contentView: some View {
    #if os(macOS)
      if model.hasLocalServerSupport
        && selectedMode == .localServer
        && model.localWorkflowWizardStep == .workflow
      {
        WorkflowAuthoringEditorView(model: model) {
          macOSConnectionTypePicker
        }
          .frame(
            minWidth: 1040,
            idealWidth: 1180,
            minHeight: 620,
            idealHeight: 740,
            maxHeight: 900
          )
      } else {
        Form {
          macOSConnectionTypePicker
          if model.hasLocalServerSupport && selectedMode == .localServer {
            localServerSections
          } else {
            existingServerSections
          }
        }
        .frame(
          minWidth: 680,
          idealWidth: 760,
          minHeight: 360,
          idealHeight: 460,
          maxHeight: 700
        )
      }
    #else
      Form {
        existingServerSections
      }
    #endif
  }

  private var existingServerSections: some View {
    Group {
      Section {
        TextField("Host", text: $draftHost)
          .accessibilityIdentifier("server-editor-host")
        TextField("Port", text: $draftPort)
          .accessibilityIdentifier("server-editor-port")
      } header: {
        Text("Server")
      }

      if let connectionError = model.connectionError {
        Section {
          Text(connectionError)
            .foregroundStyle(.red)
        } header: {
          Text("Last Error")
        }
      }

      Section {
        Button(
          "Connect",
          systemImage: "bolt.horizontal.circle",
          action: Self.makeEndpointConnectAction(
            model: model,
            draftHost: draftHost,
            draftPort: draftPort,
            dismiss: dismiss.callAsFunction
          )
        )
        .operatorProminentActionButton()
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityIdentifier("server-editor-connect-button")
      }
    }
  }

  private func refreshConnectionDrafts() {
    draftHost = model.host
    draftPort = model.portText
  }

  #if os(macOS)
    private var macOSConnectionTypePicker: some View {
      Group {
        if model.hasLocalServerSupport {
          Picker("Connection Type", selection: $selectedMode) {
            ForEach(ServerEditorMode.allCases) { mode in
              Text(mode.title).tag(mode)
            }
          }
          .pickerStyle(.segmented)
          .accessibilityIdentifier("server-editor-mode-picker")
        }
      }
    }


    private var localServerSections: some View {
      Group {
        Section {
          VStack(alignment: .leading, spacing: 10) {
            workflowStepHeader(
              eyebrow: "Step 2 of 2",
              title: "Start Local Server",
              message:
                "Review the generated workflow, fill any required environment values, and launch the bundled Symphony server."
            )
          }
          .accessibilityIdentifier("local-server-step")
        }

        Section {
          if model.localServerWorkflowPath.isEmpty {
            Text("Choose a WORKFLOW.md file to launch the bundled Symphony server.")
              .foregroundStyle(.secondary)
          } else {
            Text(model.localServerWorkflowPath)
              .font(.footnote.monospaced())
              .textSelection(.enabled)
              .accessibilityIdentifier("local-server-workflow-path")
          }

          HStack(spacing: 12) {
            Button(
              "Edit Generated Workflow",
              systemImage: "pencil.and.scribble",
              action: model.showWorkflowAuthoringStep
            )
            .accessibilityIdentifier("local-server-edit-generated-workflow-button")

            Button(
              "Choose WORKFLOW.md",
              systemImage: "doc.badge.plus",
              action: model.chooseLocalWorkflow
            )
            .accessibilityIdentifier("local-server-choose-workflow-button")
          }
        } header: {
          Text("Workflow")
        }

        Section {
          TextField("Host", text: $model.host)
            .accessibilityIdentifier("local-server-host")
          TextField("Port", text: $model.portText)
            .accessibilityIdentifier("local-server-port")
          TextField("SQLite Path (Optional)", text: $model.localServerSQLitePath)
            .accessibilityIdentifier("local-server-sqlite-path")
        } header: {
          Text("Server")
        }

        Section {
          if model.localServerEnvironmentEntries.isEmpty {
            Text("Environment values referenced by the workflow will appear here.")
              .foregroundStyle(.secondary)
          } else {
            ForEach($model.localServerEnvironmentEntries) { $entry in
              VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                  TextField("Name", text: $entry.name)
                    .accessibilityIdentifier("local-server-env-name-\(entry.id.uuidString)")
                  if entry.isRequired {
                    Text("Required")
                      .font(.caption.weight(.semibold))
                      .foregroundStyle(.secondary)
                  }
                }

                SecureField("Value", text: $entry.value)
                  .accessibilityIdentifier("local-server-env-value-\(entry.id.uuidString)")

                HStack {
                  Spacer()
                  Button(
                    "Remove",
                    role: .destructive,
                    action: { model.removeLocalServerEnvironmentEntry(id: entry.id) }
                  )
                }
              }
              .padding(.vertical, 4)
            }
          }

          Button(
            "Add Variable",
            systemImage: "plus",
            action: model.addLocalServerEnvironmentEntry
          )
          .accessibilityIdentifier("local-server-add-env-button")
        } header: {
          Text("Environment")
        }

        if let localServerFailure = model.localServerFailure {
          Section {
            Text(localServerFailure)
              .foregroundStyle(.red)
              .accessibilityIdentifier("local-server-error")
          } header: {
            Text("Local Server Error")
          }
        }

        if !model.localServerTranscript.isEmpty {
          Section {
            ScrollView {
              Text(verbatim: model.localServerTranscript.joined(separator: "\n"))
                .font(.footnote.monospaced())
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .accessibilityIdentifier("local-server-transcript")
            }
            .frame(idealHeight: 120)
          } header: {
            Text("Launch Transcript")
          }
        }

        Section {
          Button(
            model.localServerPrimaryActionTitle,
            systemImage: model.isLocalServerRunning
              ? "arrow.clockwise.circle" : "play.circle",
            action: Self.makeLocalServerStartAction(
              model: model,
              draftHost: model.host,
              draftPort: model.portText,
              dismiss: dismiss.callAsFunction
            )
          )
          .operatorProminentActionButton()
          .frame(maxWidth: .infinity, alignment: .center)
          .disabled(
            model.localServerLaunchState == .validating
              || model.localServerLaunchState == .starting
              || model.localServerLaunchState == .waitingForHealth
          )
          .accessibilityIdentifier("local-server-start-button")

          if model.isLocalServerRunning {
            Button(
              "Stop Local Server",
              systemImage: "stop.circle",
              action: Self.makeLocalServerStopAction(model: model)
            )
            .operatorSecondaryActionButton()
            .accessibilityIdentifier("local-server-stop-button")
          }
        } footer: {
          Text("The local helper launches the bundled Symphony server and reconnects the app automatically when health checks succeed.")
        }
      }
    }
  #endif
}

extension OperatorEndpointEditorView {
  @MainActor
  static func operatorEndpointDismiss(_ dismiss: @escaping @MainActor () -> Void) {
    dismiss()
  }

  @MainActor
  static func operatorEndpointConnect(
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
  static func makeEndpointDismissAction(_ dismiss: @escaping @MainActor () -> Void) -> () -> Void {
    { operatorEndpointDismiss(dismiss) }
  }

  @MainActor
  static func makeEndpointConnectAction(
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

  #if os(macOS)
    @MainActor
    static func operatorLocalServerStart(
      model: SymphonyOperatorModel,
      draftHost: String,
      draftPort: String,
      dismiss: @escaping @MainActor () -> Void
    ) {
      model.host = draftHost.trimmingCharacters(in: .whitespacesAndNewlines)
      model.portText = draftPort.trimmingCharacters(in: .whitespacesAndNewlines)

      Task { @MainActor in
        if model.isLocalServerRunning {
          await model.restartLocalServer()
        } else {
          await model.startLocalServer()
        }

        if model.localServerLaunchState == .running {
          dismiss()
        }
      }
    }

    @MainActor
    static func makeLocalServerStartAction(
      model: SymphonyOperatorModel,
      draftHost: String,
      draftPort: String,
      dismiss: @escaping @MainActor () -> Void
    ) -> () -> Void {
      {
        operatorLocalServerStart(
          model: model,
          draftHost: draftHost,
          draftPort: draftPort,
          dismiss: dismiss
        )
      }
    }

    @MainActor
    static func makeLocalServerStopAction(model: SymphonyOperatorModel) -> () -> Void {
      {
        Task { @MainActor in
          await model.stopLocalServer()
        }
      }
    }
  #endif
}
