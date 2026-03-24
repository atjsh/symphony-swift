import Foundation
import Testing
import SymphonyShared

@Test func scalarValueTypesRoundTripAndValidate() throws {
    #expect(try roundTrip(IssueID("issue-1")) == IssueID("issue-1"))
    #expect(try roundTrip(RunID("run-1")) == RunID("run-1"))
    #expect(try roundTrip(SessionID(threadID: "thread-1", turnID: "turn-2")) == SessionID("thread-1-turn-2"))
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

    let validEndpoint = try JSONDecoder().decode(ServerEndpoint.self, from: Data(#"{"scheme":"https","host":"example.com","port":9443}"#.utf8))
    #expect(validEndpoint.url?.absoluteString == "https://example.com:9443")
}

@Test func tokenUsageAndRunLogStatsRoundTrip() throws {
    let derived = try roundTrip(TokenUsage(inputTokens: 9, outputTokens: 4))
    #expect(derived.totalTokens == 13)

    let explicitJSON = #"{"input_tokens":3,"output_tokens":2,"total_tokens":5}"#
    let explicit = try JSONDecoder().decode(TokenUsage.self, from: Data(explicitJSON.utf8))
    #expect(explicit == TokenUsage(inputTokens: 3, outputTokens: 2))

    do {
        _ = try JSONDecoder().decode(TokenUsage.self, from: Data(#"{"input_tokens":3,"output_tokens":2,"total_tokens":6}"#.utf8))
        Issue.record("Expected invalid explicit total to fail.")
    } catch let error as SymphonySharedValidationError {
        #expect(error == .invalidTokenUsage(expectedTotal: 5, actualTotal: 6))
    }

    let stats = try roundTrip(RunLogStats(eventCount: 8, latestSequence: EventSequence(7)))
    #expect(stats.eventCount == 8)
    #expect(stats.latestSequence == EventSequence(7))

    let derivedFromDecode = try JSONDecoder().decode(TokenUsage.self, from: Data(#"{"input_tokens":4,"output_tokens":6}"#.utf8))
    #expect(derivedFromDecode.totalTokens == 10)
}

@Test func issueAndRunDTOsRoundTrip() throws {
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
        currentRunID: RunID("run-1"),
        currentSessionID: SessionID(threadID: "thread-1", turnID: "turn-2")
    )

    let runSummary = RunSummary(
        runID: RunID("run-1"),
        issueID: issue.id,
        issueIdentifier: identifier,
        attempt: 2,
        status: "running",
        startedAt: "2026-03-24T02:00:00Z",
        endedAt: "2026-03-24T03:00:00Z",
        workspacePath: "/tmp/workspace",
        sessionID: SessionID(threadID: "thread-1", turnID: "turn-2"),
        lastError: "none"
    )

    let session = CodexSession(
        sessionID: SessionID(threadID: "thread-1", turnID: "turn-2"),
        threadID: "thread-1",
        turnID: "turn-2",
        runID: RunID("run-1"),
        codexAppServerPID: "123",
        status: "active",
        lastEventType: "assistant",
        lastEventAt: "2026-03-24T04:00:00Z",
        turnCount: 3,
        tokenUsage: TokenUsage(inputTokens: 11, outputTokens: 13)
    )

    let runDetail = RunDetail(
        runID: RunID("run-1"),
        issueID: issue.id,
        issueIdentifier: identifier,
        attempt: 2,
        status: "running",
        startedAt: "2026-03-24T02:00:00Z",
        endedAt: "2026-03-24T03:00:00Z",
        workspacePath: "/tmp/workspace",
        sessionID: session.sessionID,
        lastError: "none",
        issue: issue,
        turnCount: 3,
        lastCodexEvent: "assistant",
        lastCodexMessage: "hello",
        tokens: TokenUsage(inputTokens: 11, outputTokens: 13),
        logs: RunLogStats(eventCount: 3, latestSequence: EventSequence(2))
    )

    let issueDetail = IssueDetail(issue: issue, latestRun: runSummary, workspacePath: "/tmp/workspace", recentSessions: [session])

    #expect(try roundTrip(blocker) == blocker)
    #expect((try roundTrip(issue)).labels == ["bug", "needs-test"])
    #expect(try roundTrip(issueSummary) == issueSummary)
    #expect(try roundTrip(runSummary) == runSummary)
    #expect(try roundTrip(session) == session)
    #expect(try roundTrip(runDetail) == runDetail)
    #expect(try roundTrip(issueDetail) == issueDetail)
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

@Test func eventCursorAndRolloutEventRoundTrip() throws {
    let sessionID = SessionID(threadID: "thread-1", turnID: "turn-9")
    let cursor = EventCursor(sessionID: sessionID, lastDeliveredSequence: EventSequence(99))
    let decoded = try roundTrip(cursor)

    #expect(cursor.description == cursor.rawValue)
    #expect(decoded.sessionID == sessionID)
    #expect(decoded.lastDeliveredSequence == EventSequence(99))
    #expect(EventCursor(rawValue: "%%%").sessionID == nil)
    #expect(EventCursor(rawValue: "%%%").lastDeliveredSequence == nil)

    let rawJSON = #"{"type":"message","payload":{"text":"hello"}}"#
    let event = CodexRolloutEvent(
        sessionID: sessionID,
        sequence: EventSequence(4),
        timestamp: "2026-03-24T10:00:00Z",
        rawJSON: rawJSON,
        topLevelType: "message",
        payloadType: "assistant"
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
