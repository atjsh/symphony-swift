// swiftlint:disable force_try
import Foundation
import Synchronization
import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore
@testable import SymphonyShared

@Suite("OrchestratorEngineState")
struct OrchestratorEngineStateTests {
  @Test func rawValues() {
    #expect(OrchestratorEngineState.idle.rawValue == "idle")
    #expect(OrchestratorEngineState.starting.rawValue == "starting")
    #expect(OrchestratorEngineState.running.rawValue == "running")
    #expect(OrchestratorEngineState.stopping.rawValue == "stopping")
    #expect(OrchestratorEngineState.stopped.rawValue == "stopped")
  }
}

// MARK: - OrchestratorEngineError Tests

@Suite("OrchestratorEngineError")
struct OrchestratorEngineErrorTests {
  @Test func errorsAreEquatable() {
    #expect(
      OrchestratorEngineError.workflowLoadFailed("a")
        == OrchestratorEngineError.workflowLoadFailed("a"))
    #expect(
      OrchestratorEngineError.trackerCreationFailed("a")
        == OrchestratorEngineError.trackerCreationFailed("a"))
    #expect(OrchestratorEngineError.alreadyRunning == OrchestratorEngineError.alreadyRunning)
    #expect(OrchestratorEngineError.notRunning == OrchestratorEngineError.notRunning)
  }
}

// MARK: - RunContext Tests

@Suite("RunContext")
struct RunContextTests {
  @Test func initAndEquality() throws {
    let ctx1 = RunContext(
      issueID: IssueID("I_1"),
      issueIdentifier: try IssueIdentifier(validating: "owner/repo#1"),
      runID: RunID("R_1"),
      attempt: 1
    )
    let ctx2 = RunContext(
      issueID: IssueID("I_1"),
      issueIdentifier: try IssueIdentifier(validating: "owner/repo#1"),
      runID: RunID("R_1"),
      attempt: 1
    )
    #expect(ctx1 == ctx2)
  }
}

// MARK: - NoOpEngineEventObserver Tests

@Suite("NoOpEngineEventObserver")
struct NoOpEngineEventObserverTests {
  @Test func noOpDoesNotCrash() async {
    let observer = NoOpEngineEventObserver()
    await observer.engineStateChanged(.running)
    await observer.engineTickCompleted(
      TickResult(reconciled: 0, candidatesFetched: 0, dispatched: 0, retriesProcessed: 0))
    await observer.engineDispatchStarted(
      RunContext(
        issueID: IssueID("I_1"),
        issueIdentifier: try! IssueIdentifier(validating: "o/r#1"),
        runID: RunID("R_1"),
        attempt: 1
      ))
    await observer.engineRunCompleted(
      RunContext(
        issueID: IssueID("I_1"),
        issueIdentifier: try! IssueIdentifier(validating: "o/r#1"),
        runID: RunID("R_1"),
        attempt: 1
      ), success: true)
    await observer.engineError(OrchestratorEngineError.notRunning, context: "test")
  }
}

// MARK: - CollectingEngineObserver Tests

@Suite("CollectingEngineObserver")
struct CollectingEngineObserverTests {
  @Test func collectsAllEventTypes() async {
    let observer = CollectingEngineObserver()

    await observer.engineStateChanged(.running)
    await observer.engineTickCompleted(
      TickResult(reconciled: 1, candidatesFetched: 2, dispatched: 3, retriesProcessed: 0))
    await observer.engineDispatchStarted(
      RunContext(
        issueID: IssueID("I_1"),
        issueIdentifier: try! IssueIdentifier(validating: "o/r#1"),
        runID: RunID("R_1"),
        attempt: 1
      ))
    await observer.engineRunCompleted(
      RunContext(
        issueID: IssueID("I_1"),
        issueIdentifier: try! IssueIdentifier(validating: "o/r#1"),
        runID: RunID("R_1"),
        attempt: 1
      ), success: false)
    await observer.engineError(OrchestratorEngineError.notRunning, context: "ctx")

    #expect(observer.stateChanges == [.running])
    #expect(observer.tickResults.count == 1)
    #expect(observer.dispatches.count == 1)
    #expect(observer.completions.count == 1)
    #expect(observer.errors.count == 1)
    #expect(observer.errors[0].context == "ctx")
  }
}

// MARK: - WorkflowReloader Tests

@Suite("WorkflowReloader")
struct WorkflowReloaderTests {
  @Test func startWatchingOnNonExistentPathThrows() {
    let reloader = WorkflowReloader(workflowPath: "/nonexistent/WORKFLOW.md") { _ in }
    #expect(throws: OrchestratorEngineError.self) {
      try reloader.startWatching()
    }
    #expect(!reloader.isWatching)
  }

  @Test func startAndStopWatching() throws {
    let tmpFile = NSTemporaryDirectory() + "reloader_test_\(UUID().uuidString).md"
    FileManager.default.createFile(atPath: tmpFile, contents: Data("---\n---\nHello".utf8))
    defer { try? FileManager.default.removeItem(atPath: tmpFile) }

    let reloader = WorkflowReloader(workflowPath: tmpFile) { _ in }
    try reloader.startWatching()
    #expect(reloader.isWatching)

    reloader.stopWatching()
    #expect(!reloader.isWatching)
  }

  @Test func fileChangeTriggersCallback() async throws {
    let tmpFile = NSTemporaryDirectory() + "reloader_callback_\(UUID().uuidString).md"
    FileManager.default.createFile(
      atPath: tmpFile, contents: Data("---\npolling:\n  interval_ms: 1000\n---\nPrompt".utf8))
    defer { try? FileManager.default.removeItem(atPath: tmpFile) }

    let reloadedDefinition = Mutex<WorkflowDefinition?>(nil)

    let reloader = WorkflowReloader(workflowPath: tmpFile) { definition in
      reloadedDefinition.withLock { $0 = definition }
    }
    try reloader.startWatching()

    try "---\npolling:\n  interval_ms: 2000\n---\nUpdated prompt".write(
      toFile: tmpFile, atomically: true, encoding: .utf8)
    reloader.processFileChange()

    reloader.stopWatching()

    let definition = try #require(reloadedDefinition.withLock { $0 })
    #expect(definition.config.polling.intervalMS == 2000)
    #expect(definition.promptTemplate == "Updated prompt")
  }

  @Test func invalidFileChangeKeepsLastGoodConfig() async throws {
    let tmpFile = NSTemporaryDirectory() + "reloader_invalid_\(UUID().uuidString).md"
    FileManager.default.createFile(
      atPath: tmpFile,
      contents: Data("---\npolling:\n  interval_ms: 1000\n---\nPrompt".utf8))
    defer { try? FileManager.default.removeItem(atPath: tmpFile) }

    let reloadCount = Mutex(0)

    let reloader = WorkflowReloader(workflowPath: tmpFile) { _ in
      reloadCount.withLock { $0 += 1 }
    }

    // Write invalid content that will cause parse error
    try Data([0xFF, 0xFE]).write(to: URL(fileURLWithPath: tmpFile))

    // Call processFileChange directly to exercise the catch block
    reloader.processFileChange()

    // The invalid change should not trigger callback
    let count = reloadCount.withLock { $0 }
    #expect(count == 0)
  }

  @Test func stopWatchingTwiceDoesNotCrash() throws {
    let tmpFile = NSTemporaryDirectory() + "reloader_double_stop_\(UUID().uuidString).md"
    FileManager.default.createFile(atPath: tmpFile, contents: Data("---\n---\nTest".utf8))
    defer { try? FileManager.default.removeItem(atPath: tmpFile) }

    let reloader = WorkflowReloader(workflowPath: tmpFile) { _ in }
    try reloader.startWatching()
    reloader.stopWatching()
    reloader.stopWatching()
    #expect(!reloader.isWatching)
  }
}

func waitUntil(
  timeoutMS: Int = 1_000,
  pollIntervalMS: Int = 25,
  condition: @escaping @Sendable () -> Bool
) async throws -> Bool {
  let deadline = Date().addingTimeInterval(Double(timeoutMS) / 1000)
  while Date() <= deadline {
    if condition() {
      return true
    }
    try await Task.sleep(nanoseconds: UInt64(pollIntervalMS) * 1_000_000)
  }
  return condition()
}

// swiftlint:enable force_try
