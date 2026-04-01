import Foundation

public struct TokenUsage: Codable, Hashable, Sendable {
  public let inputTokens: Int?
  public let outputTokens: Int?
  public let totalTokens: Int?

  public init(inputTokens: Int? = nil, outputTokens: Int? = nil, totalTokens: Int? = nil) throws {
    if let inputTokens, let outputTokens, let totalTokens {
      let expectedTotal = inputTokens + outputTokens
      guard expectedTotal == totalTokens else {
        throw SymphonySharedValidationError.invalidTokenUsage(
          expectedTotal: expectedTotal, actualTotal: totalTokens)
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
