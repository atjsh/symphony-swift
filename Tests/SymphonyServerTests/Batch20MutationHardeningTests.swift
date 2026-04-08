// Batch 20 — mutation hardening for CodexTimeoutMonitor consume/cancelAll,
// copilot helper extraction, and SnapshotExtractor non-standard value type coverage.

import Foundation
import SymphonyShared
import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore

// MARK: - CodexTimeoutMonitor consumeTerminalError

@Suite("CodexTimeoutMonitor consumeTerminalError")
struct CodexTimeoutMonitorConsumeTests {

  @Test func consumeTerminalErrorReturnsNilInitially() {
    let monitor = CodexTimeoutMonitor()
    #expect(monitor.consumeTerminalError() == nil)
  }

  @Test func consumeTerminalErrorReturnsNilOnDoubleConsume() async throws {
    let monitor = CodexTimeoutMonitor()
    let stubProcess = StubLaunchedProcess()

    // Trigger a read timeout with a very short delay (1ms).
    monitor.startReadTimeout(
      sessionID: SessionID("consume-test"),
      readTimeoutMS: 1,
      process: stubProcess
    ) { _ in }

    // Wait for the timeout to fire.
    try await Task.sleep(for: .milliseconds(50))

    // First consume might return the error.
    _ = monitor.consumeTerminalError()
    // Second consume must return nil (cleared by defer).
    #expect(monitor.consumeTerminalError() == nil)
  }
}

// MARK: - CodexTimeoutMonitor cancelAll

@Suite("CodexTimeoutMonitor cancelAll")
struct CodexTimeoutMonitorCancelAllTests {

  @Test func cancelAllClearsTerminalErrorAndTasks() async throws {
    let monitor = CodexTimeoutMonitor()
    let stubProcess = StubLaunchedProcess()

    monitor.startReadTimeout(
      sessionID: SessionID("cancel-all-test"),
      readTimeoutMS: 1,
      process: stubProcess
    ) { _ in }
    monitor.startTurnTimeout(
      sessionID: SessionID("cancel-all-test"),
      turnTimeoutMS: 1,
      process: stubProcess
    )

    try await Task.sleep(for: .milliseconds(50))

    // cancelAll should clear terminal error and tasks.
    monitor.cancelAll()
    #expect(monitor.consumeTerminalError() == nil)
  }

  @Test func cancelAllIsIdempotent() {
    let monitor = CodexTimeoutMonitor()
    // Calling cancelAll without any active tasks should not crash.
    monitor.cancelAll()
    monitor.cancelAll()
    #expect(monitor.consumeTerminalError() == nil)
  }
}

// MARK: - copilotProviderSessionID / copilotPromptStopReason

@Suite("Copilot Provider Helpers")
struct CopilotProviderHelperTests {

  @Test func copilotProviderSessionIDExtractsFromResult() {
    let msg = ProviderJSONMessage.parse(
      #"{"id":2,"result":{"sessionId":"copilot-abc-123"}}"#
    )
    #expect(copilotProviderSessionID(from: msg) == "copilot-abc-123")
  }

  @Test func copilotProviderSessionIDReturnsNilForMissingResult() {
    let msg = ProviderJSONMessage.parse(#"{"id":2,"params":{}}"#)
    #expect(copilotProviderSessionID(from: msg) == nil)
  }

  @Test func copilotProviderSessionIDReturnsNilForNilMessage() {
    #expect(copilotProviderSessionID(from: nil) == nil)
  }

  @Test func copilotPromptStopReasonExtractsFromResult() {
    let msg = ProviderJSONMessage.parse(
      #"{"id":3,"result":{"stopReason":"end_turn"}}"#
    )
    #expect(copilotPromptStopReason(from: msg) == "end_turn")
  }

  @Test func copilotPromptStopReasonReturnsNilForMissingResult() {
    let msg = ProviderJSONMessage.parse(#"{"id":3,"params":{}}"#)
    #expect(copilotPromptStopReason(from: msg) == nil)
  }

  @Test func copilotPromptStopReasonReturnsNilForNilMessage() {
    #expect(copilotPromptStopReason(from: nil) == nil)
  }
}

// MARK: - messageText with non-standard JSON value types

@Suite("SnapshotExtractor messageText edge types")
struct SnapshotExtractorMessageTextEdgeTypeTests {

  @Test func messageTextReturnsNilForIntValue() {
    #expect(ProviderSessionSnapshotExtractor.messageText(from: .int(42)) == nil)
  }

  @Test func messageTextReturnsNilForDoubleValue() {
    #expect(ProviderSessionSnapshotExtractor.messageText(from: .double(3.14)) == nil)
  }

  @Test func messageTextReturnsNilForBoolValue() {
    #expect(ProviderSessionSnapshotExtractor.messageText(from: .bool(true)) == nil)
  }

  @Test func messageTextReturnsNilForNullValue() {
    #expect(ProviderSessionSnapshotExtractor.messageText(from: .null) == nil)
  }

  @Test func messageTextReturnsNilForEmptyArray() {
    #expect(ProviderSessionSnapshotExtractor.messageText(from: .array([])) == nil)
  }

  @Test func messageTextReturnsNilForEmptyObject() {
    #expect(ProviderSessionSnapshotExtractor.messageText(from: .object([:])) == nil)
  }
}

// MARK: - tokenUsage with non-object value types

@Suite("SnapshotExtractor tokenUsage edge types")
struct SnapshotExtractorTokenUsageEdgeTypeTests {

  @Test func tokenUsageReturnsNilForStringValue() {
    #expect(ProviderSessionSnapshotExtractor.tokenUsage(from: .string("not tokens")) == nil)
  }

  @Test func tokenUsageReturnsNilForIntValue() {
    #expect(ProviderSessionSnapshotExtractor.tokenUsage(from: .int(42)) == nil)
  }

  @Test func tokenUsageReturnsNilForNullValue() {
    #expect(ProviderSessionSnapshotExtractor.tokenUsage(from: .null) == nil)
  }

  @Test func tokenUsageReturnsNilForBoolValue() {
    #expect(ProviderSessionSnapshotExtractor.tokenUsage(from: .bool(false)) == nil)
  }

  @Test func tokenUsageReturnsNilForEmptyArray() {
    #expect(ProviderSessionSnapshotExtractor.tokenUsage(from: .array([])) == nil)
  }
}

// MARK: - ProviderSessionSnapshotUpdate with all-nil fields

@Suite("SnapshotUpdate all-nil merging")
struct SnapshotUpdateAllNilMergingTests {

  @Test func mergingWithAllNilFieldsPreservesExistingSnapshot() throws {
    let snapshot = ProviderSessionSnapshot(
      providerSessionID: "existing-session",
      providerThreadID: "existing-thread",
      providerTurnID: "existing-turn",
      providerRunID: "existing-run",
      tokenUsage: try TokenUsage(inputTokens: 10, outputTokens: 20),
      latestRateLimitPayload: #"{"remaining":50}"#,
      lastAgentMessage: "hello",
      latestSequence: EventSequence(5)
    )

    let allNilUpdate = ProviderSessionSnapshotUpdate(
      providerSessionID: nil,
      providerThreadID: nil,
      providerTurnID: nil,
      providerRunID: nil,
      tokenUsage: nil,
      latestRateLimitPayload: nil,
      lastAgentMessage: nil,
      latestSequence: nil
    )

    let merged = snapshot.merging(allNilUpdate)
    #expect(merged.providerSessionID == "existing-session")
    #expect(merged.providerThreadID == "existing-thread")
    #expect(merged.providerTurnID == "existing-turn")
    #expect(merged.providerRunID == "existing-run")
    #expect(merged.tokenUsage.inputTokens == 10)
    #expect(merged.tokenUsage.outputTokens == 20)
    #expect(merged.latestRateLimitPayload == #"{"remaining":50}"#)
    #expect(merged.lastAgentMessage == "hello")
    #expect(merged.latestSequence == EventSequence(5))
  }
}
