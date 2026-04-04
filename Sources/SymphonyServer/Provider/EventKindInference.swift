import Foundation
import SymphonyShared

// MARK: - Event Kind Inference

enum EventKindInference {
  static func infer(from rawJSON: String, provider: ProviderName) -> NormalizedEventKind {
    guard let message = ProviderJSONMessage.parse(rawJSON) else { return .unknown }

    switch provider {
    case .codex:
      return inferCodex(message)
    case .claudeCode:
      return inferClaudeCode(message)
    case .copilotCLI:
      return inferCopilotCLI(message)
    }
  }

  private static func inferCodex(_ msg: ProviderJSONMessage) -> NormalizedEventKind {
    if msg.error != nil {
      return .error
    }

    if let method = msg.method {
      if let kind = inferCodex(method: method, msg: msg) {
        return kind
      }
    }

    guard let type = msg.type else { return .unknown }
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

  static func inferCodex(method: String, msg: ProviderJSONMessage) -> NormalizedEventKind? {
    if isCodexApprovalEvent(method: method, msg: msg) {
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
      switch codexItemType(in: msg) {
      case "agentMessage":
        return .message
      case "commandExecution":
        return method == "item/started" ? .toolCall : .toolResult
      default:
        return codexApprovalLikePayload(in: msg) ? .approvalRequest : nil
      }
    default:
      return nil
    }
  }

  private static func codexItemType(in msg: ProviderJSONMessage) -> String? {
    msg.paramsString("item", "type")
  }

  private static func isCodexApprovalEvent(method: String, msg: ProviderJSONMessage) -> Bool {
    codexApprovalLikeIdentifier(method) || codexApprovalLikePayload(in: msg)
  }

  private static func codexApprovalLikePayload(in msg: ProviderJSONMessage) -> Bool {
    codexApprovalCandidateStrings(in: msg).contains(where: codexApprovalLikeIdentifier)
  }

  private static func codexApprovalCandidateStrings(in msg: ProviderJSONMessage) -> [String] {
    let paths: [[String]] = [
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

    return paths.compactMap { stringValue(at: $0, in: msg) }
  }

  private static func stringValue(at path: [String], in msg: ProviderJSONMessage) -> String? {
    guard let first = path.first else { return nil }

    // Top-level field access
    let topValue: JSONValue?
    switch first {
    case "type": return msg.type
    case "method": return msg.method
    case "params":
      guard let params = msg.params else { return nil }
      return nestedStringValue(at: Array(path.dropFirst()), in: params)
    case "result":
      guard let result = msg.result else { return nil }
      return nestedStringValue(at: Array(path.dropFirst()), in: result)
    default:
      topValue = nil
    }
    return topValue?.stringValue
  }

  private static func nestedStringValue(at path: [String], in obj: [String: JSONValue]) -> String? {
    guard let first = path.first, let value = obj[first] else { return nil }
    if path.count == 1 {
      return value.stringValue
    }
    guard let nested = value.objectValue else { return nil }
    return nestedStringValue(at: Array(path.dropFirst()), in: nested)
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

  private static func inferClaudeCode(_ msg: ProviderJSONMessage) -> NormalizedEventKind {
    guard let type = msg.type else { return .unknown }
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

  private static func inferCopilotCLI(_ msg: ProviderJSONMessage) -> NormalizedEventKind {
    if let method = msg.method,
      ["session/request_permission", "requestPermission"].contains(method)
    {
      return .approvalRequest
    }
    if let method = msg.method, ["session/update", "sessionUpdate"].contains(method)
    {
      return .status
    }
    if msg.resultString("stopReason") != nil {
      return .status
    }
    if msg.error != nil {
      return .error
    }

    guard let type = msg.type ?? msg.event else { return .unknown }
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
    guard let msg = ProviderJSONMessage.parse(rawJSON) else {
      return ProviderEventDescriptor(
        eventType: "unknown",
        normalizedKind: .unknown,
        isTerminal: false
      )
    }

    let eventType = eventType(from: msg, provider: provider)
    let normalizedKind = EventKindInference.infer(from: rawJSON, provider: provider)
    let isTerminal = isTerminalEvent(msg, provider: provider)
    return ProviderEventDescriptor(
      eventType: eventType,
      normalizedKind: normalizedKind,
      isTerminal: isTerminal
    )
  }

  static func eventType(from msg: ProviderJSONMessage, provider: ProviderName) -> String {
    switch provider {
    case .codex:
      if msg.error != nil {
        return "error"
      }
      return msg.method ?? msg.type ?? "unknown"
    case .claudeCode:
      return msg.type ?? "unknown"
    case .copilotCLI:
      if msg.error != nil {
        return "error"
      }
      if msg.result != nil {
        return "result"
      }
      return msg.method ?? msg.type ?? msg.event ?? "unknown"
    }
  }

  private static func isTerminalEvent(_ msg: ProviderJSONMessage, provider: ProviderName) -> Bool {
    switch provider {
    case .codex:
      return ["turn/completed", "turn/failed", "turn/cancelled", "turn/interrupted"].contains(msg.method)
    case .claudeCode:
      return ["result", "error"].contains(msg.type)
    case .copilotCLI:
      return msg.resultString("stopReason") != nil || msg.error != nil
    }
  }
}
