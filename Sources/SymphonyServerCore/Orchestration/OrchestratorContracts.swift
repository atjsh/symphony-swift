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
