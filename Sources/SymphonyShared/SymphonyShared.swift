import Foundation

public enum SymphonySharedValidationError: Error, Equatable, Sendable {
    case invalidIssueIdentifier(String)
    case invalidServerEndpoint
    case invalidTokenUsage(expectedTotal: Int, actualTotal: Int)
}

public struct IssueID: Codable, Hashable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct RunID: Codable, Hashable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct SessionID: Codable, Hashable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct EventSequence: Codable, Hashable, Comparable, Sendable {
    public let rawValue: Int

    public init(_ rawValue: Int) {
        self.rawValue = rawValue
    }

    public static func < (lhs: EventSequence, rhs: EventSequence) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(try container.decode(Int.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct IssueIdentifier: Codable, Hashable, Sendable, CustomStringConvertible {
    public let owner: String
    public let repository: String
    public let number: Int

    public init(owner: String, repository: String, number: Int) throws {
        guard !owner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !repository.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              number > 0 else {
            throw SymphonySharedValidationError.invalidIssueIdentifier("\(owner)/\(repository)#\(number)")
        }

        self.owner = owner
        self.repository = repository
        self.number = number
    }

    public init(validating rawValue: String) throws {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed == rawValue else {
            throw SymphonySharedValidationError.invalidIssueIdentifier(rawValue)
        }

        let ownerAndRepository = rawValue.split(separator: "#", omittingEmptySubsequences: false)
        guard ownerAndRepository.count == 2,
              let issueNumber = Int(ownerAndRepository[1]),
              issueNumber > 0 else {
            throw SymphonySharedValidationError.invalidIssueIdentifier(rawValue)
        }

        let repositoryComponents = ownerAndRepository[0].split(separator: "/", omittingEmptySubsequences: false)
        guard repositoryComponents.count == 2,
              !repositoryComponents[0].isEmpty,
              !repositoryComponents[1].isEmpty else {
            throw SymphonySharedValidationError.invalidIssueIdentifier(rawValue)
        }

        self.owner = String(repositoryComponents[0])
        self.repository = String(repositoryComponents[1])
        self.number = issueNumber
    }

    public var rawValue: String {
        "\(owner)/\(repository)#\(number)"
    }

    public var description: String {
        rawValue
    }

    public var workspaceKey: WorkspaceKey {
        WorkspaceKey(issueIdentifier: self)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = try IssueIdentifier(validating: try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct WorkspaceKey: Codable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = WorkspaceKey.sanitized(rawValue)
    }

    public init(issueIdentifier: IssueIdentifier) {
        self.init(issueIdentifier.rawValue)
    }

    public var description: String {
        rawValue
    }

    private static func sanitized(_ rawValue: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")
        return String(rawValue.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct ServerEndpoint: Codable, Hashable, Sendable {
    public let scheme: String
    public let host: String
    public let port: Int

    public init(scheme: String = "http", host: String = "localhost", port: Int = 8080) throws {
        guard Self.isValidScheme(scheme), Self.isValidHost(host), Self.isValidPort(port) else {
            throw SymphonySharedValidationError.invalidServerEndpoint
        }

        self.scheme = scheme
        self.host = host
        self.port = port
    }

    public var url: URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = port
        return components.url
    }

    private static func isValidScheme(_ scheme: String) -> Bool {
        !scheme.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func isValidHost(_ host: String) -> Bool {
        !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func isValidPort(_ port: Int) -> Bool {
        (1...65535).contains(port)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self = try ServerEndpoint(
            scheme: container.decode(String.self, forKey: .scheme),
            host: container.decode(String.self, forKey: .host),
            port: container.decode(Int.self, forKey: .port)
        )
    }
}

public struct TokenUsage: Codable, Hashable, Sendable {
    public let inputTokens: Int?
    public let outputTokens: Int?
    public let totalTokens: Int?

    public init(inputTokens: Int? = nil, outputTokens: Int? = nil, totalTokens: Int? = nil) throws {
        if let inputTokens, let outputTokens, let totalTokens {
            let expectedTotal = inputTokens + outputTokens
            guard expectedTotal == totalTokens else {
                throw SymphonySharedValidationError.invalidTokenUsage(expectedTotal: expectedTotal, actualTotal: totalTokens)
            }
        }

        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        if let totalTokens {
            self.totalTokens = totalTokens
        } else if let inputTokens, let outputTokens {
            self.totalTokens = inputTokens + outputTokens
        } else {
            self.totalTokens = nil
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self = try TokenUsage(
            inputTokens: try container.decodeIfPresent(Int.self, forKey: .inputTokens),
            outputTokens: try container.decodeIfPresent(Int.self, forKey: .outputTokens),
            totalTokens: try container.decodeIfPresent(Int.self, forKey: .totalTokens)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case totalTokens = "total_tokens"
    }
}

public struct RunLogStats: Codable, Hashable, Sendable {
    public let eventCount: Int
    public let latestSequence: EventSequence?

    public init(eventCount: Int, latestSequence: EventSequence?) {
        self.eventCount = eventCount
        self.latestSequence = latestSequence
    }

    private enum CodingKeys: String, CodingKey {
        case eventCount = "event_count"
        case latestSequence = "latest_sequence"
    }
}

public enum NormalizedEventKind: String, Codable, Hashable, CaseIterable, Sendable {
    case message
    case toolCall = "tool_call"
    case toolResult = "tool_result"
    case status
    case usage
    case approvalRequest = "approval_request"
    case error
    case unknown
}

public struct BlockerReference: Codable, Hashable, Sendable {
    public let issueID: IssueID
    public let identifier: IssueIdentifier
    public let state: String
    public let issueState: String
    public let url: String?

    public init(
        issueID: IssueID,
        identifier: IssueIdentifier,
        state: String,
        issueState: String,
        url: String?
    ) {
        self.issueID = issueID
        self.identifier = identifier
        self.state = state
        self.issueState = issueState
        self.url = url
    }

    private enum CodingKeys: String, CodingKey {
        case issueID = "issue_id"
        case identifier
        case state
        case issueState = "issue_state"
        case url
    }
}

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
        self.labels = (try container.decodeIfPresent([String].self, forKey: .labels) ?? []).map { $0.lowercased() }
        self.blockedBy = try container.decodeIfPresent([BlockerReference].self, forKey: .blockedBy) ?? []
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
              let kind = NormalizedEventKind(rawValue: normalizedEventKind) else {
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

public struct EventCursor: Codable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(sessionID: SessionID, lastDeliveredSequence: EventSequence) {
        let payload = CursorPayload(sessionID: sessionID.rawValue, sequence: lastDeliveredSequence.rawValue)
        self.rawValue = Self.encode(payload)
    }

    public var description: String {
        rawValue
    }

    public var sessionID: SessionID? {
        guard let sessionID = Self.decode(rawValue)?.sessionID else {
            return nil
        }

        return SessionID(sessionID)
    }

    public var lastDeliveredSequence: EventSequence? {
        Self.decode(rawValue).map { EventSequence($0.sequence) }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    private struct CursorPayload: Codable, Hashable, Sendable {
        let sessionID: String
        let sequence: Int

        private enum CodingKeys: String, CodingKey {
            case sessionID = "session_id"
            case sequence
        }
    }

    private static func encode(_ payload: CursorPayload) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try! encoder.encode(payload)
        return data.base64URLEncodedString()
    }

    private static func decode(_ rawValue: String) -> CursorPayload? {
        guard let data = Data(base64URLEncoded: rawValue) else {
            return nil
        }

        return try? JSONDecoder().decode(CursorPayload.self, from: data)
    }
}

public struct HealthResponse: Codable, Hashable, Sendable {
    public let status: String
    public let serverTime: String
    public let version: String
    public let trackerKind: String

    public init(status: String, serverTime: String, version: String, trackerKind: String) {
        self.status = status
        self.serverTime = serverTime
        self.version = version
        self.trackerKind = trackerKind
    }

    private enum CodingKeys: String, CodingKey {
        case status
        case serverTime = "server_time"
        case version
        case trackerKind = "tracker_kind"
    }
}

public struct IssuesResponse: Codable, Hashable, Sendable {
    public let items: [IssueSummary]

    public init(items: [IssueSummary]) {
        self.items = items
    }
}

public struct LogEntriesResponse: Codable, Hashable, Sendable {
    public let sessionID: SessionID
    public let provider: String
    public let items: [AgentRawEvent]
    public let nextCursor: EventCursor?
    public let hasMore: Bool

    public init(
        sessionID: SessionID,
        provider: String,
        items: [AgentRawEvent],
        nextCursor: EventCursor?,
        hasMore: Bool
    ) {
        self.sessionID = sessionID
        self.provider = provider
        self.items = items
        self.nextCursor = nextCursor
        self.hasMore = hasMore
    }

    private enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case provider
        case items
        case nextCursor = "next_cursor"
        case hasMore = "has_more"
    }
}

public struct RefreshResponse: Codable, Hashable, Sendable {
    public let queued: Bool
    public let requestedAt: String

    public init(queued: Bool, requestedAt: String) {
        self.queued = queued
        self.requestedAt = requestedAt
    }

    private enum CodingKeys: String, CodingKey {
        case queued
        case requestedAt = "requested_at"
    }
}

public struct ErrorPayload: Codable, Hashable, Sendable {
    public let code: String
    public let message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

public struct ErrorEnvelope: Codable, Hashable, Sendable {
    public let error: ErrorPayload

    public init(error: ErrorPayload) {
        self.error = error
    }
}

private extension Data {
    init?(base64URLEncoded rawValue: String) {
        var base64 = rawValue
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let remainder = base64.count % 4
        if remainder != 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }

        self.init(base64Encoded: base64)
    }

    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
