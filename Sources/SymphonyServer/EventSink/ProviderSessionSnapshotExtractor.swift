import Foundation
import SymphonyServerCore
import SymphonyShared

struct ProviderSessionSnapshot: Sendable {
  var providerSessionID: String?
  var providerThreadID: String?
  var providerTurnID: String?
  var providerRunID: String?
  var tokenUsage: TokenUsage
  var latestRateLimitPayload: String?
  var lastAgentMessage: String?
  var latestSequence: EventSequence?

  init(
    providerSessionID: String? = nil,
    providerThreadID: String? = nil,
    providerTurnID: String? = nil,
    providerRunID: String? = nil,
    tokenUsage: TokenUsage = .empty,
    latestRateLimitPayload: String? = nil,
    lastAgentMessage: String? = nil,
    latestSequence: EventSequence? = nil
  ) {
    self.providerSessionID = providerSessionID
    self.providerThreadID = providerThreadID
    self.providerTurnID = providerTurnID
    self.providerRunID = providerRunID
    self.tokenUsage = tokenUsage
    self.latestRateLimitPayload = latestRateLimitPayload
    self.lastAgentMessage = lastAgentMessage
    self.latestSequence = latestSequence
  }

  func merging(_ update: ProviderSessionSnapshotUpdate) -> ProviderSessionSnapshot {
    ProviderSessionSnapshot(
      providerSessionID: update.providerSessionID ?? providerSessionID,
      providerThreadID: update.providerThreadID ?? providerThreadID,
      providerTurnID: update.providerTurnID ?? providerTurnID,
      providerRunID: update.providerRunID ?? providerRunID,
      tokenUsage: update.tokenUsage ?? tokenUsage,
      latestRateLimitPayload: update.latestRateLimitPayload ?? latestRateLimitPayload,
      lastAgentMessage: update.lastAgentMessage ?? lastAgentMessage,
      latestSequence: update.latestSequence ?? latestSequence
    )
  }
}

struct ProviderSessionSnapshotUpdate: Sendable {
  var providerSessionID: String?
  var providerThreadID: String?
  var providerTurnID: String?
  var providerRunID: String?
  var tokenUsage: TokenUsage?
  var latestRateLimitPayload: String?
  var lastAgentMessage: String?
  var latestSequence: EventSequence?
}

enum ProviderSessionSnapshotExtractor {
  static func update(from event: AgentRawEvent, storedSequence: EventSequence)
    -> ProviderSessionSnapshotUpdate
  {
    let rawJSONValue = parseJSONValue(from: event.rawJSON)
    return ProviderSessionSnapshotUpdate(
      providerSessionID: rawJSONValue.flatMap {
        firstString(for: ["provider_session_id", "session_id", "sessionId"], in: $0)
      },
      providerThreadID: rawJSONValue.flatMap {
        nestedObjectID(for: "thread", in: $0)
          ?? firstString(for: ["provider_thread_id", "thread_id", "threadId"], in: $0)
      },
      providerTurnID: rawJSONValue.flatMap {
        nestedObjectID(for: "turn", in: $0)
          ?? firstString(for: ["provider_turn_id", "turn_id", "turnId"], in: $0)
      },
      providerRunID: rawJSONValue.flatMap {
        firstString(for: ["provider_run_id", "run_id", "runId"], in: $0)
      },
      tokenUsage: rawJSONValue.flatMap(tokenUsage(from:)),
      latestRateLimitPayload: rawJSONValue.flatMap(rateLimitPayload(from:)),
      lastAgentMessage: lastAgentMessage(from: event, rawJSONValue: rawJSONValue),
      latestSequence: storedSequence
    )
  }

  private static func parseJSONValue(from rawJSON: String) -> JSONValue? {
    guard let data = rawJSON.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(JSONValue.self, from: data)
  }

  static func tokenUsage(from value: JSONValue) -> TokenUsage? {
    if let usageValue = firstValue(
      for: ["usage", "token_usage", "tokenUsage", "tokens", "tokenUsageTotals"],
      in: value
    ),
      let usage = tokenUsageObject(from: usageValue)
    {
      return usage
    }

    return tokenUsageObject(from: value)
  }

  private static func tokenUsageObject(from value: JSONValue) -> TokenUsage? {
    guard let json = value.objectValue else { return nil }
    let inputTokens = firstInt(for: ["input_tokens", "inputTokens"], in: json)
    let outputTokens = firstInt(for: ["output_tokens", "outputTokens"], in: json)
    let totalTokens = firstInt(for: ["total_tokens", "totalTokens"], in: json)
    guard inputTokens != nil || outputTokens != nil || totalTokens != nil else { return nil }
    return try? TokenUsage(
      inputTokens: inputTokens,
      outputTokens: outputTokens,
      totalTokens: totalTokens
    )
  }

  private static func rateLimitPayload(from value: JSONValue) -> String? {
    guard
      let rateLimitValue = firstValue(
        for: ["rate_limit", "rate_limits", "rateLimit", "rateLimits"],
        in: value
      )
    else { return nil }
    return jsonString(from: rateLimitValue)
  }

  private static func lastAgentMessage(from event: AgentRawEvent, rawJSONValue: JSONValue?)
    -> String?
  {
    guard event.normalizedKind == .message, let rawJSONValue else { return nil }
    return messageText(from: rawJSONValue)
  }

  static func messageText(from value: JSONValue) -> String? {
    if case .string(let string) = value {
      let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? nil : trimmed
    }

    if case .array(let array) = value {
      for item in array {
        if let text = messageText(from: item) {
          return text
        }
      }
      return nil
    }

    guard let json = value.objectValue else { return nil }

    for key in ["message", "content", "text"] {
      if let nested = json[key], let text = messageText(from: nested) {
        return text
      }
    }

    for key in ["payload", "data", "delta"] {
      if let nested = json[key], let text = messageText(from: nested) {
        return text
      }
    }

    return nil
  }

  private static func firstString(for keys: [String], in value: JSONValue) -> String? {
    if case .array(let array) = value {
      for item in array {
        if let string = firstString(for: keys, in: item) {
          return string
        }
      }
      return nil
    }

    guard let json = value.objectValue else { return nil }
    guard !keys.isEmpty else { return nil }
    for key in keys {
      if let nested = json[key] {
        if let string = stringValue(from: nested) {
          return string
        }
        if let string = firstString(for: keys, in: nested) {
          return string
        }
      }
    }

    for nested in json.values {
      if let string = firstString(for: keys, in: nested) {
        return string
      }
    }

    return nil
  }

  private static func firstValue(for keys: [String], in value: JSONValue) -> JSONValue? {
    if case .array(let array) = value {
      for item in array {
        if let found = firstValue(for: keys, in: item) {
          return found
        }
      }
      return nil
    }

    guard let json = value.objectValue else { return nil }
    for key in keys {
      if let found = json[key] {
        return found
      }
    }

    for nested in json.values {
      if let nestedValue = firstValue(for: keys, in: nested) {
        return nestedValue
      }
    }

    return nil
  }

  private static func nestedObjectID(for objectKey: String, in value: JSONValue) -> String? {
    if case .array(let array) = value {
      for item in array {
        if let identifier = nestedObjectID(for: objectKey, in: item) {
          return identifier
        }
      }
      return nil
    }

    guard let json = value.objectValue else { return nil }
    if let nested = json[objectKey]?.objectValue,
      let idValue = nested["id"],
      let identifier = stringValue(from: idValue)
    {
      return identifier
    }

    for nested in json.values {
      if let identifier = nestedObjectID(for: objectKey, in: nested) {
        return identifier
      }
    }

    return nil
  }

  private static func firstInt(for keys: [String], in json: [String: JSONValue]) -> Int? {
    for key in keys {
      if let value = json[key], let intVal = intValue(from: value) {
        return intVal
      }
    }
    return nil
  }

  private static func intValue(from value: JSONValue) -> Int? {
    switch value {
    case .int(let intVal):
      return intVal
    case .double(let doubleVal):
      return Int(doubleVal)
    case .string(let string):
      return Int(string)
    default:
      return nil
    }
  }

  private static func stringValue(from value: JSONValue) -> String? {
    switch value {
    case .string(let string):
      let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? nil : trimmed
    case .int(let intVal):
      return String(intVal)
    case .double(let doubleVal):
      return String(doubleVal)
    default:
      return nil
    }
  }

  private static func jsonString(from value: JSONValue) -> String? {
    if case .string(let string) = value {
      return string
    }
    guard let data = try? JSONEncoder().encode(value),
      let string = String(data: data, encoding: .utf8)
    else { return nil }
    return string
  }
}
