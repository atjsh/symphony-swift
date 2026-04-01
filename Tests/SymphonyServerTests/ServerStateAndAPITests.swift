import Foundation
import SymphonyShared
import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore

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
  } catch let error as SymphonyServerError {
    #expect(String(describing: error).contains("unable to open database file"))
  }

  let missingParentURL = try makeTemporaryDirectory()
  do {
    _ = try SQLiteServerStateStore(databaseURL: missingParentURL)
    Issue.record("Expected a missing parent directory to fail during SQLite open.")
  } catch let error as SymphonyServerError {
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

@Test func sqliteStoreOmitsCurrentRunFieldsForTerminalLatestRun() throws {
  let databaseURL = try makeTemporaryDirectory().appendingPathComponent("terminal-run.sqlite3")
  let fixture = try makeFixtureRecords()
  let store = try SQLiteServerStateStore(databaseURL: databaseURL)
  let stalledRun = RunDetail(
    runID: fixture.runDetail.runID,
    issueID: fixture.runDetail.issueID,
    issueIdentifier: fixture.runDetail.issueIdentifier,
    attempt: fixture.runDetail.attempt,
    status: "Stalled",
    provider: fixture.runDetail.provider,
    providerSessionID: fixture.runDetail.providerSessionID,
    providerRunID: fixture.runDetail.providerRunID,
    startedAt: fixture.runDetail.startedAt,
    endedAt: "2026-03-24T03:10:00Z",
    workspacePath: fixture.runDetail.workspacePath,
    sessionID: fixture.runDetail.sessionID,
    lastError: "approval stalled",
    issue: fixture.issue,
    turnCount: fixture.runDetail.turnCount,
    lastAgentEventType: fixture.runDetail.lastAgentEventType,
    lastAgentMessage: fixture.runDetail.lastAgentMessage,
    tokens: fixture.runDetail.tokens,
    logs: fixture.runDetail.logs
  )

  try store.upsertIssue(fixture.issue)
  try store.upsertRun(stalledRun)

  let issues = try store.issues()
  #expect(issues.count == 1)
  #expect(issues[0].currentProvider == nil)
  #expect(issues[0].currentRunID == nil)
  #expect(issues[0].currentSessionID == nil)
}

@Test func sqliteStoreTreatsCompletedStatusesAsHistoricalAndUnknownStatusesAsCurrent() throws {
  let databaseURL = try makeTemporaryDirectory().appendingPathComponent("status-current.sqlite3")
  let fixture = try makeFixtureRecords()
  let store = try SQLiteServerStateStore(databaseURL: databaseURL)
  try store.upsertIssue(fixture.issue)
  try store.upsertRun(fixture.runDetail)

  let completedRun = RunDetail(
    runID: RunID("run-completed"),
    issueID: fixture.issue.id,
    issueIdentifier: fixture.issue.identifier,
    attempt: 2,
    status: "completed",
    provider: fixture.runDetail.provider,
    providerSessionID: fixture.runDetail.providerSessionID,
    providerRunID: fixture.runDetail.providerRunID,
    startedAt: fixture.runDetail.startedAt,
    endedAt: "2026-03-24T03:10:00Z",
    workspacePath: fixture.runDetail.workspacePath,
    sessionID: fixture.runDetail.sessionID,
    lastError: nil,
    issue: fixture.issue,
    turnCount: fixture.runDetail.turnCount,
    lastAgentEventType: fixture.runDetail.lastAgentEventType,
    lastAgentMessage: fixture.runDetail.lastAgentMessage,
    tokens: fixture.runDetail.tokens,
    logs: fixture.runDetail.logs
  )
  try store.upsertRun(completedRun)

  var issues = try store.issues()
  #expect(issues.count == 1)
  #expect(issues[0].currentRunID == nil)

  let unknownRun = RunDetail(
    runID: RunID("run-unknown"),
    issueID: fixture.issue.id,
    issueIdentifier: fixture.issue.identifier,
    attempt: 3,
    status: "mystery-status",
    provider: fixture.runDetail.provider,
    providerSessionID: fixture.runDetail.providerSessionID,
    providerRunID: fixture.runDetail.providerRunID,
    startedAt: fixture.runDetail.startedAt,
    endedAt: nil,
    workspacePath: fixture.runDetail.workspacePath,
    sessionID: fixture.runDetail.sessionID,
    lastError: nil,
    issue: fixture.issue,
    turnCount: fixture.runDetail.turnCount,
    lastAgentEventType: fixture.runDetail.lastAgentEventType,
    lastAgentMessage: fixture.runDetail.lastAgentMessage,
    tokens: fixture.runDetail.tokens,
    logs: fixture.runDetail.logs
  )
  try store.upsertRun(unknownRun)

  issues = try store.issues()
  #expect(issues[0].currentRunID == unknownRun.runID)
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
  let recentSession = try #require(issueDetail.recentSessions.first)
  #expect(recentSession.providerSessionID == fixture.session.providerSessionID)
  #expect(recentSession.providerThreadID == fixture.session.providerThreadID)
  #expect(recentSession.providerTurnID == fixture.session.providerTurnID)
  #expect(recentSession.providerRunID == fixture.session.providerRunID)
  #expect(recentSession.tokenUsage == fixture.session.tokenUsage)
  #expect(recentSession.latestRateLimitPayload == fixture.session.latestRateLimitPayload)

  let runDetailResponse = try api.respond(
    to: SymphonyAPIRequest(method: "GET", path: "/api/v1/runs/\(fixture.runDetail.runID.rawValue)"))
  #expect(runDetailResponse.statusCode == 200)
  let runDetail = try decodeBody(RunDetail.self, from: runDetailResponse)
  #expect(runDetail.runID == fixture.runDetail.runID)
  #expect(runDetail.provider == fixture.runDetail.provider)
  #expect(runDetail.providerSessionID == fixture.runDetail.providerSessionID)
  #expect(runDetail.providerRunID == fixture.runDetail.providerRunID)
  #expect(runDetail.lastAgentMessage == fixture.runDetail.lastAgentMessage)
  #expect(runDetail.tokens == fixture.runDetail.tokens)
  #expect(runDetail.logs.latestSequence == EventSequence(1))

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

  let defaultRefresh = try api.respond(
    to: SymphonyAPIRequest(method: "POST", path: "/api/v1/refresh"))
  #expect(defaultRefresh.statusCode == 202)
  #expect(try decodeBody(RefreshResponse.self, from: defaultRefresh).queued)
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

@Test func apiRouterEmitsStructuredErrorLogs() async throws {
  let databaseURL = try makeTemporaryDirectory().appendingPathComponent("api-logs.sqlite3")
  let store = try SQLiteServerStateStore(databaseURL: databaseURL)
  let api = SymphonyHTTPAPI(store: store, version: "1.0.0", trackerKind: "github")

  let (_, logs) = try await withCapturedRuntimeLogs {
    _ = try api.respond(
      to: SymphonyAPIRequest(
        method: "GET",
        path: "/api/v1/issues/missing?authorization=Bearer%20ghp_api_secret"
      ))
  }

  let errorLog = try #require(
    logs.first {
      $0.json["event"] as? String == "http_api_error_response"
        && $0.json["path"] as? String == "/api/v1/issues/missing"
    })
  #expect(errorLog.json["status_code"] as? String == "404")
  #expect(errorLog.json["path"] as? String == "/api/v1/issues/missing")
  #expect(!errorLog.line.contains("ghp_api_secret"))
}

