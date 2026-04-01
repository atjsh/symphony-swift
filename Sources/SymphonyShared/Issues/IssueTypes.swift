import Foundation

public struct Issue: Codable, Hashable, Sendable {
  public let id: IssueID
  public let identifier: IssueIdentifier
  public let repository: String
  public let number: Int
  public let title: String
  public let description: String?
  public let priority: Int?
  public let state: String
  public let issueState: String
  public let projectItemID: String?
  public let url: String?
  public let labels: [String]
  public let blockedBy: [BlockerReference]
  public let createdAt: String?
  public let updatedAt: String?

  public init(
    id: IssueID,
    identifier: IssueIdentifier,
    repository: String,
    number: Int,
    title: String,
    description: String?,
    priority: Int?,
    state: String,
    issueState: String,
    projectItemID: String?,
    url: String?,
    labels: [String],
    blockedBy: [BlockerReference],
    createdAt: String?,
    updatedAt: String?
  ) {
    self.id = id
    self.identifier = identifier
    self.repository = repository
    self.number = number
    self.title = title
    self.description = description
    self.priority = priority
    self.state = state
    self.issueState = issueState
    self.projectItemID = projectItemID
    self.url = url
    self.labels = labels.map { $0.lowercased() }
    self.blockedBy = blockedBy
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.id = try container.decode(IssueID.self, forKey: .id)
    self.identifier = try container.decode(IssueIdentifier.self, forKey: .identifier)
    self.repository = try container.decode(String.self, forKey: .repository)
    self.number = try container.decode(Int.self, forKey: .number)
    self.title = try container.decode(String.self, forKey: .title)
    self.description = try container.decodeIfPresent(String.self, forKey: .description)
    self.priority = try container.decodeIfPresent(Int.self, forKey: .priority)
    self.state = try container.decode(String.self, forKey: .state)
    self.issueState = try container.decode(String.self, forKey: .issueState)
    self.projectItemID = try container.decodeIfPresent(String.self, forKey: .projectItemID)
    self.url = try container.decodeIfPresent(String.self, forKey: .url)
    self.labels = (try container.decodeIfPresent([String].self, forKey: .labels) ?? []).map {
      $0.lowercased()
    }
    self.blockedBy =
      try container.decodeIfPresent([BlockerReference].self, forKey: .blockedBy) ?? []
    self.createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
    self.updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case identifier
    case repository
    case number
    case title
    case description
    case priority
    case state
    case issueState = "issue_state"
    case projectItemID = "project_item_id"
    case url
    case labels
    case blockedBy = "blocked_by"
    case createdAt = "created_at"
    case updatedAt = "updated_at"
  }
}

public struct IssueSummary: Codable, Hashable, Sendable {
  public let issueID: IssueID
  public let identifier: IssueIdentifier
  public let title: String
  public let state: String
  public let issueState: String
  public let priority: Int?
  public let currentProvider: String?
  public let currentRunID: RunID?
  public let currentSessionID: SessionID?

  public init(
    issueID: IssueID,
    identifier: IssueIdentifier,
    title: String,
    state: String,
    issueState: String,
    priority: Int?,
    currentProvider: String?,
    currentRunID: RunID?,
    currentSessionID: SessionID?
  ) {
    self.issueID = issueID
    self.identifier = identifier
    self.title = title
    self.state = state
    self.issueState = issueState
    self.priority = priority
    self.currentProvider = currentProvider
    self.currentRunID = currentRunID
    self.currentSessionID = currentSessionID
  }

  private enum CodingKeys: String, CodingKey {
    case issueID = "issue_id"
    case identifier
    case title
    case state
    case issueState = "issue_state"
    case priority
    case currentProvider = "current_provider"
    case currentRunID = "current_run_id"
    case currentSessionID = "current_session_id"
  }
}

public struct IssueDetail: Codable, Hashable, Sendable {
  public let issue: Issue
  public let latestRun: RunSummary?
  public let workspacePath: String?
  public let recentSessions: [AgentSession]

  public init(
    issue: Issue,
    latestRun: RunSummary?,
    workspacePath: String?,
    recentSessions: [AgentSession]
  ) {
    self.issue = issue
    self.latestRun = latestRun
    self.workspacePath = workspacePath
    self.recentSessions = recentSessions
  }

  private enum CodingKeys: String, CodingKey {
    case issue
    case latestRun = "latest_run"
    case workspacePath = "workspace_path"
    case recentSessions = "recent_sessions"
  }
}

public struct IssueProgressReportResponse: Codable, Hashable, Sendable {
  public let issueID: IssueID
  public let generatedAt: String
  public let report: RepositoryHistoryReport
  public let syntaxHealth: RepositorySyntaxHealth

  public init(
    issueID: IssueID,
    generatedAt: String,
    report: RepositoryHistoryReport,
    syntaxHealth: RepositorySyntaxHealth
  ) {
    self.issueID = issueID
    self.generatedAt = generatedAt
    self.report = report
    self.syntaxHealth = syntaxHealth
  }

  private enum CodingKeys: String, CodingKey {
    case issueID = "issue_id"
    case generatedAt = "generated_at"
    case report
    case syntaxHealth = "syntax_health"
  }
}
