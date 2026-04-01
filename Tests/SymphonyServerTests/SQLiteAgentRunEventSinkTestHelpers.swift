import Foundation
import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore
@testable import SymphonyShared

func makeAgentRunSinkIssue(
  id: String = "I_1",
  number: Int = 1
) throws -> SymphonyShared.Issue {
  SymphonyShared.Issue(
    id: IssueID(id),
    identifier: try IssueIdentifier(validating: "owner/repo#\(number)"),
    repository: "owner/repo",
    number: number,
    title: "Persist runtime state",
    description: "Ensure the sink stores lifecycle updates.",
    priority: 1,
    state: "In Progress",
    issueState: "OPEN",
    projectItemID: nil,
    url: "https://github.com/owner/repo/issues/\(number)",
    labels: [],
    blockedBy: [],
    createdAt: "2026-03-26T01:00:00Z",
    updatedAt: "2026-03-26T01:00:00Z"
  )
}

func makeAgentRunSinkContext(
  issueID: IssueID = IssueID("I_1"),
  number: Int = 1,
  runID: String = "R_1",
  attempt: Int = 1
) throws -> RunContext {
  RunContext(
    issueID: issueID,
    issueIdentifier: try IssueIdentifier(validating: "owner/repo#\(number)"),
    runID: RunID(runID),
    attempt: attempt
  )
}

func makeAgentRunSinkTemporaryDirectory() throws -> URL {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    UUID().uuidString,
    isDirectory: true
  )
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  return root
}
