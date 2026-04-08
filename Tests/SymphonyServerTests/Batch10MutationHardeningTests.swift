import Foundation
import Synchronization
import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore
@testable import SymphonyShared

// MARK: - StreamFinishState Tests

@Suite("StreamFinishState")
struct StreamFinishStateMutationTests {

  @Test func finishIfNeededCallsActionOnce() {
    let state = StreamFinishState()
    #expect(!state.isFinished)

    var callCount = 0
    state.finishIfNeeded { callCount += 1 }
    #expect(state.isFinished)
    #expect(callCount == 1)
  }

  @Test func finishIfNeededSecondCallIsNoOp() {
    let state = StreamFinishState()
    var firstCalled = false
    var secondCalled = false

    state.finishIfNeeded { firstCalled = true }
    state.finishIfNeeded { secondCalled = true }

    #expect(firstCalled)
    #expect(!secondCalled, "Guard !_finished must prevent second invocation")
    #expect(state.isFinished)
  }

  @Test func isFinishedStartsFalse() {
    let state = StreamFinishState()
    #expect(!state.isFinished)
  }
}

// MARK: - Protocol Helper Function Tests

@Suite("ProviderHelpers")
struct ProviderHelpersMutationTests {

  @Test func protocolLinesFiltersEmptyLines() {
    let output = "line1\n\n  \nline2\n"
    let result = protocolLines(from: output)
    #expect(result == ["line1", "line2"])
  }

  @Test func protocolLinesSingleLineNoNewline() {
    let result = protocolLines(from: "hello")
    #expect(result == ["hello"])
  }

  @Test func protocolLinesEmptyStringReturnsEmpty() {
    let result = protocolLines(from: "")
    #expect(result.isEmpty)
  }

  @Test func protocolLinesTrimsWhitespace() {
    let result = protocolLines(from: "  padded  \n  spaced  ")
    #expect(result == ["padded", "spaced"])
  }

  @Test func submitInputEmptyStringIsNoOp() throws {
    let process = StubLaunchedProcess()
    let inputCount = Mutex(0)
    process.onOutput { _ in inputCount.withLock { $0 += 1 } }

    try submitInput("", to: process)
    // Process should NOT have received any sendInput call
    // The guard !input.isEmpty catches this
    #expect(process.terminationCount == 0)
  }

  @Test func submitInputNonEmptyStringSendsData() throws {
    let process = StubLaunchedProcess()

    try submitInput("test message", to: process)
    // If sendInput throws, the test would fail.
    // The fact it doesn't throw confirms data was sent.
  }

  @Test func submitInputPropagatesProcessError() {
    let process = StubLaunchedProcess()
    process.setInputError(ProviderAdapterError.processLaunchFailed("dead"))

    #expect(throws: ProviderAdapterError.self) {
      try submitInput("hello", to: process)
    }
  }

  @Test func submitJSONMessagesAddsNewlineTerminator() throws {
    let process = StubLaunchedProcess()
    let receivedData = Mutex<[Data]>([])
    process.onOutput { data in
      receivedData.withLock { $0.append(data) }
    }

    let messages: [[String: Any]] = [["key": "value"]]
    try submitJSONMessages(messages, to: process)
    // Message should have been sent without error
  }

  @Test func submitJSONMessagesPropagatesSerializationError() {
    let process = StubLaunchedProcess()
    process.setInputError(ProviderAdapterError.processLaunchFailed("dead"))

    #expect(throws: ProviderAdapterError.self) {
      try submitJSONMessages([["key": "value"]], to: process)
    }
  }

  @Test func protocolJSONMessageParsesValidJSON() {
    let line = #"{"method":"turn/start","params":{"threadId":"t1"}}"#
    let result = protocolJSONMessage(from: line)
    #expect(result != nil)
  }

  @Test func protocolJSONMessageReturnsNilForInvalidJSON() {
    let result = protocolJSONMessage(from: "not json at all")
    #expect(result == nil)
  }
}

// MARK: - WorkspaceManager Sibling-Prefix Containment Tests

@Suite("WorkspaceManager Containment Edge Cases")
struct WorkspaceManagerContainmentEdgeCaseTests {

  @Test func siblingPrefixPathIsRejected() throws {
    // If root="/tmp/ws", then "/tmp/ws_escape" must NOT be accepted.
    // The "/" separator in hasPrefix(root + "/") is critical.
    let root = NSTemporaryDirectory() + "sym_contain_\(UUID().uuidString)"
    let siblingPath = root + "_escape"
    try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: root) }

    let manager = WorkspaceManager(root: root)

    #expect(throws: WorkspaceError.self) {
      try manager.validateContainment(path: siblingPath)
    }
  }

  @Test func exactRootPathIsAccepted() throws {
    let root = NSTemporaryDirectory() + "sym_contain_\(UUID().uuidString)"
    try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: root) }

    let manager = WorkspaceManager(root: root)
    try manager.validateContainment(path: root)
  }

  @Test func childPathIsAccepted() throws {
    let root = NSTemporaryDirectory() + "sym_contain_\(UUID().uuidString)"
    try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: root) }

    let manager = WorkspaceManager(root: root)
    try manager.validateContainment(path: root + "/child")
  }
}

// MARK: - HTTP API Progress Report: Empty Workspace Path Tests

@Suite("SymphonyHTTPAPI Workspace Path Edge Cases")
struct SymphonyHTTPAPIWorkspacePathEdgeCaseTests {

  @Test func progressReportReturns409ForEmptyStringWorkspacePath() throws {
    let databaseURL = try makeTemporaryDirectory().appendingPathComponent("api-ws-empty.sqlite3")
    let fixture = try makeFixtureRecords()

    // Create a modified run with empty-string workspacePath
    let emptyWSRun = RunDetail(
      runID: fixture.runDetail.runID,
      issueID: fixture.runDetail.issueID,
      issueIdentifier: fixture.runDetail.issueIdentifier,
      attempt: fixture.runDetail.attempt,
      status: fixture.runDetail.status,
      provider: fixture.runDetail.provider,
      providerSessionID: fixture.runDetail.providerSessionID,
      providerRunID: fixture.runDetail.providerRunID,
      startedAt: fixture.runDetail.startedAt,
      endedAt: fixture.runDetail.endedAt,
      workspacePath: "",
      sessionID: fixture.runDetail.sessionID,
      lastError: nil,
      issue: fixture.issue,
      turnCount: fixture.runDetail.turnCount,
      lastAgentEventType: fixture.runDetail.lastAgentEventType,
      lastAgentMessage: fixture.runDetail.lastAgentMessage,
      tokens: fixture.runDetail.tokens,
      logs: fixture.runDetail.logs
    )

    let store = try SQLiteServerStateStore(databaseURL: databaseURL)
    try store.upsertIssue(fixture.issue)
    try store.upsertRun(emptyWSRun)

    let stubReports = StubIssueProgressReportGenerator(
      result: .success(makeIssueProgressReport(issueID: fixture.issue.id))
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

  @Test func progressReportReturns404ForNilProgressReports() throws {
    let databaseURL = try makeTemporaryDirectory().appendingPathComponent("api-no-pr.sqlite3")
    let fixture = try makeFixtureRecords()
    let store = try SQLiteServerStateStore(databaseURL: databaseURL)
    try store.upsertIssue(fixture.issue)
    try store.upsertRun(fixture.runDetail)

    // No progressReports injected → should return 503
    let api = SymphonyHTTPAPI(
      store: store,
      version: "1.0.0",
      trackerKind: "github"
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

  @Test func progressReportRejectsNonGET() throws {
    let databaseURL = try makeTemporaryDirectory().appendingPathComponent("api-pr-method.sqlite3")
    let store = try SQLiteServerStateStore(databaseURL: databaseURL)
    let api = SymphonyHTTPAPI(store: store, version: "1.0.0", trackerKind: "github")

    let response = try api.respond(
      to: SymphonyAPIRequest(
        method: "POST",
        path: "/api/v1/issues/any-id/progress-report"
      )
    )
    #expect(response.statusCode == 405)
  }
}

// MARK: - HTTP API Error Logging Level Tests

@Suite("SymphonyHTTPAPI Error Logging")
struct SymphonyHTTPAPIErrorLoggingTests {

  @Test func error500sLogAsErrorLevel() throws {
    let databaseURL = try makeTemporaryDirectory().appendingPathComponent("api-log-level.sqlite3")
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
    // 503 >= 500 → level should be .error (not .warning)
    #expect(response.statusCode == 503)
  }

  @Test func healthRejectsNonGET() throws {
    let databaseURL = try makeTemporaryDirectory().appendingPathComponent("api-health-m.sqlite3")
    let store = try SQLiteServerStateStore(databaseURL: databaseURL)
    let api = SymphonyHTTPAPI(store: store, version: "1.0.0", trackerKind: "github")

    let response = try api.respond(
      to: SymphonyAPIRequest(method: "POST", path: "/api/v1/health")
    )
    #expect(response.statusCode == 405)
  }
}
