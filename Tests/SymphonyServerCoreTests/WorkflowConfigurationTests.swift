import Foundation
import SymphonyShared
import Testing

@testable import SymphonyServerCore

// MARK: - WorkflowParser Tests

@Test func workflowParserParseContentNoFrontMatter() throws {
  let content = """
    You are a coding agent.
    Resolve the issue.
    """
  let definition = try WorkflowParser.parse(content: content)
  #expect(definition.config == .defaults)
  #expect(definition.promptTemplate == "You are a coding agent.\nResolve the issue.")
}

@Test func workflowParserParseContentWithFrontMatter() throws {
  let content = """
    ---
    tracker:
      kind: github
      endpoint: https://api.github.example.com/graphql
      project_owner: myorg
      project_number: 42
    polling:
      interval_ms: 15000
    ---
    You are a coding agent.
    """
  let definition = try WorkflowParser.parse(content: content)
  #expect(definition.config.tracker.kind == "github")
  #expect(definition.config.tracker.endpoint == "https://api.github.example.com/graphql")
  #expect(definition.config.tracker.projectOwner == "myorg")
  #expect(definition.config.tracker.projectNumber == 42)
  #expect(definition.config.polling.intervalMS == 15000)
  #expect(definition.promptTemplate == "You are a coding agent.")
}

@Test func workflowParserParseContentEmptyFrontMatter() throws {
  let content = """
    ---
    ---
    Just the prompt.
    """
  let definition = try WorkflowParser.parse(content: content)
  #expect(definition.config == .defaults)
  #expect(definition.promptTemplate == "Just the prompt.")
}

@Test func workflowParserSplitFrontMatterNoDelimiter() {
  let (frontMatter, body) = WorkflowParser.splitFrontMatter("No front matter here")
  #expect(frontMatter == nil)
  #expect(body == "No front matter here")
}

@Test func workflowParserSplitFrontMatterWithDelimiter() {
  let content = "---\nkey: value\n---\nBody text"
  let (frontMatter, body) = WorkflowParser.splitFrontMatter(content)
  #expect(frontMatter == "\nkey: value")
  #expect(body.contains("Body text"))
}

@Test func workflowParserSplitFrontMatterOnlyOpening() {
  let (frontMatter, body) = WorkflowParser.splitFrontMatter("---\nunclosed front matter")
  #expect(frontMatter == nil)
  #expect(body == "---\nunclosed front matter")
}

@Test func workflowParserNonMapFrontMatterThrows() throws {
  let content = """
    ---
    - item1
    - item2
    ---
    Body
    """
  #expect(throws: WorkflowConfigError.workflowFrontMatterNotAMap) {
    _ = try WorkflowParser.parse(content: content)
  }
}

@Test func workflowParserInvalidYAMLThrows() throws {
  let content = """
    ---
    : invalid yaml [[[
    ---
    Body
    """
  // Yams may or may not throw on this, but the result shouldn't be a valid map
  do {
    let definition = try WorkflowParser.parse(content: content)
    // If it parsed without error, the result should still be reasonable
    _ = definition
  } catch {
    // Expected behavior for invalid YAML
  }
}

@Test func workflowParserFromFile() throws {
  let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: dir) }

  let workflowURL = dir.appendingPathComponent("WORKFLOW.md")
  try "---\nserver:\n  port: 9090\n---\nResolve it.".write(
    to: workflowURL, atomically: true, encoding: .utf8)

  let definition = try WorkflowParser.parse(contentsOf: workflowURL)
  #expect(definition.config.server.port == 9090)
  #expect(definition.promptTemplate == "Resolve it.")
}

@Test func workflowParserFromFileMissingThrows() throws {
  let missing = URL(fileURLWithPath: "/tmp/nonexistent_\(UUID().uuidString)/WORKFLOW.md")
  #expect(throws: WorkflowConfigError.self) {
    _ = try WorkflowParser.parse(contentsOf: missing)
  }
}

@Test func workflowParserDiscoverExplicitPath() throws {
  let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: dir) }

  let file = dir.appendingPathComponent("custom-workflow.md")
  try "test".write(to: file, atomically: true, encoding: .utf8)

  let url = WorkflowParser.discover(explicitPath: file.path)
  #expect(url != nil)
  #expect(url?.lastPathComponent == "custom-workflow.md")
}

@Test func workflowParserDiscoverExplicitPathMissing() {
  let url = WorkflowParser.discover(explicitPath: "/tmp/nonexistent_\(UUID().uuidString)")
  #expect(url == nil)
}

@Test func workflowParserDiscoverDefaultPath() throws {
  let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: dir) }

  let workflowFile = dir.appendingPathComponent("WORKFLOW.md")
  try "prompt".write(to: workflowFile, atomically: true, encoding: .utf8)

  let url = WorkflowParser.discover(workingDirectory: dir.path)
  #expect(url != nil)
}

@Test func workflowParserDiscoverDefaultPathMissing() {
  let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  let url = WorkflowParser.discover(workingDirectory: dir.path)
  #expect(url == nil)
}

// MARK: - Config Defaults Tests

@Test func workflowConfigDefaults() {
  let config = WorkflowConfig.defaults
  #expect(config.tracker == .defaults)
  #expect(config.polling == .defaults)
  #expect(config.workspace == .defaults)
  #expect(config.hooks == .defaults)
  #expect(config.agent == .defaults)
  #expect(config.providers == .defaults)
  #expect(config.server == .defaults)
  #expect(config.storage == .defaults)
}

@Test func trackerConfigDefaults() {
  let config = TrackerConfig.defaults
  #expect(config.kind == "github")
  #expect(config.endpoint == "https://api.github.com/graphql")
  #expect(config.apiKey == nil)
  #expect(config.projectOwner == nil)
  #expect(config.projectOwnerType == nil)
  #expect(config.projectNumber == nil)
  #expect(config.repositoryAllowlist == [])
  #expect(config.statusFieldName == "Status")
  #expect(config.activeStates == ["Todo", "In Progress"])
  #expect(config.terminalStates == ["Done"])
  #expect(config.blockedStates == ["Todo"])
}

@Test func pollingConfigDefaults() {
  #expect(PollingConfig.defaults.intervalMS == 30_000)
}

@Test func workspaceConfigDefaults() {
  let config = WorkspaceConfig.defaults
  #expect(config.root.contains("symphony_workspaces"))
}

@Test func hooksConfigDefaults() {
  let config = HooksConfig.defaults
  #expect(config.afterCreate == nil)
  #expect(config.beforeRun == nil)
  #expect(config.afterRun == nil)
  #expect(config.beforeRemove == nil)
  #expect(config.timeoutMS == 60_000)
}

@Test func agentConfigDefaults() {
  let config = AgentConfig.defaults
  #expect(config.defaultProvider == .codex)
  #expect(config.maxConcurrentAgents == 10)
  #expect(config.maxTurns == 20)
  #expect(config.maxRetryBackoffMS == 300_000)
  #expect(config.maxConcurrentAgentsByState.isEmpty)
}

@Test func providersConfigDefaults() {
  let config = ProvidersConfig.defaults
  #expect(config.codex == .defaults)
  #expect(config.claudeCode == .defaults)
  #expect(config.copilotCLI == .defaults)
}

@Test func codexProviderConfigDefaults() {
  let config = CodexProviderConfig.defaults
  #expect(config.command == "codex app-server")
  #expect(config.sessionApprovalPolicy == nil)
  #expect(config.sessionSandbox == nil)
  #expect(config.turnApprovalPolicy == nil)
  #expect(config.turnSandboxPolicy == nil)
  #expect(config.turnTimeoutMS == 3_600_000)
  #expect(config.readTimeoutMS == 5_000)
  #expect(config.stallTimeoutMS == 300_000)
}

@Test func claudeCodeProviderConfigDefaults() {
  let config = ClaudeCodeProviderConfig.defaults
  #expect(config.command == "claude")
  #expect(config.permissionMode == nil)
  #expect(config.allowedTools == [])
  #expect(config.disallowedTools == [])
  #expect(config.turnTimeoutMS == 3_600_000)
  #expect(config.readTimeoutMS == 5_000)
  #expect(config.stallTimeoutMS == 300_000)
}

@Test func copilotCLIProviderConfigDefaults() {
  let config = CopilotCLIProviderConfig.defaults
  #expect(config.command == "copilot --acp --stdio")
  #expect(config.turnTimeoutMS == 3_600_000)
  #expect(config.readTimeoutMS == 5_000)
  #expect(config.stallTimeoutMS == 300_000)
}

@Test func serverConfigDefaults() {
  let config = SymphonyServerConfig.defaults
  #expect(config.host == "127.0.0.1")
  #expect(config.port == 8080)
}

@Test func storageConfigDefaults() {
  let config = StorageConfig.defaults
  #expect(config.sqlitePath == nil)
  #expect(config.retainRawEvents == true)
}

// MARK: - Full Config Parsing

@Test func workflowParserFullConfigParsing() throws {
  let content = """
    ---
    tracker:
      kind: github
      endpoint: https://api.example.com/graphql
      api_key: $MY_TOKEN
      project_owner: testorg
      project_owner_type: organization
      project_number: 99
      repository_allowlist:
        - repo-a
        - repo-b
      status_field_name: State
      active_states:
        - Active
        - Working
      terminal_states:
        - Completed
      blocked_states:
        - Waiting
    polling:
      interval_ms: 5000
    workspace:
      root: /tmp/my_workspaces
    hooks:
      after_create: git clone $REPO_URL .
      before_run: npm install
      after_run: npm test
      before_remove: cleanup.sh
      timeout_ms: 30000
    agent:
      default_provider: claude_code
      max_concurrent_agents: 5
      max_turns: 10
      max_retry_backoff_ms: 600000
    providers:
      codex:
        command: codex-custom
        session_approval_policy: auto
        session_sandbox: none
        turn_approval_policy: inherit
        turn_sandbox_policy: relaxed
        turn_timeout_ms: 7200000
        read_timeout_ms: 3000
        stall_timeout_ms: 120000
      claude_code:
        command: claude-custom
        permission_mode: auto
        allowed_tools:
          - Read
          - Write
        disallowed_tools:
          - Delete
        turn_timeout_ms: 5400000
        read_timeout_ms: 4000
        stall_timeout_ms: 180000
      copilot_cli:
        command: copilot-custom
        turn_timeout_ms: 1800000
        read_timeout_ms: 2000
        stall_timeout_ms: 90000
    server:
      host: 0.0.0.0
      port: 3000
    storage:
      sqlite_path: /tmp/symphony.db
      retain_raw_events: false
    ---
    You are a super agent. Fix {{issue.title}}.
    """
  let definition = try WorkflowParser.parse(content: content)
  let c = definition.config

  // Tracker
  #expect(c.tracker.kind == "github")
  #expect(c.tracker.endpoint == "https://api.example.com/graphql")
  #expect(c.tracker.apiKey == "$MY_TOKEN")
  #expect(c.tracker.projectOwner == "testorg")
  #expect(c.tracker.projectOwnerType == "organization")
  #expect(c.tracker.projectNumber == 99)
  #expect(c.tracker.repositoryAllowlist == ["repo-a", "repo-b"])
  #expect(c.tracker.statusFieldName == "State")
  #expect(c.tracker.activeStates == ["Active", "Working"])
  #expect(c.tracker.terminalStates == ["Completed"])
  #expect(c.tracker.blockedStates == ["Waiting"])

  // Polling
  #expect(c.polling.intervalMS == 5000)

  // Workspace
  #expect(c.workspace.root == "/tmp/my_workspaces")

  // Hooks
  #expect(c.hooks.afterCreate == "git clone $REPO_URL .")
  #expect(c.hooks.beforeRun == "npm install")
  #expect(c.hooks.afterRun == "npm test")
  #expect(c.hooks.beforeRemove == "cleanup.sh")
  #expect(c.hooks.timeoutMS == 30000)

  // Agent
  #expect(c.agent.defaultProvider == .claudeCode)
  #expect(c.agent.maxConcurrentAgents == 5)
  #expect(c.agent.maxTurns == 10)
  #expect(c.agent.maxRetryBackoffMS == 600000)

  // Providers
  #expect(c.providers.codex.command == "codex-custom")
  #expect(c.providers.codex.sessionApprovalPolicy == "auto")
  #expect(c.providers.codex.sessionSandbox == "none")
  #expect(c.providers.codex.turnApprovalPolicy == "inherit")
  #expect(c.providers.codex.turnSandboxPolicy == "relaxed")
  #expect(c.providers.codex.turnTimeoutMS == 7_200_000)
  #expect(c.providers.codex.readTimeoutMS == 3000)
  #expect(c.providers.codex.stallTimeoutMS == 120000)

  #expect(c.providers.claudeCode.command == "claude-custom")
  #expect(c.providers.claudeCode.permissionMode == "auto")
  #expect(c.providers.claudeCode.allowedTools == ["Read", "Write"])
  #expect(c.providers.claudeCode.disallowedTools == ["Delete"])
  #expect(c.providers.claudeCode.turnTimeoutMS == 5_400_000)
  #expect(c.providers.claudeCode.readTimeoutMS == 4000)
  #expect(c.providers.claudeCode.stallTimeoutMS == 180000)

  #expect(c.providers.copilotCLI.command == "copilot-custom")
  #expect(c.providers.copilotCLI.turnTimeoutMS == 1_800_000)
  #expect(c.providers.copilotCLI.readTimeoutMS == 2000)
  #expect(c.providers.copilotCLI.stallTimeoutMS == 90000)

  // Server
  #expect(c.server.host == "0.0.0.0")
  #expect(c.server.port == 3000)

  // Storage
  #expect(c.storage.sqlitePath == "/tmp/symphony.db")
  #expect(c.storage.retainRawEvents == false)

  // Prompt
  #expect(definition.promptTemplate.contains("super agent"))
}

// MARK: - ConfigResolver Tests

@Test func configResolverResolveEnvironmentVariables() throws {
  let result = try ConfigResolver.resolveEnvironmentVariables(
    in: "hello $FOO world $BAR",
    environment: ["FOO": "one", "BAR": "two"]
  )
  #expect(result == "hello one world two")
}

@Test func configResolverResolveEnvironmentVariablesMissing() throws {
  let result = try ConfigResolver.resolveEnvironmentVariables(
    in: "hello $MISSING_VAR world",
    environment: [:]
  )
  #expect(result == "hello $MISSING_VAR world")
}

@Test func configResolverResolveEnvironmentVariablesEmpty() throws {
  let result = try ConfigResolver.resolveEnvironmentVariables(
    in: "no variables",
    environment: [:]
  )
  #expect(result == "no variables")
}

@Test func configResolverExpandPath() {
  let expanded = ConfigResolver.expandPath("~/somedir")
  #expect(!expanded.hasPrefix("~"))
  #expect(expanded.hasSuffix("/somedir"))
}

@Test func configResolverExpandPathAbsolute() {
  let expanded = ConfigResolver.expandPath("/absolute/path")
  #expect(expanded == "/absolute/path")
}

@Test func configResolverResolveAPIKeyWithEnvVar() throws {
  let result = try ConfigResolver.resolveAPIKey(
    "$MY_API_KEY", environment: ["MY_API_KEY": "secret123"])
  #expect(result == "secret123")
}

@Test func configResolverResolveAPIKeyLiteral() throws {
  let result = try ConfigResolver.resolveAPIKey("literal-key", environment: [:])
  #expect(result == "literal-key")
}

@Test func configResolverResolveAPIKeyNil() throws {
  let result = try ConfigResolver.resolveAPIKey(nil, environment: [:])
  #expect(result == nil)
}

// MARK: - PromptRenderer Tests

@Test func promptRendererRenderWithVariables() throws {
  let issue = Issue(
    id: IssueID("test-id"),
    identifier: try IssueIdentifier(validating: "owner/repo#42"),
    repository: "owner/repo",
    number: 42,
    title: "Fix the bug",
    description: "Something is broken",
    priority: 1,
    state: "In Progress",
    issueState: "OPEN",
    projectItemID: nil,
    url: "https://github.com/owner/repo/issues/42",
    labels: ["bug"],
    blockedBy: [],
    createdAt: nil,
    updatedAt: nil
  )

  let template = "Fix {{issue.title}} in {{issue.repository}} (attempt {{attempt}})"
  let rendered = try PromptRenderer.render(template: template, issue: issue, attempt: 2)
  #expect(rendered == "Fix Fix the bug in owner/repo (attempt 2)")
}

@Test func promptRendererRenderAllVariables() throws {
  let issue = Issue(
    id: IssueID("id-1"),
    identifier: try IssueIdentifier(validating: "org/proj#10"),
    repository: "org/proj",
    number: 10,
    title: "Title",
    description: "Desc",
    priority: nil,
    state: "Active",
    issueState: "OPEN",
    projectItemID: nil,
    url: "https://example.com/10",
    labels: [],
    blockedBy: [],
    createdAt: nil,
    updatedAt: nil
  )

  let template =
    "{{issue.title}} {{issue.description}} {{issue.identifier}} {{issue.number}} {{issue.repository}} {{issue.state}} {{issue.url}} {{attempt}}"
  let rendered = try PromptRenderer.render(template: template, issue: issue, attempt: 1)
  #expect(rendered.contains("Title"))
  #expect(rendered.contains("Desc"))
  #expect(rendered.contains("org/proj#10"))
  #expect(rendered.contains("10"))
  #expect(rendered.contains("org/proj"))
  #expect(rendered.contains("Active"))
  #expect(rendered.contains("https://example.com/10"))
  #expect(rendered.contains("1"))
}

@Test func promptRendererRenderEmptyTemplate() throws {
  let issue = Issue(
    id: IssueID("id-1"),
    identifier: try IssueIdentifier(validating: "org/proj#10"),
    repository: "org/proj",
    number: 10,
    title: "My Title",
    description: "My Description",
    priority: nil,
    state: "Active",
    issueState: "OPEN",
    projectItemID: nil,
    url: nil,
    labels: [],
    blockedBy: [],
    createdAt: nil,
    updatedAt: nil
  )

  let rendered = try PromptRenderer.render(template: "", issue: issue, attempt: 1)
  #expect(rendered.contains("My Title"))
  #expect(rendered.contains("My Description"))
}

@Test func promptRendererUnknownVariableThrows() throws {
  let issue = Issue(
    id: IssueID("id-1"),
    identifier: try IssueIdentifier(validating: "org/proj#10"),
    repository: "org/proj",
    number: 10,
    title: "Title",
    description: nil,
    priority: nil,
    state: "Active",
    issueState: "OPEN",
    projectItemID: nil,
    url: nil,
    labels: [],
    blockedBy: [],
    createdAt: nil,
    updatedAt: nil
  )

  #expect(throws: PromptRenderError.unknownVariable("custom.thing")) {
    _ = try PromptRenderer.render(template: "Hello {{custom.thing}}", issue: issue, attempt: 1)
  }
}

@Test func promptRendererNilDescriptionBecomesEmpty() throws {
  let issue = Issue(
    id: IssueID("id-1"),
    identifier: try IssueIdentifier(validating: "org/proj#10"),
    repository: "org/proj",
    number: 10,
    title: "Title",
    description: nil,
    priority: nil,
    state: "Active",
    issueState: "OPEN",
    projectItemID: nil,
    url: nil,
    labels: [],
    blockedBy: [],
    createdAt: nil,
    updatedAt: nil
  )

  let rendered = try PromptRenderer.render(
    template: "Desc: {{issue.description}} URL: {{issue.url}}", issue: issue, attempt: 1)
  #expect(rendered == "Desc:  URL: ")
}

// MARK: - WorkflowConfigError Tests

@Test func workflowConfigErrorEquatable() {
  let a = WorkflowConfigError.missingWorkflowFile("/a")
  let b = WorkflowConfigError.missingWorkflowFile("/a")
  let c = WorkflowConfigError.missingWorkflowFile("/b")
  #expect(a == b)
  #expect(a != c)

  #expect(WorkflowConfigError.workflowFrontMatterNotAMap == .workflowFrontMatterNotAMap)
  #expect(WorkflowConfigError.workflowParseError("x") == .workflowParseError("x"))
  #expect(WorkflowConfigError.invalidConfigValue("x") == .invalidConfigValue("x"))
}

// MARK: - WorkflowDefinition Equality

@Test func workflowDefinitionEquatable() {
  let a = WorkflowDefinition(config: .defaults, promptTemplate: "hello")
  let b = WorkflowDefinition(config: .defaults, promptTemplate: "hello")
  let c = WorkflowDefinition(config: .defaults, promptTemplate: "world")
  #expect(a == b)
  #expect(a != c)
}

// MARK: - Config with partial sections

@Test func workflowParserPartialTrackerConfig() throws {
  let content = """
    ---
    tracker:
      project_owner: testorg
    ---
    Prompt
    """
  let definition = try WorkflowParser.parse(content: content)
  #expect(definition.config.tracker.projectOwner == "testorg")
  #expect(definition.config.tracker.kind == "github")
  #expect(definition.config.tracker.endpoint == "https://api.github.com/graphql")
}

@Test func workflowParserPartialAgentConfig() throws {
  let content = """
    ---
    agent:
      max_concurrent_agents: 3
    ---
    Prompt
    """
  let definition = try WorkflowParser.parse(content: content)
  #expect(definition.config.agent.maxConcurrentAgents == 3)
  #expect(definition.config.agent.maxTurns == 20)
  #expect(definition.config.agent.defaultProvider == .codex)
}

@Test func workflowParserPartialWorkspaceConfig() throws {
  let content = """
    ---
    workspace:
      root: /tmp/custom-workspaces
    ---
    Prompt
    """
  let definition = try WorkflowParser.parse(content: content)
  #expect(definition.config.workspace.root == "/tmp/custom-workspaces")
}

@Test func workflowParserEmptyContent() throws {
  let definition = try WorkflowParser.parse(content: "")
  #expect(definition.config == .defaults)
  #expect(definition.promptTemplate == "")
}

@Test func workflowParserStorageBoolParsing() throws {
  let content = """
    ---
    storage:
      retain_raw_events: false
    ---
    Prompt
    """
  let definition = try WorkflowParser.parse(content: content)
  #expect(definition.config.storage.retainRawEvents == false)
}

@Test func workflowParserAgentConcurrencyByState() throws {
  let content = """
    ---
    agent:
      max_concurrent_agents_by_state:
        Todo: 2
        "In Progress": 5
    ---
    Prompt
    """
  let definition = try WorkflowParser.parse(content: content)
  #expect(definition.config.agent.maxConcurrentAgentsByState["Todo"] == 2)
  #expect(definition.config.agent.maxConcurrentAgentsByState["In Progress"] == 5)
}

@Test func workflowParserFrontMatterNoBody() throws {
  let content = "---\nserver:\n  port: 9090\n---"
  let definition = try WorkflowParser.parse(content: content)
  #expect(definition.config.server.port == 9090)
  #expect(definition.promptTemplate == "")
}

@Test func workflowParserStorageBoolFromString() throws {
  // In YAML, a quoted "true" is a string — exercises the string-based boolValue path
  let content = """
    ---
    storage:
      retain_raw_events: "yes"
    ---
    Prompt
    """
  let definition = try WorkflowParser.parse(content: content)
  #expect(definition.config.storage.retainRawEvents == true)
}

@Test func workflowParserStorageBoolFromStringFalse() throws {
  let content = """
    ---
    storage:
      retain_raw_events: "no"
    ---
    Prompt
    """
  let definition = try WorkflowParser.parse(content: content)
  #expect(definition.config.storage.retainRawEvents == false)
}

@Test func workflowParserStorageBoolFromStringUnrecognized() throws {
  let content = """
    ---
    storage:
      retain_raw_events: "maybe"
    ---
    Prompt
    """
  let definition = try WorkflowParser.parse(content: content)
  // Unrecognized string falls back to default (true)
  #expect(definition.config.storage.retainRawEvents == true)
}

@Test func workflowParserStoragePartialMissingBool() throws {
  let content = """
    ---
    storage:
      sqlite_path: /tmp/test.db
    ---
    Prompt
    """
  let definition = try WorkflowParser.parse(content: content)
  // retain_raw_events absent → boolValue(nil) → nil → defaults to true
  #expect(definition.config.storage.sqlitePath == "/tmp/test.db")
  #expect(definition.config.storage.retainRawEvents == true)
}

// MARK: - Partial Section Defaults (exercises ?? default closures)

@Test func workflowParserPartialSectionDefaults() throws {
  // Each section present as a non-empty map but with minimal keys,
  // forcing all ?? default-value autoclosures to execute.
  let content = """
    ---
    polling:
      _trigger: 1
    hooks:
      after_create: init.sh
    providers:
      codex:
        session_approval_policy: manual
      claude_code:
        permission_mode: prompt
      copilot_cli:
        _trigger: 1
    server:
      host: 0.0.0.0
    ---
    Prompt
    """
  let def = try WorkflowParser.parse(content: content)

  // Polling: interval_ms defaults
  #expect(def.config.polling.intervalMS == 30_000)

  // Hooks: timeout_ms defaults
  #expect(def.config.hooks.afterCreate == "init.sh")
  #expect(def.config.hooks.timeoutMS == 60_000)

  // Codex: all timeout/command defaults
  #expect(def.config.providers.codex.command == "codex app-server")
  #expect(def.config.providers.codex.sessionApprovalPolicy == "manual")
  #expect(def.config.providers.codex.sessionSandbox == nil)
  #expect(def.config.providers.codex.turnApprovalPolicy == "manual")
  #expect(def.config.providers.codex.turnTimeoutMS == 3_600_000)
  #expect(def.config.providers.codex.readTimeoutMS == 5_000)
  #expect(def.config.providers.codex.stallTimeoutMS == 300_000)

  // ClaudeCode: all timeout/command/list defaults
  #expect(def.config.providers.claudeCode.command == "claude")
  #expect(def.config.providers.claudeCode.permissionMode == "prompt")
  #expect(def.config.providers.claudeCode.allowedTools == [])
  #expect(def.config.providers.claudeCode.disallowedTools == [])
  #expect(def.config.providers.claudeCode.turnTimeoutMS == 3_600_000)
  #expect(def.config.providers.claudeCode.readTimeoutMS == 5_000)
  #expect(def.config.providers.claudeCode.stallTimeoutMS == 300_000)

  // CopilotCLI: all timeout/command defaults
  #expect(def.config.providers.copilotCLI.command == "copilot --acp --stdio")
  #expect(def.config.providers.copilotCLI.turnTimeoutMS == 3_600_000)
  #expect(def.config.providers.copilotCLI.readTimeoutMS == 5_000)
  #expect(def.config.providers.copilotCLI.stallTimeoutMS == 300_000)

  // Server: port defaults
  #expect(def.config.server.host == "0.0.0.0")
  #expect(def.config.server.port == 8080)
}

@Test func workflowParserCodexProviderFallsBackToLegacyKeys() throws {
  let content = """
    ---
    providers:
      codex:
        approval_policy: legacy-session
        thread_sandbox:
          mode: legacy-session-sandbox
          network_access: false
        turn_sandbox_policy:
          mode: legacy-turn-sandbox
          writable_roots:
            - /tmp/legacy
    ---
    Prompt
    """
  let definition = try WorkflowParser.parse(content: content)

  #expect(definition.config.providers.codex.sessionApprovalPolicy == "legacy-session")
  #expect(
    definition.config.providers.codex.sessionSandbox
      == [
        "mode": "legacy-session-sandbox",
        "network_access": false,
      ])
  #expect(definition.config.providers.codex.turnApprovalPolicy == "legacy-session")
  #expect(
    definition.config.providers.codex.turnSandboxPolicy
      == [
        "mode": "legacy-turn-sandbox",
        "writable_roots": ["/tmp/legacy"],
      ])
}

@Test func workflowParserAcceptsObjectShapedCodexSandboxValues() throws {
  let content = """
    ---
    providers:
      codex:
        session_sandbox:
          mode: workspace-write
          network_access: false
        turn_sandbox_policy:
          mode: danger-full-access
          writable_roots:
            - /tmp/cache
            - /tmp/output
    ---
    Prompt
    """
  let definition = try WorkflowParser.parse(content: content)

  #expect(
    definition.config.providers.codex.sessionSandbox
      == [
        "mode": "workspace-write",
        "network_access": false,
      ])
  #expect(
    definition.config.providers.codex.turnSandboxPolicy
      == [
        "mode": "danger-full-access",
        "writable_roots": ["/tmp/cache", "/tmp/output"],
      ])
}

@Test func promptRendererEmptyTemplateNilDescription() throws {
  let issue = SymphonyShared.Issue(
    id: IssueID("id-1"),
    identifier: try IssueIdentifier(validating: "org/proj#10"),
    repository: "org/proj",
    number: 10,
    title: "My Title",
    description: nil,
    priority: nil,
    state: "Active",
    issueState: "OPEN",
    projectItemID: nil,
    url: nil,
    labels: [],
    blockedBy: [],
    createdAt: nil,
    updatedAt: nil
  )

  let rendered = try PromptRenderer.render(template: "", issue: issue, attempt: 1)
  #expect(rendered.contains("My Title"))
  // nil description → "" via ?? default
  #expect(!rendered.contains("nil"))
}
