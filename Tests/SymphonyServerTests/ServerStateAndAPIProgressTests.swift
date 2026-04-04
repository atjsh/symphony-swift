import Foundation
import SymphonyShared
import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore

@Test func apiRouterServesIssueProgressReports() throws {
  let databaseURL = try makeTemporaryDirectory().appendingPathComponent("api-progress.sqlite3")
  let fixture = try makeFixtureRecords()
  let store = try SQLiteServerStateStore(databaseURL: databaseURL)
  try store.upsertIssue(fixture.issue)
  try store.upsertRun(fixture.runDetail)

  let progressReport = makeIssueProgressReport(issueID: fixture.issue.id)
  let api = SymphonyHTTPAPI(
    store: store,
    version: "1.0.0",
    trackerKind: "github",
    progressReports: StubIssueProgressReportGenerator(result: .success(progressReport))
  )

  let response = try api.respond(
    to: SymphonyAPIRequest(
      method: "GET",
      path: "/api/v1/issues/\(fixture.issue.id.rawValue)/progress-report"
    )
  )

  #expect(response.statusCode == 200)
  let decoded = try decodeBody(IssueProgressReportResponse.self, from: response)
  #expect(decoded == progressReport)
}

@Test func apiRouterMapsIssueProgressReportErrorsToExpectedEnvelopes() throws {
  let databaseURL = try makeTemporaryDirectory().appendingPathComponent("api-progress-errors.sqlite3")
  let fixture = try makeFixtureRecords()
  let store = try SQLiteServerStateStore(databaseURL: databaseURL)
  try store.upsertIssue(fixture.issue)
  try store.upsertRun(fixture.runDetail)

  let workspaceUnavailableAPI = SymphonyHTTPAPI(
    store: store,
    version: "1.0.0",
    trackerKind: "github",
    progressReports: StubIssueProgressReportGenerator(result: .failure(.workspaceUnavailable))
  )

  let workspaceUnavailable = try workspaceUnavailableAPI.respond(
    to: SymphonyAPIRequest(
      method: "GET",
      path: "/api/v1/issues/\(fixture.issue.id.rawValue)/progress-report"
    )
  )
  #expect(workspaceUnavailable.statusCode == 409)
  #expect(
    try decodeBody(ErrorEnvelope.self, from: workspaceUnavailable).error.code == "workspace_unavailable"
  )

  let historyUnavailableAPI = SymphonyHTTPAPI(
    store: store,
    version: "1.0.0",
    trackerKind: "github",
    progressReports: StubIssueProgressReportGenerator(
      result: .failure(.repositoryHistoryUnavailable("go-enry is not materialized"))
    )
  )

  let historyUnavailable = try historyUnavailableAPI.respond(
    to: SymphonyAPIRequest(
      method: "GET",
      path: "/api/v1/issues/\(fixture.issue.id.rawValue)/progress-report"
    )
  )
  #expect(historyUnavailable.statusCode == 503)
  #expect(
    try decodeBody(ErrorEnvelope.self, from: historyUnavailable).error.code
      == "repository_history_unavailable"
  )
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
  } catch let error as SymphonyServerError {
    #expect(error == .encoding("Missing JSON snapshot in SQLite row."))
  }

  do {
    _ = try store.diagnostics.decodeIssueSnapshot(rawSnapshot: "{")
    Issue.record("Expected malformed snapshots to fail decoding.")
  } catch let error as SymphonyServerError {
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
  } catch let error as SymphonyServerError {
    #expect(String(describing: error).contains("SQLite database is closed"))
  }
}
