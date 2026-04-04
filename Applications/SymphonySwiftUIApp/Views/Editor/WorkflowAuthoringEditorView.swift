#if os(macOS)
import SwiftUI
import SymphonyShared

struct WorkflowAuthoringEditorView<ConnectionPicker: View>: View {
  @Bindable var model: SymphonyOperatorModel
  let connectionPicker: ConnectionPicker

  @State private var isTrackerExpanded = true
  @State private var isRuntimeExpanded = false
  @State private var isAgentProvidersExpanded = false
  @State private var isServerStorageExpanded = false
  @State private var isPromptExpanded = true

  init(model: SymphonyOperatorModel, @ViewBuilder connectionPicker: () -> ConnectionPicker) {
    self.model = model
    self.connectionPicker = connectionPicker()
  }

  private var preview: WorkflowAuthoringPreviewState {
    model.workflowAuthoringPreview
  }

  private var workflowAuthoringInlineError: String? {
    model.workflowAuthoringFailure ?? preview.validationError
  }

  var body: some View {
    VStack(spacing: 0) {
      VStack(spacing: 16) {
        connectionPicker
        workflowStepHeader(
          eyebrow: "Step 1 of 2",
          title: "Create a WORKFLOW.md",
          message:
            "Build a valid Symphony workflow here or jump straight to an existing file if you already have one."
        )
      }
      .padding(.horizontal, 20)
      .padding(.top, 20)
      .padding(.bottom, 16)

      Divider()

      HSplitView {
        VStack(spacing: 0) {
          ScrollView {
            VStack(alignment: .leading, spacing: 18) {
              if let inlineError = workflowAuthoringInlineError {
                workflowInlineError(message: inlineError)
              }

              workflowSection(
                title: "Tracker",
                subtitle: "Point Symphony at the right GitHub project and status fields.",
                isExpanded: $isTrackerExpanded
              ) {
                trackerSectionContent
              }

              workflowSection(
                title: "Runtime",
                subtitle: "Tune polling, workspace location, and lifecycle hooks.",
                isExpanded: $isRuntimeExpanded
              ) {
                runtimeSectionContent
              }

              workflowSection(
                title: "Agent & Providers",
                subtitle: "Pick defaults for the orchestrator and adjust provider commands and timeouts.",
                isExpanded: $isAgentProvidersExpanded
              ) {
                agentProvidersSectionContent
              }

              workflowSection(
                title: "Server & Storage",
                subtitle: "Seed the generated workflow with server defaults and storage preferences.",
                isExpanded: $isServerStorageExpanded
              ) {
                serverStorageSectionContent
              }

              workflowSection(
                title: "Prompt",
                subtitle: "Start from a preset, then tailor the body to match your team's workflow.",
                isExpanded: $isPromptExpanded
              ) {
                promptSectionContent
              }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 24)
            .frame(maxWidth: 620, alignment: .leading)
          }

          Divider()

          workflowAuthoringActionBar
        }
        .frame(minWidth: 520, maxWidth: 620, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workflow-authoring-step")

        workflowPreviewPane
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  // MARK: - Tracker Section

  private var trackerSectionContent: some View {
    Group {
      workflowTextField(
        "Endpoint",
        text: workflowBinding(\.trackerEndpoint),
        identifier: "workflow-tracker-endpoint"
      )
      workflowTextField(
        "GitHub Token Variable Name",
        text: workflowBinding(\.trackerGitHubTokenVariableName),
        identifier: "workflow-tracker-token-variable"
      )
      workflowTextField(
        "Project Owner",
        text: workflowBinding(\.trackerProjectOwner),
        identifier: "workflow-tracker-project-owner"
      )
      workflowTextField(
        "Project Owner Type",
        text: workflowBinding(\.trackerProjectOwnerType),
        identifier: "workflow-tracker-project-owner-type"
      )
      workflowTextField(
        "Project Number",
        text: workflowBinding(\.trackerProjectNumber),
        identifier: "workflow-tracker-project-number"
      )
      workflowTextEditor(
        "Repository Allowlist",
        text: workflowBinding(\.trackerRepositoryAllowlistText),
        identifier: "workflow-tracker-allowlist",
        footer: "One repository per line or comma-separated.",
        idealHeight: 88
      )
      workflowTextField(
        "Status Field Name",
        text: workflowBinding(\.trackerStatusFieldName),
        identifier: "workflow-tracker-status-field"
      )
      workflowTextEditor(
        "Active States",
        text: workflowBinding(\.trackerActiveStatesText),
        identifier: "workflow-tracker-active-states",
        footer: "One state per line.",
        idealHeight: 72
      )
      workflowTextEditor(
        "Terminal States",
        text: workflowBinding(\.trackerTerminalStatesText),
        identifier: "workflow-tracker-terminal-states",
        footer: "One state per line.",
        idealHeight: 72
      )
      workflowTextEditor(
        "Blocked States",
        text: workflowBinding(\.trackerBlockedStatesText),
        identifier: "workflow-tracker-blocked-states",
        footer: "One state per line.",
        idealHeight: 72
      )
    }
  }

  // MARK: - Runtime Section

  private var runtimeSectionContent: some View {
    Group {
      workflowTextField(
        "Polling Interval (ms)",
        text: workflowBinding(\.pollingIntervalMS),
        identifier: "workflow-runtime-polling"
      )
      workflowTextField(
        "Workspace Root",
        text: workflowBinding(\.workspaceRoot),
        identifier: "workflow-runtime-workspace-root"
      )
      workflowTextField(
        "after_create Hook",
        text: workflowBinding(\.hooksAfterCreate),
        identifier: "workflow-runtime-after-create"
      )
      workflowTextField(
        "before_run Hook",
        text: workflowBinding(\.hooksBeforeRun),
        identifier: "workflow-runtime-before-run"
      )
      workflowTextField(
        "after_run Hook",
        text: workflowBinding(\.hooksAfterRun),
        identifier: "workflow-runtime-after-run"
      )
      workflowTextField(
        "before_remove Hook",
        text: workflowBinding(\.hooksBeforeRemove),
        identifier: "workflow-runtime-before-remove"
      )
      workflowTextField(
        "Hook Timeout (ms)",
        text: workflowBinding(\.hooksTimeoutMS),
        identifier: "workflow-runtime-hook-timeout"
      )
    }
  }

  private var serverStorageSectionContent: some View {
    Group {
      workflowTextField(
        "Server Host",
        text: workflowBinding(\.serverHost),
        identifier: "workflow-server-host"
      )
      workflowTextField(
        "Server Port",
        text: workflowBinding(\.serverPort),
        identifier: "workflow-server-port"
      )
      workflowTextField(
        "SQLite Path (Optional)",
        text: workflowBinding(\.storageSQLitePath),
        identifier: "workflow-storage-sqlite-path"
      )
      Toggle("Retain Raw Events", isOn: workflowBinding(\.storageRetainRawEvents))
        .toggleStyle(.switch)
        .accessibilityIdentifier("workflow-storage-retain-raw-events")
    }
  }

  // MARK: - Prompt Section

  private var promptSectionContent: some View {
    Group {
      Picker("Preset", selection: promptPresetBinding) {
        ForEach(WorkflowPromptPreset.allCases) { preset in
          Text(preset.title).tag(preset)
        }
      }
      .accessibilityIdentifier("workflow-prompt-preset")

      workflowTextEditor(
        "Prompt Body",
        text: workflowBinding(\.promptBody),
        identifier: "workflow-prompt-body",
        footer: "Supported placeholders include {{issue.title}}, {{issue.identifier}}, and {{issue.repository}}.",
        idealHeight: 220
      )
    }
  }

  // MARK: - Action Bar

  private var workflowAuthoringActionBar: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Save a validated workflow, then continue into local server setup.")
        .font(.footnote)
        .foregroundStyle(.secondary)

      HStack(spacing: 12) {
        Button(
          "Use Existing WORKFLOW.md",
          systemImage: "doc.badge.plus",
          action: model.chooseLocalWorkflow
        )
        .operatorSecondaryActionButton()
        .accessibilityIdentifier("workflow-choose-existing-button")

        Spacer()

        Button(
          "Save WORKFLOW.md",
          systemImage: "square.and.arrow.down",
          action: model.saveGeneratedWorkflow
        )
        .operatorProminentActionButton()
        .disabled(preview.validationError != nil)
        .accessibilityIdentifier("workflow-save-button")
      }
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 16)
    .background(
      Rectangle()
        .fill(Color(nsColor: .underPageBackgroundColor))
    )
  }

  // MARK: - Preview Pane

  private var workflowPreviewPane: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .top, spacing: 12) {
        VStack(alignment: .leading, spacing: 6) {
          Text("Preview")
            .font(.title3.weight(.semibold))
          Text("A live view of the WORKFLOW.md file that will be written to disk.")
            .font(.callout)
            .foregroundStyle(.secondary)
        }

        Spacer()

        Label(
          preview.validationError == nil ? "Validated Live" : "Needs Attention",
          systemImage: preview.validationError == nil
            ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
        )
        .font(.footnote.weight(.semibold))
        .foregroundStyle(preview.validationError == nil ? Color.green : Color.orange)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
          Capsule(style: .continuous)
            .fill(
              (preview.validationError == nil ? Color.green : Color.orange)
                .opacity(0.10)
            )
        )
        .overlay(
          Capsule(style: .continuous)
            .strokeBorder(
              (preview.validationError == nil ? Color.green : Color.orange).opacity(0.18),
              lineWidth: 1
            )
        )
      }

      ScrollView {
        Text(verbatim: preview.content)
          .font(.system(size: 13, weight: .regular, design: .monospaced))
          .lineSpacing(4)
          .frame(maxWidth: .infinity, alignment: .leading)
          .textSelection(.enabled)
          .padding(18)
      }
      .background(
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .fill(Color(nsColor: .textBackgroundColor))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
      )
      .accessibilityIdentifier("workflow-preview")
    }
    .padding(20)
    .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(Color(nsColor: .underPageBackgroundColor))
  }

  // MARK: - Helpers

  func workflowBinding<Value>(
    _ keyPath: WritableKeyPath<WorkflowAuthoringDraft, Value>
  ) -> Binding<Value> {
    Binding(
      get: { model.workflowAuthoringDraft[keyPath: keyPath] },
      set: { model.updateWorkflowAuthoringDraft(keyPath, value: $0) }
    )
  }

  private var promptPresetBinding: Binding<WorkflowPromptPreset> {
    Binding(
      get: { model.workflowAuthoringDraft.promptPreset },
      set: { model.applyWorkflowPromptPreset($0) }
    )
  }
}
#endif
