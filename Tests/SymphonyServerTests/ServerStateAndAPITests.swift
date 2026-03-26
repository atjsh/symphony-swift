import Foundation
import SymphonyShared
import Testing

@testable import SymphonyRuntime

@Test func sqliteStorePersistsProviderNeutralStateAndReplaysLogsByCursor() throws {
  let databaseURL = try makeTemporaryDirectory().appendingPathComponent("symphony.sqlite3")
  let fixture = try makeFixtureRecords()

  let store = try SQLiteServerStateStore(databaseURL: databaseURL)
  try store.upsertIssue(fixture.issue)
  try store.upsertRun(fixture.runDetail)
  try store.upsertSession(fixture.session)

  let firstEvent = try store.appendEvent(
    sessionID: fixture.session.sessionID,
    provider: fixture.session.provider,
    timestamp: "2026-03-24T03:00:01Z",
    rawJSON: #"{"type":"status","payload":{"message":"starting"}}"#,
    providerEventType: "status",
    normalizedEventKind: "status"
  )
  let secondEvent = try store.appendEvent(
    sessionID: fixture.session.sessionID,
    provider: fixture.session.provider,
    timestamp: "2026-03-24T03:00:02Z",
    rawJSON: #"{"type":"message","payload":{"text":"working"}}"#,
    providerEventType: "message",
    normalizedEventKind: "message"
  )

  #expect(firstEvent.sequence == EventSequence(1))
  #expect(secondEvent.sequence == EventSequence(2))

  let reopened = try SQLiteServerStateStore(databaseURL: databaseURL)
  let issues = try reopened.issues()

  #expect(
    issues == [
      IssueSummary(
        issueID: fixture.issue.id,
        identifier: fixture.issue.identifier,
        title: fixture.issue.title,
        state: fixture.issue.state,
        issueState: fixture.issue.issueState,
        priority: fixture.issue.priority,
        currentProvider: fixture.runDetail.provider,
        currentRunID: fixture.runDetail.runID,
        currentSessionID: fixture.runDetail.sessionID
      )
    ])

  let loadedIssueDetail = try reopened.issueDetail(id: fixture.issue.id)
  let issueDetail = try #require(loadedIssueDetail)
  #expect(issueDetail.workspacePath == fixture.runDetail.workspacePath)
  #expect(issueDetail.latestRun?.provider == fixture.runDetail.provider)
  #expect(issueDetail.recentSessions == [fixture.session])

  let loadedRunDetail = try reopened.runDetail(id: fixture.runDetail.runID)
  let runDetail = try #require(loadedRunDetail)
  #expect(runDetail.logs.eventCount == 2)
  #expect(runDetail.logs.latestSequence == EventSequence(2))
  #expect(runDetail.providerSessionID == fixture.runDetail.providerSessionID)
  #expect(runDetail.providerRunID == fixture.runDetail.providerRunID)

  let loadedFirstPage = try reopened.logs(
    sessionID: fixture.session.sessionID, cursor: nil, limit: 1)
  let firstPage = try #require(loadedFirstPage)
  #expect(firstPage.provider == fixture.session.provider)
  #expect(firstPage.items == [firstEvent])
  #expect(firstPage.hasMore)

  let loadedSecondPage = try reopened.logs(
    sessionID: fixture.session.sessionID, cursor: firstPage.nextCursor, limit: 1)
  let secondPage = try #require(loadedSecondPage)
  #expect(secondPage.items == [secondEvent])
  #expect(!secondPage.hasMore)
  #expect(secondPage.nextCursor?.lastDeliveredSequence == EventSequence(2))
}

@Test func sqliteStoreInitializationFailureAndMissingEntityBranchesAreReported() throws {
  do {
    _ = try SQLiteServerStateStore(databaseURL: URL(fileURLWithPath: "/dev/null"))
    Issue.record("Expected /dev/null to fail during schema installation.")
  } catch let error as SymphonyRuntimeError {
    #expect(String(describing: error).contains("unable to open database file"))
  }

  let missingParentURL = try makeTemporaryDirectory()
  do {
    _ = try SQLiteServerStateStore(databaseURL: missingParentURL)
    Issue.record("Expected a missing parent directory to fail during SQLite open.")
  } catch let error as SymphonyRuntimeError {
    #expect(
      String(describing: error).contains(
        "Failed to open SQLite database at \(missingParentURL.path)."))
  }

  let databaseURL = try makeTemporaryDirectory().appendingPathComponent("missing.sqlite3")
  let store = try SQLiteServerStateStore(databaseURL: databaseURL)
  let issue = try makeFixtureRecords().issue
  let runWithoutSession = RunDetail(
    runID: RunID("run-without-session"),
    issueID: issue.id,
    issueIdentifier: issue.identifier,
    attempt: 2,
    status: "queued",
    provider: "copilot",
    providerSessionID: nil,
    providerRunID: nil,
    startedAt: "2026-03-24T04:00:00Z",
    endedAt: nil,
    workspacePath: "/tmp/symphony/atjsh_example_42",
    sessionID: nil,
    lastError: nil,
    issue: issue,
    turnCount: 0,
    lastAgentEventType: nil,
    lastAgentMessage: nil,
    tokens: try TokenUsage(),
    logs: RunLogStats(eventCount: 0, latestSequence: nil)
  )
  try store.upsertRun(runWithoutSession)

  #expect(try store.runDetail(id: RunID("missing")) == nil)
  #expect(try store.runDetail(id: runWithoutSession.runID) == runWithoutSession)
  #expect(try store.logs(sessionID: SessionID("missing"), cursor: nil, limit: 50) == nil)
  let fixture = try makeFixtureRecords()
  try store.upsertSession(fixture.session)
  #expect(
    try store.logs(
      sessionID: fixture.session.sessionID,
      cursor: EventCursor(sessionID: SessionID("other"), lastDeliveredSequence: EventSequence(3)),
      limit: 50
    ) == nil
  )

  let defaultAPI = SymphonyHTTPAPI(store: store, version: "1.0.0", trackerKind: "github")
  let defaultHealth = try defaultAPI.respond(
    to: SymphonyAPIRequest(method: "GET", path: "/api/v1/health"))
  #expect(defaultHealth.statusCode == 200)
}

@Test func apiRouterServesSpecEndpointsAndUsesErrorEnvelope() throws {
  let databaseURL = try makeTemporaryDirectory().appendingPathComponent("api.sqlite3")
  let fixture = try makeFixtureRecords()
  let store = try SQLiteServerStateStore(databaseURL: databaseURL)
  try store.upsertIssue(fixture.issue)
  try store.upsertRun(fixture.runDetail)
  try store.upsertSession(fixture.session)
  _ = try store.appendEvent(
    sessionID: fixture.session.sessionID,
    provider: fixture.session.provider,
    timestamp: "2026-03-24T03:00:01Z",
    rawJSON: #"{"type":"message","payload":{"text":"hello"}}"#,
    providerEventType: "message",
    normalizedEventKind: "message"
  )

  let refreshCounter = Counter()
  let api = SymphonyHTTPAPI(
    store: store,
    version: "1.0.0",
    trackerKind: "github",
    now: { Date(timeIntervalSince1970: 1_711_281_600) },
    refresh: { refreshCounter.increment() }
  )

  let healthResponse = try api.respond(
    to: SymphonyAPIRequest(method: "GET", path: "/api/v1/health"))
  #expect(healthResponse.statusCode == 200)
  let health = try decodeBody(HealthResponse.self, from: healthResponse)
  #expect(
    health
      == HealthResponse(
        status: "ok", serverTime: "2024-03-24T12:00:00Z", version: "1.0.0", trackerKind: "github"))

  let issuesResponse = try api.respond(
    to: SymphonyAPIRequest(method: "GET", path: "/api/v1/issues"))
  #expect(issuesResponse.statusCode == 200)
  let issues = try decodeBody(IssuesResponse.self, from: issuesResponse)
  #expect(issues.items.count == 1)
  #expect(issues.items[0].currentProvider == fixture.runDetail.provider)

  let issueDetailResponse = try api.respond(
    to: SymphonyAPIRequest(method: "GET", path: "/api/v1/issues/\(fixture.issue.id.rawValue)"))
  #expect(issueDetailResponse.statusCode == 200)
  let issueDetail = try decodeBody(IssueDetail.self, from: issueDetailResponse)
  #expect(issueDetail.issue.id == fixture.issue.id)

  let runDetailResponse = try api.respond(
    to: SymphonyAPIRequest(method: "GET", path: "/api/v1/runs/\(fixture.runDetail.runID.rawValue)"))
  #expect(runDetailResponse.statusCode == 200)
  let runDetail = try decodeBody(RunDetail.self, from: runDetailResponse)
  #expect(runDetail.runID == fixture.runDetail.runID)
  #expect(runDetail.provider == fixture.runDetail.provider)

  let logsResponse = try api.respond(
    to: SymphonyAPIRequest(
      method: "GET", path: "/api/v1/logs/\(fixture.session.sessionID.rawValue)?limit=50"))
  #expect(logsResponse.statusCode == 200)
  let logs = try decodeBody(LogEntriesResponse.self, from: logsResponse)
  #expect(logs.items.count == 1)
  #expect(logs.provider == fixture.session.provider)

  let invalidCursorLogsResponse = try api.respond(
    to: SymphonyAPIRequest(
      method: "GET",
      path: "/api/v1/logs/\(fixture.session.sessionID.rawValue)?cursor=not-a-valid-cursor&limit=50"
    )
  )
  #expect(invalidCursorLogsResponse.statusCode == 200)
  let invalidCursorLogs = try decodeBody(LogEntriesResponse.self, from: invalidCursorLogsResponse)
  #expect(invalidCursorLogs.items.count == 1)
  #expect(invalidCursorLogs.items[0].sequence == EventSequence(1))

  let refreshResponse = try api.respond(
    to: SymphonyAPIRequest(method: "POST", path: "/api/v1/refresh"))
  #expect(refreshResponse.statusCode == 202)
  let refresh = try decodeBody(RefreshResponse.self, from: refreshResponse)
  #expect(refresh.queued)
  #expect(refreshCounter.value == 1)

  let missingIssueResponse = try api.respond(
    to: SymphonyAPIRequest(method: "GET", path: "/api/v1/issues/missing"))
  #expect(missingIssueResponse.statusCode == 404)
  let missingIssue = try decodeBody(ErrorEnvelope.self, from: missingIssueResponse)
  #expect(missingIssue.error.code == "issue_not_found")

  let unsupportedResponse = try api.respond(
    to: SymphonyAPIRequest(method: "DELETE", path: "/api/v1/issues"))
  #expect(unsupportedResponse.statusCode == 405)
  let unsupported = try decodeBody(ErrorEnvelope.self, from: unsupportedResponse)
  #expect(unsupported.error.code == "method_not_allowed")
}

@Test func apiRouterCoversDefaultClockRefreshAndAdditionalErrorBranches() throws {
  let databaseURL = try makeTemporaryDirectory().appendingPathComponent("api-edge.sqlite3")
  let fixture = try makeFixtureRecords()
  let store = try SQLiteServerStateStore(databaseURL: databaseURL)
  try store.upsertIssue(fixture.issue)
  try store.upsertRun(fixture.runDetail)

  let api = SymphonyHTTPAPI(store: store, version: "1.0.0", trackerKind: "github")

  let issueMethod = try api.respond(
    to: SymphonyAPIRequest(method: "POST", path: "/api/v1/issues/\(fixture.issue.id.rawValue)"))
  #expect(issueMethod.statusCode == 405)
  #expect(try decodeBody(ErrorEnvelope.self, from: issueMethod).error.code == "method_not_allowed")

  let runMethod = try api.respond(
    to: SymphonyAPIRequest(method: "POST", path: "/api/v1/runs/\(fixture.runDetail.runID.rawValue)")
  )
  #expect(runMethod.statusCode == 405)
  #expect(try decodeBody(ErrorEnvelope.self, from: runMethod).error.code == "method_not_allowed")

  let missingRun = try api.respond(
    to: SymphonyAPIRequest(method: "GET", path: "/api/v1/runs/missing-run"))
  #expect(missingRun.statusCode == 404)
  #expect(try decodeBody(ErrorEnvelope.self, from: missingRun).error.code == "run_not_found")

  let logsMethod = try api.respond(
    to: SymphonyAPIRequest(
      method: "POST", path: "/api/v1/logs/\(fixture.session.sessionID.rawValue)"))
  #expect(logsMethod.statusCode == 405)
  #expect(try decodeBody(ErrorEnvelope.self, from: logsMethod).error.code == "method_not_allowed")

  let missingSession = try api.respond(
    to: SymphonyAPIRequest(method: "GET", path: "/api/v1/logs/missing-session"))
  #expect(missingSession.statusCode == 404)
  #expect(
    try decodeBody(ErrorEnvelope.self, from: missingSession).error.code == "session_not_found")

  let notFound = try api.respond(to: SymphonyAPIRequest(method: "GET", path: "/api/v1/unknown"))
  #expect(notFound.statusCode == 404)
  #expect(try decodeBody(ErrorEnvelope.self, from: notFound).error.code == "not_found")

  let reservedPrefix = try api.respond(
    to: SymphonyAPIRequest(method: "GET", path: "/api/v1/issues-reserved"))
  #expect(reservedPrefix.statusCode == 405)
  #expect(
    try decodeBody(ErrorEnvelope.self, from: reservedPrefix).error.code == "method_not_allowed")
}

@Test func apiRouterReturnsMethodNotAllowedForExactEndpointVerbMismatches() throws {
  let databaseURL = try makeTemporaryDirectory().appendingPathComponent("api-methods.sqlite3")
  let fixture = try makeFixtureRecords()
  let store = try SQLiteServerStateStore(databaseURL: databaseURL)
  try store.upsertIssue(fixture.issue)

  let api = SymphonyHTTPAPI(store: store, version: "1.0.0", trackerKind: "github")

  let headHealth = try api.respond(
    to: SymphonyAPIRequest(method: "HEAD", path: "/api/v1/health"))
  #expect(headHealth.statusCode == 405)
  #expect(try decodeBody(ErrorEnvelope.self, from: headHealth).error.code == "method_not_allowed")

  let putIssues = try api.respond(
    to: SymphonyAPIRequest(method: "PUT", path: "/api/v1/issues"))
  #expect(putIssues.statusCode == 405)
  #expect(try decodeBody(ErrorEnvelope.self, from: putIssues).error.code == "method_not_allowed")

  let patchRefresh = try api.respond(
    to: SymphonyAPIRequest(method: "PATCH", path: "/api/v1/refresh"))
  #expect(patchRefresh.statusCode == 405)
  #expect(
    try decodeBody(ErrorEnvelope.self, from: patchRefresh).error.code == "method_not_allowed")
}

@Test func sqliteDiagnosticsCoverPrivateFailureBranches() throws {
  let databaseURL = try makeTemporaryDirectory().appendingPathComponent("diagnostics.sqlite3")
  let store = try SQLiteServerStateStore(databaseURL: databaseURL)

  let executeError = try #require(store.diagnostics.executeSelectStatementError())
  #expect(String(describing: executeError).contains("Failed to execute SQLite statement"))

  let invalidSQL = try #require(store.diagnostics.prepareInvalidStatementError())
  #expect(String(describing: invalidSQL).contains("Failed to prepare SQLite statement"))

  let interrupted = try #require(store.diagnostics.queryInterruptedStatementError())
  #expect(String(describing: interrupted).contains("Failed to query SQLite statement"))
  #expect(store.diagnostics.queryCompletedStatementError() == nil)

  try store.diagnostics.bindNilValues()

  let finalizedBinding = try #require(store.diagnostics.bindValueOnFinalizedStatementError())
  #expect(String(describing: finalizedBinding).contains("Failed to bind SQLite statement value"))

  let encodingError = try #require(store.diagnostics.encodeThrowingValueError())
  #expect(encodingError == .encoding("Failed to encode JSON snapshot."))
  #expect(store.diagnostics.stepRowsProbe(mode: .rowFailure) == .rowFailure)
  #expect(store.diagnostics.stepRowsProbe(mode: .success) == .success)
  #expect(store.diagnostics.stepRowsProbe(mode: .unexpectedFailure) == .unexpectedFailure)
  #expect(store.diagnostics.captureRuntimeErrorWhenBodySucceeds() == nil)
  let knownRuntimeError = try #require(store.diagnostics.captureRuntimeErrorForRuntimeFailure())
  #expect(knownRuntimeError == .sqlite("Known diagnostic error."))
  let unexpectedError = try #require(store.diagnostics.captureRuntimeErrorForUnexpectedProbe())
  #expect(String(describing: unexpectedError).contains("Unexpected diagnostic error"))
  let unexpectedAutoclosureError = try #require(
    store.diagnostics.captureRuntimeErrorForUnexpectedAutoclosureProbe())
  #expect(String(describing: unexpectedAutoclosureError).contains("Unexpected diagnostic error"))

  do {
    _ = try store.diagnostics.decodeIssueSnapshot(rawSnapshot: nil)
    Issue.record("Expected NULL snapshots to fail decoding.")
  } catch let error as SymphonyRuntimeError {
    #expect(error == .encoding("Missing JSON snapshot in SQLite row."))
  }

  do {
    _ = try store.diagnostics.decodeIssueSnapshot(rawSnapshot: "{")
    Issue.record("Expected malformed snapshots to fail decoding.")
  } catch let error as SymphonyRuntimeError {
    #expect(error == .encoding("Failed to decode JSON snapshot."))
  }

  let sqliteError = store.diagnostics.sqliteError(message: "probe")
  #expect(String(describing: sqliteError).contains("probe"))

  store.diagnostics.closeDatabase()
  let closedDatabaseSQLiteError = store.diagnostics.sqliteError(message: "closed")
  #expect(String(describing: closedDatabaseSQLiteError).contains("unknown sqlite error"))
  do {
    _ = try store.issues()
    Issue.record("Expected closed stores to reject queries.")
  } catch let error as SymphonyRuntimeError {
    #expect(String(describing: error).contains("SQLite database is closed"))
  }
}

private struct FixtureRecords {
  let issue: SymphonyShared.Issue
  let runDetail: RunDetail
  let session: AgentSession
}

private func makeFixtureRecords() throws -> FixtureRecords {
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

private func makeTemporaryDirectory() throws -> URL {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    UUID().uuidString, isDirectory: true)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  return root
}

private func decodeBody<T: Decodable>(_ type: T.Type, from response: SymphonyHTTPResponse) throws
  -> T
{
  try JSONDecoder().decode(T.self, from: response.body)
}

private final class Counter: @unchecked Sendable {
  private let lock = NSLock()
  private(set) var value = 0

  func increment() {
    lock.lock()
    value += 1
    lock.unlock()
  }
}
