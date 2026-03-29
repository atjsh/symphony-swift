#if os(macOS)
  import AppKit
  import Foundation
  import Security
  import SymphonyServerCore
  import SymphonyShared

  struct LocalServerEnvironmentEntry: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var value: String
    var isRequired: Bool

    init(
      id: UUID = UUID(),
      name: String,
      value: String = "",
      isRequired: Bool = false
    ) {
      self.id = id
      self.name = name
      self.value = value
      self.isRequired = isRequired
    }
  }

  struct LocalServerProfile: Codable, Equatable, Sendable {
    var workflowBookmarkData: Data?
    var workflowPath: String?
    var host: String
    var port: Int
    var sqlitePath: String?
    var environmentKeys: [String]

    init(
      workflowBookmarkData: Data? = nil,
      workflowPath: String? = nil,
      host: String = "localhost",
      port: Int = 8080,
      sqlitePath: String? = nil,
      environmentKeys: [String] = []
    ) {
      self.workflowBookmarkData = workflowBookmarkData
      self.workflowPath = workflowPath
      self.host = host
      self.port = port
      self.sqlitePath = sqlitePath
      self.environmentKeys = environmentKeys
    }

    static func bookmarkData(for workflowURL: URL) throws -> Data {
      try workflowURL.bookmarkData()
    }

    func resolvedWorkflowURL(
      bookmarkResolver: (Data) throws -> (url: URL, isStale: Bool) = Self.resolveBookmark
    ) -> URL? {
      if let workflowBookmarkData {
        if let resolved = try? bookmarkResolver(workflowBookmarkData).url {
          return resolved
        }
      }

      guard let workflowPath,
        !workflowPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else {
        return nil
      }

      return URL(fileURLWithPath: NSString(string: workflowPath).expandingTildeInPath)
    }

    private static func resolveBookmark(_ data: Data) throws -> (url: URL, isStale: Bool) {
      var isStale = false
      let url = try URL(
        resolvingBookmarkData: data,
        options: [],
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
      )
      return (url, isStale)
    }
  }

  enum LocalServerLaunchState: String, Codable, Equatable, Sendable {
    case idle
    case needsSetup
    case validating
    case starting
    case waitingForHealth
    case running
    case failed
  }

  enum LocalWorkflowWizardStep: String, Codable, Equatable, Sendable {
    case workflow
    case localServer
  }

  enum WorkflowPromptPreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case generalIssueResolution
    case featureDelivery
    case bugInvestigation
    case blank

    var id: String { rawValue }

    var title: String {
      switch self {
      case .generalIssueResolution:
        return "General Issue Resolution"
      case .featureDelivery:
        return "Feature Delivery"
      case .bugInvestigation:
        return "Bug Investigation"
      case .blank:
        return "Blank"
      }
    }

    var seededPrompt: String {
      switch self {
      case .generalIssueResolution:
        return """
          You are a coding agent working on a GitHub issue.

          Review the issue, inspect the relevant code, and implement the requested change.
          Run the best-fit validations before finishing.
          Summarize what changed, how you validated it, and any follow-up work that remains.

          Issue: {{issue.title}}
          Repository: {{issue.repository}}
          Identifier: {{issue.identifier}}
          """
      case .featureDelivery:
        return """
          Deliver the requested feature for this issue.

          Confirm the current behavior, implement the new capability, and update tests or supporting code as needed.
          Call out user-facing changes and any setup or rollout details in your final summary.

          Issue: {{issue.title}}
          Repository: {{issue.repository}}
          """
      case .bugInvestigation:
        return """
          Investigate and fix the bug described in this issue.

          Reproduce the problem when possible, identify the root cause, implement the safest fix, and add coverage that would catch the regression again.
          Explain the cause and validation clearly in your final summary.

          Issue: {{issue.title}}
          Repository: {{issue.repository}}
          """
      case .blank:
        return ""
      }
    }
  }

  struct WorkflowAuthoringPreviewState: Equatable, Sendable {
    var content: String
    var validationError: String?
  }

  struct WorkflowAuthoringDraft: Equatable, Sendable {
    static let defaultWorkflowFileName = "WORKFLOW.md"

    var trackerEndpoint: String
    var trackerGitHubTokenVariableName: String
    var trackerProjectOwner: String
    var trackerProjectOwnerType: String
    var trackerProjectNumber: String
    var trackerRepositoryAllowlistText: String
    var trackerStatusFieldName: String
    var trackerActiveStatesText: String
    var trackerTerminalStatesText: String
    var trackerBlockedStatesText: String

    var pollingIntervalMS: String
    var workspaceRoot: String
    var hooksAfterCreate: String
    var hooksBeforeRun: String
    var hooksAfterRun: String
    var hooksBeforeRemove: String
    var hooksTimeoutMS: String

    var agentDefaultProvider: ProviderName
    var agentMaxConcurrentAgents: String
    var agentMaxTurns: String
    var agentMaxRetryBackoffMS: String
    var agentMaxConcurrentAgentsByStateText: String

    var codexCommand: String
    var codexSessionApprovalPolicy: String
    var codexSessionSandbox: String
    var codexTurnApprovalPolicy: String
    var codexTurnSandboxPolicy: String
    var codexTurnTimeoutMS: String
    var codexReadTimeoutMS: String
    var codexStallTimeoutMS: String

    var claudeCommand: String
    var claudePermissionMode: String
    var claudeAllowedToolsText: String
    var claudeDisallowedToolsText: String
    var claudeTurnTimeoutMS: String
    var claudeReadTimeoutMS: String
    var claudeStallTimeoutMS: String

    var copilotCommand: String
    var copilotTurnTimeoutMS: String
    var copilotReadTimeoutMS: String
    var copilotStallTimeoutMS: String

    var serverHost: String
    var serverPort: String
    var storageSQLitePath: String
    var storageRetainRawEvents: Bool

    var promptPreset: WorkflowPromptPreset
    var promptBody: String

    init(
      config: WorkflowConfig = .defaults,
      promptPreset: WorkflowPromptPreset = .generalIssueResolution,
      promptBody: String? = nil
    ) {
      self.trackerEndpoint = config.tracker.endpoint
      self.trackerGitHubTokenVariableName =
        Self.variableName(from: config.tracker.apiKey) ?? "GITHUB_TOKEN"
      self.trackerProjectOwner = config.tracker.projectOwner ?? ""
      self.trackerProjectOwnerType = config.tracker.projectOwnerType ?? ""
      self.trackerProjectNumber = config.tracker.projectNumber.map(String.init) ?? ""
      self.trackerRepositoryAllowlistText = config.tracker.repositoryAllowlist.joined(separator: "\n")
      self.trackerStatusFieldName = config.tracker.statusFieldName
      self.trackerActiveStatesText = config.tracker.activeStates.joined(separator: "\n")
      self.trackerTerminalStatesText = config.tracker.terminalStates.joined(separator: "\n")
      self.trackerBlockedStatesText = config.tracker.blockedStates.joined(separator: "\n")
      self.pollingIntervalMS = String(config.polling.intervalMS)
      self.workspaceRoot = config.workspace.root
      self.hooksAfterCreate = config.hooks.afterCreate ?? ""
      self.hooksBeforeRun = config.hooks.beforeRun ?? ""
      self.hooksAfterRun = config.hooks.afterRun ?? ""
      self.hooksBeforeRemove = config.hooks.beforeRemove ?? ""
      self.hooksTimeoutMS = String(config.hooks.timeoutMS)
      self.agentDefaultProvider = config.agent.defaultProvider
      self.agentMaxConcurrentAgents = String(config.agent.maxConcurrentAgents)
      self.agentMaxTurns = String(config.agent.maxTurns)
      self.agentMaxRetryBackoffMS = String(config.agent.maxRetryBackoffMS)
      self.agentMaxConcurrentAgentsByStateText = Self.renderStateConcurrencyMap(
        config.agent.maxConcurrentAgentsByState
      )
      self.codexCommand = config.providers.codex.command
      self.codexSessionApprovalPolicy = config.providers.codex.sessionApprovalPolicy ?? ""
      self.codexSessionSandbox = Self.renderCodexSandbox(config.providers.codex.sessionSandbox)
      self.codexTurnApprovalPolicy = config.providers.codex.turnApprovalPolicy ?? ""
      self.codexTurnSandboxPolicy = Self.renderCodexSandbox(config.providers.codex.turnSandboxPolicy)
      self.codexTurnTimeoutMS = String(config.providers.codex.turnTimeoutMS)
      self.codexReadTimeoutMS = String(config.providers.codex.readTimeoutMS)
      self.codexStallTimeoutMS = String(config.providers.codex.stallTimeoutMS)
      self.claudeCommand = config.providers.claudeCode.command
      self.claudePermissionMode = config.providers.claudeCode.permissionMode ?? ""
      self.claudeAllowedToolsText = config.providers.claudeCode.allowedTools.joined(separator: "\n")
      self.claudeDisallowedToolsText = config.providers.claudeCode.disallowedTools.joined(
        separator: "\n"
      )
      self.claudeTurnTimeoutMS = String(config.providers.claudeCode.turnTimeoutMS)
      self.claudeReadTimeoutMS = String(config.providers.claudeCode.readTimeoutMS)
      self.claudeStallTimeoutMS = String(config.providers.claudeCode.stallTimeoutMS)
      self.copilotCommand = config.providers.copilotCLI.command
      self.copilotTurnTimeoutMS = String(config.providers.copilotCLI.turnTimeoutMS)
      self.copilotReadTimeoutMS = String(config.providers.copilotCLI.readTimeoutMS)
      self.copilotStallTimeoutMS = String(config.providers.copilotCLI.stallTimeoutMS)
      self.serverHost = config.server.host
      self.serverPort = String(config.server.port)
      self.storageSQLitePath = config.storage.sqlitePath ?? ""
      self.storageRetainRawEvents = config.storage.retainRawEvents
      self.promptPreset = promptPreset
      self.promptBody = promptBody ?? promptPreset.seededPrompt
    }

    init(definition: WorkflowDefinition) {
      self.init(
        config: definition.config,
        promptPreset: .blank,
        promptBody: definition.promptTemplate
      )
    }

    private static func variableName(from apiKey: String?) -> String? {
      guard let apiKey else {
        return nil
      }

      let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
      guard trimmed.hasPrefix("$"), trimmed.count > 1 else {
        return trimmed.isEmpty ? nil : trimmed
      }
      return String(trimmed.dropFirst())
    }

    private static func renderStateConcurrencyMap(_ value: [String: Int]) -> String {
      value.keys.sorted().compactMap { key in
        guard let limit = value[key] else {
          return nil
        }
        return "\(key): \(limit)"
      }.joined(separator: "\n")
    }

    private static func renderCodexSandbox(_ value: CodexSandboxValue?) -> String {
      guard let value else {
        return ""
      }

      switch value {
      case .string(let scalar):
        return scalar
      case .bool(let scalar):
        return scalar ? "true" : "false"
      case .integer(let scalar):
        return String(scalar)
      case .double(let scalar):
        return String(scalar)
      case .array(let values):
        return values.map { "- \(renderCodexSandbox($0))" }.joined(separator: "\n")
      case .object(let values):
        return values.keys.sorted().compactMap { key in
          guard let nested = values[key] else {
            return nil
          }
          let rendered = renderCodexSandbox(nested)
          if rendered.contains("\n") {
            let indented = rendered.split(separator: "\n").map { "  \($0)" }.joined(separator: "\n")
            return "\(key):\n\(indented)"
          }
          return "\(key): \(rendered)"
        }.joined(separator: "\n")
      case .null:
        return "null"
      }
    }
  }

  enum WorkflowAuthoringError: LocalizedError, Equatable, Sendable {
    case invalidInteger(field: String, value: String)
    case invalidStateConcurrencyLine(String)

    var errorDescription: String? {
      switch self {
      case .invalidInteger(let field, let value):
        return "Enter a whole number for \(field) instead of “\(value)”."
      case .invalidStateConcurrencyLine(let value):
        return "Use “State: 2” or “State=2” for max concurrent agents by state. Invalid line: \(value)"
      }
    }
  }

  struct LocalServerStatusSnapshot: Equatable, Sendable {
    var state: LocalServerLaunchState
    var endpoint: BootstrapServerEndpoint
    var transcript: [String]
    var failureDescription: String?
    var processIdentifier: Int32?

    init(
      state: LocalServerLaunchState,
      endpoint: BootstrapServerEndpoint,
      transcript: [String] = [],
      failureDescription: String? = nil,
      processIdentifier: Int32? = nil
    ) {
      self.state = state
      self.endpoint = endpoint
      self.transcript = transcript
      self.failureDescription = failureDescription
      self.processIdentifier = processIdentifier
    }
  }

  struct LocalServerLaunchRequest: Equatable, Sendable {
    var helperURL: URL
    var workflowURL: URL
    var currentDirectoryURL: URL
    var endpoint: BootstrapServerEndpoint
    var environment: [String: String]
  }

  enum LocalServerLaunchError: LocalizedError, Equatable, Sendable {
    case workflowNotConfigured
    case workflowMissing(String)
    case invalidPort(String)
    case missingEnvironmentKeys([String])
    case helperUnavailable(String)
    case startupFailed(String)
    case helperExitedBeforeReady(Int32)
    case healthTimedOut(String)
    case occupiedPort(Int)

    var errorDescription: String? {
      switch self {
      case .workflowNotConfigured:
        return "Choose a WORKFLOW.md file before starting the local server."
      case .workflowMissing(let path):
        return "The configured workflow file no longer exists at \(path)."
      case .invalidPort(let value):
        return "Enter a valid port instead of “\(value)”."
      case .missingEnvironmentKeys(let keys):
        return "Fill in the required environment values: \(keys.joined(separator: ", "))."
      case .helperUnavailable(let path):
        return "The bundled local server helper was not found at \(path)."
      case .startupFailed(let message):
        return message
      case .helperExitedBeforeReady(let status):
        return "The local server exited before it became ready (status \(status))."
      case .healthTimedOut(let endpoint):
        return "The local server did not become healthy at \(endpoint) before timing out."
      case .occupiedPort(let port):
        return "Port \(port) is already in use."
      }
    }
  }

  enum SymphonyServerBootstrapEnvironment {
    static let workflowPathKey = "SYMPHONY_WORKFLOW_PATH"
    static let serverSQLitePathKey = "SYMPHONY_STORAGE_SQLITE_PATH"
  }

  @MainActor
  protocol LocalServerManaging: AnyObject {
    var statusSnapshot: LocalServerStatusSnapshot { get }
    var onStatusChange: ((LocalServerStatusSnapshot) -> Void)? { get set }
    func start(request: LocalServerLaunchRequest) async
    func stop() async
    func restart(request: LocalServerLaunchRequest) async
  }

  protocol LocalServerProfileStoring {
    func loadProfile() -> LocalServerProfile?
    func saveProfile(_ profile: LocalServerProfile) throws
    func clearProfile() throws
  }

  protocol LocalServerSecretStoring {
    func secret(for key: String) -> String?
    func setSecret(_ value: String, for key: String) throws
    func removeSecret(for key: String) throws
  }

  @MainActor
  protocol LocalWorkflowSelecting {
    func selectWorkflowURL() -> URL?
  }

  @MainActor
  protocol LocalWorkflowSaving {
    func saveWorkflow(
      named fileName: String,
      suggestedDirectoryURL: URL?,
      content: String
    ) throws -> URL?
  }

  protocol LocalServerVariableScanning {
    func scanVariables(at workflowURL: URL) throws -> [String]
  }

  protocol LocalServerHelperLocating {
    func helperURL() throws -> URL
  }

  protocol LocalServerProcessControlling: AnyObject {
    var processIdentifier: Int32 { get }
    func terminate()
  }

  protocol LocalServerProcessLaunching {
    func launch(
      request: LocalServerLaunchRequest,
      onOutput: @escaping @Sendable (String) -> Void,
      onExit: @escaping @Sendable (Int32) -> Void
    ) throws -> any LocalServerProcessControlling
  }

  struct LocalServerServices {
    var manager: any LocalServerManaging
    var profileStore: any LocalServerProfileStoring
    var secretStore: any LocalServerSecretStoring
    var workflowSelector: any LocalWorkflowSelecting
    var workflowSaver: any LocalWorkflowSaving
    var variableScanner: any LocalServerVariableScanning
    var helperLocator: any LocalServerHelperLocating
    var environmentProvider: @Sendable () -> [String: String]

    init(
      manager: any LocalServerManaging,
      profileStore: any LocalServerProfileStoring,
      secretStore: any LocalServerSecretStoring,
      workflowSelector: any LocalWorkflowSelecting,
      workflowSaver: any LocalWorkflowSaving,
      variableScanner: any LocalServerVariableScanning,
      helperLocator: any LocalServerHelperLocating,
      environmentProvider: @escaping @Sendable () -> [String: String]
    ) {
      self.manager = manager
      self.profileStore = profileStore
      self.secretStore = secretStore
      self.workflowSelector = workflowSelector
      self.workflowSaver = workflowSaver
      self.variableScanner = variableScanner
      self.helperLocator = helperLocator
      self.environmentProvider = environmentProvider
    }

    @MainActor
    static func live(
      bundle: Bundle = .main,
      environmentProvider: @escaping @Sendable () -> [String: String] = {
        ProcessInfo.processInfo.environment
      }
    ) -> Self {
      let manager = DefaultLocalServerManager()
      return Self(
        manager: manager,
        profileStore: UserDefaultsLocalServerProfileStore(),
        secretStore: KeychainLocalServerSecretStore(),
        workflowSelector: NSOpenPanelWorkflowSelector(),
        workflowSaver: NSSavePanelWorkflowSaver(),
        variableScanner: WorkflowEnvironmentVariableScanner(),
        helperLocator: BundledLocalServerHelperLocator(bundle: bundle),
        environmentProvider: environmentProvider
      )
    }

    @MainActor
    static func uiTesting(
      environmentProvider: @escaping @Sendable () -> [String: String] = {
        ProcessInfo.processInfo.environment
      }
    ) -> Self {
      let environment = environmentProvider()
      let startsWithoutWorkflowProfile = environment["SYMPHONY_UI_TESTING_EMPTY_LOCAL_SERVER_PROFILE"]
        == "1"
      let workflowURL = FileManager.default.temporaryDirectory.appendingPathComponent(
        "symphony-ui-testing-WORKFLOW.md",
        isDirectory: false
      )
      if !FileManager.default.fileExists(atPath: workflowURL.path) {
        try? """
          ---
          tracker:
            project_owner: atjsh
            project_owner_type: organization
            project_number: 1
          ---
          Resolve {{issue.title}}
          """.write(to: workflowURL, atomically: true, encoding: .utf8)
      }

      let profileStore = InMemoryLocalServerProfileStore(
        profile: startsWithoutWorkflowProfile
          ? nil
          : LocalServerProfile(
            workflowPath: workflowURL.path,
            host: "localhost",
            port: 8080,
            sqlitePath: nil,
            environmentKeys: []
          )
      )

      return Self(
        manager: UITestingLocalServerManager(),
        profileStore: profileStore,
        secretStore: InMemoryLocalServerSecretStore(),
        workflowSelector: StubWorkflowSelector(selectedURL: workflowURL),
        workflowSaver: UITestingWorkflowFileSaver(environmentProvider: { environment }),
        variableScanner: WorkflowEnvironmentVariableScanner(),
        helperLocator: StubHelperLocator(url: URL(fileURLWithPath: "/tmp/SymphonyLocalServerHelper")),
        environmentProvider: { environment }
      )
    }
  }

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

  struct UserDefaultsLocalServerProfileStore: LocalServerProfileStoring {
    private let key: String
    private let userDefaults: UserDefaults

    init(
      key: String = "Symphony.LocalServerProfile",
      userDefaults: UserDefaults = .standard
    ) {
      self.key = key
      self.userDefaults = userDefaults
    }

    func loadProfile() -> LocalServerProfile? {
      guard let data = userDefaults.data(forKey: key) else {
        return nil
      }
      return try? JSONDecoder().decode(LocalServerProfile.self, from: data)
    }

    func saveProfile(_ profile: LocalServerProfile) throws {
      let data = try JSONEncoder().encode(profile)
      userDefaults.set(data, forKey: key)
    }

    func clearProfile() throws {
      userDefaults.removeObject(forKey: key)
    }
  }

  struct InMemoryLocalServerProfileStore: LocalServerProfileStoring {
    final class Storage: @unchecked Sendable {
      var profile: LocalServerProfile?

      init(profile: LocalServerProfile?) {
        self.profile = profile
      }
    }

    private let storage: Storage

    init(profile: LocalServerProfile? = nil) {
      self.storage = Storage(profile: profile)
    }

    func loadProfile() -> LocalServerProfile? {
      storage.profile
    }

    func saveProfile(_ profile: LocalServerProfile) throws {
      storage.profile = profile
    }

    func clearProfile() throws {
      storage.profile = nil
    }
  }

  struct KeychainLocalServerSecretStore: LocalServerSecretStoring {
    private let service: String

    init(service: String = "dev.atjsh.symphony.local-server") {
      self.service = service
    }

    func secret(for key: String) -> String? {
      let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: key,
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne,
      ]

      var item: CFTypeRef?
      let status = SecItemCopyMatching(query as CFDictionary, &item)
      guard status == errSecSuccess,
        let data = item as? Data
      else {
        return nil
      }

      return String(data: data, encoding: .utf8)
    }

    func setSecret(_ value: String, for key: String) throws {
      let encodedValue = Data(value.utf8)
      let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: key,
      ]

      let attributes: [String: Any] = [
        kSecValueData as String: encodedValue
      ]

      let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
      if updateStatus == errSecItemNotFound {
        var insert = query
        insert[kSecValueData as String] = encodedValue
        let insertStatus = SecItemAdd(insert as CFDictionary, nil)
        guard insertStatus == errSecSuccess else {
          throw LocalServerLaunchError.startupFailed("Failed to store \(key) in the keychain.")
        }
        return
      }

      guard updateStatus == errSecSuccess else {
        throw LocalServerLaunchError.startupFailed("Failed to update \(key) in the keychain.")
      }
    }

    func removeSecret(for key: String) throws {
      let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: key,
      ]
      let status = SecItemDelete(query as CFDictionary)
      guard status == errSecSuccess || status == errSecItemNotFound else {
        throw LocalServerLaunchError.startupFailed("Failed to remove \(key) from the keychain.")
      }
    }
  }

  struct InMemoryLocalServerSecretStore: LocalServerSecretStoring {
    final class Storage: @unchecked Sendable {
      var values: [String: String]

      init(values: [String: String]) {
        self.values = values
      }
    }

    private let storage: Storage

    init(values: [String: String] = [:]) {
      self.storage = Storage(values: values)
    }

    func secret(for key: String) -> String? {
      storage.values[key]
    }

    func setSecret(_ value: String, for key: String) throws {
      storage.values[key] = value
    }

    func removeSecret(for key: String) throws {
      storage.values.removeValue(forKey: key)
    }
  }

  struct WorkflowEnvironmentVariableScanner: LocalServerVariableScanning {
    func scanVariables(at workflowURL: URL) throws -> [String] {
      let contents = try String(contentsOf: workflowURL, encoding: .utf8)
      let regex = try NSRegularExpression(pattern: "\\$([A-Za-z_][A-Za-z0-9_]*)")
      let range = NSRange(contents.startIndex..<contents.endIndex, in: contents)
      var values = Set<String>()

      for match in regex.matches(in: contents, range: range) {
        guard let variableRange = Range(match.range(at: 1), in: contents) else {
          continue
        }
        values.insert(String(contents[variableRange]))
      }

      return values.sorted()
    }
  }

  struct NSOpenPanelWorkflowSelector: LocalWorkflowSelecting {
    func selectWorkflowURL() -> URL? {
      let panel = NSOpenPanel()
      panel.title = "Choose WORKFLOW.md"
      panel.prompt = "Choose"
      panel.canChooseDirectories = false
      panel.canChooseFiles = true
      panel.allowsMultipleSelection = false
      panel.allowedContentTypes = []
      panel.nameFieldStringValue = "WORKFLOW.md"
      return panel.runModal() == .OK ? panel.url : nil
    }
  }

  struct NSSavePanelWorkflowSaver: LocalWorkflowSaving {
    let fileManager: FileManager

    init(fileManager: FileManager = .default) {
      self.fileManager = fileManager
    }

    func saveWorkflow(
      named fileName: String,
      suggestedDirectoryURL: URL?,
      content: String
    ) throws -> URL? {
      let panel = NSSavePanel()
      panel.title = "Save WORKFLOW.md"
      panel.prompt = "Save"
      panel.canCreateDirectories = true
      panel.nameFieldStringValue = fileName
      panel.directoryURL = suggestedDirectoryURL ?? fileManager.homeDirectoryForCurrentUser

      guard panel.runModal() == .OK, let destinationURL = panel.url else {
        return nil
      }

      try content.write(to: destinationURL, atomically: true, encoding: .utf8)
      return destinationURL
    }
  }

  struct UITestingWorkflowFileSaver: LocalWorkflowSaving {
    let fileManager: FileManager
    let environmentProvider: @Sendable () -> [String: String]

    init(
      fileManager: FileManager = .default,
      environmentProvider: @escaping @Sendable () -> [String: String]
    ) {
      self.fileManager = fileManager
      self.environmentProvider = environmentProvider
    }

    func saveWorkflow(
      named fileName: String,
      suggestedDirectoryURL: URL?,
      content: String
    ) throws -> URL? {
      let environment = environmentProvider()
      let baseDirectory =
        environment["SYMPHONY_UI_TESTING_WORKFLOW_DIRECTORY"].map {
          URL(fileURLWithPath: NSString(string: $0).expandingTildeInPath, isDirectory: true)
        }
        ?? suggestedDirectoryURL
        ?? fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
      try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)

      let resolvedFileName = environment["SYMPHONY_UI_TESTING_WORKFLOW_FILENAME"] ?? fileName
      let workflowURL = baseDirectory.appendingPathComponent(resolvedFileName, isDirectory: false)
      try content.write(to: workflowURL, atomically: true, encoding: .utf8)
      return workflowURL
    }
  }

  struct StubWorkflowSelector: LocalWorkflowSelecting {
    var selectedURL: URL?

    func selectWorkflowURL() -> URL? {
      selectedURL
    }
  }

  struct BundledLocalServerHelperLocator: LocalServerHelperLocating {
    let bundle: Bundle
    let fileManager: FileManager

    init(bundle: Bundle = .main, fileManager: FileManager = .default) {
      self.bundle = bundle
      self.fileManager = fileManager
    }

    func helperURL() throws -> URL {
      let candidates = [
        bundle.bundleURL.appendingPathComponent("Contents/Resources/SymphonyLocalServerHelper"),
        bundle.bundleURL.appendingPathComponent("Contents/Helpers/SymphonyLocalServerHelper"),
        bundle.bundleURL.appendingPathComponent("Contents/MacOS/SymphonyLocalServerHelper"),
        bundle.bundleURL.deletingLastPathComponent().appendingPathComponent("SymphonyLocalServerHelper"),
      ]

      for candidate in candidates where fileManager.isExecutableFile(atPath: candidate.path) {
        return candidate
      }

      throw LocalServerLaunchError.helperUnavailable(candidates[0].path)
    }
  }

  struct StubHelperLocator: LocalServerHelperLocating {
    var url: URL

    func helperURL() throws -> URL {
      url
    }
  }

  final class DefaultLocalServerProcessController: LocalServerProcessControlling, @unchecked Sendable
  {
    private let process: Process
    private let pipe: Pipe
    private let outputBuffer: OutputBuffer

    var processIdentifier: Int32 {
      process.processIdentifier
    }

    fileprivate init(process: Process, pipe: Pipe, outputBuffer: OutputBuffer) {
      self.process = process
      self.pipe = pipe
      self.outputBuffer = outputBuffer
    }

    func terminate() {
      pipe.fileHandleForReading.readabilityHandler = nil
      process.terminate()
      _ = outputBuffer.finish()
    }
  }

  struct DefaultLocalServerProcessLauncher: LocalServerProcessLaunching {
    func launch(
      request: LocalServerLaunchRequest,
      onOutput: @escaping @Sendable (String) -> Void,
      onExit: @escaping @Sendable (Int32) -> Void
    ) throws -> any LocalServerProcessControlling {
      let process = Process()
      let pipe = Pipe()
      let outputBuffer = OutputBuffer(onLine: onOutput)
      process.executableURL = request.helperURL
      process.arguments = []
      process.environment = request.environment
      process.currentDirectoryURL = request.currentDirectoryURL
      process.standardOutput = pipe
      process.standardError = pipe
      pipe.fileHandleForReading.readabilityHandler = { handle in
        let data = handle.availableData
        if data.isEmpty {
          for line in outputBuffer.finish() {
            onOutput(line)
          }
          return
        }

        for line in outputBuffer.append(data) {
          onOutput(line)
        }
      }

      process.terminationHandler = { process in
        pipe.fileHandleForReading.readabilityHandler = nil
        for line in outputBuffer.finish() {
          onOutput(line)
        }
        onExit(process.terminationStatus)
      }

      try process.run()
      return DefaultLocalServerProcessController(
        process: process,
        pipe: pipe,
        outputBuffer: outputBuffer
      )
    }
  }

  @MainActor
  final class DefaultLocalServerManager: LocalServerManaging, @unchecked Sendable {
    var onStatusChange: ((LocalServerStatusSnapshot) -> Void)?
    private(set) var statusSnapshot = LocalServerStatusSnapshot(
      state: .idle,
      endpoint: .defaultEndpoint
    )

    private let processLauncher: any LocalServerProcessLaunching
    private let healthCheck: @Sendable (BootstrapServerEndpoint) async throws -> Void
    private let clock: ContinuousClock
    private var process: (any LocalServerProcessControlling)?
    private var generation: Int = 0
    private var requestedStopGenerations = Set<Int>()

    init(
      processLauncher: (any LocalServerProcessLaunching)? = nil,
      healthCheck: (@Sendable (BootstrapServerEndpoint) async throws -> Void)? = nil,
      clock: ContinuousClock = ContinuousClock()
    ) {
      self.processLauncher = processLauncher ?? DefaultLocalServerProcessLauncher()
      self.clock = clock
      if let healthCheck {
        self.healthCheck = healthCheck
      } else {
        let client = URLSessionSymphonyAPIClient()
        self.healthCheck = { endpoint in
          let resolved = try ServerEndpoint(
            scheme: endpoint.scheme,
            host: endpoint.host,
            port: endpoint.port
          )
          _ = try await client.health(endpoint: resolved)
        }
      }
    }

    func start(request: LocalServerLaunchRequest) async {
      await stop()
      generation += 1
      let currentGeneration = generation
      updateStatus(
        LocalServerStatusSnapshot(
          state: .starting,
          endpoint: request.endpoint,
          transcript: [],
          failureDescription: nil,
          processIdentifier: nil
        )
      )

      do {
        let process = try processLauncher.launch(
          request: request,
          onOutput: { [weak self] line in
            Task { @MainActor in
              self?.appendTranscript(line, generation: currentGeneration)
            }
          },
          onExit: { [weak self] status in
            Task { @MainActor in
              self?.handleProcessExit(status: status, generation: currentGeneration)
            }
          }
        )

        self.process = process
        updateStatus(
          LocalServerStatusSnapshot(
            state: .waitingForHealth,
            endpoint: request.endpoint,
            transcript: statusSnapshot.transcript,
            failureDescription: nil,
            processIdentifier: process.processIdentifier
          )
        )

        do {
          try await waitForHealth(endpoint: request.endpoint, generation: currentGeneration)
          guard currentGeneration == generation else {
            return
          }
          updateStatus(
            LocalServerStatusSnapshot(
              state: .running,
              endpoint: request.endpoint,
              transcript: statusSnapshot.transcript,
              failureDescription: nil,
              processIdentifier: process.processIdentifier
            )
          )
        } catch let error as LocalServerLaunchError {
          fail(with: error, generation: currentGeneration)
        } catch {
          fail(with: .startupFailed(error.localizedDescription), generation: currentGeneration)
        }
      } catch let error as LocalServerLaunchError {
        fail(with: error, generation: currentGeneration)
      } catch {
        fail(with: .startupFailed(error.localizedDescription), generation: currentGeneration)
      }
    }

    func stop() async {
      guard let process else {
        updateStatus(
          LocalServerStatusSnapshot(
            state: .idle,
            endpoint: statusSnapshot.endpoint,
            transcript: statusSnapshot.transcript,
            failureDescription: nil,
            processIdentifier: nil
          )
        )
        return
      }

      requestedStopGenerations.insert(generation)
      process.terminate()
      self.process = nil
      updateStatus(
        LocalServerStatusSnapshot(
          state: .idle,
          endpoint: statusSnapshot.endpoint,
          transcript: statusSnapshot.transcript,
          failureDescription: nil,
          processIdentifier: nil
        )
      )
    }

    func restart(request: LocalServerLaunchRequest) async {
      await stop()
      await start(request: request)
    }

    private func waitForHealth(endpoint: BootstrapServerEndpoint, generation: Int) async throws {
      let deadline = clock.now.advanced(by: .seconds(15))
      while clock.now < deadline {
        if generation != self.generation {
          throw LocalServerLaunchError.startupFailed("The local server launch was cancelled.")
        }

        do {
          try await healthCheck(endpoint)
          return
        } catch {
          if process == nil {
            throw mappedFailure(
              from: statusSnapshot.transcript,
              endpoint: endpoint,
              fallback: .helperExitedBeforeReady(-1)
            )
          }
        }

        try await Task.sleep(for: .milliseconds(150))
      }

      throw mappedFailure(
        from: statusSnapshot.transcript,
        endpoint: endpoint,
        fallback: .healthTimedOut(endpoint.displayString)
      )
    }

    private func handleProcessExit(status: Int32, generation: Int) {
      guard generation == self.generation else {
        return
      }

      process = nil
      if requestedStopGenerations.remove(generation) != nil || statusSnapshot.state == .idle {
        return
      }

      let failure = mappedFailure(
        from: statusSnapshot.transcript,
        endpoint: statusSnapshot.endpoint,
        fallback: .helperExitedBeforeReady(status)
      )
      fail(with: failure, generation: generation)
    }

    private func appendTranscript(_ line: String, generation: Int) {
      guard generation == self.generation else {
        return
      }

      var updated = statusSnapshot
      updated.transcript.append(line)
      updateStatus(updated)
    }

    private func fail(with error: LocalServerLaunchError, generation: Int) {
      guard generation == self.generation else {
        return
      }

      updateStatus(
        LocalServerStatusSnapshot(
          state: .failed,
          endpoint: statusSnapshot.endpoint,
          transcript: statusSnapshot.transcript,
          failureDescription: error.localizedDescription,
          processIdentifier: statusSnapshot.processIdentifier
        )
      )
    }

    private func updateStatus(_ status: LocalServerStatusSnapshot) {
      statusSnapshot = status
      onStatusChange?(status)
    }

    private func mappedFailure(
      from transcript: [String],
      endpoint: BootstrapServerEndpoint,
      fallback: LocalServerLaunchError
    ) -> LocalServerLaunchError {
      if transcript.contains(where: { $0.localizedCaseInsensitiveContains("address already in use") })
      {
        return .occupiedPort(endpoint.port)
      }

      if let lastFailure = transcript.last(where: { $0.contains("failed to start:") }) {
        return .startupFailed(lastFailure)
      }

      return fallback
    }
  }

  @MainActor
  final class UITestingLocalServerManager: LocalServerManaging, @unchecked Sendable {
    var onStatusChange: ((LocalServerStatusSnapshot) -> Void)?
    private(set) var statusSnapshot = LocalServerStatusSnapshot(
      state: .needsSetup,
      endpoint: .defaultEndpoint
    )

    func start(request: LocalServerLaunchRequest) async {
      statusSnapshot = LocalServerStatusSnapshot(
        state: .running,
        endpoint: request.endpoint,
        transcript: [
          "[SymphonyServer] starting",
          "[SymphonyServer] endpoint=\(request.endpoint.displayString)",
        ],
        failureDescription: nil,
        processIdentifier: 4242
      )
      onStatusChange?(statusSnapshot)
    }

    func stop() async {
      statusSnapshot = LocalServerStatusSnapshot(
        state: .idle,
        endpoint: statusSnapshot.endpoint,
        transcript: statusSnapshot.transcript,
        failureDescription: nil,
        processIdentifier: nil
      )
      onStatusChange?(statusSnapshot)
    }

    func restart(request: LocalServerLaunchRequest) async {
      await start(request: request)
    }
  }

  private final class OutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()

    init(onLine _: @escaping @Sendable (String) -> Void) {}

    func append(_ data: Data) -> [String] {
      guard !data.isEmpty else {
        return []
      }

      lock.lock()
      buffer.append(data)
      let lines = consumeLines()
      lock.unlock()
      return lines
    }

    func finish() -> [String] {
      lock.lock()
      defer {
        buffer.removeAll(keepingCapacity: false)
        lock.unlock()
      }

      guard !buffer.isEmpty else {
        return []
      }

      let line = String(decoding: buffer, as: UTF8.self)
      return line.isEmpty ? [] : [line]
    }

    private func consumeLines() -> [String] {
      guard !buffer.isEmpty else {
        return []
      }

      var lines = [String]()
      while let newlineIndex = buffer.firstIndex(of: 0x0A) {
        let lineData = buffer.prefix(upTo: newlineIndex)
        buffer.removeSubrange(...newlineIndex)
        let line = String(decoding: lineData, as: UTF8.self)
          .trimmingCharacters(in: .newlines)
        if !line.isEmpty {
          lines.append(line)
        }
      }
      return lines
    }
  }
#endif
