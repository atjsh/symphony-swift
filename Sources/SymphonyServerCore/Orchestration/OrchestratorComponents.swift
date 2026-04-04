import Foundation
import SymphonyShared

// MARK: - Retry Queue (Section 8.5)

// SAFETY: @unchecked Sendable — `_entries` is exclusively accessed through `lock`.
public final class RetryQueue: @unchecked Sendable {
  private let lock = NSLock()
  private var _entries: [IssueID: RetryRecord] = [:]

  public init() {}

  public var entries: [IssueID: RetryRecord] {
    lock.lock()
    defer { lock.unlock() }
    return _entries
  }

  public func enqueue(_ record: RetryRecord) {
    lock.lock()
    _entries[record.issueID] = record
    lock.unlock()
  }

  public func dequeue(issueID: IssueID) -> RetryRecord? {
    lock.lock()
    defer { lock.unlock() }
    return _entries.removeValue(forKey: issueID)
  }

  public func dueEntries(asOf now: Date = Date()) -> [RetryRecord] {
    lock.lock()
    defer { lock.unlock() }
    return _entries.values.filter { $0.dueAt <= now }
  }

  public func removeAll() {
    lock.lock()
    _entries.removeAll()
    lock.unlock()
  }

  public var count: Int {
    lock.lock()
    defer { lock.unlock() }
    return _entries.count
  }

  public static func backoffDelay(
    attempt: Int,
    maxRetryBackoffMS: Int
  ) -> Int {
    let base = 10_000.0
    let exponential = base * pow(2.0, Double(attempt - 1))
    return min(Int(exponential), maxRetryBackoffMS)
  }

  public static func continuationDelay() -> Int {
    1_000
  }
}

// MARK: - Stall Detector (Section 8.6)

public struct StallDetector: Sendable {
  public let stallTimeoutMS: Int

  public init(stallTimeoutMS: Int) {
    self.stallTimeoutMS = stallTimeoutMS
  }

  public var isEnabled: Bool {
    stallTimeoutMS > 0
  }

  public func isStalled(lastEventAt: Date, now: Date = Date()) -> Bool {
    guard isEnabled else { return false }
    let elapsed = now.timeIntervalSince(lastEventAt) * 1000
    return elapsed >= Double(stallTimeoutMS)
  }
}

// MARK: - Concurrency Slot Manager

public struct ConcurrencySlotManager: Sendable {
  public let maxConcurrentAgents: Int
  public let maxConcurrentAgentsByState: [String: Int]

  public init(config: AgentConfig) {
    self.maxConcurrentAgents = config.maxConcurrentAgents
    self.maxConcurrentAgentsByState = config.maxConcurrentAgentsByState
  }

  public func availableSlots(currentRunning: Int) -> Int {
    max(0, maxConcurrentAgents - currentRunning)
  }

  public func availableSlots(forState state: String, currentInState: Int) -> Int {
    guard let stateMax = maxConcurrentAgentsByState[state] else {
      return Int.max
    }
    return max(0, stateMax - currentInState)
  }

  public func canDispatch(
    currentRunning: Int,
    state: String,
    currentInState: Int
  ) -> Bool {
    availableSlots(currentRunning: currentRunning) > 0
      && availableSlots(forState: state, currentInState: currentInState) > 0
  }
}
