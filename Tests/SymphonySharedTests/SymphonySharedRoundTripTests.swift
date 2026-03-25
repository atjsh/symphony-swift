import Foundation
import SymphonyShared
import Testing

@Test func scalarValueTypesRoundTripAndValidate() throws {
  #expect(try roundTrip(IssueID("issue-1")) == IssueID("issue-1"))
  #expect(try roundTrip(RunID("run-1")) == RunID("run-1"))
  #expect(try roundTrip(SessionID("session-2")) == SessionID("session-2"))
  #expect(try roundTrip(EventSequence(42)) == EventSequence(42))
  #expect(EventSequence(1) < EventSequence(2))
  #expect(try roundTrip(WorkspaceKey("owner/repo#17")) == WorkspaceKey("owner/repo#17"))
  #expect(WorkspaceKey("owner/repo#17").rawValue == "owner_repo_17")
}

@Test func issueIdentifierAndServerEndpointValidationFailuresThrowExpectedErrors() throws {
  let direct = try IssueIdentifier(owner: "atjsh", repository: "example", number: 9)
  #expect(direct.rawValue == "atjsh/example#9")
  #expect(direct.description == "atjsh/example#9")
  #expect(direct.workspaceKey.description == "atjsh_example_9")

  do {
    _ = try IssueIdentifier(owner: "", repository: "repo", number: 1)
    Issue.record("Expected invalid owner to fail.")
  } catch let error as SymphonySharedValidationError {
    #expect(error == .invalidIssueIdentifier("/repo#1"))
  }

  do {
    _ = try IssueIdentifier(validating: " owner/repo#1")
    Issue.record("Expected leading whitespace to fail.")
  } catch let error as SymphonySharedValidationError {
    #expect(error == .invalidIssueIdentifier(" owner/repo#1"))
  }

  do {
    _ = try IssueIdentifier(validating: "owner/#1")
    Issue.record("Expected missing repository names to fail.")
  } catch let error as SymphonySharedValidationError {
    #expect(error == .invalidIssueIdentifier("owner/#1"))
  }

  do {
    _ = try ServerEndpoint(scheme: "", host: "localhost", port: 8080)
    Issue.record("Expected invalid endpoint to fail.")
  } catch let error as SymphonySharedValidationError {
    #expect(error == .invalidServerEndpoint)
  }

  let invalidEndpointJSON = #"{"scheme":"http","host":"localhost","port":70000}"#
  do {
    _ = try JSONDecoder().decode(ServerEndpoint.self, from: Data(invalidEndpointJSON.utf8))
    Issue.record("Expected invalid decoded endpoint to fail.")
  } catch let error as SymphonySharedValidationError {
    #expect(error == .invalidServerEndpoint)
  }

  let validEndpoint = try JSONDecoder().decode(
    ServerEndpoint.self, from: Data(#"{"scheme":"https","host":"example.com","port":9443}"#.utf8))
  #expect(validEndpoint.url?.absoluteString == "https://example.com:9443")
}

@Test func tokenUsageAndRunLogStatsRoundTrip() throws {
  let derived = try roundTrip(TokenUsage(inputTokens: 9, outputTokens: 4))
  #expect(derived.totalTokens == 13)

  let nullableJSON = #"{"input_tokens":3,"output_tokens":2}"#
  let explicit = try JSONDecoder().decode(TokenUsage.self, from: Data(nullableJSON.utf8))
  let expectedExplicit = try TokenUsage(inputTokens: 3, outputTokens: 2)
  #expect(explicit == expectedExplicit)

  let partial = try JSONDecoder().decode(TokenUsage.self, from: Data(#"{"total_tokens":5}"#.utf8))
  #expect(partial.inputTokens == nil)
  #expect(partial.outputTokens == nil)
  #expect(partial.totalTokens == 5)

  do {
    _ = try JSONDecoder().decode(
      TokenUsage.self, from: Data(#"{"input_tokens":3,"output_tokens":2,"total_tokens":6}"#.utf8))
    Issue.record("Expected invalid explicit total to fail.")
  } catch let error as SymphonySharedValidationError {
    #expect(error == .invalidTokenUsage(expectedTotal: 5, actualTotal: 6))
  }

  let stats = try roundTrip(RunLogStats(eventCount: 8, latestSequence: EventSequence(7)))
  #expect(stats.eventCount == 8)
  #expect(stats.latestSequence == EventSequence(7))
}

@Test func issueRunSessionAndEnvelopeDTOsRoundTrip() throws {
  let identifier = try IssueIdentifier(validating: "atjsh/example#42")
  let blocker = BlockerReference(
    issueID: IssueID("issue-2"),
    identifier: try IssueIdentifier(validating: "atjsh/example#7"),
    state: "blocked",
    issueState: "OPEN",
    url: "https://example.com/issues/7"
  )
  let issue = Issue(
    id: IssueID("issue-1"),
    identifier: identifier,
    repository: "atjsh/example",
    number: 42,
    title: "Implement feature",
    description: "Need to implement the feature.",
    priority: 1,
    state: "in_progress",
    issueState: "OPEN",
    projectItemID: "item-1",
    url: "https://example.com/issues/42",
    labels: ["Bug", "Needs-Test"],
    blockedBy: [blocker],
    createdAt: "2026-03-24T00:00:00Z",
    updatedAt: "2026-03-24T01:00:00Z"
  )

  let issueSummary = IssueSummary(
    issueID: issue.id,
    identifier: identifier,
    title: issue.title,
    state: issue.state,
    issueState: issue.issueState,
    priority: issue.priority,
    currentProvider: "claude_code",
    currentRunID: RunID("run-1"),
    currentSessionID: SessionID("session-1")
  )

  let runSummary = RunSummary(
    runID: RunID("run-1"),
    issueID: issue.id,
    issueIdentifier: identifier,
    attempt: 2,
    status: "running",
    provider: "claude_code",
    providerSessionID: "provider-session-77",
    providerRunID: "provider-run-88",
    startedAt: "2026-03-24T02:00:00Z",
    endedAt: "2026-03-24T03:00:00Z",
    workspacePath: "/tmp/workspace",
    sessionID: SessionID("session-1"),
    lastError: "none"
  )

  let session = AgentSession(
    sessionID: SessionID("session-1"),
    provider: "claude_code",
    providerSessionID: "provider-session-77",
    providerThreadID: "thread-1",
    providerTurnID: "turn-2",
    providerRunID: "provider-run-88",
    runID: RunID("run-1"),
    providerProcessPID: "123",
    status: "active",
    lastEventType: "message",
    lastEventAt: "2026-03-24T04:00:00Z",
    turnCount: 3,
    tokenUsage: try TokenUsage(inputTokens: 11, outputTokens: 13),
    latestRateLimitPayload: #"{"remaining":99}"#
  )

  let runDetail = RunDetail(
    runID: RunID("run-1"),
    issueID: issue.id,
    issueIdentifier: identifier,
    attempt: 2,
    status: "running",
    provider: "claude_code",
    providerSessionID: "provider-session-77",
    providerRunID: "provider-run-88",
    startedAt: "2026-03-24T02:00:00Z",
    endedAt: "2026-03-24T03:00:00Z",
    workspacePath: "/tmp/workspace",
    sessionID: session.sessionID,
    lastError: "none",
    issue: issue,
    turnCount: 3,
    lastAgentEventType: "message",
    lastAgentMessage: "hello",
    tokens: try TokenUsage(inputTokens: 11, outputTokens: 13),
    logs: RunLogStats(eventCount: 3, latestSequence: EventSequence(2))
  )

  let issueDetail = IssueDetail(
    issue: issue, latestRun: runSummary, workspacePath: "/tmp/workspace", recentSessions: [session])
  let health = HealthResponse(
    status: "ok", serverTime: "2026-03-24T12:00:00Z", version: "1.0.0", trackerKind: "github")
  let logs = LogEntriesResponse(
    sessionID: session.sessionID,
    provider: "claude_code",
    items: [
      AgentRawEvent(
        sessionID: session.sessionID,
        provider: "claude_code",
        sequence: EventSequence(1),
        timestamp: "2026-03-24T12:00:01Z",
        rawJSON: #"{"type":"message","payload":{"text":"hello"}}"#,
        providerEventType: "message",
        normalizedEventKind: "message"
      )
    ],
    nextCursor: EventCursor(sessionID: session.sessionID, lastDeliveredSequence: EventSequence(1)),
    hasMore: false
  )
  let refresh = RefreshResponse(queued: true, requestedAt: "2026-03-24T12:00:00Z")
  let errorEnvelope = ErrorEnvelope(
    error: ErrorPayload(code: "missing_issue", message: "Issue not found."))
  let issueList = IssuesResponse(items: [issueSummary])

  #expect(try roundTrip(blocker) == blocker)
  #expect((try roundTrip(issue)).labels == ["bug", "needs-test"])
  #expect(try roundTrip(issueSummary) == issueSummary)
  #expect(try roundTrip(runSummary) == runSummary)
  #expect(try roundTrip(session) == session)
  #expect(try roundTrip(runDetail) == runDetail)
  #expect(try roundTrip(issueDetail) == issueDetail)
  #expect(try roundTrip(health) == health)
  #expect(try roundTrip(issueList) == issueList)
  #expect(try roundTrip(logs) == logs)
  #expect(try roundTrip(refresh) == refresh)
  #expect(try roundTrip(errorEnvelope) == errorEnvelope)
  #expect(identifier.description == identifier.rawValue)
  #expect(issue.identifier.workspaceKey.description == "atjsh_example_42")

  let sparseIssueJSON = #"""
    {
      "id": "issue-9",
      "identifier": "atjsh/example#9",
      "repository": "atjsh/example",
      "number": 9,
      "title": "Sparse",
      "state": "open",
      "issue_state": "OPEN"
    }
    """#
  let sparseIssue = try JSONDecoder().decode(Issue.self, from: Data(sparseIssueJSON.utf8))
  #expect(sparseIssue.labels.isEmpty)
  #expect(sparseIssue.blockedBy.isEmpty)
}

@Test func eventCursorAndRawEventRoundTrip() throws {
  let sessionID = SessionID("session-9")
  let cursor = EventCursor(sessionID: sessionID, lastDeliveredSequence: EventSequence(99))
  let decoded = try roundTrip(cursor)

  #expect(cursor.description == cursor.rawValue)
  #expect(decoded.sessionID == sessionID)
  #expect(decoded.lastDeliveredSequence == EventSequence(99))
  #expect(EventCursor(rawValue: "%%%").sessionID == nil)
  #expect(EventCursor(rawValue: "%%%").lastDeliveredSequence == nil)

  let rawJSON = #"{"type":"message","payload":{"text":"hello"}}"#
  let event = AgentRawEvent(
    sessionID: sessionID,
    provider: "copilot_cli",
    sequence: EventSequence(4),
    timestamp: "2026-03-24T10:00:00Z",
    rawJSON: rawJSON,
    providerEventType: "message",
    normalizedEventKind: "message"
  )
  let roundTripped = try roundTrip(event)
  #expect(roundTripped == event)
  #expect(roundTripped.rawJSON == rawJSON)

  let workspaceKey = WorkspaceKey("space and/slash")
  #expect(workspaceKey.description == "space_and_slash")
}

private func roundTrip<T: Codable & Hashable>(_ value: T) throws -> T {
  let data = try JSONEncoder().encode(value)
  return try JSONDecoder().decode(T.self, from: data)
}
