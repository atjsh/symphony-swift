// Batch38MutationHardeningTests.swift
// -----------------------------------------------------------------
// Mutation targets:
//
// CopilotCLIAdapter.swift — makeEventStream non-zero exit code path:
//   Mutation removes the `else` branch in onTermination that throws
//   processExitedUnexpectedly when exitCode != 0.
//
// ClaudeCodeAdapter.swift — makeEventStream non-zero exit code path:
//   Same mutation pattern for ClaudeCode's onTermination handler.
//
// OrchestratorEngine.swift — orchestratorDidCancel cleanup failure log:
//   Mutation removes the catch block that logs cancel_workspace_removal_failed
//   when removeWorkspace throws during cancel with cleanup.
// -----------------------------------------------------------------

import Foundation
import SymphonyShared
import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore

// MARK: - CopilotCLI Adapter Non-Zero Exit

@Suite("CopilotCLI adapter makeEventStream non-zero exit code")
struct CopilotCLIAdapterNonZeroExitTests {

  @Test func nonZeroExitThrowsProcessExitedUnexpectedly() async throws {
    let stubProcess = StubLaunchedProcess()
    let adapter = CopilotCLIAdapter(config: .defaults, processLauncher: StubProcessLauncher())

    let stream = adapter.makeEventStream(from: stubProcess, sessionID: SessionID("s-exit"))
    stubProcess.simulateTermination(exitCode: 42)

    var caughtError: ProviderAdapterError?
    do {
      for try await _ in stream {}
    } catch let error as ProviderAdapterError {
      caughtError = error
    }
    #expect(caughtError == .processExitedUnexpectedly(exitCode: 42))
  }

  @Test func zeroExitFinishesStreamCleanly() async throws {
    let stubProcess = StubLaunchedProcess()
    let adapter = CopilotCLIAdapter(config: .defaults, processLauncher: StubProcessLauncher())

    let stream = adapter.makeEventStream(from: stubProcess, sessionID: SessionID("s-ok"))
    stubProcess.simulateTermination(exitCode: 0)

    var events: [AgentRawEvent] = []
    for try await event in stream {
      events.append(event)
    }
    #expect(events.isEmpty)
  }
}

// MARK: - ClaudeCode Adapter Non-Zero Exit

@Suite("ClaudeCode adapter makeEventStream non-zero exit code")
struct ClaudeCodeAdapterNonZeroExitTests {

  @Test func nonZeroExitThrowsProcessExitedUnexpectedly() async throws {
    let stubProcess = StubLaunchedProcess()
    let adapter = ClaudeCodeAdapter(config: .defaults)

    let stream = adapter.makeEventStream(from: stubProcess, sessionID: SessionID("s-exit"))
    stubProcess.simulateTermination(exitCode: 7)

    var caughtError: ProviderAdapterError?
    do {
      for try await _ in stream {}
    } catch let error as ProviderAdapterError {
      caughtError = error
    }
    #expect(caughtError == .processExitedUnexpectedly(exitCode: 7))
  }

  @Test func zeroExitFinishesStreamCleanly() async throws {
    let stubProcess = StubLaunchedProcess()
    let adapter = ClaudeCodeAdapter(config: .defaults)

    let stream = adapter.makeEventStream(from: stubProcess, sessionID: SessionID("s-ok"))
    stubProcess.simulateTermination(exitCode: 0)

    var events: [AgentRawEvent] = []
    for try await event in stream {
      events.append(event)
    }
    #expect(events.isEmpty)
  }
}

// MARK: - EngineOrchestratorDelegate Cancel Workspace Removal Failure

/// A custom WorkspaceManaging stub that throws from removeWorkspace.
private final class ThrowingRemoveWorkspaceManager: WorkspaceManaging, @unchecked Sendable {
  private let lock = NSLock()
  private var _removeError: Error?

  init(removeError: Error) {
    self._removeError = removeError
  }

  func workspacePath(for key: WorkspaceKey) -> String {
    "/tmp/throwing/\(key.rawValue)"
  }

  func ensureWorkspace(for key: WorkspaceKey, hooks: HooksConfig) throws -> String {
    workspacePath(for: key)
  }

  func removeWorkspace(for key: WorkspaceKey, hooks: HooksConfig) throws {
    if let error = lock.withLock({ _removeError }) {
      throw error
    }
  }

  func validateContainment(path: String) throws {}
}

@Suite("EngineOrchestratorDelegate cancel workspace removal failure")
struct DelegateCancelWorkspaceRemovalFailureTests {

  @Test func cancelWithCleanupFailureLogsWarning() async throws {
    let observer = CollectingEngineObserver()
    let throwingManager = ThrowingRemoveWorkspaceManager(
      removeError: WorkspaceError.workspaceCreationFailed("disk full"))
    let delegate = EngineOrchestratorDelegate(
      workspaceManager: throwingManager, observer: observer)

    let (_, logs) = try await withCapturedRuntimeLogs {
      await delegate.orchestratorDidCancel(
        issueID: IssueID("I_fail"),
        issueIdentifier: try IssueIdentifier(validating: "owner/repo#99"),
        reason: "closed",
        cleanup: true
      )
    }

    let failureLogs = logs.filter { $0.entry.event == "cancel_workspace_removal_failed" }
    #expect(failureLogs.count == 1)
    #expect(failureLogs[0].entry.level == "warning")
    #expect(failureLogs[0].entry.issueID == "I_fail")
    #expect(failureLogs[0].entry.issueIdentifier == "owner/repo#99")
    #expect(observer.completions.count == 1)
    #expect(observer.completions[0].1 == false)
  }

  @Test func cancelWithCleanupSuccessDoesNotLogWarning() async throws {
    let observer = CollectingEngineObserver()
    let wsManager = StubWorkspaceManager()
    let delegate = EngineOrchestratorDelegate(
      workspaceManager: wsManager, observer: observer)

    let (_, logs) = try await withCapturedRuntimeLogs {
      await delegate.orchestratorDidCancel(
        issueID: IssueID("I_ok"),
        issueIdentifier: try IssueIdentifier(validating: "owner/repo#1"),
        reason: "closed",
        cleanup: true
      )
    }

    let failureLogs = logs.filter { $0.entry.event == "cancel_workspace_removal_failed" }
    #expect(failureLogs.isEmpty)
    #expect(observer.completions.count == 1)
  }
}
