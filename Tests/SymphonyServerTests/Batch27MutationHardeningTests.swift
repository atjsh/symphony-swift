import Foundation
import SymphonyShared
import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore

// MARK: - Batch 27: clearState individual removal + CopilotCLI inference precedence

// ──────────────────────────────────────────────────────────────────────────────
// SQLiteAgentRunEventSink — individual clearState removeValue mutations
//
// Muter injects RemoveSideEffects on EACH of the 8 removeValue calls inside
// `clearState(for:sessionID:)`. The existing `eventSinkCompletionClearsInMemoryState`
// only checks snapshot (count, type, time). We also need to verify:
//   - runIDBySessionID mapping is broken (events for old sessionID ignored)
//   - providerSnapshot returns fresh empty after clear
//   - startedAt falls back to fresh timestamp after clear
// ──────────────────────────────────────────────────────────────────────────────

@Test func clearStateBreaksSessionToRunIDMappingSoEventsAreIgnored() throws {
  let databaseURL = try makeAgentRunSinkTemporaryDirectory()
    .appendingPathComponent("sink-sessmap.sqlite3")
  let store = try SQLiteServerStateStore(databaseURL: databaseURL)
  let sink = SQLiteAgentRunEventSink(store: store)

  let issue = try makeAgentRunSinkIssue()
  let context = try makeAgentRunSinkContext()
  let sessionID = SessionID("s-sessmap")
  let startInfo = AgentRunStartInfo(
    context: context,
    issue: issue,
    provider: "codex",
    sessionID: sessionID,
    workspacePath: "/tmp/ws"
  )
  sink.runDidStart(startInfo)

  // Send one event so there's something persisted
  sink.runDidReceiveEvent(AgentRawEvent(
    sessionID: sessionID,
    provider: "codex",
    sequence: EventSequence(0),
    timestamp: "2026-01-01T00:00:00Z",
    rawJSON: #"{"type":"message"}"#,
    providerEventType: "message",
    normalizedEventKind: "message"
  ))
  let countBefore = try #require(try store.runDetail(id: context.runID)?.logs.eventCount)
  #expect(countBefore == 1)

  // Complete → triggers clearState which removes runIDBySessionID[sessionID]
  sink.runDidComplete(AgentRunResult(
    context: context,
    sessionID: sessionID,
    finalState: .succeeded,
    eventCount: 1,
    error: nil
  ))

  // Now send another event on the SAME sessionID — should be silently ignored
  // because runIDBySessionID[sessionID] was removed by clearState.
  sink.runDidReceiveEvent(AgentRawEvent(
    sessionID: sessionID,
    provider: "codex",
    sequence: EventSequence(1),
    timestamp: "2026-01-01T00:00:01Z",
    rawJSON: #"{"type":"status"}"#,
    providerEventType: "status",
    normalizedEventKind: "status"
  ))

  // Event count in the database should still be 1 (the post-clear event was dropped)
  let detail = try #require(try store.runDetail(id: context.runID))
  #expect(detail.logs.eventCount == 1)
}

@Test func clearStateResetsProviderSnapshotToEmpty() throws {
  let databaseURL = try makeAgentRunSinkTemporaryDirectory()
    .appendingPathComponent("sink-psclr.sqlite3")
  let store = try SQLiteServerStateStore(databaseURL: databaseURL)
  let sink = SQLiteAgentRunEventSink(store: store)

  let issue = try makeAgentRunSinkIssue()
  let context = try makeAgentRunSinkContext()
  let sessionID = SessionID("s-psclr")
  let startInfo = AgentRunStartInfo(
    context: context,
    issue: issue,
    provider: "codex",
    sessionID: sessionID,
    workspacePath: "/tmp/ws"
  )
  sink.runDidStart(startInfo)

  // Merge a provider snapshot with actual data
  sink.testingMergeProviderSnapshot(
    for: context.runID,
    providerSessionID: "ps-abc",
    providerThreadID: "thread-1"
  )
  let before = sink.testingProviderSnapshot(for: context.runID)
  #expect(before.providerSessionID == "ps-abc")
  #expect(before.providerThreadID == "thread-1")

  // Complete → clearState removes providerSnapshotByRunID[runID]
  sink.runDidComplete(AgentRunResult(
    context: context,
    sessionID: sessionID,
    finalState: .succeeded,
    eventCount: 0,
    error: nil
  ))

  // After clear, providerSnapshot should return the nil-coalescing default
  let after = sink.testingProviderSnapshot(for: context.runID)
  #expect(after.providerSessionID == nil)
  #expect(after.providerThreadID == nil)
}

@Test func clearStateResetsStartedAtToFreshTimestamp() throws {
  let databaseURL = try makeAgentRunSinkTemporaryDirectory()
    .appendingPathComponent("sink-start.sqlite3")
  let store = try SQLiteServerStateStore(databaseURL: databaseURL)
  let sink = SQLiteAgentRunEventSink(store: store)

  let issue = try makeAgentRunSinkIssue()
  let context = try makeAgentRunSinkContext()
  let sessionID = SessionID("s-startclr")
  let startInfo = AgentRunStartInfo(
    context: context,
    issue: issue,
    provider: "codex",
    sessionID: sessionID,
    workspacePath: "/tmp/ws"
  )
  sink.runDidStart(startInfo)
  let startedBefore = sink.testingStartedAt(for: context.runID)

  // Complete → clearState removes startedAtByRunID[runID]
  sink.runDidComplete(AgentRunResult(
    context: context,
    sessionID: sessionID,
    finalState: .succeeded,
    eventCount: 0,
    error: nil
  ))

  // After clear, startedAt for this runID fallback returns a fresh timestamp
  let startedAfter = sink.testingStartedAt(for: context.runID)
  // The original timestamp was recorded at start; after clear, a new ISO8601 timestamp is returned.
  // They must differ because the clear removed the stored one.
  #expect(startedBefore != startedAfter)
}

@Test func clearStateRemovesStartInfoSoTransitionIsNoOp() throws {
  let databaseURL = try makeAgentRunSinkTemporaryDirectory()
    .appendingPathComponent("sink-trnoop.sqlite3")
  let store = try SQLiteServerStateStore(databaseURL: databaseURL)
  let sink = SQLiteAgentRunEventSink(store: store)

  let issue = try makeAgentRunSinkIssue()
  let context = try makeAgentRunSinkContext()
  let sessionID = SessionID("s-trnoop")
  let startInfo = AgentRunStartInfo(
    context: context,
    issue: issue,
    provider: "codex",
    sessionID: sessionID,
    workspacePath: "/tmp/ws"
  )
  sink.runDidStart(startInfo)

  // Complete → clearState removes startInfoByRunID[runID]
  sink.runDidComplete(AgentRunResult(
    context: context,
    sessionID: sessionID,
    finalState: .succeeded,
    eventCount: 0,
    error: nil
  ))

  let detailAtCompletion = try #require(try store.runDetail(id: context.runID))
  let statusAtCompletion = detailAtCompletion.status

  // After clear, a transition attempt for the same runID should be a no-op
  // because recordTransition's startInfoByRunID[context.runID] returns nil.
  sink.runDidTransition(context, to: .buildingPrompt)

  let detailAfter = try #require(try store.runDetail(id: context.runID))
  // Status should NOT have changed (transition was no-op)
  #expect(detailAfter.status == statusAtCompletion)
}

// ──────────────────────────────────────────────────────────────────────────────
// SQLiteAgentRunEventSink — persistTransition endedAt ternary
//
// Muter mutates `state.isTerminal ? Self.timestampString() : nil` in
// persistTransition. The SwapTernary mutation would set endedAt=nil for terminal
// states and endedAt=timestamp for non-terminal states.
// ──────────────────────────────────────────────────────────────────────────────

@Test func nonTerminalTransitionHasNilEndedAtAndTerminalSetsEndedAt() throws {
  let databaseURL = try makeAgentRunSinkTemporaryDirectory()
    .appendingPathComponent("sink-term.sqlite3")
  let store = try SQLiteServerStateStore(databaseURL: databaseURL)
  let sink = SQLiteAgentRunEventSink(store: store)

  let issue = try makeAgentRunSinkIssue()
  let context = try makeAgentRunSinkContext()
  let startInfo = AgentRunStartInfo(
    context: context,
    issue: issue,
    provider: "codex",
    sessionID: SessionID("s-term"),
    workspacePath: "/tmp/ws"
  )
  sink.runDidStart(startInfo)

  // Non-terminal transition: endedAt must be nil
  sink.runDidTransition(context, to: .streamingTurn)
  let nonTerminal = try #require(try store.runDetail(id: context.runID))
  #expect(nonTerminal.endedAt == nil)

  // Terminal transition: endedAt must be set
  sink.runDidTransition(context, to: .succeeded)
  let terminal = try #require(try store.runDetail(id: context.runID))
  #expect(terminal.endedAt != nil)
}

// ──────────────────────────────────────────────────────────────────────────────
// SQLiteAgentRunEventSink — testingClearEventCount verification
//
// Muter can remove the `eventCountByRunID.removeValue(forKey: runID)` call.
// ──────────────────────────────────────────────────────────────────────────────

@Test func testingClearEventCountResetsSnapshotCountToZero() throws {
  let databaseURL = try makeAgentRunSinkTemporaryDirectory()
    .appendingPathComponent("sink-clrev.sqlite3")
  let store = try SQLiteServerStateStore(databaseURL: databaseURL)
  let sink = SQLiteAgentRunEventSink(store: store)

  let issue = try makeAgentRunSinkIssue()
  let context = try makeAgentRunSinkContext()
  let startInfo = AgentRunStartInfo(
    context: context,
    issue: issue,
    provider: "codex",
    sessionID: SessionID("s-clrev"),
    workspacePath: "/tmp/ws"
  )
  sink.runDidStart(startInfo)

  // Send 3 events
  for i in 0..<3 {
    sink.runDidReceiveEvent(AgentRawEvent(
      sessionID: startInfo.sessionID,
      provider: "codex",
      sequence: EventSequence(i),
      timestamp: "2026-01-01T00:00:0\(i)Z",
      rawJSON: "{}",
      providerEventType: "status",
      normalizedEventKind: "status"
    ))
  }
  #expect(sink.testingSnapshot(for: context.runID).count == 3)

  // Clear the event count
  sink.testingClearEventCount(for: context.runID)
  #expect(sink.testingSnapshot(for: context.runID).count == 0)

  // Next event should start from 0+1 = 1 (not 3+1 = 4)
  sink.runDidReceiveEvent(AgentRawEvent(
    sessionID: startInfo.sessionID,
    provider: "codex",
    sequence: EventSequence(3),
    timestamp: "2026-01-01T00:00:03Z",
    rawJSON: "{}",
    providerEventType: "message",
    normalizedEventKind: "message"
  ))
  #expect(sink.testingSnapshot(for: context.runID).count == 1)
}

// ──────────────────────────────────────────────────────────────────────────────
// SQLiteAgentRunEventSink — providerSnapshot for unknown runID
//
// Kills the nil-coalescing mutation in `providerSnapshot(for:)`.
// ──────────────────────────────────────────────────────────────────────────────

@Test func providerSnapshotForUnknownRunIDReturnsEmptyDefaults() throws {
  let databaseURL = try makeAgentRunSinkTemporaryDirectory()
    .appendingPathComponent("sink-unkps.sqlite3")
  let store = try SQLiteServerStateStore(databaseURL: databaseURL)
  let sink = SQLiteAgentRunEventSink(store: store)

  let unknown = RunID("R_never_started")
  let snap = sink.testingProviderSnapshot(for: unknown)
  #expect(snap.providerSessionID == nil)
  #expect(snap.providerThreadID == nil)
  #expect(snap.providerTurnID == nil)
  #expect(snap.providerRunID == nil)
  #expect(snap.tokenUsage.inputTokens == nil)
  #expect(snap.tokenUsage.outputTokens == nil)
  #expect(snap.latestRateLimitPayload == nil)
  #expect(snap.lastAgentMessage == nil)
  #expect(snap.latestSequence == nil)
}

// ──────────────────────────────────────────────────────────────────────────────
// EventKindInference — CopilotCLI inference precedence and fallback
//
// Muter targets the ordering of checks in inferCopilotCLI:
//   1. method == approval/permission → .approvalRequest
//   2. method == session/update → .status
//   3. stopReason != nil → .status
//   4. error != nil → .error
//   5. guard type ?? event → switch
//
// Tests verify each check can't be removed/reordered without detection.
// ──────────────────────────────────────────────────────────────────────────────

@Test func copilotCLIStopReasonPrecedesErrorCheck() {
  // Message has BOTH stopReason and error — stopReason check comes first
  let kind = EventKindInference.infer(
    from: #"{"result":{"stopReason":"end_turn"},"error":{"message":"oops"}}"#,
    provider: .copilotCLI
  )
  // stopReason check (line ~200) returns .status before error check (line ~203)
  #expect(kind == .status)
}

@Test func copilotCLIErrorAloneReturnsError() {
  let kind = EventKindInference.infer(
    from: #"{"error":{"message":"fatal"}}"#,
    provider: .copilotCLI
  )
  #expect(kind == .error)
}

@Test func copilotCLIEventFieldFallbackWhenTypeIsNil() {
  // type is nil but event is set — guard uses nil coalescing (type ?? event)
  let message = EventKindInference.infer(
    from: #"{"event":"message"}"#,
    provider: .copilotCLI
  )
  #expect(message == .message)

  let toolCall = EventKindInference.infer(
    from: #"{"event":"tool_call"}"#,
    provider: .copilotCLI
  )
  #expect(toolCall == .toolCall)

  let usage = EventKindInference.infer(
    from: #"{"event":"usage"}"#,
    provider: .copilotCLI
  )
  #expect(usage == .usage)
}

@Test func copilotCLINeitherTypeNorEventReturnsUnknown() {
  // Neither type nor event → guard returns .unknown
  let kind = EventKindInference.infer(
    from: #"{"params":{"data":"ok"}}"#,
    provider: .copilotCLI
  )
  #expect(kind == .unknown)
}

@Test func copilotCLIMethodCheckPrecedesStopReasonAndError() {
  // Method is "requestPermission" with stopReason — method check wins
  let kind = EventKindInference.infer(
    from: #"{"method":"requestPermission","result":{"stopReason":"end_turn"}}"#,
    provider: .copilotCLI
  )
  #expect(kind == .approvalRequest)

  // Method is "sessionUpdate" with error — method check wins
  let kind2 = EventKindInference.infer(
    from: #"{"method":"sessionUpdate","error":{"code":1}}"#,
    provider: .copilotCLI
  )
  #expect(kind2 == .status)
}

// ──────────────────────────────────────────────────────────────────────────────
// EventKindInference — isTerminalEvent copilotCLI || operator
//
// Muter ChangeLogicalConnector targets `msg.resultString("stopReason") != nil || msg.error != nil`
// on line ~273. If || becomes &&, then messages with ONLY stopReason (and no error)
// would return false. Similarly for ONLY error.
// ──────────────────────────────────────────────────────────────────────────────

@Test func copilotCLITerminalWithOnlyStopReasonNoError() {
  let desc = ProviderEventInspection.describe(
    from: #"{"result":{"stopReason":"end_turn"}}"#, provider: .copilotCLI
  )
  #expect(desc.isTerminal == true)
  // Also verify normalizedKind is .status (from inferCopilotCLI)
  #expect(desc.normalizedKind == .status)
}

@Test func copilotCLITerminalWithOnlyErrorNoStopReason() {
  let desc = ProviderEventInspection.describe(
    from: #"{"error":{"message":"crash"}}"#, provider: .copilotCLI
  )
  #expect(desc.isTerminal == true)
  #expect(desc.normalizedKind == .error)
}

@Test func copilotCLINonTerminalWithNeitherStopReasonNorError() {
  let desc = ProviderEventInspection.describe(
    from: #"{"type":"message","data":"hello"}"#, provider: .copilotCLI
  )
  #expect(desc.isTerminal == false)
  #expect(desc.normalizedKind == .message)
}

// ──────────────────────────────────────────────────────────────────────────────
// EventKindInference — isTerminalEvent codex individual method strings
//
// Muter can remove individual strings from the terminal event list.
// Each terminal method must be tested individually to kill those mutations.
// ──────────────────────────────────────────────────────────────────────────────

@Test func codexEachTerminalMethodReturnsTrueIndividually() {
  let terminals = ["turn/completed", "turn/failed", "turn/cancelled", "turn/interrupted"]
  for method in terminals {
    let desc = ProviderEventInspection.describe(
      from: #"{"method":"\#(method)"}"#, provider: .codex
    )
    #expect(desc.isTerminal == true, "Expected \(method) to be terminal")
  }

  // Non-terminal methods must be false
  let nonTerminals = ["turn/started", "thread/start", "item/started", "initialized"]
  for method in nonTerminals {
    let desc = ProviderEventInspection.describe(
      from: #"{"method":"\#(method)"}"#, provider: .codex
    )
    #expect(desc.isTerminal == false, "Expected \(method) to be non-terminal")
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// EventKindInference — claudeCode individual terminal type strings
//
// Muter can remove "result" or "error" from the list individually.
// ──────────────────────────────────────────────────────────────────────────────

@Test func claudeCodeEachTerminalTypeReturnsTrueIndividually() {
  let resultDesc = ProviderEventInspection.describe(
    from: #"{"type":"result"}"#, provider: .claudeCode
  )
  #expect(resultDesc.isTerminal == true)

  let errorDesc = ProviderEventInspection.describe(
    from: #"{"type":"error"}"#, provider: .claudeCode
  )
  #expect(errorDesc.isTerminal == true)

  // Non-terminal types
  for nonTerm in ["message", "tool_use", "tool_result", "system", "status", "usage"] {
    let desc = ProviderEventInspection.describe(
      from: #"{"type":"\#(nonTerm)"}"#, provider: .claudeCode
    )
    #expect(desc.isTerminal == false, "Expected \(nonTerm) to be non-terminal for claudeCode")
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// EventKindInference — codexApprovalLikeIdentifier negative cases
//
// Muter ChangeLogicalConnector mutations on && operators. If && becomes ||,
// then partial matches like "filechange" alone would incorrectly return true.
// These negative tests kill those mutations.
// ──────────────────────────────────────────────────────────────────────────────

@Test func approvalLikeNegativeJustToolNoUnsupported() {
  // "tool" alone without "unsupported" should NOT match the split-token check
  let kind = EventKindInference.infer(
    from: #"{"type":"tool_action"}"#,
    provider: .codex
  )
  #expect(kind != .approvalRequest)
}

@Test func approvalLikeNegativeUnsupportedWithoutTool() {
  // "unsupported_action" has "unsupported" but not "tool"
  let kind = EventKindInference.infer(
    from: #"{"type":"unsupported_action"}"#,
    provider: .codex
  )
  #expect(kind != .approvalRequest)
}

@Test func approvalLikeNegativeApprovalWithoutFileChangeOrPermission() {
  // "approval" alone doesn't match any block
  let kind = EventKindInference.infer(
    from: #"{"type":"approval"}"#,
    provider: .codex
  )
  #expect(kind != .approvalRequest)
}

@Test func approvalLikeNegativeRequestWithoutFileChangeOrPermission() {
  // "request" alone doesn't match any compound block
  let kind = EventKindInference.infer(
    from: #"{"type":"request"}"#,
    provider: .codex
  )
  #expect(kind != .approvalRequest)
}
