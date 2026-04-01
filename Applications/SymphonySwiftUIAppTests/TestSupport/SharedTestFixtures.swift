import Foundation
import SymphonyShared

@testable import SymphonySwiftUIApp

func makeIssueSummary() -> IssueSummary {
  IssueSummary(
    issueID: IssueID("issue-42"),
    identifier: try! IssueIdentifier(validating: "atjsh/example#42"),
    title: "Implement provider-neutral server",
    state: "in_progress",
    issueState: "OPEN",
    priority: 1,
    currentProvider: "claude_code",
    currentRunID: RunID("run-42"),
    currentSessionID: SessionID("session-42")
  )
}

func makeIssueDetail() -> IssueDetail {
  let issue = SymphonyShared.Issue(
    id: IssueID("issue-42"),
    identifier: try! IssueIdentifier(validating: "atjsh/example#42"),
    repository: "atjsh/example",
    number: 42,
    title: "Implement provider-neutral server",
    description: "The bootstrap runtime must become a real API.",
    priority: 1,
    state: "in_progress",
    issueState: "OPEN",
    projectItemID: "item-42",
    url: "https://example.com/issues/42",
    labels: ["Server"],
    blockedBy: [],
    createdAt: "2026-03-24T01:00:00Z",
    updatedAt: "2026-03-24T02:00:00Z"
  )
  let run = makeRunSummary()
  let session = AgentSession(
    sessionID: SessionID("session-42"),
    provider: "claude_code",
    providerSessionID: "provider-session-42",
    providerThreadID: "thread-42",
    providerTurnID: "turn-42",
    providerRunID: "provider-run-42",
    runID: RunID("run-42"),
    providerProcessPID: "999",
    status: "active",
    lastEventType: "message",
    lastEventAt: "2026-03-24T03:00:02Z",
    turnCount: 2,
    tokenUsage: try! TokenUsage(inputTokens: 7, outputTokens: 5),
    latestRateLimitPayload: nil
  )
  return IssueDetail(
    issue: issue, latestRun: run, workspacePath: "/tmp/symphony/atjsh_example_42",
    recentSessions: [session])
}

func makeRunSummary() -> RunSummary {
  RunSummary(
    runID: RunID("run-42"),
    issueID: IssueID("issue-42"),
    issueIdentifier: try! IssueIdentifier(validating: "atjsh/example#42"),
    attempt: 1,
    status: "running",
    provider: "claude_code",
    providerSessionID: "provider-session-42",
    providerRunID: "provider-run-42",
    startedAt: "2026-03-24T03:00:00Z",
    endedAt: nil,
    workspacePath: "/tmp/symphony/atjsh_example_42",
    sessionID: SessionID("session-42"),
    lastError: nil
  )
}

func makeRunDetail() -> RunDetail {
  RunDetail(
    runID: RunID("run-42"),
    issueID: IssueID("issue-42"),
    issueIdentifier: try! IssueIdentifier(validating: "atjsh/example#42"),
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
    issue: makeIssueDetail().issue,
    turnCount: 2,
    lastAgentEventType: "message",
    lastAgentMessage: "hello",
    tokens: try! TokenUsage(inputTokens: 7, outputTokens: 5),
    logs: RunLogStats(eventCount: 1, latestSequence: EventSequence(1))
  )
}

func makeEvent(sequence: Int, kind: String) -> AgentRawEvent {
  AgentRawEvent(
    sessionID: SessionID("session-42"),
    provider: "claude_code",
    sequence: EventSequence(sequence),
    timestamp: "2026-03-24T03:00:0\(sequence)Z",
    rawJSON: #"{"type":"event","payload":{"text":"hello"}}"#,
    providerEventType: "event",
    normalizedEventKind: kind
  )
}

func makeEvent(sequence: Int, kind: String, rawJSON: String) -> AgentRawEvent {
  AgentRawEvent(
    sessionID: SessionID("session-42"),
    provider: "claude_code",
    sequence: EventSequence(sequence),
    timestamp: "2026-03-24T00:00:0\(sequence)Z",
    rawJSON: rawJSON,
    providerEventType: "event",
    normalizedEventKind: kind
  )
}

func makeIssueProgressReport(
  issueID: IssueID = IssueID("issue-42"),
  headCommitID: String = "abcdef1234567890",
  lineCount: Int = 640,
  syntaxHealth: RepositorySyntaxHealth? = nil
) -> IssueProgressReportResponse {
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
    lineCount: lineCount,
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
      headCommitID: headCommitID,
      summary: metrics,
      commits: [
        RepositoryHistoryCommit(
          commitID: headCommitID,
          shortID: String(headCommitID.prefix(7)),
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
    syntaxHealth: syntaxHealth
      ?? RepositorySyntaxHealth(
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
