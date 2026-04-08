import Foundation
import SymphonyShared
import Testing

@testable import SymphonyServer

// MARK: - EventKindInference mutation hardening

/// Tests targeting surviving mutants in EventKindInference.swift.
/// Covers ChangeLogicalConnector, RelationalOperatorReplacement, and SwapTernary operators.

// L21: Codex error field takes precedence over method/type
@Test func codexErrorFieldTakesPrecedenceOverMethodAndType() {
  // If error != nil, must return .error regardless of method/type
  let kind = EventKindInference.infer(
    from: #"{"error":{"code":-1,"message":"oops"},"method":"turn/completed","type":"status"}"#,
    provider: .codex
  )
  #expect(kind == .error)
}

// L66: item/started with commandExecution → .toolCall (NOT .toolResult)
@Test func codexItemStartedCommandExecutionIsToolCallNotToolResult() {
  let started = EventKindInference.infer(
    from: #"{"method":"item/started","params":{"item":{"type":"commandExecution"}}}"#,
    provider: .codex
  )
  #expect(started == .toolCall)

  let completed = EventKindInference.infer(
    from: #"{"method":"item/completed","params":{"item":{"type":"commandExecution"}}}"#,
    provider: .codex
  )
  #expect(completed == .toolResult)

  // They must be different
  #expect(started != completed)
}

// L68: item/started|completed with unknown type + no approval → nil → fallback
@Test func codexItemStartedWithNonApprovalUnknownTypeReturnsNil() {
  let kind = EventKindInference.infer(
    from: #"{"method":"item/started","params":{"item":{"type":"someCustomType"}}}"#,
    provider: .codex
  )
  // Not an approval, not agentMessage, not commandExecution → default case returns nil → falls through
  #expect(kind == .unknown)
}

// L80: isCodexApprovalEvent uses || — both branches must be checked independently
@Test func codexApprovalDetectedByIdentifierAloneAndPayloadAlone() {
  // Detected by identifier (method name)
  let byMethod = EventKindInference.infer(
    from: #"{"method":"requestApproval"}"#,
    provider: .codex
  )
  #expect(byMethod == .approvalRequest)

  // Detected by payload (nested type)
  let byPayload = EventKindInference.infer(
    from: #"{"method":"item/started","params":{"item":{"type":"requestApproval"}}}"#,
    provider: .codex
  )
  #expect(byPayload == .approvalRequest)

  // NOT detected when neither identifier nor payload match
  let noMatch = EventKindInference.infer(
    from: #"{"method":"item/started","params":{"item":{"type":"normalItem"}}}"#,
    provider: .codex
  )
  #expect(noMatch != .approvalRequest)
}

// L134: codexApprovalLikeIdentifier with nil input
@Test func codexApprovalLikeIdentifierReturnsFalseForNilAndEmpty() {
  // nil identifier
  let nilKind = EventKindInference.infer(
    from: #"{"params":{}}"#,
    provider: .codex
  )
  #expect(nilKind == .unknown)

  // empty string identifier
  let emptyKind = EventKindInference.infer(
    from: #"{"type":""}"#,
    provider: .codex
  )
  #expect(emptyKind == .unknown)

  // whitespace-only that compacts to empty
  let whitespaceKind = EventKindInference.infer(
    from: #"{"type":"   "}"#,
    provider: .codex
  )
  #expect(whitespaceKind == .unknown)
}

// L143-168: ChangeLogicalConnector mutations in codexApprovalLikeIdentifier
// Each || and && must be exercised with inputs that distinguish them

@Test func approvalLikeFileChangeRequiresFileChangeANDApprovalOrRequestOrRequired() {
  // filechange + approval
  let fc1 = EventKindInference.infer(
    from: #"{"type":"file_change_approval"}"#,
    provider: .codex
  )
  #expect(fc1 == .approvalRequest)

  // filechange + request
  let fc2 = EventKindInference.infer(
    from: #"{"type":"fileChangeRequest"}"#,
    provider: .codex
  )
  #expect(fc2 == .approvalRequest)

  // filechange + required
  let fc3 = EventKindInference.infer(
    from: #"{"type":"fileChangeRequired"}"#,
    provider: .codex
  )
  #expect(fc3 == .approvalRequest)

  // filechange ALONE (no approval/request/required) → NOT approval
  let fcAlone = EventKindInference.infer(
    from: #"{"type":"fileChange"}"#,
    provider: .codex
  )
  #expect(fcAlone != .approvalRequest)
}

@Test func approvalLikePermissionRequiresPermissionANDApprovalOrRequestOrRequired() {
  // permission + approval
  let p1 = EventKindInference.infer(
    from: #"{"type":"permissionApproval"}"#,
    provider: .codex
  )
  #expect(p1 == .approvalRequest)

  // permission + request
  let p2 = EventKindInference.infer(
    from: #"{"type":"permissionRequest"}"#,
    provider: .codex
  )
  #expect(p2 == .approvalRequest)

  // permission + required
  let p3 = EventKindInference.infer(
    from: #"{"type":"permissionRequired"}"#,
    provider: .codex
  )
  #expect(p3 == .approvalRequest)

  // permission ALONE → NOT approval
  let permAlone = EventKindInference.infer(
    from: #"{"type":"permission"}"#,
    provider: .codex
  )
  #expect(permAlone != .approvalRequest)
}

@Test func approvalLikeInputRequiredOrUserInputRequiredOrRequestInput() {
  let ir = EventKindInference.infer(from: #"{"type":"inputRequired"}"#, provider: .codex)
  #expect(ir == .approvalRequest)

  let uir = EventKindInference.infer(from: #"{"type":"userInputRequired"}"#, provider: .codex)
  #expect(uir == .approvalRequest)

  let ri = EventKindInference.infer(from: #"{"type":"requestInput"}"#, provider: .codex)
  #expect(ri == .approvalRequest)
}

@Test func approvalLikeUnsupportedToolSingleAndSplitTokens() {
  // "unsupportedtool" in one token
  let ut = EventKindInference.infer(from: #"{"type":"unsupportedTool"}"#, provider: .codex)
  #expect(ut == .approvalRequest)

  // "unsupported" + "tool" split
  let split = EventKindInference.infer(
    from: #"{"type":"unsupported_tool_action"}"#,
    provider: .codex
  )
  #expect(split == .approvalRequest)

  // "unsupported" alone should NOT match
  let unsOnly = EventKindInference.infer(from: #"{"type":"unsupported"}"#, provider: .codex)
  #expect(unsOnly != .approvalRequest)
}

// L200-203: CopilotCLI stopReason check
@Test func copilotCLIStopReasonIsStatusNotUnknown() {
  let kind = EventKindInference.infer(
    from: #"{"result":{"stopReason":"end_turn"}}"#,
    provider: .copilotCLI
  )
  #expect(kind == .status)
}

// L249: isTerminalEvent for Codex
@Test func codexTerminalEventsDetectedCorrectly() {
  let completedDesc = ProviderEventInspection.describe(
    from: #"{"method":"turn/completed"}"#, provider: .codex
  )
  #expect(completedDesc.isTerminal == true)

  let failedDesc = ProviderEventInspection.describe(
    from: #"{"method":"turn/failed"}"#, provider: .codex
  )
  #expect(failedDesc.isTerminal == true)

  let cancelledDesc = ProviderEventInspection.describe(
    from: #"{"method":"turn/cancelled"}"#, provider: .codex
  )
  #expect(cancelledDesc.isTerminal == true)

  let interruptedDesc = ProviderEventInspection.describe(
    from: #"{"method":"turn/interrupted"}"#, provider: .codex
  )
  #expect(interruptedDesc.isTerminal == true)

  let nonTerminalDesc = ProviderEventInspection.describe(
    from: #"{"method":"turn/started"}"#, provider: .codex
  )
  #expect(nonTerminalDesc.isTerminal == false)
}

// L256/259: Claude terminal events
@Test func claudeCodeTerminalEventsDetectedCorrectly() {
  let resultDesc = ProviderEventInspection.describe(
    from: #"{"type":"result"}"#, provider: .claudeCode
  )
  #expect(resultDesc.isTerminal == true)

  let errorDesc = ProviderEventInspection.describe(
    from: #"{"type":"error"}"#, provider: .claudeCode
  )
  #expect(errorDesc.isTerminal == true)

  let nonTerminalDesc = ProviderEventInspection.describe(
    from: #"{"type":"message"}"#, provider: .claudeCode
  )
  #expect(nonTerminalDesc.isTerminal == false)
}

// L273: CopilotCLI terminal events use || — both branches must kill
@Test func copilotCLITerminalEventsBothStopReasonAndError() {
  // stopReason alone → terminal
  let stop = ProviderEventInspection.describe(
    from: #"{"result":{"stopReason":"end_turn"}}"#, provider: .copilotCLI
  )
  #expect(stop.isTerminal == true)

  // error alone → terminal
  let err = ProviderEventInspection.describe(
    from: #"{"error":{"message":"fatal"}}"#, provider: .copilotCLI
  )
  #expect(err.isTerminal == true)

  // neither → not terminal
  let neither = ProviderEventInspection.describe(
    from: #"{"type":"message"}"#, provider: .copilotCLI
  )
  #expect(neither.isTerminal == false)
}

// ProviderEventInspection.eventType
@Test func eventTypeCoversAllProviderBranches() {
  // Codex: error field → "error"
  let codexError = ProviderEventInspection.describe(
    from: #"{"error":{"code":1},"method":"turn/completed"}"#, provider: .codex
  )
  #expect(codexError.eventType == "error")

  // Codex: method fallback → type fallback → "unknown"
  let codexMethod = ProviderEventInspection.describe(
    from: #"{"method":"turn/completed"}"#, provider: .codex
  )
  #expect(codexMethod.eventType == "turn/completed")

  let codexType = ProviderEventInspection.describe(
    from: #"{"type":"message"}"#, provider: .codex
  )
  #expect(codexType.eventType == "message")

  let codexUnknown = ProviderEventInspection.describe(
    from: #"{"params":{}}"#, provider: .codex
  )
  #expect(codexUnknown.eventType == "unknown")

  // CopilotCLI: error → "error", result → "result", method → type → event → "unknown"
  let copilotResult = ProviderEventInspection.describe(
    from: #"{"result":{"data":"ok"}}"#, provider: .copilotCLI
  )
  #expect(copilotResult.eventType == "result")

  let copilotEvent = ProviderEventInspection.describe(
    from: #"{"event":"status"}"#, provider: .copilotCLI
  )
  #expect(copilotEvent.eventType == "status")

  let copilotUnknown = ProviderEventInspection.describe(
    from: #"{"params":{}}"#, provider: .copilotCLI
  )
  #expect(copilotUnknown.eventType == "unknown")

  // Claude: type → "unknown"
  let claudeUnknown = ProviderEventInspection.describe(
    from: #"{"params":{}}"#, provider: .claudeCode
  )
  #expect(claudeUnknown.eventType == "unknown")
}

// Unparseable JSON gets default descriptor
@Test func describeReturnsUnknownForInvalidJSON() {
  let desc = ProviderEventInspection.describe(from: "not-json", provider: .codex)
  #expect(desc.eventType == "unknown")
  #expect(desc.normalizedKind == .unknown)
  #expect(desc.isTerminal == false)
}

// CopilotCLI alternative method names
@Test func copilotCLIAlternativeMethodNames() {
  let perm = EventKindInference.infer(
    from: #"{"method":"requestPermission"}"#, provider: .copilotCLI
  )
  #expect(perm == .approvalRequest)

  let update = EventKindInference.infer(
    from: #"{"method":"sessionUpdate"}"#, provider: .copilotCLI
  )
  #expect(update == .status)
}

// Codex approval via deeply nested paths in params
@Test func codexApprovalDetectedViaDeepNestedPaths() {
  let resultPath = EventKindInference.infer(
    from: #"{"method":"custom","result":{"request":{"type":"requestApproval"}}}"#,
    provider: .codex
  )
  #expect(resultPath == .approvalRequest)

  let paramsTool = EventKindInference.infer(
    from: #"{"method":"custom","params":{"tool":{"kind":"unsupportedTool"}}}"#,
    provider: .codex
  )
  #expect(paramsTool == .approvalRequest)
}
