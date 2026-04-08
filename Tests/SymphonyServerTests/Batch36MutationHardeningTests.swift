// Batch 36 — mutation hardening for SymphonyHTTPAPI error log level,
// non-numeric limit fallback, refresh requestedAt field, and
// EventKindInference codex method/copilotCLI dispatch precedence gaps.

import Foundation
import SymphonyShared
import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore

// MARK: - SymphonyHTTPAPI Error Log Level Verification

@Suite("SymphonyHTTPAPI Error Log Level")
struct SymphonyHTTPAPIErrorLogLevelTests {

  @Test func error503LogsAtErrorLevel() async throws {
    let databaseURL = try makeTemporaryDirectory().appendingPathComponent("log-level-503.sqlite3")
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

    let (response, logs) = try await withCapturedRuntimeLogs {
      try api.respond(
        to: SymphonyAPIRequest(
          method: "GET",
          path: "/api/v1/issues/\(fixture.issue.id.rawValue)/progress-report"
        )
      )
    }
    #expect(response.statusCode == 503)
    let errorLog = logs.first { $0.entry.event == "http_api_error_response" }
    #expect(errorLog != nil)
    #expect(errorLog?.entry.level == "error")
  }

  @Test func error404LogsAtWarningLevel() async throws {
    let databaseURL = try makeTemporaryDirectory().appendingPathComponent("log-level-404.sqlite3")
    let store = try SQLiteServerStateStore(databaseURL: databaseURL)
    let api = SymphonyHTTPAPI(store: store, version: "1.0.0", trackerKind: "github")

    let (response, logs) = try await withCapturedRuntimeLogs {
      try api.respond(
        to: SymphonyAPIRequest(method: "GET", path: "/api/v1/issues/nonexistent")
      )
    }
    #expect(response.statusCode == 404)
    let errorLog = logs.first { $0.entry.event == "http_api_error_response" }
    #expect(errorLog != nil)
    #expect(errorLog?.entry.level == "warning")
  }
}

// MARK: - SymphonyHTTPAPI Non-Numeric Limit Fallback

@Suite("SymphonyHTTPAPI Limit Edge Cases")
struct SymphonyHTTPAPILimitEdgeCaseTests {

  @Test func nonNumericLimitFallsBackTo50() throws {
    let databaseURL = try makeTemporaryDirectory().appendingPathComponent("limit-nan.sqlite3")
    let fixture = try makeFixtureRecords()
    let store = try SQLiteServerStateStore(databaseURL: databaseURL)
    try store.upsertIssue(fixture.issue)
    try store.upsertRun(fixture.runDetail)
    try store.upsertSession(fixture.session)

    for i in 1...60 {
      _ = try store.appendEvent(
        sessionID: fixture.session.sessionID,
        provider: fixture.session.provider,
        timestamp: "2026-03-24T03:00:\(String(format: "%02d", i % 60))Z",
        rawJSON: #"{"type":"message","n":\#(i)}"#,
        providerEventType: "message",
        normalizedEventKind: "message"
      )
    }

    let api = SymphonyHTTPAPI(store: store, version: "1.0.0", trackerKind: "github")
    let response = try api.respond(
      to: SymphonyAPIRequest(
        method: "GET",
        path: "/api/v1/logs/\(fixture.session.sessionID.rawValue)?limit=abc"
      )
    )
    #expect(response.statusCode == 200)
    let logs = try decodeBody(LogEntriesResponse.self, from: response)
    #expect(logs.items.count == 50)
    #expect(logs.hasMore)
  }

  @Test func emptyLimitFallsBackTo50() throws {
    let databaseURL = try makeTemporaryDirectory().appendingPathComponent("limit-empty.sqlite3")
    let fixture = try makeFixtureRecords()
    let store = try SQLiteServerStateStore(databaseURL: databaseURL)
    try store.upsertIssue(fixture.issue)
    try store.upsertRun(fixture.runDetail)
    try store.upsertSession(fixture.session)

    for i in 1...60 {
      _ = try store.appendEvent(
        sessionID: fixture.session.sessionID,
        provider: fixture.session.provider,
        timestamp: "2026-03-24T03:00:\(String(format: "%02d", i % 60))Z",
        rawJSON: #"{"type":"message","n":\#(i)}"#,
        providerEventType: "message",
        normalizedEventKind: "message"
      )
    }

    let api = SymphonyHTTPAPI(store: store, version: "1.0.0", trackerKind: "github")
    let response = try api.respond(
      to: SymphonyAPIRequest(
        method: "GET",
        path: "/api/v1/logs/\(fixture.session.sessionID.rawValue)?limit="
      )
    )
    #expect(response.statusCode == 200)
    let logs = try decodeBody(LogEntriesResponse.self, from: response)
    #expect(logs.items.count == 50)
    #expect(logs.hasMore)
  }
}

// MARK: - SymphonyHTTPAPI Refresh Response Fields

@Suite("SymphonyHTTPAPI Refresh Response Fields")
struct SymphonyHTTPAPIRefreshFieldTests {

  @Test func refreshResponseRequestedAtUsesNowClosure() throws {
    let databaseURL = try makeTemporaryDirectory().appendingPathComponent("refresh-at.sqlite3")
    let store = try SQLiteServerStateStore(databaseURL: databaseURL)
    let fixedDate = ISO8601DateFormatter().date(from: "2026-06-15T12:00:00Z")!
    let api = SymphonyHTTPAPI(
      store: store,
      version: "1.0.0",
      trackerKind: "github",
      now: { fixedDate }
    )

    let response = try api.respond(
      to: SymphonyAPIRequest(method: "POST", path: "/api/v1/refresh")
    )
    #expect(response.statusCode == 202)
    let body = try decodeBody(RefreshResponse.self, from: response)
    #expect(body.queued == true)
    #expect(body.requestedAt == "2026-06-15T12:00:00Z")
  }
}

// MARK: - EventKindInference CopilotCLI Dispatch Precedence

@Suite("EventKindInference CopilotCLI Precedence")
struct EventKindInferenceCopilotCLIPrecedenceTests {

  @Test func typeTakesPrecedenceOverEventField() {
    // Both type and event present — type should win via ??
    let kind = EventKindInference.infer(
      from: #"{"type":"tool_call","event":"status"}"#,
      provider: .copilotCLI
    )
    #expect(kind == .toolCall)
  }

  @Test func stopReasonTakesPrecedenceOverError() {
    // Both stopReason result and error present — stopReason early-return wins
    let kind = EventKindInference.infer(
      from: #"{"result":{"stopReason":"end_turn"},"error":{"message":"fatal"}}"#,
      provider: .copilotCLI
    )
    #expect(kind == .status)
  }

  @Test func errorTakesPrecedenceOverTypeAndEvent() {
    // Error present along with type — error check (line 203) before type fallback
    let kind = EventKindInference.infer(
      from: #"{"error":{"message":"bad"},"type":"message","event":"status"}"#,
      provider: .copilotCLI
    )
    #expect(kind == .error)
  }
}

// MARK: - EventKindInference Codex Method Status Coverage

@Suite("EventKindInference Codex Status Methods")
struct EventKindInferenceCodexStatusMethodTests {

  @Test func initializedMethodIsStatus() {
    let kind = EventKindInference.infer(
      from: #"{"method":"initialized"}"#,
      provider: .codex
    )
    #expect(kind == .status)
  }

  @Test func threadStartMethodIsStatus() {
    let kind = EventKindInference.infer(
      from: #"{"method":"thread/start"}"#,
      provider: .codex
    )
    #expect(kind == .status)
  }

  @Test func turnStartMethodIsStatus() {
    let kind = EventKindInference.infer(
      from: #"{"method":"turn/start"}"#,
      provider: .codex
    )
    #expect(kind == .status)
  }

  @Test func turnFailedMethodIsStatus() {
    let kind = EventKindInference.infer(
      from: #"{"method":"turn/failed"}"#,
      provider: .codex
    )
    #expect(kind == .status)
  }

  @Test func turnCancelledMethodIsStatus() {
    let kind = EventKindInference.infer(
      from: #"{"method":"turn/cancelled"}"#,
      provider: .codex
    )
    #expect(kind == .status)
  }

  @Test func turnInterruptedMethodIsStatus() {
    let kind = EventKindInference.infer(
      from: #"{"method":"turn/interrupted"}"#,
      provider: .codex
    )
    #expect(kind == .status)
  }
}
