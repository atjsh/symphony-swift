// Batch 30 — Process termination verification for mutation hardening.
//
// Targets the following surviving mutations:
//
// ProcessLaunching.swift — DefaultLaunchedProcess.interrupt():
//   Mutation removes `process.interrupt()` call.
//   Killed by verifying onTermination fires after interrupt.
//
// ProcessLaunching.swift — DefaultLaunchedProcess.terminate():
//   Mutation removes `process.terminate()` call.
//   Killed by verifying onTermination fires after terminate.
//
// CodexAdapter.swift — startSession error cleanup:
//   Mutation removes `process.terminate()` in error handler.
//   Killed by verifying stubProcess.terminationCount == 1 after error.
//
// ClaudeCodeAdapter.swift — cancelSession cleanup:
//   Mutation removes `process.terminate()` in cancelSession.
//   Killed by verifying stubProcess.terminationCount == 1 after cancel.
//
// CopilotCLIAdapter.swift — cancelSession cleanup:
//   Mutation removes `process.terminate()` in cancelSession.
//   Killed by verifying stubProcess.terminationCount == 1 after cancel.

import Foundation
import Synchronization
import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore
@testable import SymphonyShared

// MARK: - DefaultLaunchedProcess Signal Verification

@Suite("DefaultLaunchedProcess Signal Verification")
struct DefaultLaunchedProcessSignalVerificationTests {

  @Test func interruptCausesProcessToExit() throws {
    let launcher = DefaultProcessLauncher()
    let process = try launcher.launch(
      command: "sleep 60",
      workspacePath: NSTemporaryDirectory(),
      environment: [:]
    )

    let terminated = Mutex(false)
    process.onTermination { _ in terminated.withLock { $0 = true } }

    process.interrupt()
    Thread.sleep(forTimeInterval: 1.0)

    #expect(terminated.withLock { $0 } == true)
  }

  @Test func terminateCausesProcessToExit() throws {
    let launcher = DefaultProcessLauncher()
    let process = try launcher.launch(
      command: "sleep 60",
      workspacePath: NSTemporaryDirectory(),
      environment: [:]
    )

    let terminated = Mutex(false)
    process.onTermination { _ in terminated.withLock { $0 = true } }

    process.terminate()
    Thread.sleep(forTimeInterval: 1.0)

    #expect(terminated.withLock { $0 } == true)
  }
}

// MARK: - CodexAdapter Start Session Error Terminates Process

@Suite("CodexAdapter Start Error Cleanup")
struct CodexAdapterStartErrorCleanupTests {

  @Test func startSessionErrorTerminatesProcess() async {
    let stubLauncher = StubProcessLauncher()
    let stubProcess = StubLaunchedProcess()
    stubProcess.setInputError(ProviderAdapterError.processLaunchFailed("stdin broken"))
    stubLauncher.setStubProcess(stubProcess)

    let adapter = CodexAdapter(config: .defaults, processLauncher: stubLauncher)

    await #expect(throws: ProviderAdapterError.self) {
      _ = try await adapter.startSession(
        sessionID: SessionID("s-cleanup"),
        workspacePath: "/tmp/ws",
        prompt: "Fix bug",
        environment: [:]
      )
    }

    #expect(stubProcess.terminationCount == 1)
  }
}

// MARK: - ClaudeCodeAdapter Cancel Session Terminates Process

@Suite("ClaudeCodeAdapter Cancel Cleanup")
struct ClaudeCodeAdapterCancelCleanupTests {

  @Test func cancelSessionTerminatesStubProcess() async throws {
    let stubLauncher = StubProcessLauncher()
    let stubProcess = StubLaunchedProcess()
    stubLauncher.setStubProcess(stubProcess)

    let adapter = ClaudeCodeAdapter(config: .defaults, processLauncher: stubLauncher)
    _ = try await adapter.startSession(
      sessionID: SessionID("s-cancel"),
      workspacePath: "/tmp/ws",
      prompt: "fix",
      environment: [:]
    )

    try await adapter.cancelSession(sessionID: SessionID("s-cancel"))
    #expect(stubProcess.terminationCount == 1)
  }
}

// MARK: - CopilotCLIAdapter Cancel Session Terminates Process

@Suite("CopilotCLIAdapter Cancel Cleanup")
struct CopilotCLIAdapterCancelCleanupTests {

  @Test func cancelSessionTerminatesStubProcess() async throws {
    let stubLauncher = StubProcessLauncher()
    let stubProcess = StubLaunchedProcess()
    stubLauncher.setStubProcess(stubProcess)

    let adapter = CopilotCLIAdapter(config: .defaults, processLauncher: stubLauncher)
    _ = try await adapter.startSession(
      sessionID: SessionID("s-cancel"),
      workspacePath: "/tmp/ws",
      prompt: "fix",
      environment: [:]
    )

    try await adapter.cancelSession(sessionID: SessionID("s-cancel"))
    #expect(stubProcess.terminationCount == 1)
  }
}
