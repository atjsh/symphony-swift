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
#endif
