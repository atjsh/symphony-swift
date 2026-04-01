import Foundation
import SymphonyServerCore

// MARK: - Codex Helper Functions

func codexStartupThreadID(from jsonObject: [String: Any]?) -> String? {
  guard let jsonObject else { return nil }

  if let method = jsonObject["method"] as? String,
    method == "thread/started",
    let params = jsonObject["params"] as? [String: Any],
    let thread = params["thread"] as? [String: Any],
    let threadID = thread["id"] as? String,
    !threadID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  {
    return threadID
  }

  if let result = jsonObject["result"] as? [String: Any],
    let thread = result["thread"] as? [String: Any],
    let threadID = thread["id"] as? String,
    !threadID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  {
    return threadID
  }

  if let params = jsonObject["params"] as? [String: Any],
    let threadID = params["thread_id"] as? String ?? params["threadId"] as? String,
    !threadID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  {
    return threadID
  }

  return nil
}

func codexTurnID(from jsonObject: [String: Any]?) -> String? {
  guard let jsonObject else { return nil }

  if let params = jsonObject["params"] as? [String: Any] {
    if let turn = params["turn"] as? [String: Any],
      let turnID = turn["id"] as? String,
      !turnID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      return turnID
    }

    if let turnID = params["turn_id"] as? String ?? params["turnId"] as? String,
      !turnID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      return turnID
    }
  }

  if let result = jsonObject["result"] as? [String: Any],
    let turn = result["turn"] as? [String: Any],
    let turnID = turn["id"] as? String,
    !turnID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  {
    return turnID
  }

  return nil
}

func shouldSuppressSuccessfulCodexResponse(_ jsonObject: [String: Any]?) -> Bool {
  guard let jsonObject else { return false }
  guard jsonObject["error"] == nil else { return false }
  guard jsonObject["id"] != nil, jsonObject["result"] != nil else { return false }
  return jsonObject["method"] == nil && jsonObject["type"] == nil
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
  guard
    let data = rawJSON.data(using: .utf8),
    let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
  else { return nil }

  guard let method = json["method"] as? String else { return nil }
  switch method {
  case "turn/completed":
    switch firstCodexOutcomeString(in: json)?.lowercased() {
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

private func firstCodexOutcomeString(in value: Any?) -> String? {
  if let string = value as? String {
    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  if let array = value as? [Any] {
    for entry in array {
      if let found = firstCodexOutcomeString(in: entry) {
        return found
      }
    }
    return nil
  }

  guard let json = value as? [String: Any] else { return nil }
  for key in ["status", "result", "outcome", "terminalStatus", "state", "type"] {
    if let found = firstCodexOutcomeString(in: json[key]) {
      return found
    }
  }
  for key in ["params", "turn", "terminal", "payload"] {
    if let found = firstCodexOutcomeString(in: json[key]) {
      return found
    }
  }
  return nil
}
