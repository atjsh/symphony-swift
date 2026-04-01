#if os(macOS)
import SwiftUI
import SymphonyShared

extension WorkflowAuthoringEditorView {
  var agentProvidersSectionContent: some View {
    Group {
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
          footer: "Use \u{201C}State: 2\u{201D} or \u{201C}State=2\u{201D} per line.",
          idealHeight: 88
        )
      }

      Divider()

      codexProviderSection
      Divider()
      claudeProviderSection
      Divider()
      copilotProviderSection
    }
  }

  var codexProviderSection: some View {
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
        idealHeight: 88
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
        idealHeight: 88
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
  }

  var claudeProviderSection: some View {
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
        idealHeight: 88
      )
      workflowTextEditor(
        "Disallowed Tools",
        text: workflowBinding(\.claudeDisallowedToolsText),
        identifier: "workflow-provider-claude-disallowed-tools",
        footer: "One tool per line.",
        idealHeight: 88
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
  }

  var copilotProviderSection: some View {
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
}
#endif
