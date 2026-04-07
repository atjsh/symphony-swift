import SwiftUI
import SymphonyXcodeValidation
import SymphonyXcodeValidationServerCore

/// Form for configuring a validation run before starting it.
public struct ValidationRunnerConfigurationView: View {
  @Bindable var store: ValidationRunnerStore

  public init(store: ValidationRunnerStore) {
    self.store = store
  }

  public var body: some View {
    Form {
      if store.hasServerSupport {
        serverLifecycleSection
      } else {
        externalServerSection
      }

      Section("Subject") {
        Picker("Target", selection: $store.configuration.subject) {
          ForEach(ValidationSubject.allCases, id: \.self) { subject in
            Text(subject.rawValue).tag(subject)
          }
        }
        .accessibilityIdentifier("subjectPicker")
      }

      Section("Build") {
        Picker("Build Profile", selection: $store.configuration.buildProfile) {
          ForEach(ValidationBuildProfile.allCases, id: \.self) { profile in
            Text(profile.rawValue).tag(profile)
          }
        }
        .accessibilityIdentifier("buildProfilePicker")

        Picker("Execution Profile", selection: $store.configuration.executionProfile) {
          ForEach(ValidationExecutionProfile.allCases, id: \.self) { profile in
            Text(profile.rawValue).tag(profile)
          }
        }
        .accessibilityIdentifier("executionProfilePicker")
      }

      Section("Options") {
        Picker("Artifact Retention", selection: $store.configuration.artifactRetention) {
          ForEach(ValidationArtifactRetention.allCases, id: \.self) { retention in
            Text(retention.rawValue).tag(retention)
          }
        }
        .accessibilityIdentifier("artifactRetentionPicker")

        Toggle("Skip Rich Capture", isOn: $store.configuration.skipRichCapture)
          .accessibilityIdentifier("skipRichCaptureToggle")

        Toggle("Skip Full Matrix", isOn: $store.configuration.skipFullMatrix)
          .accessibilityIdentifier("skipFullMatrixToggle")
      }

      Section {
        Button {
          Task { await store.startRun() }
        } label: {
          Label("Start Run", systemImage: "play.fill")
        }
        .disabled(!store.isConnected || store.runStatus == .running)
        .accessibilityIdentifier("startRunButton")
      }
    }
    .formStyle(.grouped)
    .task {
      await store.checkConnection()
    }
  }

  // MARK: - Server Lifecycle Section (when hasServerSupport)

  @ViewBuilder
  private var serverLifecycleSection: some View {
    Section("Server") {
      HStack {
        Text("Hostname")
          .foregroundStyle(.secondary)
        Spacer()
        TextField("127.0.0.1", text: $store.serverHostname)
          .multilineTextAlignment(.trailing)
          .accessibilityIdentifier("serverHostnameField")
          .accessibilityLabel("Server hostname")
          #if os(macOS)
            .frame(maxWidth: 200)
          #endif
      }

      HStack {
        Text("Port")
          .foregroundStyle(.secondary)
        Spacer()
        TextField("8090", text: $store.serverPort)
          .multilineTextAlignment(.trailing)
          .accessibilityIdentifier("serverPortField")
          .accessibilityLabel("Server port")
          #if os(macOS)
            .frame(maxWidth: 100)
          #endif
      }

      HStack {
        serverStatusIndicator
        Spacer()
        serverActionButton
      }
    }

    if !store.serverTranscript.isEmpty {
      Section("Server Transcript") {
        DisclosureGroup {
          ScrollView {
            Text(store.serverTranscript.joined(separator: "\n"))
              .font(.system(.caption, design: .monospaced))
              .frame(maxWidth: .infinity, alignment: .leading)
              .textSelection(.enabled)
          }
          .frame(maxHeight: 200)
          .accessibilityIdentifier("serverTranscriptContent")
        } label: {
          Text("\(store.serverTranscript.count) lines")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("serverTranscriptDisclosure")
      }
    }
  }

  @ViewBuilder
  private var serverStatusIndicator: some View {
    switch store.serverLaunchState {
    case .idle:
      HStack(spacing: 6) {
        Circle()
          .fill(.secondary)
          .frame(width: 8, height: 8)
        Text("Server stopped")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .accessibilityIdentifier("connectionIndicator")
      .accessibilityLabel("Server stopped")
    case .starting, .waitingForHealth:
      HStack(spacing: 6) {
        ProgressView()
          .controlSize(.small)
        Text("Starting…")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .accessibilityIdentifier("connectionIndicator")
      .accessibilityLabel("Starting")
    case .running:
      HStack(spacing: 6) {
        Circle()
          .fill(.green)
          .frame(width: 8, height: 8)
        Text(store.isConnected ? "Connected" : "Running")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .accessibilityIdentifier("connectionIndicator")
      .accessibilityLabel(store.isConnected ? "Connected" : "Running")
    case .failed:
      HStack(spacing: 6) {
        Circle()
          .fill(.red)
          .frame(width: 8, height: 8)
        Text(store.serverFailureDescription ?? "Failed")
          .font(.caption)
          .foregroundStyle(.red)
          .lineLimit(2)
      }
      .accessibilityIdentifier("connectionIndicator")
      .accessibilityLabel("Failed")
    }
  }

  @ViewBuilder
  private var serverActionButton: some View {
    switch store.serverLaunchState {
    case .idle:
      Button {
        Task { await store.startServer() }
      } label: {
        Label("Start Server", systemImage: "play.circle")
      }
      .accessibilityIdentifier("validationServerStartButton")
    case .starting, .waitingForHealth:
      Button {
        Task { await store.stopServer() }
      } label: {
        Label("Cancel", systemImage: "xmark.circle")
      }
      .accessibilityIdentifier("validationServerCancelButton")
    case .running:
      Button {
        Task { await store.stopServer() }
      } label: {
        Label("Stop Server", systemImage: "stop.circle")
      }
      .accessibilityIdentifier("validationServerStopButton")
    case .failed:
      Button {
        Task { await store.startServer() }
      } label: {
        Label("Retry", systemImage: "arrow.clockwise.circle")
      }
      .accessibilityIdentifier("validationServerRetryButton")
    }
  }

  // MARK: - External Server Section (no server support)

  @ViewBuilder
  private var externalServerSection: some View {
    Section("Server") {
      HStack {
        Text("Server URL")
          .foregroundStyle(.secondary)
        Spacer()
        Text(store.serverURL?.absoluteString ?? "Not configured")
          .foregroundStyle(store.isConnected ? .primary : .secondary)
          .accessibilityIdentifier("serverURLLabel")
      }
      HStack {
        Circle()
          .fill(store.isConnected ? .green : .red)
          .frame(width: 8, height: 8)
          .accessibilityIdentifier("connectionIndicator")
          .accessibilityLabel(store.isConnected ? "Connected" : "Disconnected")
        Text(store.isConnected ? "Connected" : "Disconnected")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }
}
