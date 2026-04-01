import Foundation
import SymphonyShared
import Testing

@testable import SymphonyServer

// MARK: - Event Kind Inference Tests

@Test func eventKindInferenceCodexMessage() {
  let kind = EventKindInference.infer(from: "{\"type\": \"message\"}", provider: .codex)
  #expect(kind == .message)
}

@Test func eventKindInferenceCodexToolCall() {
  let kind = EventKindInference.infer(from: "{\"type\": \"tool_call\"}", provider: .codex)
  #expect(kind == .toolCall)
}

@Test func eventKindInferenceCodexToolResult() {
  let kind = EventKindInference.infer(from: "{\"type\": \"tool_result\"}", provider: .codex)
  #expect(kind == .toolResult)
}

@Test func eventKindInferenceCodexStatus() {
  let kind = EventKindInference.infer(from: "{\"type\": \"status\"}", provider: .codex)
  #expect(kind == .status)
}

@Test func eventKindInferenceCodexThreadStartedStatus() {
  let kind = EventKindInference.infer(from: "{\"method\": \"thread/started\"}", provider: .codex)
  #expect(kind == .status)
}

@Test func eventKindInferenceCodexTurnStartedStatus() {
  let kind = EventKindInference.infer(from: "{\"method\": \"turn/started\"}", provider: .codex)
  #expect(kind == .status)
}

@Test func eventKindInferenceCodexCommandExecutionStartedMapsToolCall() {
  let kind = EventKindInference.infer(
    from:
      #"{"method":"item/started","params":{"item":{"type":"commandExecution","command":"git status --short"}}}"#,
    provider: .codex
  )
  #expect(kind == .toolCall)
}

@Test func eventKindInferenceCodexCommandExecutionCompletedMapsToolResult() {
  let kind = EventKindInference.infer(
    from:
      #"{"method":"item/completed","params":{"item":{"type":"commandExecution","command":"git status --short","status":"completed"}}}"#,
    provider: .codex
  )
  #expect(kind == .toolResult)
}

@Test func eventKindInferenceCodexAgentMessageAndApprovalMethods() {
  let completedMessage = EventKindInference.infer(
    from: #"{"method":"item/completed","params":{"item":{"type":"agentMessage","text":"done"}}}"#,
    provider: .codex
  )
  #expect(completedMessage == .message)

  let deltaMessage = EventKindInference.infer(
    from: #"{"method":"item/agentMessage/delta","params":{"delta":"working"}}"#,
    provider: .codex
  )
  #expect(deltaMessage == .message)

  let approval = EventKindInference.infer(
    from:
      #"{"method":"item/commandExecution/requestApproval","params":{"reason":"allow git rev-parse"}}"#,
    provider: .codex
  )
  #expect(approval == .approvalRequest)
}

@Test func eventKindInferenceCodexThreadStatusAndUsageMethods() {
  let status = EventKindInference.infer(
    from: #"{"method":"thread/status/changed","params":{"status":{"type":"active"}}}"#,
    provider: .codex
  )
  #expect(status == .status)

  let usage = EventKindInference.infer(
    from:
      #"{"method":"thread/tokenUsage/updated","params":{"tokenUsage":{"total":{"totalTokens":42}}}}"#,
    provider: .codex
  )
  #expect(usage == .usage)
}

@Test func eventKindInferenceCodexUnknownMethodFallsBackToType() {
  let kind = EventKindInference.infer(
    from: "{\"method\": \"custom/notification\", \"type\": \"message\"}",
    provider: .codex
  )
  #expect(kind == .message)
}

@Test func eventKindInferenceCodexUsage() {
  let kind = EventKindInference.infer(from: "{\"type\": \"usage\"}", provider: .codex)
  #expect(kind == .usage)
}

@Test func eventKindInferenceCodexApprovalRequest() {
  let kind = EventKindInference.infer(from: "{\"type\": \"approval_request\"}", provider: .codex)
  #expect(kind == .approvalRequest)
}

@Test func eventKindInferenceCodexFileChangePermissionInputAndUnsupportedToolRequests() {
  let fileChange = EventKindInference.infer(
    from:
      #"{"method":"item/fileChange/requestApproval","params":{"request":{"kind":"file_change"}}}"#,
    provider: .codex
  )
  #expect(fileChange == .approvalRequest)

  let permission = EventKindInference.infer(
    from:
      #"{"method":"turn/permissionRequired","params":{"permission":{"kind":"shell"}}}"#,
    provider: .codex
  )
  #expect(permission == .approvalRequest)

  let inputRequired = EventKindInference.infer(
    from:
      #"{"method":"item/started","params":{"item":{"type":"userInputRequired","prompt":"Need confirmation"}}}"#,
    provider: .codex
  )
  #expect(inputRequired == .approvalRequest)

  let unsupportedTool = EventKindInference.infer(
    from:
      #"{"type":"unsupported_tool","params":{"tool":{"kind":"dynamic"}}}"#,
    provider: .codex
  )
  #expect(unsupportedTool == .approvalRequest)
}

@Test func eventKindInferenceCodexFileChangeRequiredMapsApprovalRequest() {
  let kind = EventKindInference.infer(
    from:
      #"{"method":"item/fileChange/required","params":{"request":{"kind":"file_change"}}}"#,
    provider: .codex
  )
  #expect(kind == .approvalRequest)
}

@Test func eventKindInferenceCodexUnsupportedAndToolTokensMapApprovalRequest() {
  let kind = EventKindInference.infer(
    from:
      #"{"type":"tool_unsupported","params":{"tool":{"kind":"dynamic"}}}"#,
    provider: .codex
  )
  #expect(kind == .approvalRequest)
}

@Test func eventKindInferenceCodexError() {
  let kind = EventKindInference.infer(from: "{\"type\": \"error\"}", provider: .codex)
  #expect(kind == .error)
}

@Test func eventKindInferenceCodexJSONRPCErrorResponse() {
  let kind = EventKindInference.infer(
    from: #"{"error":{"code":-32600,"message":"bad request"},"id":1}"#,
    provider: .codex
  )
  #expect(kind == .error)
}

@Test func eventKindInferenceCodexUnknown() {
  let kind = EventKindInference.infer(from: "{\"type\": \"custom_thing\"}", provider: .codex)
  #expect(kind == .unknown)
}

@Test func eventKindInferenceCodexText() {
  let kind = EventKindInference.infer(from: "{\"type\": \"text\"}", provider: .codex)
  #expect(kind == .message)
}

@Test func eventKindInferenceClaudeAssistant() {
  let kind = EventKindInference.infer(from: "{\"type\": \"assistant\"}", provider: .claudeCode)
  #expect(kind == .message)
}

@Test func eventKindInferenceClaudeText() {
  let kind = EventKindInference.infer(from: "{\"type\": \"text\"}", provider: .claudeCode)
  #expect(kind == .message)
}

@Test func eventKindInferenceClaudeMessage() {
  let kind = EventKindInference.infer(from: "{\"type\": \"message\"}", provider: .claudeCode)
  #expect(kind == .message)
}

@Test func eventKindInferenceClaudeResult() {
  let kind = EventKindInference.infer(from: "{\"type\": \"result\"}", provider: .claudeCode)
  #expect(kind == .message)
}

@Test func eventKindInferenceClaudeToolUse() {
  let kind = EventKindInference.infer(from: "{\"type\": \"tool_use\"}", provider: .claudeCode)
  #expect(kind == .toolCall)
}

@Test func eventKindInferenceClaudeToolResult() {
  let kind = EventKindInference.infer(from: "{\"type\": \"tool_result\"}", provider: .claudeCode)
  #expect(kind == .toolResult)
}

@Test func eventKindInferenceClaudeSystem() {
  let kind = EventKindInference.infer(from: "{\"type\": \"system\"}", provider: .claudeCode)
  #expect(kind == .status)
}

@Test func eventKindInferenceClaudeStatus() {
  let kind = EventKindInference.infer(from: "{\"type\": \"status\"}", provider: .claudeCode)
  #expect(kind == .status)
}

@Test func eventKindInferenceClaudeUsage() {
  let kind = EventKindInference.infer(from: "{\"type\": \"usage\"}", provider: .claudeCode)
  #expect(kind == .usage)
}

@Test func eventKindInferenceClaudeError() {
  let kind = EventKindInference.infer(from: "{\"type\": \"error\"}", provider: .claudeCode)
  #expect(kind == .error)
}

@Test func eventKindInferenceClaudeUnknown() {
  let kind = EventKindInference.infer(from: "{\"type\": \"custom\"}", provider: .claudeCode)
  #expect(kind == .unknown)
}

@Test func eventKindInferenceCopilotMessage() {
  let kind = EventKindInference.infer(from: "{\"type\": \"message\"}", provider: .copilotCLI)
  #expect(kind == .message)
}

@Test func eventKindInferenceCopilotUpdate() {
  let kind = EventKindInference.infer(from: "{\"type\": \"update\"}", provider: .copilotCLI)
  #expect(kind == .message)
}

@Test func eventKindInferenceCopilotText() {
  let kind = EventKindInference.infer(from: "{\"type\": \"text\"}", provider: .copilotCLI)
  #expect(kind == .message)
}

@Test func eventKindInferenceCopilotEventFallback() {
  let kind = EventKindInference.infer(from: "{\"event\": \"status\"}", provider: .copilotCLI)
  #expect(kind == .status)
}

@Test func eventKindInferenceCopilotToolCall() {
  let kind = EventKindInference.infer(from: "{\"type\": \"tool_call\"}", provider: .copilotCLI)
  #expect(kind == .toolCall)
}

@Test func eventKindInferenceCopilotToolResult() {
  let kind = EventKindInference.infer(from: "{\"type\": \"tool_result\"}", provider: .copilotCLI)
  #expect(kind == .toolResult)
}

@Test func eventKindInferenceCopilotUsage() {
  let kind = EventKindInference.infer(from: "{\"type\": \"usage\"}", provider: .copilotCLI)
  #expect(kind == .usage)
}

@Test func eventKindInferenceCopilotError() {
  let kind = EventKindInference.infer(from: "{\"type\": \"error\"}", provider: .copilotCLI)
  #expect(kind == .error)
}

@Test func eventKindInferenceCopilotErrorEnvelopeUsesErrorBranch() {
  let kind = EventKindInference.infer(
    from: #"{"error":{"message":"bad request"},"id":1}"#,
    provider: .copilotCLI
  )
  #expect(kind == .error)
}

@Test func eventKindInferenceCopilotUnknown() {
  let kind = EventKindInference.infer(from: "{\"type\": \"custom\"}", provider: .copilotCLI)
  #expect(kind == .unknown)
}

@Test func eventKindInferenceInvalidJSON() {
  let kind = EventKindInference.infer(from: "not json", provider: .codex)
  #expect(kind == .unknown)
}

@Test func eventKindInferenceMissingType() {
  let kind = EventKindInference.infer(from: "{\"data\": \"hello\"}", provider: .codex)
  #expect(kind == .unknown)
}

@Test func eventKindInferenceMissingTypeClaudeCode() {
  let kind = EventKindInference.infer(from: "{\"data\": \"hello\"}", provider: .claudeCode)
  #expect(kind == .unknown)
}

@Test func eventKindInferenceMissingTypeCopilot() {
  let kind = EventKindInference.infer(from: "{\"data\": \"hello\"}", provider: .copilotCLI)
  #expect(kind == .unknown)
}

@Test func eventKindInferenceCodexMethodCompletionIsStatus() {
  let kind = EventKindInference.infer(
    from: "{\"method\": \"turn/completed\"}",
    provider: .codex
  )
  #expect(kind == .status)
}

@Test func eventKindInferenceCopilotMethodUpdateIsStatus() {
  let kind = EventKindInference.infer(
    from: "{\"method\": \"session/update\"}",
    provider: .copilotCLI
  )
  #expect(kind == .status)
}

@Test func eventKindInferenceCopilotPermissionRequestIsApprovalRequest() {
  let kind = EventKindInference.infer(
    from: "{\"method\": \"session/request_permission\"}",
    provider: .copilotCLI
  )
  #expect(kind == .approvalRequest)
}

@Test func eventKindInferenceCopilotPromptResultIsStatus() {
  let kind = EventKindInference.infer(
    from: "{\"id\": 3, \"result\": {\"stopReason\": \"end_turn\"}}",
    provider: .copilotCLI
  )
  #expect(kind == .status)
}

@Test func codexTurnOutcomeParsesFailedAndInterruptedStatesFromNestedPayloads() {
  let failed = codexTurnOutcome(
    from:
      #"{"method":"turn/completed","params":{"outcome":[" ","failed"]}}"#
  )
  #expect(failed == .failed)

  let interrupted = codexTurnOutcome(
    from:
      #"{"method":"turn/completed","params":{"payload":{"state":"cancelled"}}}"#
  )
  #expect(interrupted == .interrupted)

  let cancelled = codexTurnOutcome(
    from:
      #"{"method":"turn/cancelled","params":{"turn_id":"turn-cancelled"}}"#
  )
  #expect(cancelled == .interrupted)

  let completed = codexTurnOutcome(
    from:
      #"{"method":"turn/completed","params":{"outcome":[" "," "]}}"#
  )
  #expect(completed == .completed)
}
