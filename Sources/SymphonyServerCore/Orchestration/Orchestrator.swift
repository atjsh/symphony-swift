import Foundation
import SymphonyShared

// MARK: - Orchestrator (Section 8)

// SAFETY: @unchecked Sendable — all mutable state (_tracker, _config) is
// exclusively accessed through `lock.withLock`.
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
