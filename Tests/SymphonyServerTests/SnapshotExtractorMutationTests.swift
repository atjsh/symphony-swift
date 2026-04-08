import Foundation
import SymphonyShared
import Testing

@testable import SymphonyServer

// MARK: - ProviderSessionSnapshotExtractor mutation hardening

@Test func snapshotExtractorExtractsProviderSessionID() {
  let event = AgentRawEvent(
    sessionID: SessionID("s1"),
    provider: "codex",
    sequence: EventSequence(1),
    timestamp: "2026-01-01T00:00:00Z",
    rawJSON: #"{"session_id":"sess_abc"}"#,
    providerEventType: "status",
    normalizedEventKind: "status"
  )
  let update = ProviderSessionSnapshotExtractor.update(from: event, storedSequence: EventSequence(1))
  #expect(update.providerSessionID == "sess_abc")
}

@Test func snapshotExtractorExtractsProviderThreadAndTurnIDs() {
  let event = AgentRawEvent(
    sessionID: SessionID("s1"),
    provider: "codex",
    sequence: EventSequence(1),
    timestamp: "2026-01-01T00:00:00Z",
    rawJSON: #"{"thread":{"id":"t1"},"turn":{"id":"turn1"}}"#,
    providerEventType: "status",
    normalizedEventKind: "status"
  )
  let update = ProviderSessionSnapshotExtractor.update(from: event, storedSequence: EventSequence(1))
  #expect(update.providerThreadID == "t1")
  #expect(update.providerTurnID == "turn1")
}

@Test func snapshotExtractorExtractsTokenUsageFromNestedObject() {
  let event = AgentRawEvent(
    sessionID: SessionID("s1"),
    provider: "codex",
    sequence: EventSequence(1),
    timestamp: "2026-01-01T00:00:00Z",
    rawJSON: #"{"usage":{"input_tokens":100,"output_tokens":200}}"#,
    providerEventType: "usage",
    normalizedEventKind: "usage"
  )
  let update = ProviderSessionSnapshotExtractor.update(from: event, storedSequence: EventSequence(1))
  #expect(update.tokenUsage != nil)
  #expect(update.tokenUsage?.inputTokens == 100)
  #expect(update.tokenUsage?.outputTokens == 200)
}

@Test func snapshotExtractorReturnsNilTokenUsageWhenNoFields() {
  let event = AgentRawEvent(
    sessionID: SessionID("s1"),
    provider: "codex",
    sequence: EventSequence(1),
    timestamp: "2026-01-01T00:00:00Z",
    rawJSON: #"{"unrelated":"data"}"#,
    providerEventType: "status",
    normalizedEventKind: "status"
  )
  let update = ProviderSessionSnapshotExtractor.update(from: event, storedSequence: EventSequence(1))
  #expect(update.tokenUsage == nil)
}

@Test func snapshotExtractorExtractsLastAgentMessageOnlyForMessageKind() {
  let messageEvent = AgentRawEvent(
    sessionID: SessionID("s1"),
    provider: "codex",
    sequence: EventSequence(1),
    timestamp: "2026-01-01T00:00:00Z",
    rawJSON: #"{"message":"Hello from agent"}"#,
    providerEventType: "message",
    normalizedEventKind: "message"
  )
  let messageUpdate = ProviderSessionSnapshotExtractor.update(
    from: messageEvent, storedSequence: EventSequence(1)
  )
  #expect(messageUpdate.lastAgentMessage == "Hello from agent")

  // Non-message events should NOT extract lastAgentMessage
  let statusEvent = AgentRawEvent(
    sessionID: SessionID("s1"),
    provider: "codex",
    sequence: EventSequence(2),
    timestamp: "2026-01-01T00:00:00Z",
    rawJSON: #"{"message":"some text"}"#,
    providerEventType: "status",
    normalizedEventKind: "status"
  )
  let statusUpdate = ProviderSessionSnapshotExtractor.update(
    from: statusEvent, storedSequence: EventSequence(2)
  )
  #expect(statusUpdate.lastAgentMessage == nil)
}

@Test func snapshotExtractorSetsLatestSequence() {
  let event = AgentRawEvent(
    sessionID: SessionID("s1"),
    provider: "codex",
    sequence: EventSequence(5),
    timestamp: "2026-01-01T00:00:00Z",
    rawJSON: #"{}"#,
    providerEventType: "status",
    normalizedEventKind: "status"
  )
  let update = ProviderSessionSnapshotExtractor.update(from: event, storedSequence: EventSequence(42))
  #expect(update.latestSequence == EventSequence(42))
}

@Test func snapshotExtractorExtractsProviderRunID() {
  let event = AgentRawEvent(
    sessionID: SessionID("s1"),
    provider: "codex",
    sequence: EventSequence(1),
    timestamp: "2026-01-01T00:00:00Z",
    rawJSON: #"{"run_id":"run_xyz"}"#,
    providerEventType: "status",
    normalizedEventKind: "status"
  )
  let update = ProviderSessionSnapshotExtractor.update(from: event, storedSequence: EventSequence(1))
  #expect(update.providerRunID == "run_xyz")
}

@Test func snapshotMergingReplacesNonNilFields() {
  let base = ProviderSessionSnapshot(
    providerSessionID: "old",
    providerThreadID: "t1"
  )
  let update = ProviderSessionSnapshotUpdate(
    providerSessionID: "new",
    providerTurnID: "turn1"
  )
  let merged = base.merging(update)
  #expect(merged.providerSessionID == "new")
  #expect(merged.providerThreadID == "t1")
  #expect(merged.providerTurnID == "turn1")
}

@Test func snapshotExtractorExtractsRateLimitPayload() {
  let event = AgentRawEvent(
    sessionID: SessionID("s1"),
    provider: "codex",
    sequence: EventSequence(1),
    timestamp: "2026-01-01T00:00:00Z",
    rawJSON: #"{"rate_limit":{"requests_remaining":50}}"#,
    providerEventType: "status",
    normalizedEventKind: "status"
  )
  let update = ProviderSessionSnapshotExtractor.update(from: event, storedSequence: EventSequence(1))
  #expect(update.latestRateLimitPayload != nil)
  #expect(update.latestRateLimitPayload?.contains("50") == true)
}

@Test func snapshotExtractorHandlesInvalidJSON() {
  let event = AgentRawEvent(
    sessionID: SessionID("s1"),
    provider: "codex",
    sequence: EventSequence(1),
    timestamp: "2026-01-01T00:00:00Z",
    rawJSON: "not-json",
    providerEventType: "status",
    normalizedEventKind: "status"
  )
  let update = ProviderSessionSnapshotExtractor.update(from: event, storedSequence: EventSequence(1))
  #expect(update.providerSessionID == nil)
  #expect(update.tokenUsage == nil)
}

// MARK: - messageText extraction

@Test func messageTextExtractsFromStringValue() {
  let text = ProviderSessionSnapshotExtractor.messageText(from: .string("hello"))
  #expect(text == "hello")
}

@Test func messageTextReturnsNilForEmptyOrWhitespaceString() {
  #expect(ProviderSessionSnapshotExtractor.messageText(from: .string("")) == nil)
  #expect(ProviderSessionSnapshotExtractor.messageText(from: .string("   ")) == nil)
}

@Test func messageTextExtractsFromNestedContent() {
  let value = JSONValue.object([
    "content": .string("inner message")
  ])
  let text = ProviderSessionSnapshotExtractor.messageText(from: value)
  #expect(text == "inner message")
}

@Test func messageTextExtractsFromArray() {
  let value = JSONValue.array([
    .string(""),
    .string("found it")
  ])
  let text = ProviderSessionSnapshotExtractor.messageText(from: value)
  #expect(text == "found it")
}

@Test func messageTextExtractsFromDeltaPath() {
  let value = JSONValue.object([
    "delta": .string("streaming chunk")
  ])
  let text = ProviderSessionSnapshotExtractor.messageText(from: value)
  #expect(text == "streaming chunk")
}

// MARK: - tokenUsage edge cases

@Test func tokenUsageExtractedFromAlternativeFieldNames() {
  let usage1 = ProviderSessionSnapshotExtractor.tokenUsage(from: .object([
    "token_usage": .object(["inputTokens": .int(50)])
  ]))
  #expect(usage1 != nil)

  let usage2 = ProviderSessionSnapshotExtractor.tokenUsage(from: .object([
    "tokenUsageTotals": .object(["total_tokens": .int(300)])
  ]))
  #expect(usage2 != nil)
}

@Test func tokenUsageReturnsNilWhenObjectHasNoRelevantKeys() {
  let usage = ProviderSessionSnapshotExtractor.tokenUsage(from: .object([
    "unrelated": .int(42)
  ]))
  #expect(usage == nil)
}
