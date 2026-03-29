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
  @ObservedObject private var model: SymphonyOperatorModel
  @Environment(\.dismiss) private var dismiss

  @State private var draftHost: String
  @State private var draftPort: String
  #if os(macOS)
    @State private var selectedMode: ServerEditorMode
    @State private var isTrackerExpanded = true
    @State private var isRuntimeExpanded = false
    @State private var isAgentProvidersExpanded = false
    @State private var isServerStorageExpanded = false
    @State private var isPromptExpanded = true
  #endif

  #if os(macOS)
    init(
      model: SymphonyOperatorModel,
      initialMode: ServerEditorMode = .localServer
    ) {
      self._model = ObservedObject(wrappedValue: model)
      self._draftHost = State(initialValue: model.host)
      self._draftPort = State(initialValue: model.portText)
      self._selectedMode = State(initialValue: initialMode)
    }
  #else
    init(model: SymphonyOperatorModel) {
      self._model = ObservedObject(wrappedValue: model)
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
          Button("Cancel", action: makeEndpointDismissAction(dismiss.callAsFunction))
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
        workflowAuthoringRoot
          .frame(minWidth: 1040)
      } else {
        Form {
          macOSConnectionTypePicker
          if model.hasLocalServerSupport && selectedMode == .localServer {
            localServerSections
          } else {
            existingServerSections
          }
        }
        .frame(minWidth: 680)
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
          action: makeEndpointConnectAction(
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

    private var workflowAuthoringRoot: some View {
      let preview = model.workflowAuthoringPreview

      return VStack(spacing: 0) {
        VStack(spacing: 16) {
          macOSConnectionTypePicker
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
                    minHeight: 88
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
                    minHeight: 72
                  )
                  workflowTextEditor(
                    "Terminal States",
                    text: workflowBinding(\.trackerTerminalStatesText),
                    identifier: "workflow-tracker-terminal-states",
                    footer: "One state per line.",
                    minHeight: 72
                  )
                  workflowTextEditor(
                    "Blocked States",
                    text: workflowBinding(\.trackerBlockedStatesText),
                    identifier: "workflow-tracker-blocked-states",
                    footer: "One state per line.",
                    minHeight: 72
                  )
                }

                workflowSection(
                  title: "Runtime",
                  subtitle: "Tune polling, workspace location, and lifecycle hooks.",
                  isExpanded: $isRuntimeExpanded
                ) {
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

                workflowSection(
                  title: "Agent & Providers",
                  subtitle: "Pick defaults for the orchestrator and adjust provider commands and timeouts.",
                  isExpanded: $isAgentProvidersExpanded
                ) {
                  VStack(alignment: .leading, spacing: 14) {
                    Text("Agent")
                      .font(.headline)
                    Picker("Default Provider", selection: workflowBinding(\.agentDefaultProvider)) {
                      ForEach(ProviderName.allCases, id: \.self) { provider in
                        Text(provider.rawValue).tag(provider)
                      }
                    }
                    .accessibilityIdentifier("workflow-agent-default-provider")
                    workflowTextField(
                      "Max Concurrent Agents",
                      text: workflowBinding(\.agentMaxConcurrentAgents),
                      identifier: "workflow-agent-max-concurrent"
                    )
                    workflowTextField(
                      "Max Turns",
                      text: workflowBinding(\.agentMaxTurns),
                      identifier: "workflow-agent-max-turns"
                    )
                    workflowTextField(
                      "Max Retry Backoff (ms)",
                      text: workflowBinding(\.agentMaxRetryBackoffMS),
                      identifier: "workflow-agent-max-retry-backoff"
                    )
                    workflowTextEditor(
                      "Max Concurrent Agents By State",
                      text: workflowBinding(\.agentMaxConcurrentAgentsByStateText),
                      identifier: "workflow-agent-state-limits",
                      footer: "Use “State: 2” or “State=2” per line.",
                      minHeight: 88
                    )
                  }

                  Divider()

                  VStack(alignment: .leading, spacing: 14) {
                    Text("Codex")
                      .font(.headline)
                    workflowTextField(
                      "Command",
                      text: workflowBinding(\.codexCommand),
                      identifier: "workflow-provider-codex-command"
                    )
                    workflowTextField(
                      "Session Approval Policy",
                      text: workflowBinding(\.codexSessionApprovalPolicy),
                      identifier: "workflow-provider-codex-session-approval"
                    )
                    workflowTextEditor(
                      "Session Sandbox",
                      text: workflowBinding(\.codexSessionSandbox),
                      identifier: "workflow-provider-codex-session-sandbox",
                      footer: "Enter a single value or multiline YAML.",
                      minHeight: 88
                    )
                    workflowTextField(
                      "Turn Approval Policy",
                      text: workflowBinding(\.codexTurnApprovalPolicy),
                      identifier: "workflow-provider-codex-turn-approval"
                    )
                    workflowTextEditor(
                      "Turn Sandbox Policy",
                      text: workflowBinding(\.codexTurnSandboxPolicy),
                      identifier: "workflow-provider-codex-turn-sandbox",
                      footer: "Enter a single value or multiline YAML.",
                      minHeight: 88
                    )
                    workflowTextField(
                      "Turn Timeout (ms)",
                      text: workflowBinding(\.codexTurnTimeoutMS),
                      identifier: "workflow-provider-codex-turn-timeout"
                    )
                    workflowTextField(
                      "Read Timeout (ms)",
                      text: workflowBinding(\.codexReadTimeoutMS),
                      identifier: "workflow-provider-codex-read-timeout"
                    )
                    workflowTextField(
                      "Stall Timeout (ms)",
                      text: workflowBinding(\.codexStallTimeoutMS),
                      identifier: "workflow-provider-codex-stall-timeout"
                    )
                  }

                  Divider()

                  VStack(alignment: .leading, spacing: 14) {
                    Text("Claude Code")
                      .font(.headline)
                    workflowTextField(
                      "Command",
                      text: workflowBinding(\.claudeCommand),
                      identifier: "workflow-provider-claude-command"
                    )
                    workflowTextField(
                      "Permission Mode",
                      text: workflowBinding(\.claudePermissionMode),
                      identifier: "workflow-provider-claude-permission-mode"
                    )
                    workflowTextEditor(
                      "Allowed Tools",
                      text: workflowBinding(\.claudeAllowedToolsText),
                      identifier: "workflow-provider-claude-allowed-tools",
                      footer: "One tool per line.",
                      minHeight: 88
                    )
                    workflowTextEditor(
                      "Disallowed Tools",
                      text: workflowBinding(\.claudeDisallowedToolsText),
                      identifier: "workflow-provider-claude-disallowed-tools",
                      footer: "One tool per line.",
                      minHeight: 88
                    )
                    workflowTextField(
                      "Turn Timeout (ms)",
                      text: workflowBinding(\.claudeTurnTimeoutMS),
                      identifier: "workflow-provider-claude-turn-timeout"
                    )
                    workflowTextField(
                      "Read Timeout (ms)",
                      text: workflowBinding(\.claudeReadTimeoutMS),
                      identifier: "workflow-provider-claude-read-timeout"
                    )
                    workflowTextField(
                      "Stall Timeout (ms)",
                      text: workflowBinding(\.claudeStallTimeoutMS),
                      identifier: "workflow-provider-claude-stall-timeout"
                    )
                  }

                  Divider()

                  VStack(alignment: .leading, spacing: 14) {
                    Text("Copilot CLI")
                      .font(.headline)
                    workflowTextField(
                      "Command",
                      text: workflowBinding(\.copilotCommand),
                      identifier: "workflow-provider-copilot-command"
                    )
                    workflowTextField(
                      "Turn Timeout (ms)",
                      text: workflowBinding(\.copilotTurnTimeoutMS),
                      identifier: "workflow-provider-copilot-turn-timeout"
                    )
                    workflowTextField(
                      "Read Timeout (ms)",
                      text: workflowBinding(\.copilotReadTimeoutMS),
                      identifier: "workflow-provider-copilot-read-timeout"
                    )
                    workflowTextField(
                      "Stall Timeout (ms)",
                      text: workflowBinding(\.copilotStallTimeoutMS),
                      identifier: "workflow-provider-copilot-stall-timeout"
                    )
                  }
                }

                workflowSection(
                  title: "Server & Storage",
                  subtitle: "Seed the generated workflow with server defaults and storage preferences.",
                  isExpanded: $isServerStorageExpanded
                ) {
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

                workflowSection(
                  title: "Prompt",
                  subtitle: "Start from a preset, then tailor the body to match your team’s workflow.",
                  isExpanded: $isPromptExpanded
                ) {
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
                    minHeight: 220
                  )
                }
              }
              .padding(.horizontal, 20)
              .padding(.top, 20)
              .padding(.bottom, 24)
              .frame(maxWidth: 620, alignment: .leading)
            }

            Divider()

            workflowAuthoringActionBar(preview: preview)
          }
          .frame(minWidth: 520, maxWidth: 620, maxHeight: .infinity, alignment: .topLeading)
          .background(Color(nsColor: .windowBackgroundColor))
          .accessibilityElement(children: .contain)
          .accessibilityIdentifier("workflow-authoring-step")

          workflowPreviewPane(preview: preview)
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
            .frame(minHeight: 120)
          } header: {
            Text("Launch Transcript")
          }
        }

        Section {
          Button(
            model.localServerPrimaryActionTitle,
            systemImage: model.isLocalServerRunning
              ? "arrow.clockwise.circle" : "play.circle",
            action: makeLocalServerStartAction(
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
              action: makeLocalServerStopAction(model: model)
            )
            .operatorSecondaryActionButton()
            .accessibilityIdentifier("local-server-stop-button")
          }
        } footer: {
          Text("The local helper launches the bundled Symphony server and reconnects the app automatically when health checks succeed.")
        }
      }
    }

    private var workflowAuthoringInlineError: String? {
      model.workflowAuthoringFailure ?? model.workflowAuthoringPreview.validationError
    }

    private func workflowBinding<Value>(
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

    private func workflowStepHeader(
      eyebrow: String,
      title: String,
      message: String
    ) -> some View {
      VStack(alignment: .leading, spacing: 10) {
        Text(eyebrow.uppercased())
          .font(.caption2.weight(.bold))
          .tracking(0.6)
          .padding(.horizontal, 10)
          .padding(.vertical, 5)
          .background(
            Capsule(style: .continuous)
              .fill(Color.accentColor.opacity(0.08))
          )
          .overlay(
            Capsule(style: .continuous)
              .strokeBorder(Color.accentColor.opacity(0.14), lineWidth: 1)
          )
          .foregroundStyle(Color.accentColor)
        Text(title)
          .font(.title3.weight(.semibold))
        Text(message)
          .font(.callout)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func workflowAuthoringActionBar(
      preview: WorkflowAuthoringPreviewState
    ) -> some View {
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

    private func workflowPreviewPane(
      preview: WorkflowAuthoringPreviewState
    ) -> some View {
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

    private func workflowInlineError(message: String) -> some View {
      Label {
        Text(message)
          .font(.callout)
      } icon: {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.orange)
      }
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(Color.orange.opacity(0.12))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .strokeBorder(Color.orange.opacity(0.18), lineWidth: 1)
      )
    }

    private func workflowSection<Content: View>(
      title: String,
      subtitle: String,
      isExpanded: Binding<Bool>,
      @ViewBuilder content: @escaping () -> Content
    ) -> some View {
      GroupBox {
        DisclosureGroup(isExpanded: isExpanded) {
          VStack(alignment: .leading, spacing: 14) {
            content()
          }
          .padding(.top, 10)
        } label: {
          VStack(alignment: .leading, spacing: 4) {
            Text(title)
              .font(.headline.weight(.semibold))
            Text(subtitle)
              .font(.footnote)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
          .padding(.vertical, 2)
        }
      }
    }

    private func workflowTextField(
      _ title: String,
      text: Binding<String>,
      identifier: String
    ) -> some View {
      VStack(alignment: .leading, spacing: 6) {
        Text(title)
          .font(.footnote.weight(.semibold))
          .foregroundStyle(.secondary)
        TextField(title, text: text)
          .textFieldStyle(.roundedBorder)
          .accessibilityIdentifier(identifier)
      }
    }

    private func workflowTextEditor(
      _ title: String,
      text: Binding<String>,
      identifier: String,
      footer: String,
      minHeight: CGFloat
    ) -> some View {
      VStack(alignment: .leading, spacing: 6) {
        Text(title)
          .font(.footnote.weight(.semibold))
          .foregroundStyle(.secondary)
        TextEditor(text: text)
          .font(.body)
          .frame(minHeight: minHeight)
          .padding(6)
          .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
              .fill(Color(nsColor: .textBackgroundColor))
          )
          .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
              .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
          )
          .accessibilityIdentifier(identifier)
        Text(footer)
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
  #endif
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

#if os(macOS)
  @MainActor
  func operatorLocalServerStart(
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
  func makeLocalServerStartAction(
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
  func makeLocalServerStopAction(model: SymphonyOperatorModel) -> () -> Void {
    {
      Task { @MainActor in
        await model.stopLocalServer()
      }
    }
  }
#endif
