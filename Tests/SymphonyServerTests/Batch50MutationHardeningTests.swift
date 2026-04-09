// Batch 50 — RemoveSideEffects mutation hardening.
//
// Targets the following surviving mutations:
//
// ClaudeCodeAdapter.swift — makeEventStream terminal event handler:
//   RemoveSideEffects on activeSessions.remove(sessionID:) when descriptor.isTerminal.
//   Killed by verifying cancelSession throws sessionNotFound after terminal event closes stream.
//
// ClaudeCodeAdapter.swift — makeEventStream onTermination handler:
//   RemoveSideEffects on activeSessions.remove(sessionID:) in process.onTermination.
//   Killed by verifying cancelSession throws sessionNotFound after non-zero exit closes stream.
//
// CopilotCLIAdapter.swift — makeEventStream onTermination handler:
//   RemoveSideEffects on activeSessions.remove(sessionID:) in process.onTermination.
//   Killed by verifying cancelSession throws sessionNotFound after process exits cleanly.
//
// CodexAdapter.swift — startSession recordIssueContext integration:
//   RemoveSideEffects on sessionState.recordIssueContext(identifier:,title:) in startSession.
//   Killed by verifying continueSession's turn_start message uses real issue title (not "Untitled").
//
// CodexAdapter.swift — continueSession error path activeSessions.remove:
//   RemoveSideEffects on activeSessions.remove(sessionID:) in the catch block.
//   Killed by verifying cancelSession throws sessionNotFound after failed continueSession.

import Foundation
import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore
@testable import SymphonyShared

// MARK: - ClaudeCodeAdapter Terminal Event Cleanup

@Suite("ClaudeCodeAdapter Terminal Event Active Session Cleanup")
struct ClaudeCodeAdapterTerminalEventCleanupTests {

  // Kills RemoveSideEffects on activeSessions.remove(sessionID:) in terminal event handler.
  // If the remove is deleted, cancelSession finds the session instead of throwing.
  @Test func cancelSessionThrowsAfterTerminalEventClosesStream() async throws {
    let stubProcess = StubLaunchedProcess()
    let adapter = ClaudeCodeAdapter(config: .defaults)
    let sid = SessionID("s-term-cleanup")

    let stream = adapter.makeEventStream(from: stubProcess, sessionID: sid)

    // Terminal event triggers activeSessions.remove inside the stream
    stubProcess.simulateOutput("{\"type\":\"result\"}\n")
    stubProcess.simulateTermination(exitCode: 0)

    // Consume the stream to ensure the terminal event handler runs
    var events: [AgentRawEvent] = []
    for try await event in stream {
      events.append(event)
    }
    #expect(events.count == 1)
    #expect(events[0].providerEventType == "result")

    // After terminal event cleanup, the session must be gone
    await #expect(throws: ProviderAdapterError.self) {
      try await adapter.cancelSession(sessionID: sid)
    }
  }

  // Kills RemoveSideEffects on activeSessions.remove(sessionID:) in onTermination handler.
  // When no terminal event precedes process exit, onTermination must clean up.
  @Test func cancelSessionThrowsAfterNonZeroExitClosesStream() async throws {
    let stubProcess = StubLaunchedProcess()
    let adapter = ClaudeCodeAdapter(config: .defaults)
    let sid = SessionID("s-exit-cleanup")

    let stream = adapter.makeEventStream(from: stubProcess, sessionID: sid)

    // Process exits without a terminal event
    stubProcess.simulateTermination(exitCode: 1)

    // Consume the stream (should throw processExitedUnexpectedly)
    do {
      for try await _ in stream {}
      Issue.record("Expected stream to throw")
    } catch {
      #expect(error is ProviderAdapterError)
    }

    // After onTermination cleanup, the session must be gone
    await #expect(throws: ProviderAdapterError.self) {
      try await adapter.cancelSession(sessionID: sid)
    }
  }
}

// MARK: - CopilotCLIAdapter OnTermination Cleanup

@Suite("CopilotCLIAdapter OnTermination Active Session Cleanup")
struct CopilotCLIAdapterOnTerminationCleanupTests {

  // Kills RemoveSideEffects on activeSessions.remove(sessionID:) in onTermination handler.
  @Test func cancelSessionThrowsAfterProcessExitsCleanly() async throws {
    let stubLauncher = StubProcessLauncher()
    let stubProcess = StubLaunchedProcess()
    stubLauncher.setStubProcess(stubProcess)

    let adapter = CopilotCLIAdapter(config: .defaults, processLauncher: stubLauncher)
    let sid = SessionID("s-copilot-exit")

    let stream = try await adapter.startSession(
      sessionID: sid,
      workspacePath: "/tmp/ws",
      prompt: "fix",
      environment: [:]
    )

    // Process terminates normally
    stubProcess.simulateTermination(exitCode: 0)

    // Consume stream to let onTermination run
    var events: [AgentRawEvent] = []
    for try await event in stream {
      events.append(event)
    }

    // After cleanup, the session must be gone
    await #expect(throws: ProviderAdapterError.self) {
      try await adapter.cancelSession(sessionID: sid)
    }
  }

  // Kills RemoveSideEffects on activeSessions.remove(sessionID:) in onTermination
  // when process exits with non-zero code.
  @Test func cancelSessionThrowsAfterProcessExitsWithError() async throws {
    let stubLauncher = StubProcessLauncher()
    let stubProcess = StubLaunchedProcess()
    stubLauncher.setStubProcess(stubProcess)

    let adapter = CopilotCLIAdapter(config: .defaults, processLauncher: stubLauncher)
    let sid = SessionID("s-copilot-err-exit")

    let stream = try await adapter.startSession(
      sessionID: sid,
      workspacePath: "/tmp/ws",
      prompt: "fix",
      environment: [:]
    )

    stubProcess.simulateTermination(exitCode: 1)

    do {
      for try await _ in stream {}
      Issue.record("Expected stream to throw")
    } catch {
      #expect(error is ProviderAdapterError)
    }

    await #expect(throws: ProviderAdapterError.self) {
      try await adapter.cancelSession(sessionID: sid)
    }
  }
}

// MARK: - CodexAdapter Issue Context Flows Through to ContinueSession

@Suite("CodexAdapter Issue Context Integration")
struct CodexAdapterIssueContextIntegrationTests {

  // Kills RemoveSideEffects on sessionState.recordIssueContext(identifier:,title:) in startSession.
  // If the call is removed, continueSession's turn_start message will use "unknown: Untitled"
  // instead of the real issue identifier and title.
  @Test func continueSessionTurnStartUsesRecordedIssueTitle() async throws {
    let stubLauncher = StubProcessLauncher()
    let stubProcess = StubLaunchedProcess()
    stubLauncher.setStubProcess(stubProcess)

    let issue = try makeIssue(owner: "acme", repo: "engine", number: 42, title: "Fix memory leak")
    let adapter = CodexAdapter(config: .defaults, processLauncher: stubLauncher)
    let sid = SessionID("s-issue-ctx")

    _ = try await adapter.startSession(
      sessionID: sid,
      issue: issue,
      workspacePath: "/tmp/workspace",
      prompt: "Fix the bug",
      environment: [:]
    )

    // Simulate thread/started so the registry records a threadID
    stubProcess.simulateOutput(
      #"{"method":"thread/started","params":{"thread":{"id":"thread-ctx"}}}"# + "\n")

    // Now call continueSession — it should use the recorded issue context
    _ = try await adapter.continueSession(
      sessionID: sid,
      guidance: "continue work"
    )

    // The last recorded input should be the turn_start from continueSession
    let allMessages = try stubProcess.recordedInputStrings.map(parseJSONObject)
    let continueTurnStart = try #require(allMessages.last)
    let params = try #require(continueTurnStart["params"] as? [String: Any])
    let title = try #require(params["title"] as? String)

    // If recordIssueContext was removed, title would be "unknown: Untitled"
    #expect(title == "\(issue.identifier.rawValue): \(issue.title)")
    #expect(title.contains("acme/engine#42"))
    #expect(title.contains("Fix memory leak"))
  }

  // Verifies that without an issue, continueSession uses default "unknown: Untitled".
  // This is the complement that ensures the conditional path is exercised.
  @Test func continueSessionTurnStartUsesDefaultsWhenNoIssue() async throws {
    let stubLauncher = StubProcessLauncher()
    let stubProcess = StubLaunchedProcess()
    stubLauncher.setStubProcess(stubProcess)

    let adapter = CodexAdapter(config: .defaults, processLauncher: stubLauncher)
    let sid = SessionID("s-no-issue-ctx")

    _ = try await adapter.startSession(
      sessionID: sid,
      workspacePath: "/tmp/workspace",
      prompt: "Fix the bug",
      environment: [:]
    )

    stubProcess.simulateOutput(
      #"{"method":"thread/started","params":{"thread":{"id":"thread-no-ctx"}}}"# + "\n")

    _ = try await adapter.continueSession(
      sessionID: sid,
      guidance: "continue"
    )

    let allMessages = try stubProcess.recordedInputStrings.map(parseJSONObject)
    let continueTurnStart = try #require(allMessages.last)
    let params = try #require(continueTurnStart["params"] as? [String: Any])
    let title = try #require(params["title"] as? String)

    #expect(title == "unknown: Untitled")
  }
}

// MARK: - CodexAdapter ContinueSession Error Path Cleanup

@Suite("CodexAdapter ContinueSession Error Path Cleanup")
struct CodexAdapterContinueSessionErrorCleanupTests {

  // Kills RemoveSideEffects on activeSessions.remove(sessionID:) in continueSession's catch block.
  // The existing test only checks continueSession again (which is redundant because
  // sessionRegistry.remove also makes the guard fail). cancelSession checks ONLY activeSessions.
  @Test func cancelSessionThrowsAfterContinueSessionSubmissionFails() async throws {
    let stubLauncher = StubProcessLauncher()
    let stubProcess = StubLaunchedProcess()
    stubLauncher.setStubProcess(stubProcess)

    let adapter = CodexAdapter(config: .defaults, processLauncher: stubLauncher)
    let sid = SessionID("s-cont-err-cleanup")

    _ = try await adapter.startSession(
      sessionID: sid,
      workspacePath: "/tmp/workspace",
      prompt: "Fix the bug",
      environment: [:]
    )

    stubProcess.simulateOutput(
      #"{"method":"thread/started","params":{"thread":{"id":"thread-cont-err"}}}"# + "\n")

    // Make the next input fail
    stubProcess.setInputError(ProviderAdapterError.processLaunchFailed("write failed"))

    await #expect(throws: ProviderAdapterError.self) {
      _ = try await adapter.continueSession(
        sessionID: sid,
        guidance: "keep going"
      )
    }

    // cancelSession checks only activeSessions — if remove was skipped, it would succeed
    await #expect(throws: ProviderAdapterError.self) {
      try await adapter.cancelSession(sessionID: sid)
    }
  }
}
