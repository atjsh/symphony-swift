import Foundation

public struct RunSummary: Codable, Hashable, Sendable {
  public let runID: RunID
  public let issueID: IssueID
  public let issueIdentifier: IssueIdentifier
  public let attempt: Int
  public let status: String
  public let provider: String
  public let providerSessionID: String?
  public let providerRunID: String?
  public let startedAt: String
  public let endedAt: String?
  public let workspacePath: String
  public let sessionID: SessionID?
  public let lastError: String?

  public init(
    runID: RunID,
    issueID: IssueID,
    issueIdentifier: IssueIdentifier,
    attempt: Int,
    status: String,
    provider: String,
    providerSessionID: String?,
    providerRunID: String?,
    startedAt: String,
    endedAt: String?,
    workspacePath: String,
    sessionID: SessionID?,
    lastError: String?
  ) {
    self.runID = runID
    self.issueID = issueID
    self.issueIdentifier = issueIdentifier
    self.attempt = attempt
    self.status = status
    self.provider = provider
    self.providerSessionID = providerSessionID
    self.providerRunID = providerRunID
    self.startedAt = startedAt
    self.endedAt = endedAt
    self.workspacePath = workspacePath
    self.sessionID = sessionID
    self.lastError = lastError
  }

  private enum CodingKeys: String, CodingKey {
    case runID = "run_id"
    case issueID = "issue_id"
    case issueIdentifier = "issue_identifier"
    case attempt
    case status
    case provider
    case providerSessionID = "provider_session_id"
    case providerRunID = "provider_run_id"
    case startedAt = "started_at"
    case endedAt = "ended_at"
    case workspacePath = "workspace_path"
    case sessionID = "session_id"
    case lastError = "last_error"
  }
}

public struct RunDetail: Codable, Hashable, Sendable {
  public let runID: RunID
  public let issueID: IssueID
  public let issueIdentifier: IssueIdentifier
  public let attempt: Int
  public let status: String
  public let provider: String
  public let providerSessionID: String?
  public let providerRunID: String?
  public let startedAt: String
  public let endedAt: String?
  public let workspacePath: String
  public let sessionID: SessionID?
  public let lastError: String?
  public let issue: Issue
  public let turnCount: Int
  public let lastAgentEventType: String?
  public let lastAgentMessage: String?
  public let tokens: TokenUsage
  public let logs: RunLogStats

  public init(
    runID: RunID,
    issueID: IssueID,
    issueIdentifier: IssueIdentifier,
    attempt: Int,
    status: String,
    provider: String,
    providerSessionID: String?,
    providerRunID: String?,
    startedAt: String,
    endedAt: String?,
    workspacePath: String,
    sessionID: SessionID?,
    lastError: String?,
    issue: Issue,
    turnCount: Int,
    lastAgentEventType: String?,
    lastAgentMessage: String?,
    tokens: TokenUsage,
    logs: RunLogStats
  ) {
    self.runID = runID
    self.issueID = issueID
    self.issueIdentifier = issueIdentifier
    self.attempt = attempt
    self.status = status
    self.provider = provider
    self.providerSessionID = providerSessionID
    self.providerRunID = providerRunID
    self.startedAt = startedAt
    self.endedAt = endedAt
    self.workspacePath = workspacePath
    self.sessionID = sessionID
    self.lastError = lastError
    self.issue = issue
    self.turnCount = turnCount
    self.lastAgentEventType = lastAgentEventType
    self.lastAgentMessage = lastAgentMessage
    self.tokens = tokens
    self.logs = logs
  }

  private enum CodingKeys: String, CodingKey {
    case runID = "run_id"
    case issueID = "issue_id"
    case issueIdentifier = "issue_identifier"
    case attempt
    case status
    case provider
    case providerSessionID = "provider_session_id"
    case providerRunID = "provider_run_id"
    case startedAt = "started_at"
    case endedAt = "ended_at"
    case workspacePath = "workspace_path"
    case sessionID = "session_id"
    case lastError = "last_error"
    case issue
    case turnCount = "turn_count"
    case lastAgentEventType = "last_agent_event_type"
    case lastAgentMessage = "last_agent_message"
    case tokens
    case logs
  }
}

public struct AgentSession: Codable, Hashable, Sendable {
  public let sessionID: SessionID
  public let provider: String
  public let providerSessionID: String?
  public let providerThreadID: String?
  public let providerTurnID: String?
  public let providerRunID: String?
  public let runID: RunID
  public let providerProcessPID: String?
  public let status: String
  public let lastEventType: String?
  public let lastEventAt: String?
  public let turnCount: Int
  public let tokenUsage: TokenUsage
  public let latestRateLimitPayload: String?

  public init(
    sessionID: SessionID,
    provider: String,
    providerSessionID: String?,
    providerThreadID: String?,
    providerTurnID: String?,
    providerRunID: String?,
    runID: RunID,
    providerProcessPID: String?,
    status: String,
    lastEventType: String?,
    lastEventAt: String?,
    turnCount: Int,
    tokenUsage: TokenUsage,
    latestRateLimitPayload: String?
  ) {
    self.sessionID = sessionID
    self.provider = provider
    self.providerSessionID = providerSessionID
    self.providerThreadID = providerThreadID
    self.providerTurnID = providerTurnID
    self.providerRunID = providerRunID
    self.runID = runID
    self.providerProcessPID = providerProcessPID
    self.status = status
    self.lastEventType = lastEventType
    self.lastEventAt = lastEventAt
    self.turnCount = turnCount
    self.tokenUsage = tokenUsage
    self.latestRateLimitPayload = latestRateLimitPayload
  }

  private enum CodingKeys: String, CodingKey {
    case sessionID = "session_id"
    case provider
    case providerSessionID = "provider_session_id"
    case providerThreadID = "provider_thread_id"
    case providerTurnID = "provider_turn_id"
    case providerRunID = "provider_run_id"
    case runID = "run_id"
    case providerProcessPID = "provider_process_pid"
    case status
    case lastEventType = "last_event_type"
    case lastEventAt = "last_event_at"
    case turnCount = "turn_count"
    case tokenUsage = "token_usage"
    case latestRateLimitPayload = "latest_rate_limit_payload"
  }
}

public struct AgentRawEvent: Codable, Hashable, Sendable {
  public let sessionID: SessionID
  public let provider: String
  public let sequence: EventSequence
  public let timestamp: String
  public let rawJSON: String
  public let providerEventType: String
  public let normalizedEventKind: String?

  public init(
    sessionID: SessionID,
    provider: String,
    sequence: EventSequence,
    timestamp: String,
    rawJSON: String,
    providerEventType: String,
    normalizedEventKind: String?
  ) {
    self.sessionID = sessionID
    self.provider = provider
    self.sequence = sequence
    self.timestamp = timestamp
    self.rawJSON = rawJSON
    self.providerEventType = providerEventType
    self.normalizedEventKind = normalizedEventKind
  }

  public var normalizedKind: NormalizedEventKind {
    guard let normalizedEventKind,
      let kind = NormalizedEventKind(rawValue: normalizedEventKind)
    else {
      return .unknown
    }
    return kind
  }

  private enum CodingKeys: String, CodingKey {
    case sessionID = "session_id"
    case provider
    case sequence
    case timestamp
    case rawJSON = "raw_json"
    case providerEventType = "provider_event_type"
    case normalizedEventKind = "normalized_event_kind"
  }
}
