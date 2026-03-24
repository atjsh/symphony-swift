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

    public init(threadID: String, turnID: String) {
        self.rawValue = "\(threadID)-\(turnID)"
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
        let rawValue = try container.decode(String.self)
        self = try IssueIdentifier(validating: rawValue)
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
        let scheme = try container.decode(String.self, forKey: .scheme)
        let host = try container.decode(String.self, forKey: .host)
        let port = try container.decode(Int.self, forKey: .port)
        self = try ServerEndpoint(scheme: scheme, host: host, port: port)
    }
}

public struct TokenUsage: Codable, Hashable, Sendable {
    public let inputTokens: Int
    public let outputTokens: Int
    public let totalTokens: Int

    public init(inputTokens: Int, outputTokens: Int) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = inputTokens + outputTokens
    }

    public init(inputTokens: Int, outputTokens: Int, totalTokens: Int) throws {
        let expectedTotal = inputTokens + outputTokens
        guard expectedTotal == totalTokens else {
            throw SymphonySharedValidationError.invalidTokenUsage(expectedTotal: expectedTotal, actualTotal: totalTokens)
        }

        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let inputTokens = try container.decode(Int.self, forKey: .inputTokens)
        let outputTokens = try container.decode(Int.self, forKey: .outputTokens)
        if let totalTokens = try container.decodeIfPresent(Int.self, forKey: .totalTokens) {
            self = try TokenUsage(inputTokens: inputTokens, outputTokens: outputTokens, totalTokens: totalTokens)
        } else {
            self = TokenUsage(inputTokens: inputTokens, outputTokens: outputTokens)
        }
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
        if let labels = try container.decodeIfPresent([String].self, forKey: .labels) {
            self.labels = labels.map { $0.lowercased() }
        } else {
            self.labels = []
        }
        if let blockedBy = try container.decodeIfPresent([BlockerReference].self, forKey: .blockedBy) {
            self.blockedBy = blockedBy
        } else {
            self.blockedBy = []
        }
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
    public let currentRunID: RunID?
    public let currentSessionID: SessionID?

    public init(
        issueID: IssueID,
        identifier: IssueIdentifier,
        title: String,
        state: String,
        issueState: String,
        priority: Int?,
        currentRunID: RunID?,
        currentSessionID: SessionID?
    ) {
        self.issueID = issueID
        self.identifier = identifier
        self.title = title
        self.state = state
        self.issueState = issueState
        self.priority = priority
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
    public let recentSessions: [CodexSession]

    public init(
        issue: Issue,
        latestRun: RunSummary?,
        workspacePath: String?,
        recentSessions: [CodexSession]
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
    public let startedAt: String
    public let endedAt: String?
    public let workspacePath: String
    public let sessionID: SessionID?
    public let lastError: String?
    public let issue: Issue
    public let turnCount: Int
    public let lastCodexEvent: String?
    public let lastCodexMessage: String?
    public let tokens: TokenUsage
    public let logs: RunLogStats

    public init(
        runID: RunID,
        issueID: IssueID,
        issueIdentifier: IssueIdentifier,
        attempt: Int,
        status: String,
        startedAt: String,
        endedAt: String?,
        workspacePath: String,
        sessionID: SessionID?,
        lastError: String?,
        issue: Issue,
        turnCount: Int,
        lastCodexEvent: String?,
        lastCodexMessage: String?,
        tokens: TokenUsage,
        logs: RunLogStats
    ) {
        self.runID = runID
        self.issueID = issueID
        self.issueIdentifier = issueIdentifier
        self.attempt = attempt
        self.status = status
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.workspacePath = workspacePath
        self.sessionID = sessionID
        self.lastError = lastError
        self.issue = issue
        self.turnCount = turnCount
        self.lastCodexEvent = lastCodexEvent
        self.lastCodexMessage = lastCodexMessage
        self.tokens = tokens
        self.logs = logs
    }

    private enum CodingKeys: String, CodingKey {
        case runID = "run_id"
        case issueID = "issue_id"
        case issueIdentifier = "issue_identifier"
        case attempt
        case status
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case workspacePath = "workspace_path"
        case sessionID = "session_id"
        case lastError = "last_error"
        case issue
        case turnCount = "turn_count"
        case lastCodexEvent = "last_codex_event"
        case lastCodexMessage = "last_codex_message"
        case tokens
        case logs
    }
}

public struct CodexSession: Codable, Hashable, Sendable {
    public let sessionID: SessionID
    public let threadID: String
    public let turnID: String
    public let runID: RunID
    public let codexAppServerPID: String?
    public let status: String
    public let lastEventType: String?
    public let lastEventAt: String?
    public let turnCount: Int
    public let tokenUsage: TokenUsage

    public init(
        sessionID: SessionID,
        threadID: String,
        turnID: String,
        runID: RunID,
        codexAppServerPID: String?,
        status: String,
        lastEventType: String?,
        lastEventAt: String?,
        turnCount: Int,
        tokenUsage: TokenUsage
    ) {
        self.sessionID = sessionID
        self.threadID = threadID
        self.turnID = turnID
        self.runID = runID
        self.codexAppServerPID = codexAppServerPID
        self.status = status
        self.lastEventType = lastEventType
        self.lastEventAt = lastEventAt
        self.turnCount = turnCount
        self.tokenUsage = tokenUsage
    }

    private enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case threadID = "thread_id"
        case turnID = "turn_id"
        case runID = "run_id"
        case codexAppServerPID = "codex_app_server_pid"
        case status
        case lastEventType = "last_event_type"
        case lastEventAt = "last_event_at"
        case turnCount = "turn_count"
        case tokenUsage = "token_usage"
    }
}

public struct CodexRolloutEvent: Codable, Hashable, Sendable {
    public let sessionID: SessionID
    public let sequence: EventSequence
    public let timestamp: String
    public let rawJSON: String
    public let topLevelType: String
    public let payloadType: String?

    public init(
        sessionID: SessionID,
        sequence: EventSequence,
        timestamp: String,
        rawJSON: String,
        topLevelType: String,
        payloadType: String?
    ) {
        self.sessionID = sessionID
        self.sequence = sequence
        self.timestamp = timestamp
        self.rawJSON = rawJSON
        self.topLevelType = topLevelType
        self.payloadType = payloadType
    }

    private enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case sequence
        case timestamp
        case rawJSON = "raw_json"
        case topLevelType = "top_level_type"
        case payloadType = "payload_type"
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

private extension Data {
    init?(base64URLEncoded rawValue: String) {
        var base64 = rawValue.replacingOccurrences(of: "-", with: "+")
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
