import Foundation
import SymphonyShared

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
  public let analysis: AnalysisConfig
  public let agent: AgentConfig
  public let providers: ProvidersConfig
  public let server: SymphonyServerConfig
  public let storage: StorageConfig

  public init(
    tracker: TrackerConfig = .defaults,
    polling: PollingConfig = .defaults,
    workspace: WorkspaceConfig = .defaults,
    hooks: HooksConfig = .defaults,
    analysis: AnalysisConfig = .defaults,
    agent: AgentConfig = .defaults,
    providers: ProvidersConfig = .defaults,
    server: SymphonyServerConfig = .defaults,
    storage: StorageConfig = .defaults
  ) {
    self.tracker = tracker
    self.polling = polling
    self.workspace = workspace
    self.hooks = hooks
    self.analysis = analysis
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

// MARK: - Analysis Config (Section 6.3.5)

public struct AnalysisConfig: Equatable, Sendable {
  public let history: AnalysisHistoryConfig
  public let syntax: AnalysisSyntaxConfig

  public init(
    history: AnalysisHistoryConfig = .defaults,
    syntax: AnalysisSyntaxConfig = .defaults
  ) {
    self.history = history
    self.syntax = syntax
  }

  public static let defaults = AnalysisConfig()
}

public struct AnalysisHistoryConfig: Equatable, Sendable {
  public let sourcePaths: [String]
  public let testPaths: [String]

  public init(
    sourcePaths: [String] = [],
    testPaths: [String] = []
  ) {
    self.sourcePaths = sourcePaths
    self.testPaths = testPaths
  }

  public static let defaults = AnalysisHistoryConfig()
}

public struct AnalysisSyntaxConfig: Equatable, Sendable {
  public let command: String?

  public init(command: String? = nil) {
    self.command = command
  }

  public static let defaults = AnalysisSyntaxConfig()
}
