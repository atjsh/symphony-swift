import Foundation
import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore
@testable import SymphonyShared

struct FixtureRecords {
  let issue: SymphonyShared.Issue
  let runDetail: RunDetail
  let session: AgentSession
}

func makeIssueProgressReport(issueID: IssueID) -> IssueProgressReportResponse {
  let file = RepositoryFileSummary(
    path: "Sources/App/Main.swift",
    category: .source,
    lineCount: 120,
    characterCount: 3_200,
    byteCount: 3_200
  )
  let activity = RepositoryGitActivitySummary(changedFileCount: 2, additions: 14, deletions: 3)
  let metrics = RepositoryMetricsSnapshot(
    fileCount: 5,
    sourceFileCount: 3,
    testFileCount: 1,
    otherFileCount: 1,
    lineCount: 640,
    characterCount: 15_000,
    byteCount: 15_000,
    largestFile: file,
    smallestFile: file,
    activity: activity
  )
  return IssueProgressReportResponse(
    issueID: issueID,
    generatedAt: "2026-03-24T12:00:00Z",
    report: RepositoryHistoryReport(
      headCommitID: "abcdef1234567890",
      summary: metrics,
      commits: [
        RepositoryHistoryCommit(
          commitID: "abcdef1234567890",
          shortID: "abcdef1",
          subject: "Implement progress report",
          authorName: "Taylor",
          committedAt: "2026-03-24T00:00:00Z",
          metrics: metrics,
          activity: activity
        )
      ],
      buckets: [
        RepositoryMetricsBucket(
          bucketID: "bucket-1",
          label: "Current",
          rangeStart: "2026-03-18T00:00:00Z",
          rangeEnd: "2026-03-24T23:59:59Z",
          metrics: metrics
        )
      ]
    ),
    syntaxHealth: RepositorySyntaxHealth(
      status: .configured,
      checkedFileCount: 4,
      diagnosticCount: 1,
      diagnostics: [
        RepositorySyntaxDiagnostic(
          path: "Sources/App/Main.swift",
          message: "Unexpected token",
          severity: "error",
          line: 18,
          column: 7
        )
      ]
    )
  )
}

func makeFixtureRecords() throws -> FixtureRecords {
  let identifier = try IssueIdentifier(validating: "atjsh/example#42")
  let issue = SymphonyShared.Issue(
    id: IssueID("issue-42"),
    identifier: identifier,
    repository: "atjsh/example",
    number: 42,
    title: "Implement provider-neutral server",
    description: "The bootstrap runtime must become a real API.",
    priority: 1,
    state: "in_progress",
    issueState: "OPEN",
    projectItemID: "item-42",
    url: "https://example.com/issues/42",
    labels: ["Server", "Spec"],
    blockedBy: [],
    createdAt: "2026-03-24T01:00:00Z",
    updatedAt: "2026-03-24T02:00:00Z"
  )

  let runDetail = RunDetail(
    runID: RunID("run-42"),
    issueID: issue.id,
    issueIdentifier: identifier,
    attempt: 1,
    status: "running",
    provider: "claude_code",
    providerSessionID: "provider-session-42",
    providerRunID: "provider-run-42",
    startedAt: "2026-03-24T03:00:00Z",
    endedAt: nil,
    workspacePath: "/tmp/symphony/atjsh_example_42",
    sessionID: SessionID("session-42"),
    lastError: nil,
    issue: issue,
    turnCount: 2,
    lastAgentEventType: "message",
    lastAgentMessage: "hello",
    tokens: try TokenUsage(inputTokens: 7, outputTokens: 5),
    logs: RunLogStats(eventCount: 0, latestSequence: nil)
  )

  let session = AgentSession(
    sessionID: SessionID("session-42"),
    provider: "claude_code",
    providerSessionID: "provider-session-42",
    providerThreadID: "thread-42",
    providerTurnID: "turn-42",
    providerRunID: "provider-run-42",
    runID: runDetail.runID,
    providerProcessPID: "999",
    status: "active",
    lastEventType: "message",
    lastEventAt: "2026-03-24T03:00:02Z",
    turnCount: 2,
    tokenUsage: try TokenUsage(inputTokens: 7, outputTokens: 5),
    latestRateLimitPayload: #"{"remaining":100}"#
  )

  return FixtureRecords(issue: issue, runDetail: runDetail, session: session)
}

func decodeBody<T: Decodable>(_ type: T.Type, from response: SymphonyHTTPResponse) throws
  -> T
{
  try JSONDecoder().decode(T.self, from: response.body)
}

struct StubIssueProgressReportGenerator: IssueProgressReportGenerating {
  let result: Result<IssueProgressReportResponse, IssueProgressReportError>

  func issueProgressReport(issueID: IssueID, workspacePath: String) throws
    -> IssueProgressReportResponse
  {
    switch result {
    case .success(let value):
      return value
    case .failure(let error):
      throw error
    }
  }
}
