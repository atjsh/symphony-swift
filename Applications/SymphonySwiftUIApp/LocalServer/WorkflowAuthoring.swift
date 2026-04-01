#if os(macOS)
  import Foundation
  import SymphonyServerCore
  import SymphonyShared

  enum WorkflowAuthoringRenderer {
    static func preview(draft: WorkflowAuthoringDraft) -> WorkflowAuthoringPreviewState {
      let content = render(draft: draft)
      do {
        try validate(draft: draft, content: content)
        return WorkflowAuthoringPreviewState(content: content, validationError: nil)
      } catch {
        return WorkflowAuthoringPreviewState(
          content: content,
          validationError: error.localizedDescription
        )
      }
    }

    static func validatedContent(draft: WorkflowAuthoringDraft) throws -> String {
      let content = render(draft: draft)
      try validate(draft: draft, content: content)
      return content
    }

    private static func validate(draft: WorkflowAuthoringDraft, content: String) throws {
      try requireInteger(named: "tracker project number", value: draft.trackerProjectNumber, optional: true)
      try requireInteger(named: "polling interval", value: draft.pollingIntervalMS)
      try requireInteger(named: "hooks timeout", value: draft.hooksTimeoutMS)
      try requireInteger(named: "max concurrent agents", value: draft.agentMaxConcurrentAgents)
      try requireInteger(named: "max turns", value: draft.agentMaxTurns)
      try requireInteger(named: "max retry backoff", value: draft.agentMaxRetryBackoffMS)
      try requireStateConcurrencyMap(draft.agentMaxConcurrentAgentsByStateText)
      try requireInteger(named: "Codex turn timeout", value: draft.codexTurnTimeoutMS)
      try requireInteger(named: "Codex read timeout", value: draft.codexReadTimeoutMS)
      try requireInteger(named: "Codex stall timeout", value: draft.codexStallTimeoutMS)
      try requireInteger(named: "Claude Code turn timeout", value: draft.claudeTurnTimeoutMS)
      try requireInteger(named: "Claude Code read timeout", value: draft.claudeReadTimeoutMS)
      try requireInteger(named: "Claude Code stall timeout", value: draft.claudeStallTimeoutMS)
      try requireInteger(named: "Copilot CLI turn timeout", value: draft.copilotTurnTimeoutMS)
      try requireInteger(named: "Copilot CLI read timeout", value: draft.copilotReadTimeoutMS)
      try requireInteger(named: "Copilot CLI stall timeout", value: draft.copilotStallTimeoutMS)
      try requireInteger(named: "server port", value: draft.serverPort)
      _ = try WorkflowParser.parse(content: content)
    }

    private static func render(draft: WorkflowAuthoringDraft) -> String {
      var lines = [String]()
      lines.append("---")
      lines.append("tracker:")
      lines.append("  kind: \"github\"")
      lines.append("  endpoint: \(yamlQuoted(draft.trackerEndpoint))")
      if let apiKeyVariable = normalized(draft.trackerGitHubTokenVariableName) {
        lines.append("  api_key: \(yamlQuoted("$\(apiKeyVariable)"))")
      }
      appendOptionalString(draft.trackerProjectOwner, key: "project_owner", to: &lines, indent: 2)
      appendOptionalString(
        draft.trackerProjectOwnerType,
        key: "project_owner_type",
        to: &lines,
        indent: 2
      )
      appendOptionalInteger(draft.trackerProjectNumber, key: "project_number", to: &lines, indent: 2)
      appendStringArray(
        parseList(draft.trackerRepositoryAllowlistText),
        key: "repository_allowlist",
        to: &lines,
        indent: 2
      )
      lines.append("  status_field_name: \(yamlQuoted(draft.trackerStatusFieldName))")
      appendStringArray(parseList(draft.trackerActiveStatesText), key: "active_states", to: &lines, indent: 2)
      appendStringArray(
        parseList(draft.trackerTerminalStatesText),
        key: "terminal_states",
        to: &lines,
        indent: 2
      )
      appendStringArray(parseList(draft.trackerBlockedStatesText), key: "blocked_states", to: &lines, indent: 2)

      lines.append("polling:")
      lines.append(
        "  interval_ms: \(draft.pollingIntervalMS.trimmingCharacters(in: .whitespacesAndNewlines))"
      )

      lines.append("workspace:")
      lines.append("  root: \(yamlQuoted(draft.workspaceRoot))")

      lines.append("hooks:")
      appendOptionalString(draft.hooksAfterCreate, key: "after_create", to: &lines, indent: 2)
      appendOptionalString(draft.hooksBeforeRun, key: "before_run", to: &lines, indent: 2)
      appendOptionalString(draft.hooksAfterRun, key: "after_run", to: &lines, indent: 2)
      appendOptionalString(draft.hooksBeforeRemove, key: "before_remove", to: &lines, indent: 2)
      lines.append("  timeout_ms: \(draft.hooksTimeoutMS.trimmingCharacters(in: .whitespacesAndNewlines))")

      lines.append("agent:")
      lines.append("  default_provider: \(yamlQuoted(draft.agentDefaultProvider.rawValue))")
      lines.append(
        "  max_concurrent_agents: \(draft.agentMaxConcurrentAgents.trimmingCharacters(in: .whitespacesAndNewlines))"
      )
      lines.append("  max_turns: \(draft.agentMaxTurns.trimmingCharacters(in: .whitespacesAndNewlines))")
      lines.append(
        "  max_retry_backoff_ms: \(draft.agentMaxRetryBackoffMS.trimmingCharacters(in: .whitespacesAndNewlines))"
      )
      appendIntegerMap(
        parseStateConcurrencyMap(draft.agentMaxConcurrentAgentsByStateText),
        key: "max_concurrent_agents_by_state",
        to: &lines,
        indent: 2
      )

      lines.append("providers:")
      lines.append("  codex:")
      lines.append("    command: \(yamlQuoted(draft.codexCommand))")
      appendOptionalString(
        draft.codexSessionApprovalPolicy,
        key: "session_approval_policy",
        to: &lines,
        indent: 4
      )
      appendYAMLValue(draft.codexSessionSandbox, key: "session_sandbox", to: &lines, indent: 4)
      appendOptionalString(
        draft.codexTurnApprovalPolicy,
        key: "turn_approval_policy",
        to: &lines,
        indent: 4
      )
      appendYAMLValue(
        draft.codexTurnSandboxPolicy,
        key: "turn_sandbox_policy",
        to: &lines,
        indent: 4
      )
      lines.append(
        "    turn_timeout_ms: \(draft.codexTurnTimeoutMS.trimmingCharacters(in: .whitespacesAndNewlines))"
      )
      lines.append(
        "    read_timeout_ms: \(draft.codexReadTimeoutMS.trimmingCharacters(in: .whitespacesAndNewlines))"
      )
      lines.append(
        "    stall_timeout_ms: \(draft.codexStallTimeoutMS.trimmingCharacters(in: .whitespacesAndNewlines))"
      )

      lines.append("  claude_code:")
      lines.append("    command: \(yamlQuoted(draft.claudeCommand))")
      appendOptionalString(draft.claudePermissionMode, key: "permission_mode", to: &lines, indent: 4)
      appendStringArray(parseList(draft.claudeAllowedToolsText), key: "allowed_tools", to: &lines, indent: 4)
      appendStringArray(
        parseList(draft.claudeDisallowedToolsText),
        key: "disallowed_tools",
        to: &lines,
        indent: 4
      )
      lines.append(
        "    turn_timeout_ms: \(draft.claudeTurnTimeoutMS.trimmingCharacters(in: .whitespacesAndNewlines))"
      )
      lines.append(
        "    read_timeout_ms: \(draft.claudeReadTimeoutMS.trimmingCharacters(in: .whitespacesAndNewlines))"
      )
      lines.append(
        "    stall_timeout_ms: \(draft.claudeStallTimeoutMS.trimmingCharacters(in: .whitespacesAndNewlines))"
      )

      lines.append("  copilot_cli:")
      lines.append("    command: \(yamlQuoted(draft.copilotCommand))")
      lines.append(
        "    turn_timeout_ms: \(draft.copilotTurnTimeoutMS.trimmingCharacters(in: .whitespacesAndNewlines))"
      )
      lines.append(
        "    read_timeout_ms: \(draft.copilotReadTimeoutMS.trimmingCharacters(in: .whitespacesAndNewlines))"
      )
      lines.append(
        "    stall_timeout_ms: \(draft.copilotStallTimeoutMS.trimmingCharacters(in: .whitespacesAndNewlines))"
      )

      lines.append("server:")
      lines.append("  host: \(yamlQuoted(draft.serverHost))")
      lines.append("  port: \(draft.serverPort.trimmingCharacters(in: .whitespacesAndNewlines))")

      lines.append("storage:")
      appendOptionalString(draft.storageSQLitePath, key: "sqlite_path", to: &lines, indent: 2)
      lines.append("  retain_raw_events: \(draft.storageRetainRawEvents ? "true" : "false")")
      lines.append("---")

      let promptBody = draft.promptBody.trimmingCharacters(in: .whitespacesAndNewlines)
      if promptBody.isEmpty {
        return lines.joined(separator: "\n") + "\n"
      }
      return lines.joined(separator: "\n") + "\n\n" + promptBody + "\n"
    }

    private static func normalized(_ value: String) -> String? {
      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? nil : trimmed
    }

    private static func yamlQuoted(_ value: String) -> String {
      let escaped = value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
      return "\"\(escaped)\""
    }

    private static func parseList(_ value: String) -> [String] {
      value
        .split(whereSeparator: \.isNewline)
        .flatMap { line in
          line.split(separator: ",", omittingEmptySubsequences: true)
        }
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    }

    private static func parseStateConcurrencyMap(_ value: String) -> [String: Int] {
      var result = [String: Int]()
      for line in value.split(whereSeparator: \.isNewline) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
          continue
        }
        let parts = trimmed.contains(":")
          ? trimmed.split(separator: ":", maxSplits: 1).map(String.init)
          : trimmed.split(separator: "=", maxSplits: 1).map(String.init)
        guard parts.count == 2 else {
          continue
        }
        let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let value = Int(parts[1].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        if !key.isEmpty {
          result[key] = value
        }
      }
      return result
    }

    private static func appendOptionalString(
      _ value: String,
      key: String,
      to lines: inout [String],
      indent: Int
    ) {
      guard let normalized = normalized(value) else {
        return
      }
      lines.append("\(String(repeating: " ", count: indent))\(key): \(yamlQuoted(normalized))")
    }

    private static func appendOptionalInteger(
      _ value: String,
      key: String,
      to lines: inout [String],
      indent: Int
    ) {
      guard let normalized = normalized(value) else {
        return
      }
      lines.append("\(String(repeating: " ", count: indent))\(key): \(normalized)")
    }

    private static func appendStringArray(
      _ values: [String],
      key: String,
      to lines: inout [String],
      indent: Int
    ) {
      let padding = String(repeating: " ", count: indent)
      if values.isEmpty {
        lines.append("\(padding)\(key): []")
        return
      }
      lines.append("\(padding)\(key):")
      for value in values {
        lines.append("\(padding)  - \(yamlQuoted(value))")
      }
    }

    private static func appendIntegerMap(
      _ values: [String: Int],
      key: String,
      to lines: inout [String],
      indent: Int
    ) {
      let padding = String(repeating: " ", count: indent)
      if values.isEmpty {
        lines.append("\(padding)\(key): {}")
        return
      }
      lines.append("\(padding)\(key):")
      for key in values.keys.sorted() {
        guard let value = values[key] else {
          continue
        }
        lines.append("\(padding)  \(yamlQuoted(key)): \(value)")
      }
    }

    private static func appendYAMLValue(
      _ value: String,
      key: String,
      to lines: inout [String],
      indent: Int
    ) {
      guard let normalized = normalized(value) else {
        return
      }

      let padding = String(repeating: " ", count: indent)
      if normalized.contains("\n") {
        lines.append("\(padding)\(key):")
        for line in normalized.split(
          omittingEmptySubsequences: false,
          whereSeparator: \.isNewline
        ) {
          lines.append("\(padding)  \(line)")
        }
        return
      }

      if normalized == "true"
        || normalized == "false"
        || normalized == "null"
        || Int(normalized) != nil
        || Double(normalized) != nil
      {
        lines.append("\(padding)\(key): \(normalized)")
      } else {
        lines.append("\(padding)\(key): \(yamlQuoted(normalized))")
      }
    }

    private static func requireInteger(named field: String, value: String, optional: Bool = false) throws {
      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      if optional && trimmed.isEmpty {
        return
      }
      guard Int(trimmed) != nil else {
        throw WorkflowAuthoringError.invalidInteger(field: field, value: trimmed)
      }
    }

    private static func requireStateConcurrencyMap(_ value: String) throws {
      for line in value.split(whereSeparator: \.isNewline) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
          continue
        }
        let parts = trimmed.contains(":")
          ? trimmed.split(separator: ":", maxSplits: 1)
          : trimmed.split(separator: "=", maxSplits: 1)
        guard parts.count == 2,
          Int(parts[1].trimmingCharacters(in: .whitespacesAndNewlines)) != nil
        else {
          throw WorkflowAuthoringError.invalidStateConcurrencyLine(trimmed)
        }
      }
    }
  }

#endif
