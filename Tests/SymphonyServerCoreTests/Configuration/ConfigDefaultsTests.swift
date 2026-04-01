import Foundation
import SymphonyShared
import Testing

@testable import SymphonyServerCore

// MARK: - Config Defaults Tests

@Test func workflowConfigDefaults() {
  let config = WorkflowConfig.defaults
  #expect(config.tracker == .defaults)
  #expect(config.polling == .defaults)
  #expect(config.workspace == .defaults)
  #expect(config.hooks == .defaults)
  #expect(config.analysis == .defaults)
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

@Test func analysisConfigDefaults() {
  let config = AnalysisConfig.defaults
  #expect(config.history == .defaults)
  #expect(config.syntax == .defaults)
  #expect(config.history.sourcePaths.isEmpty)
  #expect(config.history.testPaths.isEmpty)
  #expect(config.syntax.command == nil)
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

@Test func providersConfigReturnsProviderSpecificStallTimeouts() {
  let config = ProvidersConfig(
    codex: CodexProviderConfig(stallTimeoutMS: 101),
    claudeCode: ClaudeCodeProviderConfig(stallTimeoutMS: 202),
    copilotCLI: CopilotCLIProviderConfig(stallTimeoutMS: 303)
  )

  #expect(config.stallTimeoutMS(for: .codex) == 101)
  #expect(config.stallTimeoutMS(for: .claudeCode) == 202)
  #expect(config.stallTimeoutMS(for: .copilotCLI) == 303)
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

@Test func codexSandboxValueSupportsLiteralConversionFoundationAccessorsAndDerivedConfigAccessors() {
  let stringValue: CodexSandboxValue = "workspace-write"
  let boolValue: CodexSandboxValue = true
  let integerValue: CodexSandboxValue = 17
  let doubleValue: CodexSandboxValue = 2.5
  let arrayValue: CodexSandboxValue = ["workspace-write", true, 17, 2.5, nil]
  let objectValue: CodexSandboxValue = [
    "mode": "workspace-write",
    "network_access": false,
    "writable_roots": ["/tmp/cache", "/tmp/output"],
    "null_value": nil,
  ]

  #expect(stringValue.stringValue == "workspace-write")
  #expect(boolValue.stringValue == nil)
  #expect(stringValue.foundationValue as? String == "workspace-write")
  #expect(boolValue.foundationValue as? Bool == true)
  #expect(integerValue.foundationValue as? Int == 17)
  #expect(doubleValue.foundationValue as? Double == 2.5)
  #expect((arrayValue.foundationValue as? [Any])?.count == 5)
  let foundationObject = objectValue.foundationValue as? [String: Any]
  #expect(foundationObject?["mode"] as? String == "workspace-write")
  #expect(foundationObject?["network_access"] as? Bool == false)
  #expect((foundationObject?["writable_roots"] as? [String]) == ["/tmp/cache", "/tmp/output"])
  #expect(foundationObject?["null_value"] is NSNull)

  let config = CodexProviderConfig(
    sessionApprovalPolicy: "manual",
    sessionSandbox: "workspace-write"
  )
  #expect(config.approvalPolicy == "manual")
  #expect(config.threadSandbox == "workspace-write")
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
    analysis:
      history:
        source_paths:
          - Sources/**
          - Applications/**
        test_paths:
          - Tests/**
          - "**/*.spec.ts"
      syntax:
        command: swift build
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

  // Analysis
  #expect(c.analysis.history.sourcePaths == ["Sources/**", "Applications/**"])
  #expect(c.analysis.history.testPaths == ["Tests/**", "**/*.spec.ts"])
  #expect(c.analysis.syntax.command == "swift build")

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

