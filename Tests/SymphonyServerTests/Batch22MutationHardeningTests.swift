// Batch 22 — mutation hardening for SymphonyHTTPAPI response headers and
// CopilotCLIAdapter startup message constants.

import Foundation
import SymphonyShared
import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore

// MARK: - SymphonyHTTPAPI Content-Type Header

@Suite("SymphonyHTTPAPI Content-Type Header")
struct SymphonyHTTPAPIContentTypeTests {

  @Test func healthResponseIncludesJSONContentType() throws {
    let databaseURL = try makeTemporaryDirectory().appendingPathComponent("ct-health.sqlite3")
    let store = try SQLiteServerStateStore(databaseURL: databaseURL)
    let api = SymphonyHTTPAPI(store: store, version: "1.0.0", trackerKind: "github")

    let response = try api.respond(
      to: SymphonyAPIRequest(method: "GET", path: "/api/v1/health"))
    #expect(response.headers["Content-Type"] == "application/json; charset=utf-8")
  }

  @Test func errorResponseIncludesJSONContentType() throws {
    let databaseURL = try makeTemporaryDirectory().appendingPathComponent("ct-error.sqlite3")
    let store = try SQLiteServerStateStore(databaseURL: databaseURL)
    let api = SymphonyHTTPAPI(store: store, version: "1.0.0", trackerKind: "github")

    let response = try api.respond(
      to: SymphonyAPIRequest(method: "GET", path: "/api/v1/unknown"))
    #expect(response.statusCode == 404)
    #expect(response.headers["Content-Type"] == "application/json; charset=utf-8")
  }

  @Test func issueListResponseIncludesJSONContentType() throws {
    let databaseURL = try makeTemporaryDirectory().appendingPathComponent("ct-issues.sqlite3")
    let store = try SQLiteServerStateStore(databaseURL: databaseURL)
    let api = SymphonyHTTPAPI(store: store, version: "1.0.0", trackerKind: "github")

    let response = try api.respond(
      to: SymphonyAPIRequest(method: "GET", path: "/api/v1/issues"))
    #expect(response.statusCode == 200)
    #expect(response.headers["Content-Type"] == "application/json; charset=utf-8")
  }
}

// MARK: - SymphonyHTTPAPI JSON Sorted Keys

@Suite("SymphonyHTTPAPI JSON Sorted Keys")
struct SymphonyHTTPAPISortedKeysTests {

  @Test func healthResponseHasSortedJSONKeys() throws {
    let databaseURL = try makeTemporaryDirectory().appendingPathComponent("sorted.sqlite3")
    let store = try SQLiteServerStateStore(databaseURL: databaseURL)
    let api = SymphonyHTTPAPI(store: store, version: "1.0.0", trackerKind: "github")

    let response = try api.respond(
      to: SymphonyAPIRequest(method: "GET", path: "/api/v1/health"))
    let json = try #require(String(data: response.body, encoding: .utf8))

    // Snake-case keys: server_time < status < tracker_kind < version
    let serverTimeRange = try #require(json.range(of: "\"server_time\""))
    let statusRange = try #require(json.range(of: "\"status\""))
    let trackerRange = try #require(json.range(of: "\"tracker_kind\""))
    let versionRange = try #require(json.range(of: "\"version\""))
    #expect(serverTimeRange.lowerBound < statusRange.lowerBound)
    #expect(statusRange.lowerBound < trackerRange.lowerBound)
    #expect(trackerRange.lowerBound < versionRange.lowerBound)
  }
}

// MARK: - CopilotCLIAdapter Startup Message Constants

@Suite("CopilotCLIAdapter Startup Constants")
struct CopilotCLIAdapterStartupConstantTests {

  @Test func initializeMessageContainsClientInfoAndProtocolVersion() async throws {
    let stubLauncher = StubProcessLauncher()
    let stubProcess = StubLaunchedProcess()
    stubLauncher.setStubProcess(stubProcess)

    let adapter = CopilotCLIAdapter(
      config: .defaults,
      processLauncher: stubLauncher
    )

    _ = try await adapter.startSession(
      sessionID: SessionID("s-init-const"),
      workspacePath: "/tmp/ws",
      prompt: "test",
      environment: [:]
    )
    stubProcess.simulateOutput(
      #"{"id":2,"result":{"sessionId":"session-1"}}"# + "\n"
        + #"{"id":3,"result":{"stopReason":"end_turn"}}"# + "\n")

    let messages = try stubProcess.recordedInputStrings.map(parseJSONObject)
    // 3 messages: initialize, newSession, startup prompt (sent after sessionId response)
    #expect(messages.count == 3)

    // Initialize message
    let initialize = try #require(messages.first)
    let params = try #require(initialize["params"] as? [String: Any])
    let clientInfo = try #require(params["clientInfo"] as? [String: Any])
    #expect(clientInfo["name"] as? String == "symphony")
    #expect(clientInfo["version"] as? String == "0.0.1")
    #expect(params["protocolVersion"] as? Int == 1)

    // clientCapabilities should be empty
    let capabilities = try #require(params["clientCapabilities"] as? [String: Any])
    #expect(capabilities.isEmpty)
  }

  @Test func newSessionMessageContainsCwdAndMcpServers() async throws {
    let stubLauncher = StubProcessLauncher()
    let stubProcess = StubLaunchedProcess()
    stubLauncher.setStubProcess(stubProcess)

    let adapter = CopilotCLIAdapter(
      config: .defaults,
      processLauncher: stubLauncher
    )

    _ = try await adapter.startSession(
      sessionID: SessionID("s-session-const"),
      workspacePath: "/tmp/my-workspace",
      prompt: "test",
      environment: [:]
    )
    stubProcess.simulateOutput(
      #"{"id":2,"result":{"sessionId":"session-2"}}"# + "\n"
        + #"{"id":3,"result":{"stopReason":"end_turn"}}"# + "\n")

    let messages = try stubProcess.recordedInputStrings.map(parseJSONObject)
    // newSession is at index 1 (after initialize, before startup prompt)
    let newSession = messages[1]
    let params = try #require(newSession["params"] as? [String: Any])
    #expect(params["cwd"] as? String == "/tmp/my-workspace")

    let mcpServers = try #require(params["mcpServers"] as? [Any])
    #expect(mcpServers.isEmpty)
  }
}
