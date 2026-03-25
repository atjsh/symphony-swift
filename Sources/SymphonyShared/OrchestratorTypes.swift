import Foundation

// MARK: - Run Lifecycle States (Section 8.3)

public enum RunLifecycleState: String, Codable, Hashable, CaseIterable, Sendable {
  case preparingWorkspace = "PreparingWorkspace"
  case buildingPrompt = "BuildingPrompt"
  case launchingAgentProcess = "LaunchingAgentProcess"
  case initializingSession = "InitializingSession"
  case streamingTurn = "StreamingTurn"
  case finishing = "Finishing"
  case succeeded = "Succeeded"
  case failed = "Failed"
  case timedOut = "TimedOut"
  case stalled = "Stalled"
  case canceledByReconciliation = "CanceledByReconciliation"

  public var isTerminal: Bool {
    switch self {
    case .succeeded, .failed, .timedOut, .stalled, .canceledByReconciliation:
      return true
    case .preparingWorkspace, .buildingPrompt, .launchingAgentProcess,
      .initializingSession, .streamingTurn, .finishing:
      return false
    }
  }

  public var isActive: Bool {
    !isTerminal
  }
}

// MARK: - Claim States (Section 8.2)

public enum ClaimState: String, Codable, Hashable, CaseIterable, Sendable {
  case unclaimed = "Unclaimed"
  case claimed = "Claimed"
  case running = "Running"
  case retryQueued = "RetryQueued"
  case released = "Released"
}

// MARK: - Tool Execution Mode (Section 10.3)

public enum ToolExecutionMode: String, Codable, Hashable, CaseIterable, Sendable {
  case providerManaged = "provider_managed"
  case orchestratorManaged = "orchestrator_managed"
  case mixed
}

// MARK: - Provider Capabilities (Section 10.3)

public struct ProviderCapabilities: Codable, Hashable, Sendable {
  public let supportsResume: Bool
  public let supportsInterrupt: Bool
  public let supportsUsageTotals: Bool
  public let supportsRateLimits: Bool
  public let supportsExplicitApprovals: Bool
  public let supportsStructuredToolEvents: Bool
  public let toolExecutionMode: ToolExecutionMode

  public init(
    supportsResume: Bool = false,
    supportsInterrupt: Bool = false,
    supportsUsageTotals: Bool = false,
    supportsRateLimits: Bool = false,
    supportsExplicitApprovals: Bool = false,
    supportsStructuredToolEvents: Bool = false,
    toolExecutionMode: ToolExecutionMode = .providerManaged
  ) {
    self.supportsResume = supportsResume
    self.supportsInterrupt = supportsInterrupt
    self.supportsUsageTotals = supportsUsageTotals
    self.supportsRateLimits = supportsRateLimits
    self.supportsExplicitApprovals = supportsExplicitApprovals
    self.supportsStructuredToolEvents = supportsStructuredToolEvents
    self.toolExecutionMode = toolExecutionMode
  }

  private enum CodingKeys: String, CodingKey {
    case supportsResume = "supports_resume"
    case supportsInterrupt = "supports_interrupt"
    case supportsUsageTotals = "supports_usage_totals"
    case supportsRateLimits = "supports_rate_limits"
    case supportsExplicitApprovals = "supports_explicit_approvals"
    case supportsStructuredToolEvents = "supports_structured_tool_events"
    case toolExecutionMode = "tool_execution_mode"
  }
}

// MARK: - Retry Record (Section 8.5)

public struct RetryRecord: Codable, Hashable, Sendable {
  public let issueID: IssueID
  public let issueIdentifier: IssueIdentifier
  public let attempt: Int
  public let dueAt: Date
  public let error: String?

  public init(
    issueID: IssueID,
    issueIdentifier: IssueIdentifier,
    attempt: Int,
    dueAt: Date,
    error: String?
  ) {
    self.issueID = issueID
    self.issueIdentifier = issueIdentifier
    self.attempt = attempt
    self.dueAt = dueAt
    self.error = error
  }

  private enum CodingKeys: String, CodingKey {
    case issueID = "issue_id"
    case issueIdentifier = "issue_identifier"
    case attempt
    case dueAt = "due_at"
    case error
  }
}

// MARK: - Provider Name Constants

public enum ProviderName: String, Codable, Hashable, CaseIterable, Sendable {
  case codex
  case claudeCode = "claude_code"
  case copilotCLI = "copilot_cli"
}
