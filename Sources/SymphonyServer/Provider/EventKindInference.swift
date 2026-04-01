import Foundation
import SymphonyShared

// MARK: - Event Kind Inference

enum EventKindInference {
  static func infer(from rawJSON: String, provider: ProviderName) -> NormalizedEventKind {
    guard let data = rawJSON.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return .unknown }

    switch provider {
    case .codex:
      return inferCodex(json)
    case .claudeCode:
      return inferClaudeCode(json)
    case .copilotCLI:
      return inferCopilotCLI(json)
    }
  }

  private static func inferCodex(_ json: [String: Any]) -> NormalizedEventKind {
    if json["error"] != nil {
      return .error
    }

    if let method = json["method"] as? String {
      if let kind = inferCodex(method: method, json: json) {
        return kind
      }
    }

    guard let type = json["type"] as? String else { return .unknown }
    if codexApprovalLikeIdentifier(type) {
      return .approvalRequest
    }

    switch type {
    case "message", "text": return .message
    case "tool_call": return .toolCall
    case "tool_result": return .toolResult
    case "status": return .status
    case "usage": return .usage
    case "approval_request": return .approvalRequest
    case "error": return .error
    default: return .unknown
    }
  }

  static func inferCodex(method: String, json: [String: Any]) -> NormalizedEventKind? {
    if isCodexApprovalEvent(method: method, json: json) {
      return .approvalRequest
    }

    switch method {
    case "turn/completed", "turn/failed", "turn/cancelled", "turn/interrupted", "initialized",
      "thread/start", "turn/start", "thread/started", "turn/started", "thread/status/changed":
      return .status
    case "thread/tokenUsage/updated":
      return .usage
    case "item/agentMessage/delta":
      return .message
    case "item/started", "item/completed":
      switch codexItemType(in: json) {
      case "agentMessage":
        return .message
      case "commandExecution":
        return method == "item/started" ? .toolCall : .toolResult
      default:
        return codexApprovalLikePayload(in: json) ? .approvalRequest : nil
      }
    default:
      return nil
    }
  }

  private static func codexItemType(in json: [String: Any]) -> String? {
    let params = json["params"] as? [String: Any]
    let item = params?["item"] as? [String: Any]
    return item?["type"] as? String
  }

  private static func isCodexApprovalEvent(method: String, json: [String: Any]) -> Bool {
    codexApprovalLikeIdentifier(method) || codexApprovalLikePayload(in: json)
  }

  private static func codexApprovalLikePayload(in json: [String: Any]) -> Bool {
    codexApprovalCandidateStrings(in: json).contains(where: codexApprovalLikeIdentifier)
  }

  private static func codexApprovalCandidateStrings(in json: [String: Any]) -> [String] {
    let paths = [
      ["type"],
      ["method"],
      ["params", "item", "type"],
      ["params", "item", "kind"],
      ["params", "request", "type"],
      ["params", "request", "kind"],
      ["params", "approval", "type"],
      ["params", "approval", "kind"],
      ["params", "permission", "type"],
      ["params", "permission", "kind"],
      ["params", "input", "type"],
      ["params", "input", "kind"],
      ["params", "tool", "type"],
      ["params", "tool", "kind"],
      ["params", "status", "type"],
      ["result", "item", "type"],
      ["result", "request", "type"],
      ["result", "request", "kind"],
    ]

    return paths.compactMap { stringValue(at: $0, in: json) }
  }

  private static func stringValue(at path: [String], in json: [String: Any]) -> String? {
    guard let first = path.first else { return nil }
    guard let value = json[first] else { return nil }
    if path.count == 1 {
      return value as? String
    }

    guard let nested = value as? [String: Any] else { return nil }
    return stringValue(at: Array(path.dropFirst()), in: nested)
  }

  private static func codexApprovalLikeIdentifier(_ identifier: String?) -> Bool {
    guard let identifier else { return false }
    let compact = identifier.lowercased().filter { $0.isLetter || $0.isNumber }
    guard !compact.isEmpty else { return false }

    if compact.contains("requestapproval") || compact.contains("approvalrequest") {
      return true
    }

    if compact.contains("filechange")
      && (compact.contains("approval") || compact.contains("request") || compact.contains("required"))
    {
      return true
    }

    if compact.contains("permission")
      && (compact.contains("approval") || compact.contains("request") || compact.contains("required"))
    {
      return true
    }

    if compact.contains("inputrequired") || compact.contains("userinputrequired")
      || compact.contains("requestinput")
    {
      return true
    }

    if compact.contains("unsupportedtool")
      || (compact.contains("unsupported") && compact.contains("tool"))
    {
      return true
    }

    return false
  }

  private static func inferClaudeCode(_ json: [String: Any]) -> NormalizedEventKind {
    guard let type = json["type"] as? String else { return .unknown }
    switch type {
    case "assistant", "text", "message", "result": return .message
    case "tool_use": return .toolCall
    case "tool_result": return .toolResult
    case "system", "status": return .status
    case "usage": return .usage
    case "error": return .error
    default: return .unknown
    }
  }

  private static func inferCopilotCLI(_ json: [String: Any]) -> NormalizedEventKind {
    if let method = json["method"] as? String,
      ["session/request_permission", "requestPermission"].contains(method)
    {
      return .approvalRequest
    }
    if let method = json["method"] as? String, ["session/update", "sessionUpdate"].contains(method)
    {
      return .status
    }
    if copilotPromptStopReason(from: json) != nil {
      return .status
    }
    if json["error"] != nil {
      return .error
    }

    guard let type = json["type"] as? String ?? json["event"] as? String else { return .unknown }
    switch type {
    case "message", "update", "text": return .message
    case "tool_call": return .toolCall
    case "tool_result": return .toolResult
    case "status": return .status
    case "usage": return .usage
    case "error": return .error
    default: return .unknown
    }
  }
}

struct ProviderEventDescriptor {
  let eventType: String
  let normalizedKind: NormalizedEventKind
  let isTerminal: Bool
}

enum ProviderEventInspection {
  static func describe(from rawJSON: String, provider: ProviderName) -> ProviderEventDescriptor {
    guard let data = rawJSON.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return ProviderEventDescriptor(
        eventType: "unknown",
        normalizedKind: .unknown,
        isTerminal: false
      )
    }

    let eventType = eventType(from: json, provider: provider)
    let normalizedKind = EventKindInference.infer(from: rawJSON, provider: provider)
    let isTerminal = isTerminalEvent(json, provider: provider)
    return ProviderEventDescriptor(
      eventType: eventType,
      normalizedKind: normalizedKind,
      isTerminal: isTerminal
    )
  }

  static func eventType(from json: [String: Any], provider: ProviderName) -> String {
    switch provider {
    case .codex:
      if json["error"] != nil {
        return "error"
      }
      return json["method"] as? String ?? json["type"] as? String ?? "unknown"
    case .claudeCode:
      return json["type"] as? String ?? "unknown"
    case .copilotCLI:
      if json["error"] != nil {
        return "error"
      }
      if json["result"] != nil {
        return "result"
      }
      return json["method"] as? String ?? json["type"] as? String ?? json["event"] as? String
        ?? "unknown"
    }
  }

  private static func isTerminalEvent(_ json: [String: Any], provider: ProviderName) -> Bool {
    switch provider {
    case .codex:
      let method = json["method"] as? String
      return ["turn/completed", "turn/failed", "turn/cancelled", "turn/interrupted"].contains(method)
    case .claudeCode:
      let type = json["type"] as? String
      return ["result", "error"].contains(type)
    case .copilotCLI:
      return copilotPromptStopReason(from: json) != nil || json["error"] != nil
    }
  }
}
