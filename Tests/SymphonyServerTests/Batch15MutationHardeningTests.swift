import Foundation
import SymphonyShared
import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore

// MARK: - SymphonyHTTPAPI: Empty Workspace Path Guard

@Suite("SymphonyHTTPAPI Empty Workspace")
struct SymphonyHTTPAPIEmptyWorkspaceTests {

  @Test func progressReportReturns409ForEmptyWorkspacePath() throws {
    let databaseURL = try makeTemporaryDirectory().appendingPathComponent("api-ews.sqlite3")
    let store = try SQLiteServerStateStore(databaseURL: databaseURL)

    let identifier = try IssueIdentifier(validating: "org/repo#10")
    let issue = SymphonyShared.Issue(
      id: IssueID("issue-ews"),
      identifier: identifier,
      repository: "org/repo",
      number: 10,
      title: "Bug",
      description: nil,
      priority: nil,
      state: "open",
      issueState: "OPEN",
      projectItemID: nil,
      url: "https://example.com/10",
      labels: [],
      blockedBy: [],
      createdAt: nil,
      updatedAt: nil
    )
    try store.upsertIssue(issue)

    // Run with empty workspacePath (not nil)
    let runDetail = RunDetail(
      runID: RunID("run-ews"),
      issueID: issue.id,
      issueIdentifier: identifier,
      attempt: 1,
      status: "running",
      provider: "codex",
      providerSessionID: nil,
      providerRunID: nil,
      startedAt: "2026-01-01T00:00:00Z",
      endedAt: nil,
      workspacePath: "",
      sessionID: SessionID("s-ews"),
      lastError: nil,
      issue: issue,
      turnCount: 0,
      lastAgentEventType: nil,
      lastAgentMessage: nil,
      tokens: .empty,
      logs: RunLogStats(eventCount: 0, latestSequence: nil)
    )
    try store.upsertRun(runDetail)

    let stubReports = StubIssueProgressReportGenerator(
      result: .failure(.workspaceUnavailable))
    let api = SymphonyHTTPAPI(
      store: store, version: "1.0.0", trackerKind: "github",
      progressReports: stubReports)

    let response = try api.respond(
      to: SymphonyAPIRequest(
        method: "GET",
        path: "/api/v1/issues/issue-ews/progress-report"))
    #expect(response.statusCode == 409)
    let body = try decodeBody(ErrorEnvelope.self, from: response)
    #expect(body.error.code == "workspace_unavailable")
  }
}

// MARK: - SymphonyHTTPAPI: Prefix Catch-All OR Chain

@Suite("SymphonyHTTPAPI Prefix Catch-All")
struct SymphonyHTTPAPIPrefixCatchAllTests {

  @Test func issuesPrefixWithoutSlashReturns405() throws {
    let databaseURL = try makeTemporaryDirectory().appendingPathComponent("api-prefix.sqlite3")
    let store = try SQLiteServerStateStore(databaseURL: databaseURL)
    let api = SymphonyHTTPAPI(store: store, version: "1.0.0", trackerKind: "github")

    // /api/v1/issues (exact, GET) is handled by switch case, but DELETE on exact path:
    let response = try api.respond(
      to: SymphonyAPIRequest(method: "DELETE", path: "/api/v1/issues"))
    // The exact match in the switch → method guard → 405
    #expect(response.statusCode == 405)
  }

  @Test func runsPrefixWithoutSlashReturns405() throws {
    let databaseURL = try makeTemporaryDirectory().appendingPathComponent("api-runs-p.sqlite3")
    let store = try SQLiteServerStateStore(databaseURL: databaseURL)
    let api = SymphonyHTTPAPI(store: store, version: "1.0.0", trackerKind: "github")

    // /api/v1/runs (no trailing slash or ID) hits the catch-all prefix check
    let response = try api.respond(
      to: SymphonyAPIRequest(method: "DELETE", path: "/api/v1/runs"))
    #expect(response.statusCode == 405)
  }

  @Test func logsPrefixWithoutSlashReturns405() throws {
    let databaseURL = try makeTemporaryDirectory().appendingPathComponent("api-logs-p.sqlite3")
    let store = try SQLiteServerStateStore(databaseURL: databaseURL)
    let api = SymphonyHTTPAPI(store: store, version: "1.0.0", trackerKind: "github")

    // /api/v1/logs (no trailing slash or ID) hits the catch-all prefix check
    let response = try api.respond(
      to: SymphonyAPIRequest(method: "DELETE", path: "/api/v1/logs"))
    #expect(response.statusCode == 405)
  }
}

// MARK: - SymphonyHTTPAPI: No Progress Reports Configured

@Suite("SymphonyHTTPAPI No Progress Reports")
struct SymphonyHTTPAPINoProgressReportsTests {

  @Test func progressReportReturns503WhenNotConfigured() throws {
    let databaseURL = try makeTemporaryDirectory().appendingPathComponent(
      "api-no-reports.sqlite3")
    let fixture = try makeFixtureRecords()
    let store = try SQLiteServerStateStore(databaseURL: databaseURL)
    try store.upsertIssue(fixture.issue)
    try store.upsertRun(fixture.runDetail)

    // No progressReports injected → nil
    let api = SymphonyHTTPAPI(
      store: store, version: "1.0.0", trackerKind: "github")

    let response = try api.respond(
      to: SymphonyAPIRequest(
        method: "GET",
        path: "/api/v1/issues/\(fixture.issue.id.rawValue)/progress-report"))
    #expect(response.statusCode == 503)
    let body = try decodeBody(ErrorEnvelope.self, from: response)
    #expect(body.error.code == "repository_history_unavailable")
  }
}

// MARK: - ClaudeCodeAdapter: Permission Mode Absence

@Suite("ClaudeCodeAdapter Permission Mode")
struct ClaudeCodeAdapterPermissionModeTests {

  @Test func nilPermissionModeOmitsFlag() async throws {
    let stubLauncher = StubProcessLauncher()
    let stubProcess = StubLaunchedProcess()
    stubLauncher.setStubProcess(stubProcess)

    let config = ClaudeCodeProviderConfig(permissionMode: nil)
    let adapter = ClaudeCodeAdapter(config: config, processLauncher: stubLauncher)

    _ = try await adapter.startSession(
      sessionID: SessionID("s-pm-nil"),
      workspacePath: "/tmp/ws",
      prompt: "fix",
      environment: [:]
    )

    let command = try #require(stubLauncher.invocations.first?.command)
    #expect(!command.contains("--permission-mode"))
    #expect(command.contains("--output-format stream-json"))
    stubProcess.simulateTermination(exitCode: 0)
  }

  @Test func nilPermissionModeOmitsFlagOnContinueSession() async throws {
    let stubLauncher = StubProcessLauncher()
    let stubProcess = StubLaunchedProcess()
    stubLauncher.setStubProcess(stubProcess)

    let config = ClaudeCodeProviderConfig(permissionMode: nil)
    let adapter = ClaudeCodeAdapter(config: config, processLauncher: stubLauncher)

    _ = try await adapter.startSession(
      sessionID: SessionID("s-pm-nil-cont"),
      workspacePath: "/tmp/ws",
      prompt: "fix",
      environment: [:]
    )

    _ = try await adapter.continueSession(
      sessionID: SessionID("s-pm-nil-cont"), guidance: "keep going")

    // Second invocation (continue) should also omit --permission-mode
    let continueCommand = try #require(stubLauncher.invocations.last?.command)
    #expect(!continueCommand.contains("--permission-mode"))
    #expect(continueCommand.contains("--continue"))
  }
}

// MARK: - EventKindInference: Compact Filter Edge Cases

@Suite("EventKindInference Compact Filter")
struct EventKindInferenceCompactFilterTests {

  @Test func allSpecialCharsIdentifierReturnsNonApproval() {
    // After .filter { $0.isLetter || $0.isNumber }, compact is empty → guard !compact.isEmpty → false
    let result = EventKindInference.infer(
      from: #"{"type":"!@#$%^&*()"}"#,
      provider: .codex
    )
    #expect(result != .approvalRequest)
  }

  @Test func twoElementNestedPathResolves() {
    // Tests nestedStringValue with path.count == 2 → recursion → path.count == 1 → extract
    let json = #"{"params":{"status":"completed"}}"#
    // This exercises the nested extraction used in EventKindInference
    let result = EventKindInference.infer(from: json, provider: .codex)
    // Should not crash and should return a valid inference
    #expect(result == .message || result == .status || result == .unknown)
  }
}

// MARK: - SymphonyHTTPAPI: Issue Not Found

@Suite("SymphonyHTTPAPI Issue Not Found")
struct SymphonyHTTPAPIIssueNotFoundTests {

  @Test func issueDetailReturns404ForMissingIssue() throws {
    let databaseURL = try makeTemporaryDirectory().appendingPathComponent("api-nf.sqlite3")
    let store = try SQLiteServerStateStore(databaseURL: databaseURL)
    let api = SymphonyHTTPAPI(store: store, version: "1.0.0", trackerKind: "github")

    let response = try api.respond(
      to: SymphonyAPIRequest(method: "GET", path: "/api/v1/issues/nonexistent"))
    #expect(response.statusCode == 404)
    let body = try decodeBody(ErrorEnvelope.self, from: response)
    #expect(body.error.code == "issue_not_found")
  }

  @Test func runDetailReturns404ForMissingRun() throws {
    let databaseURL = try makeTemporaryDirectory().appendingPathComponent("api-nfr.sqlite3")
    let store = try SQLiteServerStateStore(databaseURL: databaseURL)
    let api = SymphonyHTTPAPI(store: store, version: "1.0.0", trackerKind: "github")

    let response = try api.respond(
      to: SymphonyAPIRequest(method: "GET", path: "/api/v1/runs/nonexistent"))
    #expect(response.statusCode == 404)
    let body = try decodeBody(ErrorEnvelope.self, from: response)
    #expect(body.error.code == "run_not_found")
  }

  @Test func logsReturns404ForMissingSession() throws {
    let databaseURL = try makeTemporaryDirectory().appendingPathComponent("api-nfs.sqlite3")
    let store = try SQLiteServerStateStore(databaseURL: databaseURL)
    let api = SymphonyHTTPAPI(store: store, version: "1.0.0", trackerKind: "github")

    let response = try api.respond(
      to: SymphonyAPIRequest(method: "GET", path: "/api/v1/logs/nonexistent"))
    #expect(response.statusCode == 404)
    let body = try decodeBody(ErrorEnvelope.self, from: response)
    #expect(body.error.code == "session_not_found")
  }
}

// MARK: - SymphonyHTTPAPI: Method Not Allowed on Resource Endpoints

@Suite("SymphonyHTTPAPI Method Guards")
struct SymphonyHTTPAPIMethodGuardTests {

  @Test func postOnIssueDetailReturns405() throws {
    let databaseURL = try makeTemporaryDirectory().appendingPathComponent("api-mg1.sqlite3")
    let fixture = try makeFixtureRecords()
    let store = try SQLiteServerStateStore(databaseURL: databaseURL)
    try store.upsertIssue(fixture.issue)
    try store.upsertRun(fixture.runDetail)

    let api = SymphonyHTTPAPI(store: store, version: "1.0.0", trackerKind: "github")
    let response = try api.respond(
      to: SymphonyAPIRequest(
        method: "POST",
        path: "/api/v1/issues/\(fixture.issue.id.rawValue)"))
    #expect(response.statusCode == 405)
  }

  @Test func postOnRunDetailReturns405() throws {
    let databaseURL = try makeTemporaryDirectory().appendingPathComponent("api-mg2.sqlite3")
    let fixture = try makeFixtureRecords()
    let store = try SQLiteServerStateStore(databaseURL: databaseURL)
    try store.upsertIssue(fixture.issue)
    try store.upsertRun(fixture.runDetail)
    try store.upsertSession(fixture.session)

    let api = SymphonyHTTPAPI(store: store, version: "1.0.0", trackerKind: "github")
    let response = try api.respond(
      to: SymphonyAPIRequest(
        method: "POST",
        path: "/api/v1/runs/\(fixture.runDetail.runID.rawValue)"))
    #expect(response.statusCode == 405)
  }

  @Test func postOnLogsReturns405() throws {
    let databaseURL = try makeTemporaryDirectory().appendingPathComponent("api-mg3.sqlite3")
    let fixture = try makeFixtureRecords()
    let store = try SQLiteServerStateStore(databaseURL: databaseURL)
    try store.upsertIssue(fixture.issue)
    try store.upsertRun(fixture.runDetail)
    try store.upsertSession(fixture.session)

    let api = SymphonyHTTPAPI(store: store, version: "1.0.0", trackerKind: "github")
    let response = try api.respond(
      to: SymphonyAPIRequest(
        method: "POST",
        path: "/api/v1/logs/\(fixture.session.sessionID.rawValue)"))
    #expect(response.statusCode == 405)
  }

  @Test func postOnProgressReportReturns405() throws {
    let databaseURL = try makeTemporaryDirectory().appendingPathComponent("api-mg4.sqlite3")
    let fixture = try makeFixtureRecords()
    let store = try SQLiteServerStateStore(databaseURL: databaseURL)
    try store.upsertIssue(fixture.issue)
    try store.upsertRun(fixture.runDetail)

    let api = SymphonyHTTPAPI(
      store: store, version: "1.0.0", trackerKind: "github",
      progressReports: StubIssueProgressReportGenerator(
        result: .failure(.workspaceUnavailable)))
    let response = try api.respond(
      to: SymphonyAPIRequest(
        method: "POST",
        path: "/api/v1/issues/\(fixture.issue.id.rawValue)/progress-report"))
    #expect(response.statusCode == 405)
  }
}
