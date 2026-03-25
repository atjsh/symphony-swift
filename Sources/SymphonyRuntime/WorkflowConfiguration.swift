import Foundation
import SymphonyShared
import Yams

// MARK: - Configuration Error (Section 6.1)

public enum WorkflowConfigError: Error, Equatable, Sendable {
  case missingWorkflowFile(String)
  case workflowParseError(String)
  case workflowFrontMatterNotAMap
  case invalidConfigValue(String)
}

// MARK: - Workflow Definition (Section 5.2 / 6.2)

public struct WorkflowDefinition: Equatable, Sendable {
  public let config: WorkflowConfig
  public let promptTemplate: String

  public init(config: WorkflowConfig, promptTemplate: String) {
    self.config = config
    self.promptTemplate = promptTemplate
  }
}

// MARK: - Top-Level Config (Section 6.3)

public struct WorkflowConfig: Equatable, Sendable {
  public let tracker: TrackerConfig
  public let polling: PollingConfig
  public let workspace: WorkspaceConfig
  public let hooks: HooksConfig
  public let agent: AgentConfig
  public let providers: ProvidersConfig
  public let server: SymphonyServerConfig
  public let storage: StorageConfig

  public init(
    tracker: TrackerConfig = .defaults,
    polling: PollingConfig = .defaults,
    workspace: WorkspaceConfig = .defaults,
    hooks: HooksConfig = .defaults,
    agent: AgentConfig = .defaults,
    providers: ProvidersConfig = .defaults,
    server: SymphonyServerConfig = .defaults,
    storage: StorageConfig = .defaults
  ) {
    self.tracker = tracker
    self.polling = polling
    self.workspace = workspace
    self.hooks = hooks
    self.agent = agent
    self.providers = providers
    self.server = server
    self.storage = storage
  }

  public static let defaults = WorkflowConfig()
}

// MARK: - Tracker Config (Section 6.3.1)

public struct TrackerConfig: Equatable, Sendable {
  public let kind: String
  public let endpoint: String
  public let apiKey: String?
  public let projectOwner: String?
  public let projectOwnerType: String?
  public let projectNumber: Int?
  public let repositoryAllowlist: [String]
  public let statusFieldName: String
  public let activeStates: [String]
  public let terminalStates: [String]
  public let blockedStates: [String]

  public init(
    kind: String = "github",
    endpoint: String = "https://api.github.com/graphql",
    apiKey: String? = nil,
    projectOwner: String? = nil,
    projectOwnerType: String? = nil,
    projectNumber: Int? = nil,
    repositoryAllowlist: [String] = [],
    statusFieldName: String = "Status",
    activeStates: [String] = ["Todo", "In Progress"],
    terminalStates: [String] = ["Done"],
    blockedStates: [String] = ["Todo"]
  ) {
    self.kind = kind
    self.endpoint = endpoint
    self.apiKey = apiKey
    self.projectOwner = projectOwner
    self.projectOwnerType = projectOwnerType
    self.projectNumber = projectNumber
    self.repositoryAllowlist = repositoryAllowlist
    self.statusFieldName = statusFieldName
    self.activeStates = activeStates
    self.terminalStates = terminalStates
    self.blockedStates = blockedStates
  }

  public static let defaults = TrackerConfig()
}

// MARK: - Polling Config (Section 6.3.2)

public struct PollingConfig: Equatable, Sendable {
  public let intervalMS: Int

  public init(intervalMS: Int = 30_000) {
    self.intervalMS = intervalMS
  }

  public static let defaults = PollingConfig()
}

// MARK: - Workspace Config (Section 6.3.3)

public struct WorkspaceConfig: Equatable, Sendable {
  public let root: String

  public init(root: String? = nil) {
    self.root = root ?? Self.defaultRoot
  }

  public static let defaults = WorkspaceConfig()

  public static var defaultRoot: String {
    NSTemporaryDirectory() + "symphony_workspaces"
  }
}

// MARK: - Hooks Config (Section 6.3.4)

public struct HooksConfig: Equatable, Sendable {
  public let afterCreate: String?
  public let beforeRun: String?
  public let afterRun: String?
  public let beforeRemove: String?
  public let timeoutMS: Int

  public init(
    afterCreate: String? = nil,
    beforeRun: String? = nil,
    afterRun: String? = nil,
    beforeRemove: String? = nil,
    timeoutMS: Int = 60_000
  ) {
    self.afterCreate = afterCreate
    self.beforeRun = beforeRun
    self.afterRun = afterRun
    self.beforeRemove = beforeRemove
    self.timeoutMS = timeoutMS
  }

  public static let defaults = HooksConfig()
}

// MARK: - Agent Config (Section 6.3.5)

public struct AgentConfig: Equatable, Sendable {
  public let defaultProvider: ProviderName
  public let maxConcurrentAgents: Int
  public let maxTurns: Int
  public let maxRetryBackoffMS: Int
  public let maxConcurrentAgentsByState: [String: Int]

  public init(
    defaultProvider: ProviderName = .codex,
    maxConcurrentAgents: Int = 10,
    maxTurns: Int = 20,
    maxRetryBackoffMS: Int = 300_000,
    maxConcurrentAgentsByState: [String: Int] = [:]
  ) {
    self.defaultProvider = defaultProvider
    self.maxConcurrentAgents = maxConcurrentAgents
    self.maxTurns = maxTurns
    self.maxRetryBackoffMS = maxRetryBackoffMS
    self.maxConcurrentAgentsByState = maxConcurrentAgentsByState
  }

  public static let defaults = AgentConfig()
}

// MARK: - Provider Configs (Section 6.3.6)

public struct ProvidersConfig: Equatable, Sendable {
  public let codex: CodexProviderConfig
  public let claudeCode: ClaudeCodeProviderConfig
  public let copilotCLI: CopilotCLIProviderConfig

  public init(
    codex: CodexProviderConfig = .defaults,
    claudeCode: ClaudeCodeProviderConfig = .defaults,
    copilotCLI: CopilotCLIProviderConfig = .defaults
  ) {
    self.codex = codex
    self.claudeCode = claudeCode
    self.copilotCLI = copilotCLI
  }

  public static let defaults = ProvidersConfig()

  public func stallTimeoutMS(for provider: ProviderName) -> Int {
    switch provider {
    case .codex: return codex.stallTimeoutMS
    case .claudeCode: return claudeCode.stallTimeoutMS
    case .copilotCLI: return copilotCLI.stallTimeoutMS
    }
  }
}

public struct CodexProviderConfig: Equatable, Sendable {
  public let command: String
  public let approvalPolicy: String?
  public let threadSandbox: String?
  public let turnSandboxPolicy: String?
  public let turnTimeoutMS: Int
  public let readTimeoutMS: Int
  public let stallTimeoutMS: Int

  public init(
    command: String = "codex app-server",
    approvalPolicy: String? = nil,
    threadSandbox: String? = nil,
    turnSandboxPolicy: String? = nil,
    turnTimeoutMS: Int = 3_600_000,
    readTimeoutMS: Int = 5_000,
    stallTimeoutMS: Int = 300_000
  ) {
    self.command = command
    self.approvalPolicy = approvalPolicy
    self.threadSandbox = threadSandbox
    self.turnSandboxPolicy = turnSandboxPolicy
    self.turnTimeoutMS = turnTimeoutMS
    self.readTimeoutMS = readTimeoutMS
    self.stallTimeoutMS = stallTimeoutMS
  }

  public static let defaults = CodexProviderConfig()
}

public struct ClaudeCodeProviderConfig: Equatable, Sendable {
  public let command: String
  public let permissionMode: String?
  public let allowedTools: [String]
  public let disallowedTools: [String]
  public let turnTimeoutMS: Int
  public let readTimeoutMS: Int
  public let stallTimeoutMS: Int

  public init(
    command: String = "claude",
    permissionMode: String? = nil,
    allowedTools: [String] = [],
    disallowedTools: [String] = [],
    turnTimeoutMS: Int = 3_600_000,
    readTimeoutMS: Int = 5_000,
    stallTimeoutMS: Int = 300_000
  ) {
    self.command = command
    self.permissionMode = permissionMode
    self.allowedTools = allowedTools
    self.disallowedTools = disallowedTools
    self.turnTimeoutMS = turnTimeoutMS
    self.readTimeoutMS = readTimeoutMS
    self.stallTimeoutMS = stallTimeoutMS
  }

  public static let defaults = ClaudeCodeProviderConfig()
}

public struct CopilotCLIProviderConfig: Equatable, Sendable {
  public let command: String
  public let turnTimeoutMS: Int
  public let readTimeoutMS: Int
  public let stallTimeoutMS: Int

  public init(
    command: String = "copilot --acp --stdio",
    turnTimeoutMS: Int = 3_600_000,
    readTimeoutMS: Int = 5_000,
    stallTimeoutMS: Int = 300_000
  ) {
    self.command = command
    self.turnTimeoutMS = turnTimeoutMS
    self.readTimeoutMS = readTimeoutMS
    self.stallTimeoutMS = stallTimeoutMS
  }

  public static let defaults = CopilotCLIProviderConfig()
}

// MARK: - Server Config (Section 6.3.7)

public struct SymphonyServerConfig: Equatable, Sendable {
  public let host: String
  public let port: Int

  public init(host: String = "127.0.0.1", port: Int = 8080) {
    self.host = host
    self.port = port
  }

  public static let defaults = SymphonyServerConfig()
}

// MARK: - Storage Config (Section 6.3.8)

public struct StorageConfig: Equatable, Sendable {
  public let sqlitePath: String?
  public let retainRawEvents: Bool

  public init(sqlitePath: String? = nil, retainRawEvents: Bool = true) {
    self.sqlitePath = sqlitePath
    self.retainRawEvents = retainRawEvents
  }

  public static let defaults = StorageConfig()
}

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
    let agent = parseAgent(mapping["agent"])
    let providers = parseProviders(mapping["providers"])
    let server = parseServer(mapping["server"])
    let storage = parseStorage(mapping["storage"])

    return WorkflowConfig(
      tracker: tracker,
      polling: polling,
      workspace: workspace,
      hooks: hooks,
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
    return CodexProviderConfig(
      command: stringValue(map["command"], "codex app-server"),
      approvalPolicy: map["approval_policy"] as? String,
      threadSandbox: map["thread_sandbox"] as? String,
      turnSandboxPolicy: map["turn_sandbox_policy"] as? String,
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

// MARK: - Config Resolver (Section 6.4)

public enum ConfigResolver {
  public static func resolveEnvironmentVariables(
    in value: String,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) throws -> String {
    var result = value
    let pattern = "\\$([A-Za-z_][A-Za-z0-9_]*)"
    // Pattern is a compile-time constant; construction cannot fail.
    let regex = try! NSRegularExpression(pattern: pattern)

    let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
    for match in matches.reversed() {
      let fullRange = Range(match.range, in: result)!
      let varNameRange = Range(match.range(at: 1), in: result)!
      let varName = String(result[varNameRange])
      if let envValue = environment[varName] {
        result.replaceSubrange(fullRange, with: envValue)
      }
    }
    return result
  }

  public static func expandPath(_ path: String) -> String {
    NSString(string: path).expandingTildeInPath
  }

  public static func resolveAPIKey(
    _ rawKey: String?,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) throws -> String? {
    guard let rawKey else { return nil }
    if rawKey.hasPrefix("$") {
      return try resolveEnvironmentVariables(in: rawKey, environment: environment)
    }
    return rawKey
  }
}

// MARK: - Prompt Renderer (Section 6.5)

public enum PromptRenderError: Error, Equatable, Sendable {
  case unknownVariable(String)
}

public enum PromptRenderer {
  public static func render(
    template: String,
    issue: Issue,
    attempt: Int
  ) throws -> String {
    guard !template.isEmpty else {
      return "Resolve the following issue:\n\(issue.title)\n\(issue.description ?? "")"
    }

    var result = template
    let variables: [String: String] = [
      "{{issue.title}}": issue.title,
      "{{issue.description}}": issue.description ?? "",
      "{{issue.identifier}}": issue.identifier.rawValue,
      "{{issue.number}}": String(issue.number),
      "{{issue.repository}}": issue.repository,
      "{{issue.state}}": issue.state,
      "{{issue.url}}": issue.url ?? "",
      "{{attempt}}": String(attempt),
    ]

    for (placeholder, value) in variables {
      result = result.replacingOccurrences(of: placeholder, with: value)
    }

    let unknownPattern = "\\{\\{([^}]+)\\}\\}"
    if let regex = try? NSRegularExpression(pattern: unknownPattern),
      let match = regex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)),
      let range = Range(match.range(at: 1), in: result)
    {
      throw PromptRenderError.unknownVariable(String(result[range]))
    }

    return result
  }
}
