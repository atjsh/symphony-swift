import Foundation
import SymphonyShared
import Testing

@testable import SymphonySwiftUIApp

@MainActor
@Suite("OperatorModel – Event Presentation Codex", .tags(.model))
struct OperatorModelEventPresentationCodexTests {
  @Test func EventPresentationCoversAdditionalCodexExtractionBranches() {
    #expect(
      SymphonyEventPresentation.isEmptyAgentMessageShell(
        event: AgentRawEvent(
          sessionID: SessionID("session-42"),
          provider: "codex",
          sequence: EventSequence(24),
          timestamp: "2026-03-24T03:00:24Z",
          rawJSON:
            #"{"params":{"item":{"type":"agentMessage","text":"   "}}}"#,
          providerEventType: "item/started",
          normalizedEventKind: "message"
        )))

    #expect(
      SymphonyEventPresentation.isEmptyAgentMessageShell(
        event: AgentRawEvent(
          sessionID: SessionID("session-42"),
          provider: "codex",
          sequence: EventSequence(25),
          timestamp: "2026-03-24T03:00:25Z",
          rawJSON:
            #"{"params":{"item":{"type":"agentMessage","text":"visible"}}}"#,
          providerEventType: "item/started",
          normalizedEventKind: "message"
        )) == false)

    let delta = SymphonyEventPresentation(
      event: AgentRawEvent(
        sessionID: SessionID("session-42"),
        provider: "codex",
        sequence: EventSequence(26),
        timestamp: "2026-03-24T03:00:26Z",
        rawJSON:
          #"{"method":"item/agentMessage/delta","params":{"delta":{"text":"delta text"}}}"#,
        providerEventType: "item/agentMessage/delta",
        normalizedEventKind: "message"
      ))
    #expect(delta.detail == "delta text")

    let approval = SymphonyEventPresentation(
      event: AgentRawEvent(
        sessionID: SessionID("session-42"),
        provider: "codex",
        sequence: EventSequence(27),
        timestamp: "2026-03-24T03:00:27Z",
        rawJSON:
          #"{"method":"item/commandExecution/requestApproval","params":{"reason":"Need approval"}}"#,
        providerEventType: "item/commandExecution/requestApproval",
        normalizedEventKind: "approval_request"
      ))
    #expect(approval.detail == "Need approval")

    let threadStarted = SymphonyEventPresentation(
      event: AgentRawEvent(
        sessionID: SessionID("session-42"),
        provider: "codex",
        sequence: EventSequence(28),
        timestamp: "2026-03-24T03:00:28Z",
        rawJSON:
          #"{"method":"thread/started","params":{"thread":{"status":"queued"}}}"#,
        providerEventType: "thread/started",
        normalizedEventKind: "status"
      ))
    #expect(threadStarted.detail == "queued")

    let turnStarted = SymphonyEventPresentation(
      event: AgentRawEvent(
        sessionID: SessionID("session-42"),
        provider: "codex",
        sequence: EventSequence(29),
        timestamp: "2026-03-24T03:00:29Z",
        rawJSON:
          #"{"method":"turn/started","params":{"status":"running"}}"#,
        providerEventType: "turn/started",
        normalizedEventKind: "status"
      ))
    #expect(turnStarted.detail == "running")

    let summarizedMessage = SymphonyEventPresentation(
      event: AgentRawEvent(
        sessionID: SessionID("session-42"),
        provider: "codex",
        sequence: EventSequence(30),
        timestamp: "2026-03-24T03:00:30Z",
        rawJSON:
          #"{"method":"item/started","params":{"item":{"type":"agentMessage","summary":"Summary only"}}}"#,
        providerEventType: "item/started",
        normalizedEventKind: "message"
      ))
    #expect(summarizedMessage.detail == "Summary only")

    let aggregatedCommand = SymphonyEventPresentation(
      event: AgentRawEvent(
        sessionID: SessionID("session-42"),
        provider: "codex",
        sequence: EventSequence(31),
        timestamp: "2026-03-24T03:00:31Z",
        rawJSON:
          #"{"method":"item/completed","params":{"item":{"type":"commandExecution","aggregatedOutput":"short output"}}}"#,
        providerEventType: "item/completed",
        normalizedEventKind: "tool_result"
      ))
    #expect(aggregatedCommand.detail == "short output")

    let commandResult = SymphonyEventPresentation(
      event: AgentRawEvent(
        sessionID: SessionID("session-42"),
        provider: "codex",
        sequence: EventSequence(32),
        timestamp: "2026-03-24T03:00:32Z",
        rawJSON:
          #"{"method":"item/completed","params":{"item":{"type":"commandExecution","aggregatedOutput":"abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz","result":{"output":"command result"}}}}"#,
        providerEventType: "item/completed",
        normalizedEventKind: "tool_result"
      ))
    #expect(commandResult.detail == "command result")

    let reasoningSummary = SymphonyEventPresentation(
      event: AgentRawEvent(
        sessionID: SessionID("session-42"),
        provider: "codex",
        sequence: EventSequence(33),
        timestamp: "2026-03-24T03:00:33Z",
        rawJSON:
          #"{"method":"item/completed","params":{"item":{"type":"reasoning","summary":"Reasoned summary"}}}"#,
        providerEventType: "item/completed",
        normalizedEventKind: "message"
      ))
    #expect(reasoningSummary.detail == "Reasoned summary")

    let reasoningFallback = SymphonyEventPresentation(
      event: AgentRawEvent(
        sessionID: SessionID("session-42"),
        provider: "codex",
        sequence: EventSequence(34),
        timestamp: "2026-03-24T03:00:34Z",
        rawJSON:
          #"{"method":"item/completed","params":{"item":{"type":"reasoning"}}}"#,
        providerEventType: "item/completed",
        normalizedEventKind: "message"
      ))
    #expect(reasoningFallback.detail == "Reasoning")

    let defaultItemType = SymphonyEventPresentation(
      event: AgentRawEvent(
        sessionID: SessionID("session-42"),
        provider: "codex",
        sequence: EventSequence(35),
        timestamp: "2026-03-24T03:00:35Z",
        rawJSON:
          #"{"method":"item/started","params":{"item":{"type":"customType"}}}"#,
        providerEventType: "item/started",
        normalizedEventKind: "message"
      ))
    #expect(defaultItemType.detail == "customType")

    let itemMessageFallback = SymphonyEventPresentation(
      event: AgentRawEvent(
        sessionID: SessionID("session-42"),
        provider: "codex",
        sequence: EventSequence(36),
        timestamp: "2026-03-24T03:00:36Z",
        rawJSON:
          #"{"method":"item/started","params":{"message":"fallback message"}}"#,
        providerEventType: "item/started",
        normalizedEventKind: "message"
      ))
    #expect(itemMessageFallback.detail == "fallback message")

    let defaultParamsFallback = SymphonyEventPresentation(
      event: AgentRawEvent(
        sessionID: SessionID("session-42"),
        provider: "codex",
        sequence: EventSequence(37),
        timestamp: "2026-03-24T03:00:37Z",
        rawJSON:
          #"{"method":"custom/method","params":{"content":[{"text":"fallback content"}]}}"#,
        providerEventType: "custom/method",
        normalizedEventKind: "message"
      ))
    #expect(defaultParamsFallback.detail == "fallback content")
  }
}
