import Foundation
import SymphonyShared
import Testing

@testable import SymphonyServerCore

// MARK: - Test Issue Helper

private func makeIssue(
  id: String = "issue-1",
  owner: String = "org",
  repo: String = "repo",
  number: Int = 1,
  state: String = "In Progress",
  issueState: String = "OPEN",
  priority: Int? = nil,
  createdAt: String? = nil,
  blockedBy: [BlockerReference] = []
) throws -> SymphonyShared.Issue {
  SymphonyShared.Issue(
    id: IssueID(id),
    identifier: try IssueIdentifier(validating: "\(owner)/\(repo)#\(number)"),
    repository: "\(owner)/\(repo)",
    number: number,
    title: "Issue \(number)",
    description: nil,
    priority: priority,
    state: state,
    issueState: issueState,
    projectItemID: nil,
    url: nil,
    labels: [],
    blockedBy: blockedBy,
    createdAt: createdAt,
    updatedAt: nil
  )
}

// MARK: - CandidateEligibility Tests

@Test func candidateEligibilityBasicEligible() throws {
  let issue = try makeIssue(state: "In Progress", issueState: "OPEN")
  let config = TrackerConfig.defaults

  let eligible = CandidateEligibility.isEligible(
    issue: issue,
    config: config,
    runningIssueIDs: [],
    claimedIssueIDs: []
  )
  #expect(eligible)
}

@Test func candidateEligibilityClosedIssueNotEligible() throws {
  let issue = try makeIssue(issueState: "CLOSED")
  let config = TrackerConfig.defaults

  let eligible = CandidateEligibility.isEligible(
    issue: issue,
    config: config,
    runningIssueIDs: [],
    claimedIssueIDs: []
  )
  #expect(!eligible)
}

@Test func candidateEligibilityNonActiveStateNotEligible() throws {
  let issue = try makeIssue(state: "Backlog")
  let config = TrackerConfig.defaults

  let eligible = CandidateEligibility.isEligible(
    issue: issue,
    config: config,
    runningIssueIDs: [],
    claimedIssueIDs: []
  )
  #expect(!eligible)
}

@Test func candidateEligibilityTerminalStateNotEligible() throws {
  let config = TrackerConfig(activeStates: ["Done"], terminalStates: ["Done"])
  let issue = try makeIssue(state: "Done")

  let eligible = CandidateEligibility.isEligible(
    issue: issue,
    config: config,
    runningIssueIDs: [],
    claimedIssueIDs: []
  )
  #expect(!eligible)
}

@Test func candidateEligibilityAlreadyRunningNotEligible() throws {
  let issue = try makeIssue(id: "running-1")

  let eligible = CandidateEligibility.isEligible(
    issue: issue,
    config: .defaults,
    runningIssueIDs: [IssueID("running-1")],
    claimedIssueIDs: []
  )
  #expect(!eligible)
}

@Test func candidateEligibilityAlreadyClaimedNotEligible() throws {
  let issue = try makeIssue(id: "claimed-1")

  let eligible = CandidateEligibility.isEligible(
    issue: issue,
    config: .defaults,
    runningIssueIDs: [],
    claimedIssueIDs: [IssueID("claimed-1")]
  )
  #expect(!eligible)
}

@Test func candidateEligibilityBlockedNotEligible() throws {
  let blocker = BlockerReference(
    issueID: IssueID("blocker-1"),
    identifier: try IssueIdentifier(validating: "org/repo#99"),
    state: "Todo",
    issueState: "OPEN",
    url: nil
  )
  let issue = try makeIssue(blockedBy: [blocker])

  let eligible = CandidateEligibility.isEligible(
    issue: issue,
    config: .defaults,
    runningIssueIDs: [],
    claimedIssueIDs: []
  )
  #expect(!eligible)
}

@Test func candidateEligibilityClosedBlockerDoesNotBlock() throws {
  let blocker = BlockerReference(
    issueID: IssueID("blocker-1"),
    identifier: try IssueIdentifier(validating: "org/repo#99"),
    state: "Todo",
    issueState: "CLOSED",
    url: nil
  )
  let issue = try makeIssue(blockedBy: [blocker])

  let eligible = CandidateEligibility.isEligible(
    issue: issue,
    config: .defaults,
    runningIssueIDs: [],
    claimedIssueIDs: []
  )
  #expect(eligible)
}

@Test func candidateEligibilityBlockerNotInProjectBlocks() throws {
  let blocker = BlockerReference(
    issueID: IssueID("blocker-1"),
    identifier: try IssueIdentifier(validating: "org/repo#99"),
    state: "UnknownState",
    issueState: "OPEN",
    url: nil
  )
  let issue = try makeIssue(blockedBy: [blocker])

  let eligible = CandidateEligibility.isEligible(
    issue: issue,
    config: .defaults,
    runningIssueIDs: [],
    claimedIssueIDs: []
  )
  #expect(!eligible)
}

@Test func candidateEligibilityFilterEligible() throws {
  let issues = [
    try makeIssue(id: "1", number: 1, state: "In Progress"),
    try makeIssue(id: "2", number: 2, issueState: "CLOSED"),
    try makeIssue(id: "3", number: 3, state: "In Progress"),
  ]

  let eligible = CandidateEligibility.filterEligible(
    candidates: issues,
    config: .defaults,
    runningIssueIDs: [],
    claimedIssueIDs: []
  )
  #expect(eligible.count == 2)
}

// MARK: - Candidate Sorting Tests

@Test func candidateSortByPriorityAscending() throws {
  let issues = [
    try makeIssue(id: "3", number: 3, priority: 3),
    try makeIssue(id: "1", number: 1, priority: 1),
    try makeIssue(id: "2", number: 2, priority: 2),
  ]

  let sorted = CandidateEligibility.sortCandidates(issues)
  #expect(sorted[0].number == 1)
  #expect(sorted[1].number == 2)
  #expect(sorted[2].number == 3)
}

@Test func candidateSortNullPriorityLast() throws {
  let issues = [
    try makeIssue(id: "n", number: 1, priority: nil),
    try makeIssue(id: "p", number: 2, priority: 1),
  ]

  let sorted = CandidateEligibility.sortCandidates(issues)
  #expect(sorted[0].number == 2)
  #expect(sorted[1].number == 1)
}

@Test func candidateSortByCreatedAt() throws {
  let issues = [
    try makeIssue(id: "2", number: 2, priority: 1, createdAt: "2024-02-01T00:00:00Z"),
    try makeIssue(id: "1", number: 1, priority: 1, createdAt: "2024-01-01T00:00:00Z"),
  ]

  let sorted = CandidateEligibility.sortCandidates(issues)
  #expect(sorted[0].number == 1)
  #expect(sorted[1].number == 2)
}

@Test func candidateSortByIdentifier() throws {
  let issues = [
    try makeIssue(
      id: "b", owner: "org", repo: "b", number: 1, priority: 1, createdAt: "2024-01-01T00:00:00Z"),
    try makeIssue(
      id: "a", owner: "org", repo: "a", number: 1, priority: 1, createdAt: "2024-01-01T00:00:00Z"),
  ]

  let sorted = CandidateEligibility.sortCandidates(issues)
  #expect(sorted[0].identifier.rawValue == "org/a#1")
  #expect(sorted[1].identifier.rawValue == "org/b#1")
}

// MARK: - Blocker Semantics Tests

@Test func isBlockedNoBlockers() throws {
  let issue = try makeIssue()
  #expect(!CandidateEligibility.isBlocked(issue: issue, config: .defaults))
}

@Test func isBlockedOpenBlockerInBlockedStates() throws {
  let blocker = BlockerReference(
    issueID: IssueID("b1"),
    identifier: try IssueIdentifier(validating: "org/repo#2"),
    state: "Todo",
    issueState: "OPEN",
    url: nil
  )
  let issue = try makeIssue(blockedBy: [blocker])
  #expect(CandidateEligibility.isBlocked(issue: issue, config: .defaults))
}

@Test func isBlockedOpenBlockerNotInAnyConfiguredState() throws {
  let blocker = BlockerReference(
    issueID: IssueID("b1"),
    identifier: try IssueIdentifier(validating: "org/repo#2"),
    state: "NotConfigured",
    issueState: "OPEN",
    url: nil
  )
  let issue = try makeIssue(blockedBy: [blocker])
  #expect(CandidateEligibility.isBlocked(issue: issue, config: .defaults))
}

@Test func isBlockedOpenBlockerInActiveStateNotBlocked() throws {
  let blocker = BlockerReference(
    issueID: IssueID("b1"),
    identifier: try IssueIdentifier(validating: "org/repo#2"),
    state: "In Progress",
    issueState: "OPEN",
    url: nil
  )
  let issue = try makeIssue(blockedBy: [blocker])
  // "In Progress" is in activeStates and not in blockedStates
  #expect(!CandidateEligibility.isBlocked(issue: issue, config: .defaults))
}
