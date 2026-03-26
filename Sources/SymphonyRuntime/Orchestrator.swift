import Foundation
import SymphonyShared

// MARK: - Tracker Adapter Protocol (Section 7.1)

public protocol TrackerAdapting: Sendable {
  func fetchAllIssues() async throws -> [Issue]
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
    evaluate(issueState: issue.issueState, projectState: issue.state, config: config)
  }

  public static func evaluate(
    issueState: String,
    projectState: String,
    config: TrackerConfig
  ) -> ReconciliationAction {
    // Closed native issues are terminal overrides
    if issueState == "CLOSED" {
      return .cancelAndCleanup(reason: "Issue closed")
    }

    // Terminal project states stop the run and trigger workspace cleanup
    if config.terminalStates.contains(projectState) {
      return .cancelAndCleanup(reason: "Terminal project state: \(projectState)")
    }

    // Non-active, non-terminal states stop the run without workspace cleanup
    if !config.activeStates.contains(projectState) {
      return .cancelWithoutCleanup(reason: "Non-active project state: \(projectState)")
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
  func orchestratorDidSyncIssues(_ issues: [Issue]) async
  func orchestratorDidDispatch(issue: Issue) async
  func orchestratorDidCancel(
    issueID: IssueID, issueIdentifier: IssueIdentifier, reason: String, cleanup: Bool
  ) async
  func orchestratorDidRefreshSnapshot(issue: Issue) async
  func orchestratorDidRetry(issue: Issue, record: RetryRecord) async
}

// MARK: - Orchestrator (Section 8)

public final class Orchestrator: @unchecked Sendable {
  private let lock = NSLock()
  private var _tracker: any TrackerAdapting
  private var _config: WorkflowConfig
  private let retryQueue: RetryQueue
  private let delegate: any OrchestratorDelegate
  private var _slotManager: ConcurrencySlotManager

  private var _runningIssueIDs: Set<IssueID> = []
  private var _claimedIssueIDs: Set<IssueID> = []
  private var _runningStateCount: [String: Int] = [:]
  private var _runningIssues: [IssueID: Issue] = [:]
  private var _retryIssues: [IssueID: Issue] = [:]

  public init(
    tracker: any TrackerAdapting,
    config: WorkflowConfig,
    retryQueue: RetryQueue = RetryQueue(),
    delegate: any OrchestratorDelegate
  ) {
    self._tracker = tracker
    self._config = config
    self.retryQueue = retryQueue
    self.delegate = delegate
    self._slotManager = ConcurrencySlotManager(config: config.agent)
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

  public var config: WorkflowConfig {
    lock.withLock { _config }
  }

  public func reload(tracker: any TrackerAdapting, config: WorkflowConfig) {
    lock.withLock {
      _tracker = tracker
      _config = config
      _slotManager = ConcurrencySlotManager(config: config.agent)
    }
  }

  public func markRunning(issueID: IssueID, state: String) {
    lock.lock()
    _runningIssueIDs.insert(issueID)
    _claimedIssueIDs.remove(issueID)
    _runningStateCount[state, default: 0] += 1
    lock.unlock()
  }

  public func markRunning(issue: Issue) {
    lock.lock()
    _runningIssueIDs.insert(issue.id)
    _claimedIssueIDs.remove(issue.id)
    _runningStateCount[issue.state, default: 0] += 1
    _runningIssues[issue.id] = issue
    lock.unlock()
  }

  public func markCompleted(issueID: IssueID, state: String) {
    lock.lock()
    _runningIssueIDs.remove(issueID)
    _claimedIssueIDs.remove(issueID)
    _runningIssues.removeValue(forKey: issueID)
    _retryIssues.removeValue(forKey: issueID)
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

  @discardableResult
  public func enqueueRetry(
    issue: Issue,
    attempt: Int,
    delayMS: Int,
    error: String?,
    now: Date = Date()
  ) -> RetryRecord {
    let record = RetryRecord(
      issueID: issue.id,
      issueIdentifier: issue.identifier,
      attempt: attempt,
      dueAt: now.addingTimeInterval(Double(delayMS) / 1000),
      error: error
    )

    lock.withLock {
      _retryIssues[issue.id] = issue
      _claimedIssueIDs.insert(issue.id)
    }
    retryQueue.enqueue(record)
    return record
  }

  public func queuedRetryRecord(issueID: IssueID) -> RetryRecord? {
    retryQueue.entries[issueID]
  }

  // MARK: - Tick Execution (Section 8.4)

  public func tick() async throws -> TickResult {
    let current = currentExecutionInputs()

    // Step 1: Process due retries
    let retriesProcessed = await processRetries()

    // Step 2: Fetch the full project snapshot once, then reuse it for synchronization,
    // reconciliation, and candidate filtering.
    let allIssues: [Issue]
    do {
      allIssues = try await current.tracker.fetchAllIssues()
    } catch {
      return TickResult(
        reconciled: 0, candidatesFetched: 0, dispatched: 0,
        retriesProcessed: retriesProcessed)
    }

    await delegate.orchestratorDidSyncIssues(allIssues)

    // Step 3: Reconcile running issues against the latest snapshot.
    let reconciled = await reconcile(latestIssues: allIssues, config: current.config)

    // Step 4: Filter eligible and sort
    let running = runningIssueIDs
    let claimed = claimedIssueIDs
    let eligible = CandidateEligibility.filterEligible(
      candidates: allIssues,
      config: current.config.tracker,
      runningIssueIDs: running,
      claimedIssueIDs: claimed
    )
    let sorted = CandidateEligibility.sortCandidates(eligible)

    // Step 5: Dispatch until slots exhausted
    var dispatched = 0

    for issue in sorted {
      let (stateCount, totalRunning) = readDispatchState(forState: issue.state)

      guard
        current.slotManager.canDispatch(
          currentRunning: totalRunning,
          state: issue.state,
          currentInState: stateCount
        )
      else { break }

      markClaimed(issueID: issue.id)
      await delegate.orchestratorDidDispatch(issue: issue)
      dispatched += 1
    }

    return TickResult(
      reconciled: reconciled,
      candidatesFetched: allIssues.count,
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

  private func currentExecutionInputs() -> (
    tracker: any TrackerAdapting,
    config: WorkflowConfig,
    slotManager: ConcurrencySlotManager
  ) {
    lock.withLock { (_tracker, _config, _slotManager) }
  }

  private nonisolated func cachedRunningIssue(for issueID: IssueID) -> Issue? {
    lock.withLock { _runningIssues[issueID] }
  }

  private nonisolated func cacheRunningIssue(_ issue: Issue, for issueID: IssueID) {
    lock.withLock { _runningIssues[issueID] = issue }
  }

  // MARK: - Reconciliation (Section 7.4)

  private func reconcile(
    latestIssues: [Issue],
    config: WorkflowConfig
  ) async -> Int {
    let running = runningIssueIDs
    guard !running.isEmpty else { return 0 }

    let latestIssuesByID = Dictionary(uniqueKeysWithValues: latestIssues.map { ($0.id, $0) })
    return await evaluateReconciliation(
      running: running,
      latestIssuesByID: latestIssuesByID,
      config: config
    )
  }

  private func evaluateReconciliation(
    running: Set<IssueID>,
    latestIssuesByID: [IssueID: Issue],
    config: WorkflowConfig
  ) async -> Int {
    var reconciled = 0
    for issueID in running {
      reconciled += 1

      let cachedIssue = cachedRunningIssue(for: issueID)
      guard let latestIssue = latestIssuesByID[issueID] else {
        guard let cachedIssue else { continue }
        markCompleted(
          issueID: issueID,
          state: cachedIssue.state
        )
        await delegate.orchestratorDidCancel(
          issueID: issueID,
          issueIdentifier: cachedIssue.identifier,
          reason: "Issue no longer present in project snapshot",
          cleanup: false
        )
        continue
      }

      let action = Reconciler.evaluate(
        issueState: latestIssue.issueState,
        projectState: latestIssue.state,
        config: config.tracker
      )

      if case .cancelAndCleanup(let reason) = action {
        guard let cachedIssue else { continue }
        markCompleted(
          issueID: issueID,
          state: cachedIssue.state
        )
        await delegate.orchestratorDidCancel(
          issueID: issueID, issueIdentifier: cachedIssue.identifier,
          reason: reason, cleanup: true)
      } else if case .cancelWithoutCleanup(let reason) = action {
        guard let cachedIssue else { continue }
        markCompleted(
          issueID: issueID,
          state: cachedIssue.state
        )
        await delegate.orchestratorDidCancel(
          issueID: issueID, issueIdentifier: cachedIssue.identifier,
          reason: reason, cleanup: false)
      } else if case .refreshSnapshot = action {
        guard cachedIssue != nil else { continue }
        cacheRunningIssue(latestIssue, for: issueID)
        await delegate.orchestratorDidRefreshSnapshot(issue: latestIssue)
      }
    }
    return reconciled
  }

  // MARK: - Retry Processing

  private func processRetries() async -> Int {
    let dueEntries = retryQueue.dueEntries()
    for entry in dueEntries {
      _ = retryQueue.dequeue(issueID: entry.issueID)
      let issue = lock.withLock { _retryIssues.removeValue(forKey: entry.issueID) }
      guard let issue else { continue }
      await delegate.orchestratorDidRetry(issue: issue, record: entry)
    }
    return dueEntries.count
  }
}

// MARK: - Stub Tracker (for testing)

public final class StubTracker: TrackerAdapting, @unchecked Sendable {
  private let lock = NSLock()
  private var _allIssues: [Issue] = []
  private var _candidates: [Issue] = []
  private var _issuesByStates: [Issue] = []
  private var _statesByIDs: [IssueID: String] = [:]
  private var _fetchError: Error?

  public init() {}

  public func setAllIssues(_ issues: [Issue]) {
    lock.lock()
    _allIssues = issues
    lock.unlock()
  }

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

  public nonisolated func fetchAllIssues() async throws -> [Issue] {
    let (error, issues) = lock.withLock { (_fetchError, _allIssues) }
    if let error { throw error }
    return issues
  }

  public nonisolated func fetchCandidateIssues() async throws -> [Issue] {
    let (error, issues, candidates) = lock.withLock { (_fetchError, _allIssues, _candidates) }
    if let error { throw error }
    return candidates.isEmpty ? issues : candidates
  }

  public nonisolated func fetchIssuesByStates(_ stateNames: [String]) async throws -> [Issue] {
    let (error, issues, issuesByStates) = lock.withLock {
      (_fetchError, _allIssues, _issuesByStates)
    }
    if let error { throw error }
    let source = issuesByStates.isEmpty ? issues : issuesByStates
    return source.filter { stateNames.contains($0.state) }
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
  private var _synced: [Issue] = []
  private var _dispatched: [Issue] = []
  private var _canceled: [(IssueID, IssueIdentifier, String, Bool)] = []
  private var _refreshed: [Issue] = []
  private var _retried: [(Issue, RetryRecord)] = []

  public init() {}

  public var synced: [Issue] {
    lock.lock()
    defer { lock.unlock() }
    return _synced
  }

  public var dispatched: [Issue] {
    lock.lock()
    defer { lock.unlock() }
    return _dispatched
  }

  public var canceled: [(IssueID, IssueIdentifier, String, Bool)] {
    lock.lock()
    defer { lock.unlock() }
    return _canceled
  }

  public var refreshed: [Issue] {
    lock.lock()
    defer { lock.unlock() }
    return _refreshed
  }

  public var retried: [(Issue, RetryRecord)] {
    lock.lock()
    defer { lock.unlock() }
    return _retried
  }

  public nonisolated func orchestratorDidSyncIssues(_ issues: [Issue]) async {
    lock.withLock { _synced = issues }
  }

  public nonisolated func orchestratorDidDispatch(issue: Issue) async {
    lock.withLock { _dispatched.append(issue) }
  }

  public nonisolated func orchestratorDidCancel(
    issueID: IssueID, issueIdentifier: IssueIdentifier, reason: String, cleanup: Bool
  ) async {
    lock.withLock { _canceled.append((issueID, issueIdentifier, reason, cleanup)) }
  }

  public nonisolated func orchestratorDidRefreshSnapshot(issue: Issue) async {
    lock.withLock { _refreshed.append(issue) }
  }

  public nonisolated func orchestratorDidRetry(issue: Issue, record: RetryRecord) async {
    lock.withLock { _retried.append((issue, record)) }
  }
}
