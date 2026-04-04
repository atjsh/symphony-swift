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
}
