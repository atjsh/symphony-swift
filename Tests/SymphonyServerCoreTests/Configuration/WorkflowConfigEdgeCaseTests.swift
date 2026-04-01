import Foundation
import SymphonyShared
import Testing

@testable import SymphonyServerCore

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

@Test func workflowParserAnalysisConfigParsingAndDefaults() throws {
  let content = """
    ---
    analysis:
      history:
        source_paths:
          - src/**
        test_paths:
          - tests/**
      syntax:
        command: npm run lint
    ---
    Prompt
    """
  let definition = try WorkflowParser.parse(content: content)
  #expect(definition.config.analysis.history.sourcePaths == ["src/**"])
  #expect(definition.config.analysis.history.testPaths == ["tests/**"])
  #expect(definition.config.analysis.syntax.command == "npm run lint")
}

@Test func workflowParserAnalysisDefaultsWhenSectionIsSparse() throws {
  let content = """
    ---
    analysis:
      history:
        source_paths:
          - Sources/**
    ---
    Prompt
    """
  let definition = try WorkflowParser.parse(content: content)
  #expect(definition.config.analysis.history.sourcePaths == ["Sources/**"])
  #expect(definition.config.analysis.history.testPaths.isEmpty)
  #expect(definition.config.analysis.syntax.command == nil)
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

@Test func workflowParserCodexProviderIgnoresLegacyKeys() throws {
  let content = """
    ---
    providers:
      codex:
        approval_policy: legacy-session
        session_approval_policy: canonical-session
        thread_sandbox:
          mode: legacy-session-sandbox
          network_access: false
        session_sandbox:
          mode: canonical-session-sandbox
    ---
    Prompt
    """
  let definition = try WorkflowParser.parse(content: content)

  #expect(definition.config.providers.codex.sessionApprovalPolicy == "canonical-session")
  #expect(
    definition.config.providers.codex.sessionSandbox
      == [
        "mode": "canonical-session-sandbox",
      ])
  #expect(definition.config.providers.codex.turnApprovalPolicy == "canonical-session")
  #expect(definition.config.providers.codex.turnSandboxPolicy == nil)
}

@Test func workflowParserCodexSandboxValueCoversScalarCompositeNullAndUnsupportedInputs() {
  #expect(WorkflowParser.codexSandboxValue(42) == .integer(42))
  #expect(WorkflowParser.codexSandboxValue(1.25) == .double(1.25))
  #expect(
    WorkflowParser.codexSandboxValue(["workspace-write", true, 7])
      == .array([.string("workspace-write"), .bool(true), .integer(7)])
  )
  #expect(
    WorkflowParser.codexSandboxValue([
      "mode": "workspace-write",
      "network_access": false,
    ]) == .object([
      "mode": .string("workspace-write"),
      "network_access": .bool(false),
    ])
  )
  #expect(WorkflowParser.codexSandboxValue(NSNull()) == .null)
  #expect(WorkflowParser.codexSandboxValue(Date()) == nil)
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
