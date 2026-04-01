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
    tokenUsage: TokenUsage = try! TokenUsage(),
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
    let rawJSONObject = parseJSONObject(from: event.rawJSON)
    return ProviderSessionSnapshotUpdate(
      providerSessionID: rawJSONObject.flatMap {
        firstString(for: ["provider_session_id", "session_id", "sessionId"], in: $0)
      },
      providerThreadID: rawJSONObject.flatMap {
        nestedObjectID(for: "thread", in: $0)
          ?? firstString(for: ["provider_thread_id", "thread_id", "threadId"], in: $0)
      },
      providerTurnID: rawJSONObject.flatMap {
        nestedObjectID(for: "turn", in: $0)
          ?? firstString(for: ["provider_turn_id", "turn_id", "turnId"], in: $0)
      },
      providerRunID: rawJSONObject.flatMap {
        firstString(for: ["provider_run_id", "run_id", "runId"], in: $0)
      },
      tokenUsage: rawJSONObject.flatMap(tokenUsage(from:)),
      latestRateLimitPayload: rawJSONObject.flatMap(rateLimitPayload(from:)),
      lastAgentMessage: lastAgentMessage(from: event, rawJSONObject: rawJSONObject),
      latestSequence: storedSequence
    )
  }

  private static func parseJSONObject(from rawJSON: String) -> Any? {
    guard let data = rawJSON.data(using: .utf8) else { return nil }
    return try? JSONSerialization.jsonObject(with: data)
  }

  static func tokenUsage(from rawJSONObject: Any) -> TokenUsage? {
    if let usageObject = firstValue(
      for: ["usage", "token_usage", "tokenUsage", "tokens", "tokenUsageTotals"],
      in: rawJSONObject
    ),
      let usage = tokenUsageObject(from: usageObject)
    {
      return usage
    }

    return tokenUsageObject(from: rawJSONObject)
  }

  private static func tokenUsageObject(from rawJSONObject: Any) -> TokenUsage? {
    guard let json = rawJSONObject as? [String: Any] else { return nil }
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

  private static func rateLimitPayload(from rawJSONObject: Any) -> String? {
    guard
      let rateLimitObject = firstValue(
        for: ["rate_limit", "rate_limits", "rateLimit", "rateLimits"],
        in: rawJSONObject
      )
    else { return nil }
    return jsonString(from: rateLimitObject)
  }

  private static func lastAgentMessage(from event: AgentRawEvent, rawJSONObject: Any?) -> String? {
    guard event.normalizedKind == .message, let rawJSONObject else { return nil }
    return messageText(from: rawJSONObject)
  }

  static func messageText(from rawJSONObject: Any) -> String? {
    if let string = rawJSONObject as? String {
      let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? nil : trimmed
    }

    if let array = rawJSONObject as? [Any] {
      for item in array {
        if let text = messageText(from: item) {
          return text
        }
      }
      return nil
    }

    guard let json = rawJSONObject as? [String: Any] else { return nil }

    for key in ["message", "content", "text"] {
      if let value = json[key], let text = messageText(from: value) {
        return text
      }
    }

    for key in ["payload", "data", "delta"] {
      if let value = json[key], let text = messageText(from: value) {
        return text
      }
    }

    return nil
  }

  private static func firstString(for keys: [String], in rawJSONObject: Any) -> String? {
    if let array = rawJSONObject as? [Any] {
      for item in array {
        if let string = firstString(for: keys, in: item) {
          return string
        }
      }
      return nil
    }

    guard let json = rawJSONObject as? [String: Any] else { return nil }
    guard !keys.isEmpty else { return nil }
    for key in keys {
      if let value = json[key] {
        if let string = stringValue(from: value) {
          return string
        }
        if let string = firstString(for: keys, in: value) {
          return string
        }
      }
    }

    for value in json.values {
      if let string = firstString(for: keys, in: value) {
        return string
      }
    }

    return nil
  }

  private static func firstValue(for keys: [String], in rawJSONObject: Any) -> Any? {
    if let array = rawJSONObject as? [Any] {
      for item in array {
        if let value = firstValue(for: keys, in: item) {
          return value
        }
      }
      return nil
    }

    guard let json = rawJSONObject as? [String: Any] else { return nil }
    for key in keys {
      if let value = json[key] {
        return value
      }
    }

    for value in json.values {
      if let nestedValue = firstValue(for: keys, in: value) {
        return nestedValue
      }
    }

    return nil
  }

  private static func nestedObjectID(for objectKey: String, in rawJSONObject: Any) -> String? {
    if let array = rawJSONObject as? [Any] {
      for item in array {
        if let identifier = nestedObjectID(for: objectKey, in: item) {
          return identifier
        }
      }
      return nil
    }

    guard let json = rawJSONObject as? [String: Any] else { return nil }
    if let nested = json[objectKey] as? [String: Any],
      let idValue = nested["id"],
      let identifier = stringValue(from: idValue)
    {
      return identifier
    }

    for value in json.values {
      if let identifier = nestedObjectID(for: objectKey, in: value) {
        return identifier
      }
    }

    return nil
  }

  private static func firstInt(for keys: [String], in json: [String: Any]) -> Int? {
    for key in keys {
      if let value = json[key], let intValue = intValue(from: value) {
        return intValue
      }
    }
    return nil
  }

  private static func intValue(from value: Any) -> Int? {
    if let intValue = value as? Int {
      return intValue
    }
    if let number = value as? NSNumber {
      return number.intValue
    }
    if let string = value as? String {
      return Int(string)
    }
    return nil
  }

  private static func stringValue(from value: Any) -> String? {
    if let string = value as? String {
      let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? nil : trimmed
    }
    if let number = value as? NSNumber {
      return number.stringValue
    }
    return nil
  }

  private static func jsonString(from value: Any) -> String? {
    if let string = value as? String {
      return string
    }
    guard JSONSerialization.isValidJSONObject(value),
      let data = try? JSONSerialization.data(withJSONObject: value),
      let string = String(data: data, encoding: .utf8)
    else { return nil }
    return string
  }
}
