// Batch 21 — mutation hardening for OrchestratorEngine stop() guard
// covering the .starting state branch of the || condition.

import Foundation
import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore
@testable import SymphonyShared

// MARK: - Gated Tracker (blocks fetchIssuesByStates until released)

private final class GatedTracker: TrackerAdapting, @unchecked Sendable {
  private let stream: AsyncStream<Void>
  private let continuation: AsyncStream<Void>.Continuation

  init() {
    let (s, c) = AsyncStream<Void>.makeStream()
    self.stream = s
    self.continuation = c
  }

  func release() { continuation.finish() }

  nonisolated func fetchAllIssues() async throws -> [SymphonyShared.Issue] { [] }
  nonisolated func fetchCandidateIssues() async throws -> [SymphonyShared.Issue] { [] }
  nonisolated func fetchIssuesByStates(_ stateNames: [String]) async throws -> [SymphonyShared.Issue] {
    for await _ in stream {}
    return []
  }
  nonisolated func fetchIssueStatesByIDs(_ ids: [IssueID]) async throws -> [IssueID: String] {
    [:]
  }
}

// MARK: - OrchestratorEngine Stop While Starting

@Suite("OrchestratorEngine Stop While Starting")
struct OrchestratorEngineStopWhileStartingTests {

  private func makeConfig() -> WorkflowConfig {
    WorkflowConfig(
      tracker: TrackerConfig(
        activeStates: ["Todo"],
        terminalStates: ["Done"]
      ),
      polling: PollingConfig(intervalMS: 50)
    )
  }

  @Test func stopWhileStartingReachesStoppedState() async throws {
    let observer = CollectingEngineObserver()
    let tracker = GatedTracker()

    let engine = OrchestratorEngine(
      config: makeConfig(),
      trackerFactory: { _ in tracker },
      observer: observer
    )

    try engine.start()

    // Engine is in .starting — the task is blocked in performStartupCleanup
    // waiting on tracker.fetchIssuesByStates which is gated.
    try await bootstrapWaitUntil("engine is starting") { engine.state == .starting }

    // Stop while still in .starting — tests the || _state == .starting branch
    engine.stop()

    // Unblock the tracker so the cancelled task can complete
    tracker.release()

    try await bootstrapWaitUntil("engine stops") { engine.state == .stopped }
    #expect(observer.stateChanges.contains(.starting))
    #expect(observer.stateChanges.contains(.stopped))
  }

  @Test func stopWhileStartingIsNotANoOp() async throws {
    let tracker = GatedTracker()

    let engine = OrchestratorEngine(
      config: makeConfig(),
      trackerFactory: { _ in tracker }
    )

    try engine.start()
    try await bootstrapWaitUntil("engine is starting") { engine.state == .starting }

    // After stop(), state should no longer be .starting
    engine.stop()
    let stateAfterStop = engine.state
    #expect(stateAfterStop != .starting)

    tracker.release()
    try await bootstrapWaitUntil("engine stops") { engine.state == .stopped }
  }
}
