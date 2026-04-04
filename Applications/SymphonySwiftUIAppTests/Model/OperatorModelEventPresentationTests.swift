import Foundation
import SymphonyShared
import Testing

@testable import SymphonySwiftUIApp

private struct EventKindExpectation: @unchecked Sendable, CustomTestStringConvertible {
  let kind: String
  let expectedTitle: String
  let expectedRowStyle: SymphonyEventPresentation.RowStyle
  let expectedShowsRawJSON: Bool

  var testDescription: String { kind }

  static let knownKinds: [EventKindExpectation] = [
    .init(kind: "message", expectedTitle: "Message", expectedRowStyle: .message, expectedShowsRawJSON: false),
    .init(kind: "tool_call", expectedTitle: "Tool Call", expectedRowStyle: .tool, expectedShowsRawJSON: false),
    .init(kind: "tool_result", expectedTitle: "Tool Result", expectedRowStyle: .tool, expectedShowsRawJSON: false),
    .init(kind: "status", expectedTitle: "Status", expectedRowStyle: .compact, expectedShowsRawJSON: false),
    .init(kind: "usage", expectedTitle: "Usage", expectedRowStyle: .compact, expectedShowsRawJSON: false),
    .init(kind: "approval_request", expectedTitle: "Approval Request", expectedRowStyle: .callout, expectedShowsRawJSON: false),
    .init(kind: "error", expectedTitle: "Error", expectedRowStyle: .callout, expectedShowsRawJSON: false),
  ]
}

private struct FallbackDetailExpectation: @unchecked Sendable, CustomTestStringConvertible {
  let providerEventType: String
  let normalizedEventKind: String
  let expectedDetail: String

  var testDescription: String { "\(normalizedEventKind)/\(providerEventType)" }

  static let cases: [FallbackDetailExpectation] = [
    .init(providerEventType: "message_fallback", normalizedEventKind: "message", expectedDetail: "message_fallback"),
    .init(providerEventType: "tool_call_fallback", normalizedEventKind: "tool_call", expectedDetail: "tool_call_fallback"),
    .init(providerEventType: "tool_result_fallback", normalizedEventKind: "tool_result", expectedDetail: "tool_result_fallback"),
  ]
}

private struct HumanizedItemExpectation: @unchecked Sendable, CustomTestStringConvertible {
  let input: String?
  let expected: String?

  var testDescription: String { input ?? "nil" }

  static let cases: [HumanizedItemExpectation] = [
    .init(input: "agentMessage", expected: "Message"),
    .init(input: "commandExecution", expected: "Command execution"),
    .init(input: "customType", expected: "customType"),
    .init(input: "", expected: nil),
    .init(input: nil, expected: nil),
  ]
}

@MainActor
@Suite("OperatorModel – Event Presentation", .tags(.model))
struct OperatorModelEventPresentationTests {
  @Test(arguments: EventKindExpectation.knownKinds)
  fileprivate func knownEventKindMapsToExpectedTitleAndRowStyle(expectation: EventKindExpectation) {
    let presentation = SymphonyEventPresentation(event: makeEvent(sequence: 1, kind: expectation.kind))
    #expect(presentation.title == expectation.expectedTitle)
    #expect(presentation.rowStyle == expectation.expectedRowStyle)
    #expect(presentation.showsRawJSON == expectation.expectedShowsRawJSON)
  }

  @Test(arguments: FallbackDetailExpectation.cases)
  fileprivate func fallbackDetailUsesProviderEventType(expectation: FallbackDetailExpectation) {
    let presentation = SymphonyEventPresentation(
      event: AgentRawEvent(
        sessionID: SessionID("session-42"),
        provider: "claude_code",
        sequence: EventSequence(16),
        timestamp: "2026-03-24T03:00:16Z",
        rawJSON: #"{"payload":{}}"#,
        providerEventType: expectation.providerEventType,
        normalizedEventKind: expectation.normalizedEventKind
      ))
    #expect(presentation.detail == expectation.expectedDetail)
  }

  @Test func approvalAndErrorFallbacksUseRawJSON() {
    let approvalFallback = SymphonyEventPresentation(
      event: AgentRawEvent(
        sessionID: SessionID("session-42"),
        provider: "claude_code",
        sequence: EventSequence(19),
        timestamp: "2026-03-24T03:00:19Z",
        rawJSON: #"{"payload":{}}"#,
        providerEventType: "approval_fallback",
        normalizedEventKind: "approval_request"
      ))
    #expect(approvalFallback.detail == #"{"payload":{}}"#)

    let errorFallback = SymphonyEventPresentation(
      event: AgentRawEvent(
        sessionID: SessionID("session-42"),
        provider: "claude_code",
        sequence: EventSequence(20),
        timestamp: "2026-03-24T03:00:20Z",
        rawJSON: #"{"payload":{}}"#,
        providerEventType: "error_fallback",
        normalizedEventKind: "error"
      ))
    #expect(errorFallback.detail == #"{"payload":{}}"#)
  }

  @Test func unknownEventKindReturnsSupplemental() {
    let unknown = SymphonyEventPresentation(
      event: AgentRawEvent(
        sessionID: SessionID("session-42"),
        provider: "claude_code",
        sequence: EventSequence(8),
        timestamp: "2026-03-24T03:00:08Z",
        rawJSON: #"{"payload":{"notes":"inspect raw payload"}}"#,
        providerEventType: "provider_custom",
        normalizedEventKind: "unexpected_kind"
      ))
    #expect(unknown.title == "Unknown Event")
    #expect(unknown.rowStyle == .supplemental)
    #expect(unknown.detail == "inspect raw payload")
    #expect(unknown.showsRawJSON)
  }

  @Test func codexCompletedMessageExtractsText() {
    let codexCompletedMessage = SymphonyEventPresentation(
      event: AgentRawEvent(
        sessionID: SessionID("session-42"),
        provider: "codex",
        sequence: EventSequence(21),
        timestamp: "2026-03-24T03:00:21Z",
        rawJSON:
          #"{"method":"item/completed","params":{"item":{"type":"agentMessage","id":"msg_1","text":"Hello from Codex","phase":"commentary","memoryCitation":null},"threadId":"thread-1","turnId":"turn-1"}}"#,
        providerEventType: "item/completed",
        normalizedEventKind: "message"
      ))
    #expect(codexCompletedMessage.detail == "Hello from Codex")
    #expect(codexCompletedMessage.rowStyle == .message)
  }

  @Test func codexToolCallExtractsCommand() {
    let codexToolCall = SymphonyEventPresentation(
      event: AgentRawEvent(
        sessionID: SessionID("session-42"),
        provider: "codex",
        sequence: EventSequence(22),
        timestamp: "2026-03-24T03:00:22Z",
        rawJSON:
          #"{"method":"item/started","params":{"item":{"type":"commandExecution","id":"call_1","command":"/bin/zsh -lc pwd","cwd":"/tmp","processId":"1","status":"inProgress","commandActions":[],"aggregatedOutput":null,"exitCode":null,"durationMs":null},"threadId":"thread-1","turnId":"turn-1"}}"#,
        providerEventType: "item/started",
        normalizedEventKind: "tool_call"
      ))
    #expect(codexToolCall.detail == "/bin/zsh -lc pwd")
    #expect(codexToolCall.rowStyle == .tool)
  }

  @Test func codexStatusExtractsActiveState() {
    let codexStatus = SymphonyEventPresentation(
      event: AgentRawEvent(
        sessionID: SessionID("session-42"),
        provider: "codex",
        sequence: EventSequence(23),
        timestamp: "2026-03-24T03:00:23Z",
        rawJSON:
          #"{"method":"thread/status/changed","params":{"status":{"type":"active"},"threadId":"thread-1","turnId":"turn-1"}}"#,
        providerEventType: "thread/status/changed",
        normalizedEventKind: "status"
      ))
    #expect(codexStatus.detail == "active")
    #expect(codexStatus.rowStyle == .compact)
  }

  @Test func rawJSONEdgeCasesExtractCorrectly() {
    let rawString = SymphonyEventPresentation(
      event: AgentRawEvent(
        sessionID: SessionID("session-42"),
        provider: "claude_code",
        sequence: EventSequence(11),
        timestamp: "2026-03-24T03:00:11Z",
        rawJSON: #"["hello"]"#,
        providerEventType: "message",
        normalizedEventKind: "message"
      ))
    #expect(rawString.detail == "hello")

    let arrayContent = SymphonyEventPresentation(
      event: AgentRawEvent(
        sessionID: SessionID("session-42"),
        provider: "claude_code",
        sequence: EventSequence(12),
        timestamp: "2026-03-24T03:00:12Z",
        rawJSON: #"[{"content":"inside"}]"#,
        providerEventType: "tool_result",
        normalizedEventKind: "tool_result"
      ))
    #expect(arrayContent.detail == "inside")

    let numeric = SymphonyEventPresentation(
      event: AgentRawEvent(
        sessionID: SessionID("session-42"),
        provider: "claude_code",
        sequence: EventSequence(13),
        timestamp: "2026-03-24T03:00:13Z",
        rawJSON: #"42"#,
        providerEventType: "usage",
        normalizedEventKind: "usage"
      ))
    #expect(numeric.detail == "42")

    let arrayFallback = SymphonyEventPresentation(
      event: AgentRawEvent(
        sessionID: SessionID("session-42"),
        provider: "claude_code",
        sequence: EventSequence(15),
        timestamp: "2026-03-24T03:00:15Z",
        rawJSON: #"[{}]"#,
        providerEventType: "usage",
        normalizedEventKind: "usage"
      ))
    #expect(arrayFallback.detail == #"[{}]"#)

    let invalidJSON = SymphonyEventPresentation(
      event: AgentRawEvent(
        sessionID: SessionID("session-42"),
        provider: "claude_code",
        sequence: EventSequence(14),
        timestamp: "2026-03-24T03:00:14Z",
        rawJSON: #"{invalid"#,
        providerEventType: "provider_status",
        normalizedEventKind: "status"
      ))
    #expect(invalidJSON.detail == "provider_status")
    #expect(invalidJSON.metadata.contains("claude code"))
  }

  @Test(arguments: HumanizedItemExpectation.cases)
  fileprivate func humanizedItemTypeReturnsExpected(expectation: HumanizedItemExpectation) {
    #expect(SymphonyEventPresentation.humanizedItemType(expectation.input) == expectation.expected)
  }

  @Test func extractTextHelperMethodsCoverDirectFallbackBranches() {
    #expect(SymphonyEventPresentation.extractText(from: nil as Any?) == nil)
    #expect(SymphonyEventPresentation.extractText(fromItem: ["type": "customType"]) == "customType")
    #expect(SymphonyEventPresentation.extractText(method: "custom/method", params: ["result": "direct"]) == "direct")

    let unknownFallback = SymphonyEventPresentation(
      event: AgentRawEvent(
        sessionID: SessionID("session-42"),
        provider: "claude_code",
        sequence: EventSequence(38),
        timestamp: "2026-03-24T03:00:38Z",
        rawJSON: #"{}"#,
        providerEventType: "provider_unknown",
        normalizedEventKind: "unexpected_kind"
      ))
    #expect(unknownFallback.detail == #"{}"#)
    #expect(SymphonyEventPresentation.extractText(from: "wrapped" as Any?) == "wrapped")
    #expect(SymphonyEventPresentation.extractText(fromItem: [:]) == nil)

    #expect(
      SymphonyEventPresentation.extractText(
        method: "item/started",
        params: [:]
      ) == nil
    )
    #expect(SymphonyEventPresentation.extractText(
        fromItem: ["type": "agentMessage", "content": "content body"]
      ) == "content body")
    #expect(SymphonyEventPresentation.extractText(
        fromItem: ["type": "commandExecution", "arguments": ["--flag"]]
      ) == "--flag")
    #expect(SymphonyEventPresentation.extractText(
        fromItem: ["type": "commandExecution", "status": "completed"]
      ) == "completed")
    #expect(SymphonyEventPresentation.extractText(
        fromItem: ["type": "reasoning", "content": "reasoning body"]
      ) == "reasoning body")
    #expect(SymphonyEventPresentation.extractText(
        method: "thread/started",
        params: ["status": "queued"]
      ) == "queued")
    #expect(SymphonyEventPresentation.extractText(
        method: "turn/started",
        params: ["turn": ["status": "running"]]
      ) == "running")
  }
}
