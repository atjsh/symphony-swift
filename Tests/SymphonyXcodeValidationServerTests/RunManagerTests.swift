#if os(macOS)

import Foundation
import Testing
@testable import SymphonyXcodeValidationServer
@testable import SymphonyXcodeValidationServerCore
import SymphonyXcodeValidation

// MARK: - Mock Process Executor

final class MockValidationProcessExecutor: ValidationProcessExecuting, @unchecked Sendable {
  // SAFETY: Only mutated during test setup before concurrent access begins.
  var shouldThrow = false
  var runDelay: Duration = .milliseconds(50)

  func run(_ command: ValidationCommand) throws -> ValidationCommandResult {
    Thread.sleep(forTimeInterval: 0.05)
    if shouldThrow {
      throw MockProcessError.intentionalFailure
    }
    // The runner processes this result internally; we don't need to construct
    // a real ValidationCommandResult since XcodeValidationRunner.run()
    // builds its own return value from multi-step orchestration.
    // The mock just needs to allow the process to "complete".
    fatalError("Mock executor reached unexpected code path")
  }

  func start(_ command: ValidationCommand) throws -> RunningValidationCommand {
    MockRunningCommand()
  }
}

enum MockProcessError: Error {
  case intentionalFailure
}

final class MockRunningCommand: RunningValidationCommand {
  func stop() {}
}

// MARK: - RunManager Tests

@Suite("RunManager")
struct RunManagerTests {
  @Test("starts a run and returns a RunID")
  func startRun() async throws {
    let manager = RunManager(
      defaultProjectRoot: URL(fileURLWithPath: "/tmp"),
      processExecutor: MockValidationProcessExecutor()
    )
    let request = StartRunRequest(configuration: ValidationRunConfiguration())
    let runID = try await manager.start(request)
    #expect(runID.rawValue.isEmpty == false)
  }

  @Test("rejects concurrent run with error")
  func rejectsConcurrentRun() async throws {
    let executor = MockValidationProcessExecutor()
    executor.runDelay = .seconds(5)
    let manager = RunManager(
      defaultProjectRoot: URL(fileURLWithPath: "/tmp"),
      processExecutor: executor
    )
    let request = StartRunRequest(configuration: ValidationRunConfiguration())
    _ = try await manager.start(request)

    // Second start should throw
    do {
      _ = try await manager.start(request)
      Issue.record("Expected RunManagerError.runAlreadyActive")
    } catch is RunManagerError {
      // Expected
    }
  }

  @Test("status returns idle when no run active")
  func statusIdleByDefault() async {
    let manager = RunManager(
      defaultProjectRoot: URL(fileURLWithPath: "/tmp"),
      processExecutor: MockValidationProcessExecutor()
    )
    let runID = RunID("nonexistent")
    let status = await manager.status(for: runID, afterLine: nil)
    #expect(status.status == .idle)
  }

  @Test("cancel returns false for unknown run")
  func cancelUnknownRun() async {
    let manager = RunManager(
      defaultProjectRoot: URL(fileURLWithPath: "/tmp"),
      processExecutor: MockValidationProcessExecutor()
    )
    let cancelled = await manager.cancel(RunID("unknown"))
    #expect(cancelled == false)
  }

  @Test("appendLog adds log lines during a run")
  func appendLogLines() async throws {
    let manager = RunManager(
      defaultProjectRoot: URL(fileURLWithPath: "/tmp"),
      processExecutor: MockValidationProcessExecutor()
    )
    let request = StartRunRequest(configuration: ValidationRunConfiguration())
    let runID = try await manager.start(request)

    await manager.appendLog("line 0")
    await manager.appendLog("line 1")

    let status = await manager.status(for: runID, afterLine: nil)
    #expect(status.logLines.count == 2)
    #expect(status.logLines[0].text == "line 0")
    #expect(status.logLines[1].text == "line 1")
  }

  @Test("status returns lines after cursor")
  func statusAfterLineCursor() async throws {
    let manager = RunManager(
      defaultProjectRoot: URL(fileURLWithPath: "/tmp"),
      processExecutor: MockValidationProcessExecutor()
    )
    let request = StartRunRequest(configuration: ValidationRunConfiguration())
    let runID = try await manager.start(request)

    await manager.appendLog("line 0")
    await manager.appendLog("line 1")
    await manager.appendLog("line 2")

    let status = await manager.status(for: runID, afterLine: 0)
    #expect(status.logLines.count == 2)
    #expect(status.logLines[0].text == "line 1")
  }

  @Test("summary returns nil when no completed run")
  func summaryNilWhenNotCompleted() async {
    let manager = RunManager(
      defaultProjectRoot: URL(fileURLWithPath: "/tmp"),
      processExecutor: MockValidationProcessExecutor()
    )
    let summary = await manager.summary(for: RunID("none"))
    #expect(summary == nil)
  }
}

#endif
