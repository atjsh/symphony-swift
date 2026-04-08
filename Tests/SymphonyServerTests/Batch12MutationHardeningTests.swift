import Foundation
import SymphonyShared
import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore

// MARK: - StubLaunchedProcess Mutation Hardening

@Suite("StubLaunchedProcess Idempotency")
struct StubLaunchedProcessIdempotencyTests {

  @Test func interruptAfterTerminateIsNoOp() {
    let process = StubLaunchedProcess()
    process.terminate()
    #expect(process.interruptCount == 0)
    process.interrupt()
    #expect(process.interruptCount == 0)
  }

  @Test func simulateTerminationAfterTerminateIsNoOp() {
    let process = StubLaunchedProcess()
    nonisolated(unsafe) var exitCodes = [Int32]()
    process.onTermination { code in
      exitCodes.append(code)
    }
    process.terminate()
    #expect(exitCodes == [15])
    process.simulateTermination(exitCode: 0)
    #expect(exitCodes == [15])
    #expect(process.terminationCount == 1)
  }

  @Test func simulateTerminationAfterSimulateTerminationIsNoOp() {
    let process = StubLaunchedProcess()
    nonisolated(unsafe) var exitCodes = [Int32]()
    process.onTermination { code in
      exitCodes.append(code)
    }
    process.simulateTermination(exitCode: 42)
    #expect(exitCodes == [42])
    process.simulateTermination(exitCode: 99)
    #expect(exitCodes == [42])
    #expect(process.terminationCount == 1)
  }

  @Test func terminateAfterSimulateTerminationIsNoOp() {
    let process = StubLaunchedProcess()
    nonisolated(unsafe) var exitCodes = [Int32]()
    process.onTermination { code in
      exitCodes.append(code)
    }
    process.simulateTermination(exitCode: 7)
    #expect(exitCodes == [7])
    process.terminate()
    #expect(exitCodes == [7])
    #expect(process.terminationCount == 1)
  }

  @Test func terminateCallsHandlerWithExitCode15() {
    let process = StubLaunchedProcess()
    nonisolated(unsafe) var receivedCode: Int32?
    process.onTermination { code in
      receivedCode = code
    }
    process.terminate()
    #expect(receivedCode == 15)
  }
}

// MARK: - StubLaunchedProcess sendInput turn/interrupt

@Suite("StubLaunchedProcess SendInput JSON")
struct StubLaunchedProcessSendInputJSONTests {

  @Test func sendInputWithTurnInterruptIncrementsInterruptCount() throws {
    let process = StubLaunchedProcess()
    let message = #"{"jsonrpc":"2.0","method":"turn/interrupt","id":1}"#
    try process.sendInput(Data(message.utf8))
    #expect(process.interruptCount == 1)
    #expect(process.recordedInputStrings == [message])
  }

  @Test func sendInputWithNonInterruptMethodDoesNotIncrementInterruptCount() throws {
    let process = StubLaunchedProcess()
    let message = #"{"jsonrpc":"2.0","method":"turn/submit","id":1}"#
    try process.sendInput(Data(message.utf8))
    #expect(process.interruptCount == 0)
    #expect(process.recordedInputStrings == [message])
  }

  @Test func sendInputWithNonJSONDoesNotIncrementInterruptCount() throws {
    let process = StubLaunchedProcess()
    try process.sendInput(Data("plain text\n".utf8))
    #expect(process.interruptCount == 0)
    #expect(process.recordedInputStrings.count == 1)
  }

  @Test func sendInputWithInputErrorThrows() {
    let process = StubLaunchedProcess()
    let expectedError = NSError(domain: "test", code: 42)
    process.setInputError(expectedError)
    #expect(throws: Error.self) {
      try process.sendInput(Data("hello".utf8))
    }
  }
}

// MARK: - StubProcessLauncher Queue Behavior

@Suite("StubProcessLauncher Queue")
struct StubProcessLauncherQueueTests {

  @Test func launchReturnsDefaultStubWhenQueueEmpty() throws {
    let launcher = StubProcessLauncher()
    let process = try launcher.launch(
      command: "echo ok",
      workspacePath: "/tmp",
      environment: ["KEY": "VAL"]
    )
    #expect(process is StubLaunchedProcess)
    #expect(launcher.invocations.count == 1)
    #expect(launcher.invocations[0].command == "echo ok")
    #expect(launcher.invocations[0].environment["KEY"] == "VAL")
  }

  @Test func launchConsumesStubProcessesInOrder() throws {
    let launcher = StubProcessLauncher()
    let first = StubLaunchedProcess()
    let second = StubLaunchedProcess()
    launcher.setStubProcesses([first, second])
    let r1 = try launcher.launch(command: "a", workspacePath: "/", environment: [:])
    let r2 = try launcher.launch(command: "b", workspacePath: "/", environment: [:])
    #expect(r1 as? StubLaunchedProcess === first)
    #expect(r2 as? StubLaunchedProcess === second)
  }

  @Test func launchThrowsWhenErrorSet() {
    let launcher = StubProcessLauncher()
    let expectedError = NSError(domain: "test", code: 99)
    launcher.setLaunchError(expectedError)
    #expect(throws: Error.self) {
      try launcher.launch(command: "fail", workspacePath: "/", environment: [:])
    }
    #expect(launcher.invocations.count == 1)
  }
}

// MARK: - ProviderSessionSnapshotExtractor Type Conversion Hardening

@Suite("SnapshotExtractor Type Conversions")
struct SnapshotExtractorTypeConversionTests {

  @Test func intValueFromDoubleIsTruncated() {
    let value = JSONValue.object([
      "usage": .object(["input_tokens": .double(42.9)])
    ])
    let usage = ProviderSessionSnapshotExtractor.tokenUsage(from: value)
    #expect(usage?.inputTokens == 42)
  }

  @Test func intValueFromStringParses() {
    let value = JSONValue.object([
      "usage": .object(["output_tokens": .string("300")])
    ])
    let usage = ProviderSessionSnapshotExtractor.tokenUsage(from: value)
    #expect(usage?.outputTokens == 300)
  }

  @Test func intValueFromNonNumericStringReturnsNil() {
    let value = JSONValue.object([
      "usage": .object(["input_tokens": .string("abc")])
    ])
    let usage = ProviderSessionSnapshotExtractor.tokenUsage(from: value)
    #expect(usage == nil)
  }

  @Test func stringValueFromIntConverts() {
    let event = AgentRawEvent(
      sessionID: SessionID("s1"),
      provider: "test",
      sequence: EventSequence(1),
      timestamp: "2026-01-01T00:00:00Z",
      rawJSON: #"{"session_id":12345}"#,
      providerEventType: "status",
      normalizedEventKind: "status"
    )
    let update = ProviderSessionSnapshotExtractor.update(
      from: event, storedSequence: EventSequence(1))
    #expect(update.providerSessionID == "12345")
  }

  @Test func stringValueFromDoubleConverts() {
    let event = AgentRawEvent(
      sessionID: SessionID("s1"),
      provider: "test",
      sequence: EventSequence(1),
      timestamp: "2026-01-01T00:00:00Z",
      rawJSON: #"{"session_id":3.14}"#,
      providerEventType: "status",
      normalizedEventKind: "status"
    )
    let update = ProviderSessionSnapshotExtractor.update(
      from: event, storedSequence: EventSequence(1))
    #expect(update.providerSessionID == "3.14")
  }

  @Test func stringValueWhitespaceOnlyReturnsNil() {
    let event = AgentRawEvent(
      sessionID: SessionID("s1"),
      provider: "test",
      sequence: EventSequence(1),
      timestamp: "2026-01-01T00:00:00Z",
      rawJSON: #"{"session_id":"  \n  "}"#,
      providerEventType: "status",
      normalizedEventKind: "status"
    )
    let update = ProviderSessionSnapshotExtractor.update(
      from: event, storedSequence: EventSequence(1))
    #expect(update.providerSessionID == nil)
  }
}

// MARK: - ProviderSessionSnapshotExtractor messageText Key Coverage

@Suite("SnapshotExtractor MessageText Keys")
struct SnapshotExtractorMessageTextKeyTests {

  @Test func messageTextFromPayloadKey() {
    let value = JSONValue.object([
      "payload": .string("payload text")
    ])
    let text = ProviderSessionSnapshotExtractor.messageText(from: value)
    #expect(text == "payload text")
  }

  @Test func messageTextFromDataKey() {
    let value = JSONValue.object([
      "data": .string("data text")
    ])
    let text = ProviderSessionSnapshotExtractor.messageText(from: value)
    #expect(text == "data text")
  }

  @Test func messageTextPrefersMessageOverPayload() {
    let value = JSONValue.object([
      "payload": .string("secondary"),
      "message": .string("primary"),
    ])
    let text = ProviderSessionSnapshotExtractor.messageText(from: value)
    #expect(text == "primary")
  }

  @Test func messageTextFromNestedPayload() {
    let value = JSONValue.object([
      "payload": .object(["content": .string("deep payload")])
    ])
    let text = ProviderSessionSnapshotExtractor.messageText(from: value)
    #expect(text == "deep payload")
  }
}

// MARK: - ProviderSessionSnapshotExtractor Root-Level Token Fallback

@Suite("SnapshotExtractor Token Fallback")
struct SnapshotExtractorTokenFallbackTests {

  @Test func rootLevelTokenFieldsExtractedWithoutNestedKey() {
    let value = JSONValue.object([
      "input_tokens": .int(50),
      "output_tokens": .int(75),
    ])
    let usage = ProviderSessionSnapshotExtractor.tokenUsage(from: value)
    #expect(usage?.inputTokens == 50)
    #expect(usage?.outputTokens == 75)
  }

  @Test func nestedTokenUsageTakesPrecedenceOverRootLevel() {
    let value = JSONValue.object([
      "input_tokens": .int(999),
      "usage": .object([
        "input_tokens": .int(10),
        "output_tokens": .int(20),
      ]),
    ])
    let usage = ProviderSessionSnapshotExtractor.tokenUsage(from: value)
    #expect(usage?.inputTokens == 10)
    #expect(usage?.outputTokens == 20)
  }
}

// MARK: - SQLiteAgentRunEventSink Event for Unknown Session

@Suite("EventSink Unknown Session Guard")
struct EventSinkUnknownSessionGuardTests {

  @Test func eventCountDefaultsToZeroForNewRun() throws {
    let databaseURL = try makeAgentRunSinkTemporaryDirectory()
      .appendingPathComponent("sink-default-count.sqlite3")
    let store = try SQLiteServerStateStore(databaseURL: databaseURL)
    let sink = SQLiteAgentRunEventSink(store: store)

    let context = try makeAgentRunSinkContext(runID: "R_default")
    let snapshot = sink.testingSnapshot(for: context.runID)
    #expect(snapshot.count == 0)
    #expect(snapshot.type == nil)
    #expect(snapshot.time == nil)
  }

  @Test func clearStateRemovesAllDictionaryEntries() throws {
    let databaseURL = try makeAgentRunSinkTemporaryDirectory()
      .appendingPathComponent("sink-clear.sqlite3")
    let store = try SQLiteServerStateStore(databaseURL: databaseURL)
    let sink = SQLiteAgentRunEventSink(store: store)

    let issue = try makeAgentRunSinkIssue()
    let context = try makeAgentRunSinkContext(runID: "R_clear")
    let startInfo = AgentRunStartInfo(
      context: context,
      issue: issue,
      provider: "codex",
      sessionID: SessionID("s-clear"),
      workspacePath: "/tmp/ws"
    )
    sink.runDidStart(startInfo)
    sink.runDidTransition(context, to: .streamingTurn)

    sink.runDidReceiveEvent(AgentRawEvent(
      sessionID: startInfo.sessionID,
      provider: "codex",
      sequence: EventSequence(1),
      timestamp: "2026-01-01T00:00:01Z",
      rawJSON: #"{"n":1}"#,
      providerEventType: "message",
      normalizedEventKind: "message"
    ))
    #expect(sink.testingSnapshot(for: context.runID).count == 1)

    let result = AgentRunResult(
      context: context,
      sessionID: startInfo.sessionID,
      finalState: .succeeded,
      eventCount: 1,
      error: nil
    )
    sink.runDidComplete(result)

    let snapshotAfter = sink.testingSnapshot(for: context.runID)
    #expect(snapshotAfter.count == 0)
    #expect(snapshotAfter.type == nil)
    #expect(snapshotAfter.time == nil)

    let providerSnap = sink.testingProviderSnapshot(for: context.runID)
    #expect(providerSnap.providerSessionID == nil)
    #expect(providerSnap.latestSequence == nil)
    #expect(providerSnap.tokenUsage == .empty)
  }

  @Test func startedAtFallbackWhenRunIDNotRegistered() throws {
    let databaseURL = try makeAgentRunSinkTemporaryDirectory()
      .appendingPathComponent("sink-startedAt.sqlite3")
    let store = try SQLiteServerStateStore(databaseURL: databaseURL)
    let sink = SQLiteAgentRunEventSink(store: store)

    let timestamp = sink.testingStartedAt(for: RunID("unknown"))
    #expect(!timestamp.isEmpty)
    #expect(timestamp.contains("T"))
  }
}

// MARK: - SQLiteAgentRunEventSink Initialization Guards

@Suite("EventSink Initialization Guards")
struct EventSinkInitializationGuardTests {

  @Test func doubleStartDoesNotOverwriteExistingEventCount() throws {
    let databaseURL = try makeAgentRunSinkTemporaryDirectory()
      .appendingPathComponent("sink-double-start.sqlite3")
    let store = try SQLiteServerStateStore(databaseURL: databaseURL)
    let sink = SQLiteAgentRunEventSink(store: store)

    let issue = try makeAgentRunSinkIssue()
    let context = try makeAgentRunSinkContext(runID: "R_double")
    let startInfo = AgentRunStartInfo(
      context: context,
      issue: issue,
      provider: "codex",
      sessionID: SessionID("s-double"),
      workspacePath: "/tmp/ws"
    )
    sink.runDidStart(startInfo)
    sink.runDidTransition(context, to: .streamingTurn)

    sink.runDidReceiveEvent(AgentRawEvent(
      sessionID: startInfo.sessionID,
      provider: "codex",
      sequence: EventSequence(1),
      timestamp: "2026-01-01T00:00:01Z",
      rawJSON: #"{"n":1}"#,
      providerEventType: "message",
      normalizedEventKind: "message"
    ))
    #expect(sink.testingSnapshot(for: context.runID).count == 1)

    let startInfo2 = AgentRunStartInfo(
      context: context,
      issue: issue,
      provider: "codex",
      sessionID: SessionID("s-double-2"),
      workspacePath: "/tmp/ws"
    )
    sink.runDidStart(startInfo2)

    #expect(sink.testingSnapshot(for: context.runID).count == 1)
  }

  @Test func doubleStartDoesNotOverwriteExistingProviderSnapshot() throws {
    let databaseURL = try makeAgentRunSinkTemporaryDirectory()
      .appendingPathComponent("sink-snapshot-preserve.sqlite3")
    let store = try SQLiteServerStateStore(databaseURL: databaseURL)
    let sink = SQLiteAgentRunEventSink(store: store)

    let issue = try makeAgentRunSinkIssue()
    let context = try makeAgentRunSinkContext(runID: "R_snap")
    let startInfo = AgentRunStartInfo(
      context: context,
      issue: issue,
      provider: "codex",
      sessionID: SessionID("s-snap"),
      workspacePath: "/tmp/ws"
    )
    sink.runDidStart(startInfo)

    sink.testingMergeProviderSnapshot(
      for: context.runID,
      providerSessionID: "sess-existing"
    )
    let before = sink.testingProviderSnapshot(for: context.runID)
    #expect(before.providerSessionID == "sess-existing")

    let startInfo2 = AgentRunStartInfo(
      context: context,
      issue: issue,
      provider: "codex",
      sessionID: SessionID("s-snap-2"),
      workspacePath: "/tmp/ws"
    )
    sink.runDidStart(startInfo2)

    let after = sink.testingProviderSnapshot(for: context.runID)
    #expect(after.providerSessionID == "sess-existing")
  }
}
