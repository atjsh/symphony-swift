import Foundation
import SymphonyShared
import XCTest

@testable import Symphony

final class BootstrapSupportTests: XCTestCase {
  func testEffectiveServerEndpointUsesDefaults() {
    let endpoint = BootstrapEnvironment.effectiveServerEndpoint(environment: [:])

    XCTAssertEqual(endpoint, .defaultEndpoint)
    XCTAssertEqual(endpoint.displayString, "http://localhost:8080")
  }

  func testEffectiveServerEndpointUsesEnvironmentOverrides() {
    let endpoint = BootstrapEnvironment.effectiveServerEndpoint(
      environment: [
        BootstrapEnvironment.serverSchemeKey: "https",
        BootstrapEnvironment.serverHostKey: "example.com",
        BootstrapEnvironment.serverPortKey: "9443",
      ]
    )

    XCTAssertEqual(endpoint.scheme, "https")
    XCTAssertEqual(endpoint.host, "example.com")
    XCTAssertEqual(endpoint.port, 9443)
    XCTAssertEqual(endpoint.displayString, "https://example.com:9443")
  }

  func testStartupStateIncludesEndpointAndComponentName() {
    let state = BootstrapServerRunner.startupState(
      componentName: "SymphonyServer",
      environment: [:],
      processIdentifier: 1234,
      launchArguments: ["symphony-server", "--verbose"],
      startedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )

    XCTAssertEqual(state.componentName, "SymphonyServer")
    XCTAssertTrue(state.startupLogLines.contains("[SymphonyServer] pid=1234"))
    XCTAssertTrue(state.startupLogLines.contains("[SymphonyServer] endpoint=http://localhost:8080"))
  }

  func testBootstrapServerEndpointNormalizesInvalidComponentsBackToDefaults() {
    let endpoint = BootstrapServerEndpoint(scheme: " ", host: " ", port: 0)

    XCTAssertEqual(endpoint, .defaultEndpoint)
    XCTAssertEqual(endpoint.url?.absoluteString, "http://localhost:8080")
    XCTAssertEqual(endpoint.description, "http://localhost:8080")
  }

  func testEffectiveServerEndpointIgnoresInvalidEnvironmentValues() {
    let endpoint = BootstrapEnvironment.effectiveServerEndpoint(
      environment: [
        BootstrapEnvironment.serverSchemeKey: "   ",
        BootstrapEnvironment.serverHostKey: "",
        BootstrapEnvironment.serverPortKey: "99999",
      ]
    )

    XCTAssertEqual(endpoint, .defaultEndpoint)
  }

  func testEffectiveServerEndpointRejectsNonNumericPortAndPreservesDescription() {
    let endpoint = BootstrapEnvironment.effectiveServerEndpoint(
      environment: [
        BootstrapEnvironment.serverSchemeKey: "https",
        BootstrapEnvironment.serverHostKey: "example.com",
        BootstrapEnvironment.serverPortKey: "abc",
      ]
    )

    XCTAssertEqual(endpoint.port, 8080)
    XCTAssertEqual(endpoint.displayString, "https://example.com:8080")
    XCTAssertEqual(endpoint.description, endpoint.displayString)
  }

  func testBootstrapServerRunnerRunEmitsLogsAndInvokesKeepAlive() {
    var lines = [String]()
    var didKeepAlive = false

    BootstrapServerRunner.run(
      componentName: "TestServer",
      environment: [
        BootstrapEnvironment.serverSchemeKey: "https",
        BootstrapEnvironment.serverHostKey: "example.com",
        BootstrapEnvironment.serverPortKey: "9443",
      ],
      processIdentifier: 22,
      launchArguments: ["server", "--flag"],
      startedAt: Date(timeIntervalSince1970: 1_700_000_100),
      output: { lines.append($0) },
      keepAlive: { didKeepAlive = true }
    )

    XCTAssertTrue(didKeepAlive)
    XCTAssertEqual(lines.first, "[TestServer] starting")
    XCTAssertTrue(lines.contains("[TestServer] pid=22"))
    XCTAssertTrue(lines.contains("[TestServer] endpoint=https://example.com:9443"))
    XCTAssertTrue(lines.contains("[TestServer] arguments=server --flag"))
  }

  func testBootstrapServerRunnerRunUsesInjectedDefaultHooks() {
    var lines = [String]()
    var didKeepAlive = false
    let previousOutput = BootstrapRuntimeHooks.outputOverride
    let previousKeepAlive = BootstrapRuntimeHooks.keepAliveOverride
    BootstrapRuntimeHooks.outputOverride = { lines.append($0) }
    BootstrapRuntimeHooks.keepAliveOverride = { didKeepAlive = true }
    defer {
      BootstrapRuntimeHooks.outputOverride = previousOutput
      BootstrapRuntimeHooks.keepAliveOverride = previousKeepAlive
    }

    BootstrapServerRunner.run(
      componentName: "HookedServer",
      environment: [:],
      processIdentifier: 77,
      launchArguments: ["server"],
      startedAt: Date(timeIntervalSince1970: 1_700_000_200)
    )

    XCTAssertTrue(didKeepAlive)
    XCTAssertTrue(lines.contains("[HookedServer] starting"))
    XCTAssertTrue(lines.contains("[HookedServer] pid=77"))
  }

  func testBootstrapStartupStateDescriptionAndKeepAlivePolicyNonExitBranch() {
    let state = BootstrapStartupState.current(
      componentName: "Symphony",
      environment: [:],
      processIdentifier: 55,
      launchArguments: ["Symphony"],
      startedAt: Date(timeIntervalSince1970: 1_700_000_300)
    )
    XCTAssertTrue(state.description.contains("[Symphony] starting"))
    XCTAssertFalse(BootstrapKeepAlivePolicy.shouldExitAfterStartup(environment: [:]))

    var didKeepAlive = false
    let previousKeepAlive = BootstrapRuntimeHooks.keepAliveOverride
    BootstrapRuntimeHooks.keepAliveOverride = { didKeepAlive = true }
    defer { BootstrapRuntimeHooks.keepAliveOverride = previousKeepAlive }

    BootstrapKeepAlivePolicy.makeKeepAlive(environment: [:])()
    XCTAssertTrue(didKeepAlive)
  }

  func testBootstrapRuntimeHooksDefaultBranchesAndDisplayFallback() {
    BootstrapRuntimeHooks.defaultOutput("[Symphony] probe")

    var didRunLoop = false
    let previousKeepAliveOverride = BootstrapRuntimeHooks.keepAliveOverride
    let previousRunLoopRunner = BootstrapRuntimeHooks.runLoopRunner
    BootstrapRuntimeHooks.keepAliveOverride = nil
    BootstrapRuntimeHooks.runLoopRunner = { didRunLoop = true }
    defer {
      BootstrapRuntimeHooks.keepAliveOverride = previousKeepAliveOverride
      BootstrapRuntimeHooks.runLoopRunner = previousRunLoopRunner
    }

    BootstrapRuntimeHooks.keepAlive()
    XCTAssertTrue(didRunLoop)

    let fallbackEndpoint = BootstrapServerEndpoint(scheme: "http", host: "bad host", port: 8080)
    XCTAssertNil(fallbackEndpoint.url)
    XCTAssertEqual(fallbackEndpoint.displayString, "http://bad host:8080")
    XCTAssertEqual(fallbackEndpoint.description, "http://bad host:8080")

    let exitAction = BootstrapKeepAlivePolicy.makeKeepAlive(
      environment: [BootstrapKeepAlivePolicy.exitAfterStartupKey: "1"]
    )
    exitAction()
  }

  #if os(macOS)
    func testBuiltSymphonyAppStartsAndExitsWhenRequested() throws {
      let executable = try XCTUnwrap(Bundle.main.executableURL)
      XCTAssertTrue(FileManager.default.isExecutableFile(atPath: executable.path))

      let process = Process()
      let output = Pipe()
      var environment = ProcessInfo.processInfo.environment
      environment[BootstrapKeepAlivePolicy.exitAfterStartupKey] = "1"
      environment[BootstrapEnvironment.serverSchemeKey] = "https"
      environment[BootstrapEnvironment.serverHostKey] = "app.example.com"
      environment[BootstrapEnvironment.serverPortKey] = "9443"
      process.executableURL = executable
      process.environment = environment
      process.standardOutput = output
      process.standardError = output
      try process.run()
      process.waitUntilExit()

      let transcript = String(
        decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
      XCTAssertEqual(process.terminationStatus, 0)
      XCTAssertTrue(transcript.contains("[Symphony] starting"))
      XCTAssertTrue(transcript.contains("[Symphony] endpoint=https://app.example.com:9443"))
    }
  #endif

  @MainActor
  func testContentViewAndAppBodiesCanBeEvaluated() {
    let endpoint = BootstrapServerEndpoint(scheme: "https", host: "example.com", port: 9443)
    let view = ContentView(endpoint: endpoint)
    _ = view.body

    let defaultApp = SymphonyApp()
    _ = defaultApp.body
  }

  func testUITestingSymphonyAPIClientReturnsFixtureData() async throws {
    let client = UITestingSymphonyAPIClient()
    let endpoint = try ServerEndpoint()

    XCTAssertNil(SymphonyApp.resolveClient(arguments: ["Symphony"]))
    XCTAssertNotNil(SymphonyApp.resolveClient(arguments: ["Symphony", "--ui-testing"]))

    let healthResponse = try await client.health(endpoint: endpoint)
    XCTAssertEqual(healthResponse.status, "ok")

    let issuesResponse = try await client.issues(endpoint: endpoint)
    XCTAssertEqual(issuesResponse.items.count, 1)
    XCTAssertEqual(issuesResponse.items[0].title, "Implement feature")

    let issueDetail = try await client.issueDetail(endpoint: endpoint, issueID: IssueID("issue-1"))
    XCTAssertEqual(issueDetail.issue.title, "Implement feature")
    XCTAssertEqual(issueDetail.issue.labels, ["feature", "ui"])
    XCTAssertEqual(issueDetail.recentSessions.count, 1)

    let runDetail = try await client.runDetail(endpoint: endpoint, runID: RunID("run-1"))
    XCTAssertEqual(runDetail.status, "running")
    XCTAssertEqual(runDetail.tokens.inputTokens, 100)
    XCTAssertEqual(runDetail.turnCount, 3)

    let logsResponse = try await client.logs(
      endpoint: endpoint, sessionID: SessionID("session-1"), cursor: nil, limit: 50)
    XCTAssertEqual(logsResponse.items.count, 2)
    XCTAssertFalse(logsResponse.hasMore)

    let refreshResponse = try await client.refresh(endpoint: endpoint)
    XCTAssertTrue(refreshResponse.queued)

    let stream = try client.logStream(
      endpoint: endpoint, sessionID: SessionID("session-1"), cursor: nil)
    var streamEvents = [AgentRawEvent]()
    for try await event in stream {
      streamEvents.append(event)
    }
    XCTAssertTrue(streamEvents.isEmpty)
  }
}
