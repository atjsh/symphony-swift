import Foundation
import SymphonyServerCore
import SymphonyShared

// MARK: - Codex Helper Functions

func codexStartupThreadID(from msg: ProviderJSONMessage?) -> String? {
  guard let msg else { return nil }

  if msg.method == "thread/started" {
    if let threadID = msg.paramsString("thread", "id"),
      !threadID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      return threadID
    }
  }

  if let threadID = msg.resultString("thread", "id"),
    !threadID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  {
    return threadID
  }

  if let threadID = msg.paramsString("thread_id") ?? msg.paramsString("threadId"),
    !threadID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  {
    return threadID
  }

  return nil
}

func codexTurnID(from msg: ProviderJSONMessage?) -> String? {
  guard let msg else { return nil }

  if let params = msg.params {
    if let turnID = params["turn"]?.objectValue?["id"]?.stringValue,
      !turnID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      return turnID
    }

    let turnID = params["turn_id"]?.stringValue ?? params["turnId"]?.stringValue
    if let turnID, !turnID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return turnID
    }
  }

  if let turnID = msg.resultString("turn", "id"),
    !turnID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  {
    return turnID
  }

  return nil
}

func shouldSuppressSuccessfulCodexResponse(_ msg: ProviderJSONMessage?) -> Bool {
  guard let msg else { return false }
  guard msg.error == nil else { return false }
  guard msg.id != nil, msg.result != nil else { return false }
  return msg.method == nil && msg.type == nil
}

func makeCodexTurnStartMessage(
  id: Int,
  threadID: String,
  issueIdentifier: String,
  issueTitle: String,
  workspacePath: String,
  input: String,
  config: CodexProviderConfig
) -> [String: Any] {
  var params: [String: Any] = [
    "threadId": threadID,
    "cwd": workspacePath,
    "title": "\(issueIdentifier): \(issueTitle)",
    "input": [["type": "text", "text": input]],
  ]
  if let approvalPolicy = config.turnApprovalPolicy {
    params["approvalPolicy"] = approvalPolicy
  }
  if let sandboxPolicy = config.turnSandboxPolicy {
    params["sandboxPolicy"] = sandboxPolicy.foundationValue
  }

  return [
    "id": id,
    "method": "turn/start",
    "params": params,
  ]
}

func makeCodexInterruptMessage(
  id: Int,
  threadID: String,
  turnID: String
) -> [String: Any] {
  [
    "id": id,
    "method": "turn/interrupt",
    "params": [
      "threadId": threadID,
      "turnId": turnID,
    ],
  ]
}

func codexTurnOutcome(from rawJSON: String) -> CodexTerminalOutcome? {
  guard let msg = ProviderJSONMessage.parse(rawJSON) else { return nil }

  guard let method = msg.method else { return nil }
  switch method {
  case "turn/completed":
    switch firstCodexOutcomeString(in: msg)?.lowercased() {
    case "failed", "error":
      return .failed
    case "cancelled", "canceled", "interrupted":
      return .interrupted
    default:
      return .completed
    }
  case "turn/failed":
    return .failed
  case "turn/cancelled":
    return .interrupted
  case "turn/interrupted":
    return .interrupted
  default:
    return nil
  }
}

/// Recursively search for a terminal outcome string in a JSONValue tree.
private func firstCodexOutcomeString(in value: JSONValue?) -> String? {
  guard let value else { return nil }

  switch value {
  case .string(let string):
    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed

  case .array(let array):
    for entry in array {
      if let found = firstCodexOutcomeString(in: entry) {
        return found
      }
    }
    return nil

  case .object(let obj):
    for key in ["status", "result", "outcome", "terminalStatus", "state", "type"] {
      if let found = firstCodexOutcomeString(in: obj[key]) {
        return found
      }
    }
    for key in ["params", "turn", "terminal", "payload"] {
      if let found = firstCodexOutcomeString(in: obj[key]) {
        return found
      }
    }
    return nil

  default:
    return nil
  }
}

/// Recursively search from a ProviderJSONMessage (top-level entry point).
private func firstCodexOutcomeString(in msg: ProviderJSONMessage) -> String? {
  let searchKeys = ["status", "result", "outcome", "terminalStatus", "state", "type",
                     "params", "turn", "terminal", "payload"]
  if let result = msg.result {
    for key in searchKeys {
      if let found = firstCodexOutcomeString(in: result[key]) {
        return found
      }
    }
  }
  if let params = msg.params {
    for key in searchKeys {
      if let found = firstCodexOutcomeString(in: params[key]) {
        return found
      }
    }
  }
  return nil
}
