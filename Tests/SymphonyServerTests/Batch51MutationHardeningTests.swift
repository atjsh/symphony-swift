// Batch 51 — RemoveSideEffects mutation hardening.
//
// Targets the following surviving mutations:
//
// CodexAdapter.swift — cancelSession (non-interrupt path):
//   RemoveSideEffects on sessionRegistry.remove(sessionID:) at ~L165.
//   Killed by verifying a reused sessionID gets a fresh state with nil threadID.
//
// CodexAdapter.swift — makeEventStream finishSuccessfully closure:
//   RemoveSideEffects on self.sessionRegistry.remove(sessionID:) at ~L204.
//   Killed by verifying registry cleanup after stream ends from terminal event (.completed).
//
// CodexAdapter.swift — makeEventStream finishWithError closure:
//   RemoveSideEffects on self.sessionRegistry.remove(sessionID:) at ~L195.
//   Killed by verifying registry cleanup after stream ends from terminal event (.failed).
//
// CodexAdapter.swift — makeEventStream process.onTermination:
//   RemoveSideEffects on self.sessionRegistry.remove(sessionID:) at ~L257.
//   Killed by verifying registry cleanup after process exits without terminal event.
//
// Strategy: After registry cleanup, start a new session with the same sessionID.
// The registry's state(for:) returns existing state if present, or creates a fresh one.
// If the old state leaked (remove was deleted), the stale threadID persists and
// continueSession succeeds with stale data. If properly cleaned, continueSession
// throws sessionNotFound because the fresh state has nil threadID.

import Foundation
import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore
@testable import SymphonyShared

// Disable timeouts so they don't interfere with session-reuse tests.
private let noTimeoutConfig = CodexProviderConfig(
  readTimeoutMS: 0,
  stallTimeoutMS: 0
)

// MARK: - CodexAdapter cancelSession Registry Cleanup

@Suite("CodexAdapter cancelSession Registry Cleanup")
struct CodexAdapterCancelSessionRegistryCleanupTests {

  // Kills RemoveSideEffects on sessionRegistry.remove(sessionID:) in cancelSession.
  // If the remove is deleted, the old CodexSessionState—with its stale threadID—
  // persists across the second startSession, and continueSession succeeds with
  // the stale threadID instead of throwing.
  @Test func reusedSessionGetsCleanRegistryAfterCancel() async throws {
    let launcher = StubProcessLauncher()
    let process1 = StubLaunchedProcess()
    let process2 = StubLaunchedProcess()
    launcher.setStubProcesses([process1, process2])

    let adapter = CodexAdapter(config: noTimeoutConfig, processLauncher: launcher)
    let sid = SessionID("s-reg-cancel")

    // First session: establish a threadID in the registry
    _ = try await adapter.startSession(
      sessionID: sid,
      workspacePath: "/tmp/ws",
      prompt: "Fix bug",
      environment: [:]
    )
    process1.simulateOutput(
      #"{"method":"thread/started","params":{"thread":{"id":"thread-old"}}}"# + "\n")

    // Cancel (no turnID known → interruptSession returns false → falls through)
    try await adapter.cancelSession(sessionID: sid)

    // Second session with same ID — fresh state should have nil threadID
    _ = try await adapter.startSession(
      sessionID: sid,
      workspacePath: "/tmp/ws",
      prompt: "Again",
      environment: [:]
    )
    // DON'T simulate thread/started on process2

    // continueSession should throw: no threadID in the fresh state
    await #expect(throws: ProviderAdapterError.self) {
      _ = try await adapter.continueSession(sessionID: sid, guidance: "continue")
    }
  }
}

// MARK: - CodexAdapter finishSuccessfully Registry Cleanup

@Suite("CodexAdapter finishSuccessfully Registry Cleanup")
struct CodexAdapterFinishSuccessfullyRegistryCleanupTests {

  // Kills RemoveSideEffects on sessionRegistry.remove in finishSuccessfully closure.
  // After a turn/completed(.completed) event closes the stream,
  // the registry should be cleaned so a reused sessionID gets a fresh state.
  @Test func reusedSessionGetsCleanRegistryAfterCompletedTerminalEvent() async throws {
    let launcher = StubProcessLauncher()
    let process1 = StubLaunchedProcess()
    let process2 = StubLaunchedProcess()
    launcher.setStubProcesses([process1, process2])

    let adapter = CodexAdapter(config: noTimeoutConfig, processLauncher: launcher)
    let sid = SessionID("s-reg-finish-ok")

    // Use makeEventStream directly to isolate finishSuccessfully from onTermination
    let stream = adapter.makeEventStream(from: process1, sessionID: sid)
    process1.simulateOutput(
      #"{"method":"thread/started","params":{"thread":{"id":"thread-completed"}}}"# + "\n")

    // Terminal event with .completed outcome → finishSuccessfully → registry.remove
    process1.simulateOutput(
      #"{"method":"turn/completed","params":{"turn":{"outcome":"completed"}}}"# + "\n")

    // Consume stream — it finishes from finishSuccessfully (no process exit needed)
    var events: [AgentRawEvent] = []
    for try await event in stream {
      events.append(event)
    }
    #expect(events.count == 2)

    // Second session with same ID
    _ = try await adapter.startSession(
      sessionID: sid,
      workspacePath: "/tmp/ws",
      prompt: "Again",
      environment: [:]
    )

    // continueSession should throw: fresh state, no threadID
    await #expect(throws: ProviderAdapterError.self) {
      _ = try await adapter.continueSession(sessionID: sid, guidance: "continue")
    }
  }
}

// MARK: - CodexAdapter finishWithError Registry Cleanup

@Suite("CodexAdapter finishWithError Registry Cleanup")
struct CodexAdapterFinishWithErrorRegistryCleanupTests {

  // Kills RemoveSideEffects on sessionRegistry.remove in finishWithError closure.
  // After a turn/completed(.failed) event closes the stream with an error,
  // the registry should be cleaned so a reused sessionID gets a fresh state.
  @Test func reusedSessionGetsCleanRegistryAfterFailedTerminalEvent() async throws {
    let launcher = StubProcessLauncher()
    let process1 = StubLaunchedProcess()
    let process2 = StubLaunchedProcess()
    launcher.setStubProcesses([process1, process2])

    let adapter = CodexAdapter(config: noTimeoutConfig, processLauncher: launcher)
    let sid = SessionID("s-reg-finish-err")

    // Use makeEventStream directly to isolate finishWithError from onTermination
    let stream = adapter.makeEventStream(from: process1, sessionID: sid)
    process1.simulateOutput(
      #"{"method":"thread/started","params":{"thread":{"id":"thread-failed"}}}"# + "\n")
    process1.simulateOutput(
      #"{"method":"turn/completed","params":{"turn":{"outcome":"failed"}}}"# + "\n")

    // Consume stream — finishWithError fires (no process exit needed)
    var events: [AgentRawEvent] = []
    do {
      for try await event in stream {
        events.append(event)
      }
      Issue.record("Expected stream to throw")
    } catch {
      #expect(error is ProviderAdapterError)
    }
    #expect(events.count == 2)

    // Second session with same ID
    _ = try await adapter.startSession(
      sessionID: sid,
      workspacePath: "/tmp/ws",
      prompt: "Again",
      environment: [:]
    )

    // continueSession should throw: fresh state, no threadID
    await #expect(throws: ProviderAdapterError.self) {
      _ = try await adapter.continueSession(sessionID: sid, guidance: "continue")
    }
  }
}

// MARK: - CodexAdapter onTermination Registry Cleanup

@Suite("CodexAdapter onTermination Registry Cleanup")
struct CodexAdapterOnTerminationRegistryCleanupTests {

  // Kills RemoveSideEffects on sessionRegistry.remove in process.onTermination.
  // When the process exits without a terminal event, only onTermination cleans up.
  @Test func reusedSessionGetsCleanRegistryAfterProcessExitWithoutTerminalEvent() async throws {
    let launcher = StubProcessLauncher()
    let process1 = StubLaunchedProcess()
    let process2 = StubLaunchedProcess()
    launcher.setStubProcesses([process1, process2])

    let adapter = CodexAdapter(config: noTimeoutConfig, processLauncher: launcher)
    let sid = SessionID("s-reg-on-term")

    // Use makeEventStream directly to isolate onTermination's registry.remove
    let stream = adapter.makeEventStream(from: process1, sessionID: sid)
    process1.simulateOutput(
      #"{"method":"thread/started","params":{"thread":{"id":"thread-exit"}}}"# + "\n")

    // Process exits WITHOUT a terminal event → only onTermination fires
    process1.simulateTermination(exitCode: 0)

    var events: [AgentRawEvent] = []
    for try await event in stream {
      events.append(event)
    }
    #expect(events.count == 1)

    // Second session with same ID
    _ = try await adapter.startSession(
      sessionID: sid,
      workspacePath: "/tmp/ws",
      prompt: "Again",
      environment: [:]
    )

    // continueSession should throw: fresh state, no threadID
    await #expect(throws: ProviderAdapterError.self) {
      _ = try await adapter.continueSession(sessionID: sid, guidance: "continue")
    }
  }
}
