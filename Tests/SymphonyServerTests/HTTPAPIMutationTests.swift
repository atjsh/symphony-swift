import Foundation
import SymphonyShared
import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore

// MARK: - SymphonyHTTPAPI mutation hardening (status codes, defaults, error paths)

@Test func httpAPILogsDefaultPaginationLimitIs50() throws {
  let databaseURL = try makeTemporaryDirectory().appendingPathComponent("api-limit.sqlite3")
  let fixture = try makeFixtureRecords()
  let store = try SQLiteServerStateStore(databaseURL: databaseURL)
  try store.upsertIssue(fixture.issue)
  try store.upsertRun(fixture.runDetail)
  try store.upsertSession(fixture.session)

  // Append 60 events so we can verify limit=50 is applied by default
  for i in 1...60 {
    _ = try store.appendEvent(
      sessionID: fixture.session.sessionID,
      provider: fixture.session.provider,
      timestamp: "2026-03-24T03:00:\(String(format: "%02d", i))Z",
      rawJSON: #"{"type":"message","n":\#(i)}"#,
      providerEventType: "message",
      normalizedEventKind: "message"
    )
  }

  let api = SymphonyHTTPAPI(store: store, version: "1.0.0", trackerKind: "github")

  // No limit parameter → should use default of 50
  let response = try api.respond(
    to: SymphonyAPIRequest(
      method: "GET",
      path: "/api/v1/logs/\(fixture.session.sessionID.rawValue)"
    )
  )
  #expect(response.statusCode == 200)
  let logs = try decodeBody(LogEntriesResponse.self, from: response)
  #expect(logs.items.count == 50)
  #expect(logs.hasMore)
}

@Test func httpAPIProgressReportReturns409ForWorkspaceUnavailableError() throws {
  let databaseURL = try makeTemporaryDirectory().appendingPathComponent("api-409.sqlite3")
  let fixture = try makeFixtureRecords()
  let store = try SQLiteServerStateStore(databaseURL: databaseURL)
  try store.upsertIssue(fixture.issue)
  try store.upsertRun(fixture.runDetail)

  let stubReports = StubIssueProgressReportGenerator(
    result: .failure(.workspaceUnavailable)
  )
  let api = SymphonyHTTPAPI(
    store: store,
    version: "1.0.0",
    trackerKind: "github",
    progressReports: stubReports
  )

  let response = try api.respond(
    to: SymphonyAPIRequest(
      method: "GET",
      path: "/api/v1/issues/\(fixture.issue.id.rawValue)/progress-report"
    )
  )
  #expect(response.statusCode == 409)
  let body = try decodeBody(ErrorEnvelope.self, from: response)
  #expect(body.error.code == "workspace_unavailable")
}

@Test func httpAPIProgressReportReturns503ForRepositoryHistoryUnavailable() throws {
  let databaseURL = try makeTemporaryDirectory().appendingPathComponent("api-503.sqlite3")
  let fixture = try makeFixtureRecords()
  let store = try SQLiteServerStateStore(databaseURL: databaseURL)
  try store.upsertIssue(fixture.issue)
  try store.upsertRun(fixture.runDetail)

  let stubReports = StubIssueProgressReportGenerator(
    result: .failure(.repositoryHistoryUnavailable("no git"))
  )
  let api = SymphonyHTTPAPI(
    store: store,
    version: "1.0.0",
    trackerKind: "github",
    progressReports: stubReports
  )

  let response = try api.respond(
    to: SymphonyAPIRequest(
      method: "GET",
      path: "/api/v1/issues/\(fixture.issue.id.rawValue)/progress-report"
    )
  )
  #expect(response.statusCode == 503)
  let body = try decodeBody(ErrorEnvelope.self, from: response)
  #expect(body.error.code == "repository_history_unavailable")
}

@Test func httpAPIRefreshEndpointRejectsGET() throws {
  let databaseURL = try makeTemporaryDirectory().appendingPathComponent("api-ref.sqlite3")
  let store = try SQLiteServerStateStore(databaseURL: databaseURL)
  let api = SymphonyHTTPAPI(store: store, version: "1.0.0", trackerKind: "github")

  let response = try api.respond(
    to: SymphonyAPIRequest(method: "GET", path: "/api/v1/refresh")
  )
  #expect(response.statusCode == 405)
}

@Test func httpAPIRefreshCallsRefreshClosure() throws {
  let databaseURL = try makeTemporaryDirectory().appendingPathComponent("api-rcall.sqlite3")
  let store = try SQLiteServerStateStore(databaseURL: databaseURL)
  let counter = Counter()
  let api = SymphonyHTTPAPI(
    store: store,
    version: "1.0.0",
    trackerKind: "github",
    refresh: { counter.increment() }
  )

  let response = try api.respond(
    to: SymphonyAPIRequest(method: "POST", path: "/api/v1/refresh")
  )
  #expect(response.statusCode == 202)
  #expect(counter.value == 1)
}

@Test func httpAPIHealthReturnsCorrectVersion() throws {
  let databaseURL = try makeTemporaryDirectory().appendingPathComponent("api-ver.sqlite3")
  let store = try SQLiteServerStateStore(databaseURL: databaseURL)
  let api = SymphonyHTTPAPI(store: store, version: "2.5.0", trackerKind: "linear")

  let response = try api.respond(
    to: SymphonyAPIRequest(method: "GET", path: "/api/v1/health")
  )
  #expect(response.statusCode == 200)
  let health = try decodeBody(HealthResponse.self, from: response)
  #expect(health.version == "2.5.0")
  #expect(health.trackerKind == "linear")
  #expect(health.status == "ok")
}

@Test func httpAPIUnknownPathReturns404NotMethodNotAllowed() throws {
  let databaseURL = try makeTemporaryDirectory().appendingPathComponent("api-unk.sqlite3")
  let store = try SQLiteServerStateStore(databaseURL: databaseURL)
  let api = SymphonyHTTPAPI(store: store, version: "1.0.0", trackerKind: "github")

  let response = try api.respond(
    to: SymphonyAPIRequest(method: "GET", path: "/api/v1/widgets")
  )
  #expect(response.statusCode == 404)
  let body = try decodeBody(ErrorEnvelope.self, from: response)
  #expect(body.error.code == "not_found")
}

@Test func httpAPICustomLimitRespected() throws {
  let databaseURL = try makeTemporaryDirectory().appendingPathComponent("api-lim.sqlite3")
  let fixture = try makeFixtureRecords()
  let store = try SQLiteServerStateStore(databaseURL: databaseURL)
  try store.upsertIssue(fixture.issue)
  try store.upsertRun(fixture.runDetail)
  try store.upsertSession(fixture.session)

  for i in 1...10 {
    _ = try store.appendEvent(
      sessionID: fixture.session.sessionID,
      provider: fixture.session.provider,
      timestamp: "2026-03-24T03:00:\(String(format: "%02d", i))Z",
      rawJSON: #"{"n":\#(i)}"#,
      providerEventType: "message",
      normalizedEventKind: "message"
    )
  }

  let api = SymphonyHTTPAPI(store: store, version: "1.0.0", trackerKind: "github")
  let response = try api.respond(
    to: SymphonyAPIRequest(
      method: "GET",
      path: "/api/v1/logs/\(fixture.session.sessionID.rawValue)?limit=3"
    )
  )
  #expect(response.statusCode == 200)
  let logs = try decodeBody(LogEntriesResponse.self, from: response)
  #expect(logs.items.count == 3)
  #expect(logs.hasMore)
}
