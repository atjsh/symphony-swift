import Foundation
import SymphonyServerCore

// MARK: - Collecting Engine Observer (for testing)

public final class CollectingEngineObserver: EngineEventObserving, @unchecked Sendable {
  private let lock = NSLock()
  private var _stateChanges: [OrchestratorEngineState] = []
  private var _tickResults: [TickResult] = []
  private var _dispatches: [RunContext] = []
  private var _completions: [(RunContext, Bool)] = []
  private var _errors: [(String, String)] = []

  public init() {}

  public var stateChanges: [OrchestratorEngineState] {
    lock.withLock { _stateChanges }
  }

  public var tickResults: [TickResult] {
    lock.withLock { _tickResults }
  }

  public var dispatches: [RunContext] {
    lock.withLock { _dispatches }
  }

  public var completions: [(RunContext, Bool)] {
    lock.withLock { _completions }
  }

  public var errors: [(message: String, context: String)] {
    lock.withLock { _errors }
  }

  public nonisolated func engineStateChanged(_ state: OrchestratorEngineState) async {
    lock.withLock { _stateChanges.append(state) }
  }

  public nonisolated func engineTickCompleted(_ result: TickResult) async {
    lock.withLock { _tickResults.append(result) }
  }

  public nonisolated func engineDispatchStarted(_ context: RunContext) async {
    lock.withLock { _dispatches.append(context) }
  }

  public nonisolated func engineRunCompleted(_ context: RunContext, success: Bool) async {
    lock.withLock { _completions.append((context, success)) }
  }

  public nonisolated func engineError(_ error: Error, context: String) async {
    lock.withLock { _errors.append(("\(error)", context)) }
  }
}
