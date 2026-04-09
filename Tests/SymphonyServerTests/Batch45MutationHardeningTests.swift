// Batch 45 — Non-UTF-8 output guard tests for provider adapters.
//
// Targets:
//   ClaudeCodeAdapter.swift — guard let output = String(data:encoding:.utf8) else { return }
//   CopilotCLIAdapter.swift — same guard
//   CodexAdapter.swift — same guard
//
// Previously untestable because StubLaunchedProcess.simulateOutput accepted
// only String. Batch 45 adds simulateRawOutput(_:Data) to inject non-UTF-8
// bytes and verify the guard early-returns without producing events.

import Foundation
import SymphonyShared
import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore

// MARK: - Non-UTF-8 Output Guard

/// Invalid UTF-8 byte sequence: lone continuation byte followed by overlong.
private let invalidUTF8: Data = Data([0x80, 0xC0, 0xAF, 0xFF])

@Suite("ClaudeCodeAdapter non-UTF-8 output guard")
struct ClaudeCodeAdapterNonUTF8Tests {

  @Test func nonUTF8OutputIsDiscardedSilently() async throws {
    let stubProcess = StubLaunchedProcess()
    let adapter = ClaudeCodeAdapter(config: .defaults)

    let stream = adapter.makeEventStream(from: stubProcess, sessionID: SessionID("s-utf8"))

    // Send invalid bytes that cannot be decoded as UTF-8.
    stubProcess.simulateRawOutput(invalidUTF8)

    // Terminate cleanly so the stream ends.
    stubProcess.simulateTermination(exitCode: 0)

    var events: [AgentRawEvent] = []
    for try await event in stream {
      events.append(event)
    }
    #expect(events.isEmpty, "Non-UTF-8 output must be silently discarded")
  }

  @Test func mixedValidAndInvalidOutputOnlyProducesEventsForValid() async throws {
    let stubProcess = StubLaunchedProcess()
    let adapter = ClaudeCodeAdapter(config: .defaults)

    let stream = adapter.makeEventStream(from: stubProcess, sessionID: SessionID("s-mixed"))

    // First: invalid bytes → discarded.
    stubProcess.simulateRawOutput(invalidUTF8)
    // Second: valid JSON line → should produce an event.
    stubProcess.simulateOutput("{\"type\":\"system\",\"message\":\"hello\"}\n")
    stubProcess.simulateTermination(exitCode: 0)

    var events: [AgentRawEvent] = []
    for try await event in stream {
      events.append(event)
    }
    #expect(events.count >= 1, "Valid output after invalid must still be processed")
  }
}

@Suite("CopilotCLIAdapter non-UTF-8 output guard")
struct CopilotCLIAdapterNonUTF8Tests {

  @Test func nonUTF8OutputIsDiscardedSilently() async throws {
    let stubProcess = StubLaunchedProcess()
    let adapter = CopilotCLIAdapter(config: .defaults, processLauncher: StubProcessLauncher())

    let stream = adapter.makeEventStream(from: stubProcess, sessionID: SessionID("s-utf8"))

    stubProcess.simulateRawOutput(invalidUTF8)
    stubProcess.simulateTermination(exitCode: 0)

    var events: [AgentRawEvent] = []
    for try await event in stream {
      events.append(event)
    }
    #expect(events.isEmpty, "Non-UTF-8 output must be silently discarded")
  }

  @Test func mixedValidAndInvalidOutputOnlyProducesEventsForValid() async throws {
    let stubProcess = StubLaunchedProcess()
    let adapter = CopilotCLIAdapter(config: .defaults, processLauncher: StubProcessLauncher())

    let stream = adapter.makeEventStream(from: stubProcess, sessionID: SessionID("s-mixed"))

    stubProcess.simulateRawOutput(invalidUTF8)
    stubProcess.simulateOutput("{\"type\":\"system\",\"message\":\"hello\"}\n")
    stubProcess.simulateTermination(exitCode: 0)

    var events: [AgentRawEvent] = []
    for try await event in stream {
      events.append(event)
    }
    #expect(events.count >= 1, "Valid output after invalid must still be processed")
  }
}

@Suite("CodexAdapter non-UTF-8 output guard")
struct CodexAdapterNonUTF8Tests {

  @Test func nonUTF8OutputIsDiscardedSilently() async throws {
    let stubProcess = StubLaunchedProcess()
    let stubLauncher = StubProcessLauncher()
    let adapter = CodexAdapter(config: .defaults, processLauncher: stubLauncher)

    let stream = adapter.makeEventStream(from: stubProcess, sessionID: SessionID("s-utf8"))

    stubProcess.simulateRawOutput(invalidUTF8)
    stubProcess.simulateTermination(exitCode: 0)

    var events: [AgentRawEvent] = []
    for try await event in stream {
      events.append(event)
    }
    #expect(events.isEmpty, "Non-UTF-8 output must be silently discarded")
  }

  @Test func mixedValidAndInvalidOutputOnlyProducesEventsForValid() async throws {
    let stubProcess = StubLaunchedProcess()
    let stubLauncher = StubProcessLauncher()
    let adapter = CodexAdapter(config: .defaults, processLauncher: stubLauncher)

    let stream = adapter.makeEventStream(from: stubProcess, sessionID: SessionID("s-mixed"))

    stubProcess.simulateRawOutput(invalidUTF8)
    // Codex uses line-buffered output; send a complete JSON line.
    stubProcess.simulateOutput("{\"type\":\"status\",\"status\":\"running\"}\n")
    stubProcess.simulateTermination(exitCode: 0)

    var events: [AgentRawEvent] = []
    for try await event in stream {
      events.append(event)
    }
    #expect(events.count >= 1, "Valid output after invalid must still be processed")
  }
}

// MARK: - StubLaunchedProcess simulateRawOutput

@Suite("StubLaunchedProcess raw output")
struct StubLaunchedProcessRawOutputTests {

  @Test func simulateRawOutputInvokesHandlerWithExactBytes() {
    let process = StubLaunchedProcess()
    nonisolated(unsafe) var received: Data?
    process.onOutput { data in
      received = data
    }

    let raw = Data([0xFF, 0xFE, 0x00, 0x01])
    process.simulateRawOutput(raw)
    #expect(received == raw)
  }

  @Test func simulateRawOutputWithNoHandlerDoesNotCrash() {
    let process = StubLaunchedProcess()
    // No onOutput registered — should not crash.
    process.simulateRawOutput(Data([0x80]))
  }
}
