import Foundation
import SymphonyShared
import Yams

// MARK: - Workflow Parser (Section 6.1 / 6.2)

public enum WorkflowParser {
  public static func parse(contentsOf url: URL) throws -> WorkflowDefinition {
    let content: String
    do {
      content = try String(contentsOf: url, encoding: .utf8)
    } catch {
      throw WorkflowConfigError.missingWorkflowFile(url.path)
    }
    return try parse(content: content)
  }

  public static func parse(content: String) throws -> WorkflowDefinition {
    let (frontMatter, promptBody) = splitFrontMatter(content)
    let config: WorkflowConfig
    if let frontMatter {
      config = try parseConfig(yaml: frontMatter)
    } else {
      config = .defaults
    }
    return WorkflowDefinition(
      config: config, promptTemplate: promptBody.trimmingCharacters(in: .whitespacesAndNewlines))
  }

  public static func discover(
    explicitPath: String? = nil,
    workingDirectory: String = FileManager.default.currentDirectoryPath
  ) -> URL? {
    if let explicitPath {
      let expanded = NSString(string: explicitPath).expandingTildeInPath
      let url = URL(fileURLWithPath: expanded)
      return FileManager.default.isReadableFile(atPath: url.path) ? url : nil
    }
    let defaultURL = URL(fileURLWithPath: workingDirectory).appendingPathComponent("WORKFLOW.md")
    return FileManager.default.isReadableFile(atPath: defaultURL.path) ? defaultURL : nil
  }

  static func splitFrontMatter(_ content: String) -> (frontMatter: String?, promptBody: String) {
    let delimiter = "---"
    let trimmed = content.trimmingCharacters(in: .newlines)

    guard trimmed.hasPrefix(delimiter) else {
      return (nil, content)
    }

    let afterFirst = trimmed.dropFirst(delimiter.count)
    guard
      let closingRange = afterFirst.range(of: "\n\(delimiter)")
        ?? afterFirst.range(of: "\r\n\(delimiter)")
    else {
      return (nil, content)
    }

    let frontMatter = String(afterFirst[afterFirst.startIndex..<closingRange.lowerBound])
    let bodyStart = closingRange.upperBound
    let body: String
    if bodyStart < afterFirst.endIndex {
      body = String(afterFirst[bodyStart...])
    } else {
      body = ""
    }
    return (frontMatter, body)
  }

  static func parseConfig(yaml: String) throws -> WorkflowConfig {
    let parsed: Any?
    do {
      parsed = try Yams.load(yaml: yaml)
    } catch {
      throw WorkflowConfigError.workflowParseError(error.localizedDescription)
    }

    // Empty YAML (e.g. blank front matter) → use defaults
    guard let parsed else { return .defaults }

    guard let mapping = parsed as? [String: Any] else {
      throw WorkflowConfigError.workflowFrontMatterNotAMap
    }

    let tracker = parseTracker(mapping["tracker"])
    let polling = parsePolling(mapping["polling"])
    let workspace = parseWorkspace(mapping["workspace"])
    let hooks = parseHooks(mapping["hooks"])
    let analysis = parseAnalysis(mapping["analysis"])
    let agent = parseAgent(mapping["agent"])
    let providers = parseProviders(mapping["providers"])
    let server = parseServer(mapping["server"])
    let storage = parseStorage(mapping["storage"])

    return WorkflowConfig(
      tracker: tracker,
      polling: polling,
      workspace: workspace,
      hooks: hooks,
      analysis: analysis,
      agent: agent,
      providers: providers,
      server: server,
      storage: storage
    )
  }

  // MARK: - Section Parsers

  private static func parseTracker(_ value: Any?) -> TrackerConfig {
    guard let map = value as? [String: Any] else { return .defaults }
    return TrackerConfig(
      kind: map["kind"] as? String ?? "github",
      endpoint: map["endpoint"] as? String ?? "https://api.github.com/graphql",
      apiKey: map["api_key"] as? String,
      projectOwner: map["project_owner"] as? String,
      projectOwnerType: map["project_owner_type"] as? String,
      projectNumber: intValue(map["project_number"]),
      repositoryAllowlist: map["repository_allowlist"] as? [String] ?? [],
      statusFieldName: map["status_field_name"] as? String ?? "Status",
      activeStates: map["active_states"] as? [String] ?? ["Todo", "In Progress"],
      terminalStates: map["terminal_states"] as? [String] ?? ["Done"],
      blockedStates: map["blocked_states"] as? [String] ?? ["Todo"]
    )
  }

  private static func parsePolling(_ value: Any?) -> PollingConfig {
    guard let map = value as? [String: Any] else { return .defaults }
    return PollingConfig(intervalMS: intValue(map["interval_ms"]) ?? 30_000)
  }

  private static func parseWorkspace(_ value: Any?) -> WorkspaceConfig {
    guard let map = value as? [String: Any] else { return .defaults }
    return WorkspaceConfig(root: map["root"] as? String)
  }

  private static func parseHooks(_ value: Any?) -> HooksConfig {
    guard let map = value as? [String: Any] else { return .defaults }
    return HooksConfig(
      afterCreate: map["after_create"] as? String,
      beforeRun: map["before_run"] as? String,
      afterRun: map["after_run"] as? String,
      beforeRemove: map["before_remove"] as? String,
      timeoutMS: intValue(map["timeout_ms"]) ?? 60_000
    )
  }

  private static func parseAnalysis(_ value: Any?) -> AnalysisConfig {
    guard let map = value as? [String: Any] else { return .defaults }
    return AnalysisConfig(
      history: parseAnalysisHistory(map["history"]),
      syntax: parseAnalysisSyntax(map["syntax"])
    )
  }

  private static func parseAnalysisHistory(_ value: Any?) -> AnalysisHistoryConfig {
    guard let map = value as? [String: Any] else { return .defaults }
    return AnalysisHistoryConfig(
      sourcePaths: map["source_paths"] as? [String] ?? [],
      testPaths: map["test_paths"] as? [String] ?? []
    )
  }

  private static func parseAnalysisSyntax(_ value: Any?) -> AnalysisSyntaxConfig {
    guard let map = value as? [String: Any] else { return .defaults }
    return AnalysisSyntaxConfig(command: map["command"] as? String)
  }

  private static func parseAgent(_ value: Any?) -> AgentConfig {
    guard let map = value as? [String: Any] else { return .defaults }
    let providerStr = stringValue(map["default_provider"], "codex")
    let provider: ProviderName
    if let p = ProviderName(rawValue: providerStr) { provider = p } else { provider = .codex }
    return AgentConfig(
      defaultProvider: provider,
      maxConcurrentAgents: intOrDefault(map["max_concurrent_agents"], 10),
      maxTurns: intOrDefault(map["max_turns"], 20),
      maxRetryBackoffMS: intOrDefault(map["max_retry_backoff_ms"], 300_000),
      maxConcurrentAgentsByState: (map["max_concurrent_agents_by_state"] as? [String: Any])?
        .compactMapValues { intValue($0) } ?? [:]
    )
  }

  private static func parseProviders(_ value: Any?) -> ProvidersConfig {
    guard let map = value as? [String: Any] else { return .defaults }
    return ProvidersConfig(
      codex: parseCodexProvider(map["codex"]),
      claudeCode: parseClaudeCodeProvider(map["claude_code"]),
      copilotCLI: parseCopilotCLIProvider(map["copilot_cli"])
    )
  }

  private static func parseCodexProvider(_ value: Any?) -> CodexProviderConfig {
    guard let map = value as? [String: Any] else { return .defaults }
    let sessionApprovalPolicy = map["session_approval_policy"] as? String
    let sessionSandbox = codexSandboxValue(map["session_sandbox"])
    let turnApprovalPolicy = map["turn_approval_policy"] as? String ?? sessionApprovalPolicy
    return CodexProviderConfig(
      command: stringValue(map["command"], "codex app-server"),
      sessionApprovalPolicy: sessionApprovalPolicy,
      sessionSandbox: sessionSandbox,
      turnApprovalPolicy: turnApprovalPolicy,
      turnSandboxPolicy: codexSandboxValue(map["turn_sandbox_policy"]),
      turnTimeoutMS: intOrDefault(map["turn_timeout_ms"], 3_600_000),
      readTimeoutMS: intOrDefault(map["read_timeout_ms"], 5_000),
      stallTimeoutMS: intOrDefault(map["stall_timeout_ms"], 300_000)
    )
  }

  private static func parseClaudeCodeProvider(_ value: Any?) -> ClaudeCodeProviderConfig {
    guard let map = value as? [String: Any] else { return .defaults }
    return ClaudeCodeProviderConfig(
      command: stringValue(map["command"], "claude"),
      permissionMode: map["permission_mode"] as? String,
      allowedTools: map["allowed_tools"] as? [String] ?? [],
      disallowedTools: map["disallowed_tools"] as? [String] ?? [],
      turnTimeoutMS: intOrDefault(map["turn_timeout_ms"], 3_600_000),
      readTimeoutMS: intOrDefault(map["read_timeout_ms"], 5_000),
      stallTimeoutMS: intOrDefault(map["stall_timeout_ms"], 300_000)
    )
  }

  private static func parseCopilotCLIProvider(_ value: Any?) -> CopilotCLIProviderConfig {
    guard let map = value as? [String: Any] else { return .defaults }
    return CopilotCLIProviderConfig(
      command: stringValue(map["command"], "copilot --acp --stdio"),
      turnTimeoutMS: intOrDefault(map["turn_timeout_ms"], 3_600_000),
      readTimeoutMS: intOrDefault(map["read_timeout_ms"], 5_000),
      stallTimeoutMS: intOrDefault(map["stall_timeout_ms"], 300_000)
    )
  }

  private static func parseServer(_ value: Any?) -> SymphonyServerConfig {
    guard let map = value as? [String: Any] else { return .defaults }
    return SymphonyServerConfig(
      host: stringValue(map["host"], "127.0.0.1"),
      port: intOrDefault(map["port"], 8080)
    )
  }

  private static func parseStorage(_ value: Any?) -> StorageConfig {
    guard let map = value as? [String: Any] else { return .defaults }
    return StorageConfig(
      sqlitePath: map["sqlite_path"] as? String,
      retainRawEvents: boolOrDefault(map["retain_raw_events"], true)
    )
  }

  // MARK: - Value Helpers

  private static func stringValue(_ value: Any?, _ defaultValue: String) -> String {
    if let s = value as? String { return s }
    return defaultValue
  }

  static func codexSandboxValue(_ value: Any?) -> CodexSandboxValue? {
    guard let value else { return nil }

    switch value {
    case let value as String:
      return .string(value)
    case let value as Bool:
      return .bool(value)
    case let value as Int:
      return .integer(value)
    case let value as Double:
      return .double(value)
    case let value as [Any]:
      return .array(value.compactMap(codexSandboxValue))
    case let value as [String: Any]:
      return .object(value.compactMapValues(codexSandboxValue))
    case is NSNull:
      return .null
    default:
      return nil
    }
  }

  private static func intOrDefault(_ value: Any?, _ defaultValue: Int) -> Int {
    if let v = intValue(value) { return v }
    return defaultValue
  }

  private static func boolOrDefault(_ value: Any?, _ defaultValue: Bool) -> Bool {
    if let v = boolValue(value) { return v }
    return defaultValue
  }

  private static func intValue(_ value: Any?) -> Int? {
    if let i = value as? Int { return i }
    if let s = value as? String, let i = Int(s) { return i }
    return nil
  }

  private static func boolValue(_ value: Any?) -> Bool? {
    if let b = value as? Bool { return b }
    if let s = value as? String {
      switch s.lowercased() {
      case "true", "yes", "1": return true
      case "false", "no", "0": return false
      default: return nil
      }
    }
    return nil
  }
}
