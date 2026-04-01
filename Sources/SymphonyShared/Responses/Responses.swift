import Foundation

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
