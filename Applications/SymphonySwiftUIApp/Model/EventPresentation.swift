import Foundation
import SymphonyShared

public struct SymphonyEventPresentation: Equatable {
  public enum RowStyle: Equatable {
    case message
    case tool
    case compact
    case callout
    case supplemental
  }

  public let rowStyle: RowStyle
  public let title: String
  public let detail: String
  public let metadata: String
  public let showsRawJSON: Bool

  init(
    rowStyle: RowStyle,
    title: String,
    detail: String,
    metadata: String,
    showsRawJSON: Bool
  ) {
    self.rowStyle = rowStyle
    self.title = title
    self.detail = detail
    self.metadata = metadata
    self.showsRawJSON = showsRawJSON
  }

  public init(event: AgentRawEvent) {
    self.metadata =
      "\(Self.displayMetadataToken(event.provider)) • #\(event.sequence.rawValue) • \(Self.displayMetadataToken(event.providerEventType))"

    switch event.normalizedKind {
    case .message:
      self.rowStyle = .message
      self.title = "Message"
      self.detail = Self.extractDisplayText(from: event) ?? event.providerEventType
      self.showsRawJSON = false
    case .toolCall:
      self.rowStyle = .tool
      self.title = "Tool Call"
      self.detail = Self.extractDisplayText(from: event) ?? event.providerEventType
      self.showsRawJSON = false
    case .toolResult:
      self.rowStyle = .tool
      self.title = "Tool Result"
      self.detail = Self.extractDisplayText(from: event) ?? event.providerEventType
      self.showsRawJSON = false
    case .status:
      self.rowStyle = .compact
      self.title = "Status"
      self.detail = Self.extractDisplayText(from: event) ?? event.providerEventType
      self.showsRawJSON = false
    case .usage:
      self.rowStyle = .compact
      self.title = "Usage"
      self.detail = Self.extractDisplayText(from: event) ?? event.rawJSON
      self.showsRawJSON = false
    case .approvalRequest:
      self.rowStyle = .callout
      self.title = "Approval Request"
      self.detail = Self.extractDisplayText(from: event) ?? event.rawJSON
      self.showsRawJSON = false
    case .error:
      self.rowStyle = .callout
      self.title = "Error"
      self.detail = Self.extractDisplayText(from: event) ?? event.rawJSON
      self.showsRawJSON = false
    case .unknown:
      self.rowStyle = .supplemental
      self.title = "Unknown Event"
      if let detail = Self.extractDisplayText(from: event) {
        self.detail = detail
      } else {
        self.detail = event.rawJSON
      }
      self.showsRawJSON = true
    }
  }

  static func isEmptyAgentMessageShell(event: AgentRawEvent) -> Bool {
    guard event.providerEventType == "item/started",
      let data = event.rawJSON.data(using: .utf8),
      let object = try? JSONSerialization.jsonObject(with: data),
      let root = object as? [String: Any],
      let params = root["params"] as? [String: Any],
      let item = params["item"] as? [String: Any],
      (item["type"] as? String) == "agentMessage"
    else {
      return false
    }

    if let text = normalizedString(item["text"]), !text.isEmpty {
      return false
    }

    return true
  }

  private static func extractDisplayText(from event: AgentRawEvent) -> String? {
    extractText(from: event.rawJSON)
  }

  private static func extractText(from rawJSON: String) -> String? {
    guard let data = rawJSON.data(using: .utf8),
      let object = try? JSONSerialization.jsonObject(with: data)
    else {
      return nil
    }
    return extractText(from: object)
  }

  private static func extractText(from object: Any) -> String? {
    if let text = normalizedString(object), !text.isEmpty {
      return text
    }
    if let dictionary = object as? [String: Any] {
      if let method = dictionary["method"] as? String,
        let params = dictionary["params"] as? [String: Any],
        let extracted = extractText(method: method, params: params)
      {
        return extracted
      }

      for key in preferredDisplayKeys {
        if let value = dictionary[key], let extracted = extractText(from: value) {
          return extracted
        }
      }

      for (key, value) in dictionary where !ignoredMetadataKeys.contains(key) {
        if let extracted = extractText(from: value) {
          return extracted
        }
      }
    }
    if let array = object as? [Any] {
      let extractedParts = array.compactMap(extractText(from:)).filter { !$0.isEmpty }
      if !extractedParts.isEmpty {
        return extractedParts.joined(separator: "\n")
      }
    }
    if let number = object as? NSNumber {
      return number.stringValue
    }
    return nil
  }

  static func extractText(method: String, params: [String: Any]) -> String? {
    switch method {
    case "item/agentMessage/delta":
      return extractText(from: params["delta"] as Any)
    case "item/commandExecution/requestApproval":
      return extractText(from: params["reason"] as Any)
    case "thread/status/changed":
      return extractText(from: params["status"] as Any)
    case "thread/started":
      if let thread = extractText(from: params["thread"] as Any) {
        return thread
      }
      return extractText(from: params["status"] as Any)
    case "turn/started":
      if let turn = extractText(from: params["turn"] as Any) {
        return turn
      }
      return extractText(from: params["status"] as Any)
    case "item/started", "item/completed":
      if let item = params["item"] as? [String: Any] {
        if let extracted = extractText(fromItem: item) {
          return extracted
        }
      }
      if let message = params["message"] {
        return extractText(from: message)
      }
      return nil
    default:
      return extractText(from: params as Any)
    }
  }

  static func extractText(fromItem item: [String: Any]) -> String? {
    let itemType = normalizedString(item["type"])

    switch itemType {
    case "agentMessage":
      if let text = extractText(from: item["text"] as Any) {
        return text
      }
      if let content = extractText(from: item["content"] as Any) {
        return content
      }
      return extractText(from: item["summary"] as Any)
    case "commandExecution":
      if let aggregatedOutput = normalizedString(item["aggregatedOutput"]),
        aggregatedOutput.count <= 240
      {
        return aggregatedOutput
      }
      if let command = extractText(from: item["command"] as Any) {
        return command
      }
      if let arguments = extractText(from: item["arguments"] as Any) {
        return arguments
      }
      if let result = extractText(from: item["result"] as Any) {
        return result
      }
      return extractText(from: item["status"] as Any)
    case "reasoning":
      if let summary = extractText(from: item["summary"] as Any) {
        return summary
      }
      if let content = extractText(from: item["content"] as Any) {
        return content
      }
      return humanizedItemType(itemType)
    default:
      for key in preferredDisplayKeys {
        if let extracted = extractText(from: item[key] as Any) {
          return extracted
        }
      }
      return humanizedItemType(itemType)
    }
  }

  static func humanizedItemType(_ itemType: String?) -> String? {
    guard let itemType, !itemType.isEmpty else {
      return nil
    }

    switch itemType {
    case "agentMessage":
      return "Message"
    case "commandExecution":
      return "Command execution"
    case "reasoning":
      return "Reasoning"
    default:
      return itemType
    }
  }

  private static func normalizedString(_ value: Any?) -> String? {
    guard let text = value as? String else {
      return nil
    }

    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private static let preferredDisplayKeys = [
    "message",
    "text",
    "delta",
    "content",
    "output",
    "result",
    "arguments",
    "reason",
    "command",
    "name",
    "status",
    "type",
  ]

  private static let ignoredMetadataKeys: Set<String> = [
    "id",
    "itemId",
    "threadId",
    "turnId",
    "sessionId",
    "providerSessionID",
    "providerRunID",
    "providerThreadID",
    "providerTurnID",
    "method",
    "phase",
    "cwd",
    "path",
    "processId",
    "memoryCitation",
  ]

  static func extractText(from object: Any?) -> String? {
    guard let object else {
      return nil
    }
    return extractText(from: object)
  }

  private static func displayMetadataToken(_ value: String) -> String {
    value.replacingOccurrences(of: "_", with: " ")
  }
}
