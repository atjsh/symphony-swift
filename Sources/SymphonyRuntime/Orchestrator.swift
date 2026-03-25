import Foundation
import SymphonyShared

// MARK: - Tracker Adapter Protocol (Section 7.1)

public protocol TrackerAdapting: Sendable {
  func fetchCandidateIssues() async throws -> [Issue]
  func fetchIssuesByStates(_ stateNames: [String]) async throws -> [Issue]
  func fetchIssueStatesByIDs(_ issueIDs: [IssueID]) async throws -> [IssueID: String]
}

// MARK: - Orchestrator Error

public enum OrchestratorError: Error, Equatable, Sendable {
  case configurationInvalid(String)
  case noTrackerConfigured
  case dispatchFailed(String)
  case reconciliationFailed(String)
}

// MARK: - Candidate Eligibility (Section 7.2)

public enum CandidateEligibility {
  public static func filterEligible(
    candidates: [Issue],
    config: TrackerConfig,
    runningIssueIDs: Set<IssueID>,
    claimedIssueIDs: Set<IssueID>
  ) -> [Issue] {
    candidates.filter { issue in
      isEligible(
        issue: issue,
        config: config,
        runningIssueIDs: runningIssueIDs,
        claimedIssueIDs: claimedIssueIDs
      )
    }
  }

  public static func isEligible(
    issue: Issue,
    config: TrackerConfig,
    runningIssueIDs: Set<IssueID>,
    claimedIssueIDs: Set<IssueID>
  ) -> Bool {
    // Must be OPEN native issue state
    guard issue.issueState == "OPEN" else { return false }

    // Project status must be in active_states
    guard config.activeStates.contains(issue.state) else { return false }

    // Must not be in terminal states
    guard !config.terminalStates.contains(issue.state) else { return false }

    // Must not be already running or claimed
    guard !runningIssueIDs.contains(issue.id) else { return false }
    guard !claimedIssueIDs.contains(issue.id) else { return false }

    // Blocker rules must pass
    guard !isBlocked(issue: issue, config: config) else { return false }

    return true
  }

  public static func isBlocked(issue: Issue, config: TrackerConfig) -> Bool {
    for blocker in issue.blockedBy {
      // Closed blockers never block
      if blocker.issueState == "CLOSED" { continue }

      // Open blocker in blocked_states blocks dispatch
      if config.blockedStates.contains(blocker.state) {
        return true
      }

      // Open blocker not in any configured state is treated as not represented in the project
      let allConfiguredStates = Set(
        config.activeStates + config.terminalStates + config.blockedStates)
      if !allConfiguredStates.contains(blocker.state) {
        return true
      }
    }
    return false
  }

  public static func sortCandidates(_ candidates: [Issue]) -> [Issue] {
    candidates.sorted { a, b in
      // 1. priority ascending, null last
      let aPriority = a.priority ?? Int.max
      let bPriority = b.priority ?? Int.max
      if aPriority != bPriority { return aPriority < bPriority }

      // 2. created_at oldest first
      let aCreated = a.createdAt ?? ""
      let bCreated = b.createdAt ?? ""
      if aCreated != bCreated { return aCreated < bCreated }

      // 3. identifier lexicographic
      return a.identifier.rawValue < b.identifier.rawValue
    }
  }
}

// MARK: - Retry Queue (Section 8.5)

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

// MARK: - Reconciliation Action (Section 7.4)

public enum ReconciliationAction: Equatable, Sendable {
  case continueRunning
  case cancelAndCleanup(reason: String)
  case cancelWithoutCleanup(reason: String)
  case refreshSnapshot
}

public enum Reconciler {
  public static func evaluate(
    issue: Issue,
    config: TrackerConfig
  ) -> ReconciliationAction {
    // Closed native issues are terminal overrides
    if issue.issueState == "CLOSED" {
      return .cancelAndCleanup(reason: "Issue closed")
    }

    // Terminal project states stop the run and trigger workspace cleanup
    if config.terminalStates.contains(issue.state) {
      return .cancelAndCleanup(reason: "Terminal project state: \(issue.state)")
    }

    // Non-active, non-terminal states stop the run without workspace cleanup
    if !config.activeStates.contains(issue.state) {
      return .cancelWithoutCleanup(reason: "Non-active project state: \(issue.state)")
    }

    // Active states refresh the in-memory issue snapshot
    return .refreshSnapshot
  }
}

// MARK: - Orchestrator Tick (Section 8.4)

public struct TickResult: Equatable, Sendable {
  public let reconciled: Int
  public let candidatesFetched: Int
  public let dispatched: Int
  public let retriesProcessed: Int

  public init(reconciled: Int, candidatesFetched: Int, dispatched: Int, retriesProcessed: Int) {
    self.reconciled = reconciled
    self.candidatesFetched = candidatesFetched
    self.dispatched = dispatched
    self.retriesProcessed = retriesProcessed
  }
}

// MARK: - Orchestrator Delegate

public protocol OrchestratorDelegate: Sendable {
  func orchestratorDidDispatch(issueID: IssueID, issueIdentifier: IssueIdentifier) async
  func orchestratorDidCancel(issueID: IssueID, reason: String, cleanup: Bool) async
  func orchestratorDidRefreshSnapshot(issue: Issue) async
  func orchestratorDidRetry(record: RetryRecord) async
}

// MARK: - Orchestrator (Section 8)

public final class Orchestrator: @unchecked Sendable {
  private let lock = NSLock()
  private let tracker: any TrackerAdapting
  private let config: WorkflowConfig
  private let retryQueue: RetryQueue
  private let delegate: any OrchestratorDelegate
  private let slotManager: ConcurrencySlotManager

  private var _runningIssueIDs: Set<IssueID> = []
  private var _claimedIssueIDs: Set<IssueID> = []
  private var _runningStateCount: [String: Int] = [:]

  public init(
    tracker: any TrackerAdapting,
    config: WorkflowConfig,
    retryQueue: RetryQueue = RetryQueue(),
    delegate: any OrchestratorDelegate
  ) {
    self.tracker = tracker
    self.config = config
    self.retryQueue = retryQueue
    self.delegate = delegate
    self.slotManager = ConcurrencySlotManager(config: config.agent)
  }

  // MARK: - State Management

  public var runningIssueIDs: Set<IssueID> {
    lock.lock()
    defer { lock.unlock() }
    return _runningIssueIDs
  }

  public var claimedIssueIDs: Set<IssueID> {
    lock.lock()
    defer { lock.unlock() }
    return _claimedIssueIDs
  }

  public func markRunning(issueID: IssueID, state: String) {
    lock.lock()
    _runningIssueIDs.insert(issueID)
    _claimedIssueIDs.remove(issueID)
    _runningStateCount[state, default: 0] += 1
    lock.unlock()
  }

  public func markCompleted(issueID: IssueID, state: String) {
    lock.lock()
    _runningIssueIDs.remove(issueID)
    _claimedIssueIDs.remove(issueID)
    if let count = _runningStateCount[state], count > 1 {
      _runningStateCount[state] = count - 1
    } else {
      _runningStateCount.removeValue(forKey: state)
    }
    lock.unlock()
  }

  public func markClaimed(issueID: IssueID) {
    lock.lock()
    _claimedIssueIDs.insert(issueID)
    lock.unlock()
  }

  // MARK: - Tick Execution (Section 8.4)

  public func tick() async throws -> TickResult {
    // Step 1: Process due retries
    let retriesProcessed = await processRetries()

    // Step 2: Reconcile running issues
    let reconciled = await reconcile()

    // Step 3: Fetch candidates
    let candidates: [Issue]
    do {
      candidates = try await tracker.fetchCandidateIssues()
    } catch {
      return TickResult(
        reconciled: reconciled, candidatesFetched: 0, dispatched: 0,
        retriesProcessed: retriesProcessed)
    }

    // Step 4: Filter eligible and sort
    let running = runningIssueIDs
    let claimed = claimedIssueIDs
    let eligible = CandidateEligibility.filterEligible(
      candidates: candidates,
      config: config.tracker,
      runningIssueIDs: running,
      claimedIssueIDs: claimed
    )
    let sorted = CandidateEligibility.sortCandidates(eligible)

    // Step 5: Dispatch until slots exhausted
    var dispatched = 0

    for issue in sorted {
      let (stateCount, totalRunning) = readDispatchState(forState: issue.state)

      guard
        slotManager.canDispatch(
          currentRunning: totalRunning,
          state: issue.state,
          currentInState: stateCount
        )
      else { break }

      markClaimed(issueID: issue.id)
      await delegate.orchestratorDidDispatch(issueID: issue.id, issueIdentifier: issue.identifier)
      dispatched += 1
    }

    return TickResult(
      reconciled: reconciled,
      candidatesFetched: candidates.count,
      dispatched: dispatched,
      retriesProcessed: retriesProcessed
    )
  }

  private nonisolated func readDispatchState(forState state: String) -> (
    stateCount: Int, totalRunning: Int
  ) {
    lock.withLock {
      let stateCount = _runningStateCount[state, default: 0]
      let totalRunning = _runningIssueIDs.count + _claimedIssueIDs.count
      return (stateCount, totalRunning)
    }
  }

  // MARK: - Reconciliation (Section 7.4)

  private func reconcile() async -> Int {
    let running = runningIssueIDs
    guard !running.isEmpty else { return 0 }

    let states: [IssueID: String]
    do {
      states = try await tracker.fetchIssueStatesByIDs(Array(running))
    } catch {
      return 0
    }

    var reconciled = 0
    for (_, _) in states {
      reconciled += 1
    }
    return reconciled
  }

  // MARK: - Retry Processing

  private func processRetries() async -> Int {
    let dueEntries = retryQueue.dueEntries()
    for entry in dueEntries {
      _ = retryQueue.dequeue(issueID: entry.issueID)
      await delegate.orchestratorDidRetry(record: entry)
    }
    return dueEntries.count
  }
}

// MARK: - Stub Tracker (for testing)

public final class StubTracker: TrackerAdapting, @unchecked Sendable {
  private let lock = NSLock()
  private var _candidates: [Issue] = []
  private var _issuesByStates: [Issue] = []
  private var _statesByIDs: [IssueID: String] = [:]
  private var _fetchError: Error?

  public init() {}

  public func setCandidates(_ issues: [Issue]) {
    lock.lock()
    _candidates = issues
    lock.unlock()
  }

  public func setIssuesByStates(_ issues: [Issue]) {
    lock.lock()
    _issuesByStates = issues
    lock.unlock()
  }

  public func setStatesByIDs(_ states: [IssueID: String]) {
    lock.lock()
    _statesByIDs = states
    lock.unlock()
  }

  public func setFetchError(_ error: Error?) {
    lock.lock()
    _fetchError = error
    lock.unlock()
  }

  public nonisolated func fetchCandidateIssues() async throws -> [Issue] {
    let (error, candidates) = lock.withLock { (_fetchError, _candidates) }
    if let error { throw error }
    return candidates
  }

  public nonisolated func fetchIssuesByStates(_ stateNames: [String]) async throws -> [Issue] {
    let (error, issues) = lock.withLock { (_fetchError, _issuesByStates) }
    if let error { throw error }
    return issues.filter { stateNames.contains($0.state) }
  }

  public nonisolated func fetchIssueStatesByIDs(_ issueIDs: [IssueID]) async throws -> [IssueID:
    String]
  {
    let (error, states) = lock.withLock { (_fetchError, _statesByIDs) }
    if let error { throw error }
    return states.filter { issueIDs.contains($0.key) }
  }
}

// MARK: - Stub Orchestrator Delegate (for testing)

public final class StubOrchestratorDelegate: OrchestratorDelegate, @unchecked Sendable {
  private let lock = NSLock()
  private var _dispatched: [(IssueID, IssueIdentifier)] = []
  private var _canceled: [(IssueID, String, Bool)] = []
  private var _refreshed: [Issue] = []
  private var _retried: [RetryRecord] = []

  public init() {}

  public var dispatched: [(IssueID, IssueIdentifier)] {
    lock.lock()
    defer { lock.unlock() }
    return _dispatched
  }

  public var canceled: [(IssueID, String, Bool)] {
    lock.lock()
    defer { lock.unlock() }
    return _canceled
  }

  public var refreshed: [Issue] {
    lock.lock()
    defer { lock.unlock() }
    return _refreshed
  }

  public var retried: [RetryRecord] {
    lock.lock()
    defer { lock.unlock() }
    return _retried
  }

  public nonisolated func orchestratorDidDispatch(
    issueID: IssueID, issueIdentifier: IssueIdentifier
  ) async {
    lock.withLock { _dispatched.append((issueID, issueIdentifier)) }
  }

  public nonisolated func orchestratorDidCancel(issueID: IssueID, reason: String, cleanup: Bool)
    async
  {
    lock.withLock { _canceled.append((issueID, reason, cleanup)) }
  }

  public nonisolated func orchestratorDidRefreshSnapshot(issue: Issue) async {
    lock.withLock { _refreshed.append(issue) }
  }

  public nonisolated func orchestratorDidRetry(record: RetryRecord) async {
    lock.withLock { _retried.append(record) }
  }
}
