import Foundation
import SymphonyShared
import Testing

@testable import SymphonySwiftUIApp

@Suite("Bootstrap Support", .serialized)
struct BootstrapSupportTests {
  @Test func effectiveServerEndpointUsesDefaults() {
    let endpoint = BootstrapEnvironment.effectiveServerEndpoint(environment: [:])

    #expect(endpoint == .defaultEndpoint)
    #expect(endpoint.displayString == "http://localhost:8080")
  }

  @Test func effectiveServerEndpointUsesEnvironmentOverrides() {
    let endpoint = BootstrapEnvironment.effectiveServerEndpoint(
      environment: [
        BootstrapEnvironment.serverSchemeKey: "https",
        BootstrapEnvironment.serverHostKey: "example.com",
        BootstrapEnvironment.serverPortKey: "9443",
      ]
    )

    #expect(endpoint.scheme == "https")
    #expect(endpoint.host == "example.com")
    #expect(endpoint.port == 9443)
    #expect(endpoint.displayString == "https://example.com:9443")
  }

  @Test func startupStateIncludesEndpointAndComponentName() {
    let state = BootstrapServerRunner.startupState(
      componentName: "SymphonyServer",
      environment: [:],
      processIdentifier: 1234,
      launchArguments: ["symphony-server", "--verbose"],
      startedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )

    #expect(state.componentName == "SymphonyServer")
    #expect(state.startupLogLines.contains("[SymphonyServer] pid=1234"))
    #expect(state.startupLogLines.contains("[SymphonyServer] endpoint=http://localhost:8080"))
  }

  @Test func bootstrapServerEndpointNormalizesInvalidComponentsBackToDefaults() {
    let endpoint = BootstrapServerEndpoint(scheme: " ", host: " ", port: 0)

    #expect(endpoint == .defaultEndpoint)
    #expect(endpoint.url?.absoluteString == "http://localhost:8080")
    #expect(endpoint.description == "http://localhost:8080")
  }

  @Test func effectiveServerEndpointIgnoresInvalidEnvironmentValues() {
    let endpoint = BootstrapEnvironment.effectiveServerEndpoint(
      environment: [
        BootstrapEnvironment.serverSchemeKey: "   ",
        BootstrapEnvironment.serverHostKey: "",
        BootstrapEnvironment.serverPortKey: "99999",
      ]
    )

    #expect(endpoint == .defaultEndpoint)
  }

  @Test func effectiveServerEndpointRejectsNonNumericPortAndPreservesDescription() {
    let endpoint = BootstrapEnvironment.effectiveServerEndpoint(
      environment: [
        BootstrapEnvironment.serverSchemeKey: "https",
        BootstrapEnvironment.serverHostKey: "example.com",
        BootstrapEnvironment.serverPortKey: "abc",
      ]
    )

    #expect(endpoint.port == 8080)
    #expect(endpoint.displayString == "https://example.com:8080")
    #expect(endpoint.description == endpoint.displayString)
  }

  @Test func bootstrapServerRunnerRunEmitsLogsAndInvokesKeepAlive() {
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

    #expect(didKeepAlive)
    #expect(lines.first == "[TestServer] starting")
    #expect(lines.contains("[TestServer] pid=22"))
    #expect(lines.contains("[TestServer] endpoint=https://example.com:9443"))
    #expect(lines.contains("[TestServer] arguments=server --flag"))
  }

  @Test func bootstrapServerRunnerRunUsesInjectedDefaultHooks() {
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

    #expect(didKeepAlive)
    #expect(lines.contains("[HookedServer] starting"))
    #expect(lines.contains("[HookedServer] pid=77"))
  }

  @Test func bootstrapStartupStateDescriptionAndKeepAlivePolicyNonExitBranch() {
    let state = BootstrapStartupState.current(
      componentName: "Symphony",
      environment: [:],
      processIdentifier: 55,
      launchArguments: ["Symphony"],
      startedAt: Date(timeIntervalSince1970: 1_700_000_300)
    )
    #expect(state.description.contains("[Symphony] starting"))
    #expect(!BootstrapKeepAlivePolicy.shouldExitAfterStartup(environment: [:]))

    var didKeepAlive = false
    let previousKeepAlive = BootstrapRuntimeHooks.keepAliveOverride
    BootstrapRuntimeHooks.keepAliveOverride = { didKeepAlive = true }
    defer { BootstrapRuntimeHooks.keepAliveOverride = previousKeepAlive }

    BootstrapKeepAlivePolicy.makeKeepAlive(environment: [:])()
    #expect(didKeepAlive)
  }

  @Test func bootstrapRuntimeHooksDefaultBranchesAndDisplayFallback() {
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
    #expect(didRunLoop)

    let fallbackEndpoint = BootstrapServerEndpoint(scheme: "http", host: "bad host", port: 8080)
    #expect(fallbackEndpoint.url == nil)
    #expect(fallbackEndpoint.displayString == "http://bad host:8080")
    #expect(fallbackEndpoint.description == "http://bad host:8080")

    let exitAction = BootstrapKeepAlivePolicy.makeKeepAlive(
      environment: [BootstrapKeepAlivePolicy.exitAfterStartupKey: "1"]
    )
    exitAction()
  }

  #if os(macOS)
    @Test func builtSymphonyAppStartsAndExitsWhenRequested() throws {
      let executable = try #require(Bundle.main.executableURL)
      #expect(FileManager.default.isExecutableFile(atPath: executable.path))

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
      #expect(process.terminationStatus == 0)
      #expect(transcript.contains("[Symphony] starting"))
      #expect(transcript.contains("[Symphony] endpoint=https://app.example.com:9443"))
    }
  #endif

  @MainActor
  @Test func contentViewAndAppBodiesCanBeEvaluated() {
    let endpoint = BootstrapServerEndpoint(scheme: "https", host: "example.com", port: 9443)
    let view = ContentView(endpoint: endpoint)
    _ = view.body

    let defaultApp = SymphonyApp()
    _ = defaultApp.body

    let configuredApp = SymphonyApp(arguments: ["Symphony"], environment: [:], startupOutput: { _ in })
    _ = configuredApp.body
  }

  @Test func defaultStartupOutputCanBeInvokedDirectly() {
    SymphonyApp.defaultStartupOutput("[Symphony] startup output probe")
  }

  @Test func defaultStartupLogEmitterCanBeInvokedDirectly() {
    SymphonyApp.emitStartupLogsIfNeeded(
      environment: [
        BootstrapKeepAlivePolicy.exitAfterStartupKey: "1",
        BootstrapEnvironment.serverSchemeKey: "https",
        BootstrapEnvironment.serverHostKey: "app.example.com",
        BootstrapEnvironment.serverPortKey: "9443",
      ]
    )
  }

  @MainActor
  @Test func symphonyAppInitEmitsStartupLogsWhenExitAfterStartupIsRequested() {
    let outputRecorder = SynchronizedOutputRecorder()

    SymphonyApp.emitStartupLogsIfNeeded(
      environment: [
        BootstrapKeepAlivePolicy.exitAfterStartupKey: "1",
        BootstrapEnvironment.serverSchemeKey: "https",
        BootstrapEnvironment.serverHostKey: "app.example.com",
        BootstrapEnvironment.serverPortKey: "9443",
      ],
      output: outputRecorder.append
    )

    #expect(outputRecorder.lines.contains("[Symphony] starting"))
    #expect(outputRecorder.lines.contains("[Symphony] endpoint=https://app.example.com:9443"))
  }

  @Test func uitestingSymphonyAPIClientReturnsFixtureData() async throws {
    let client = UITestingSymphonyAPIClient()
    let endpoint = try ServerEndpoint()

    #expect(SymphonyApp.resolveClient(arguments: ["Symphony"]) == nil)
    #expect(SymphonyApp.resolveClient(arguments: ["Symphony", "--ui-testing"]) != nil)
    #expect(
      SymphonyApp.resolveClient(
        arguments: ["Symphony"],
        environment: [BootstrapEnvironment.uiTestingKey: "1"]
      ) != nil
    )
    #expect(
      BootstrapEnvironment.isUITesting(
        arguments: ["Symphony"],
        environment: [BootstrapEnvironment.uiTestingKey: "1"]
      )
    )

    let healthResponse = try await client.health(endpoint: endpoint)
    #expect(healthResponse.status == "ok")

    let issuesResponse = try await client.issues(endpoint: endpoint)
    #expect(issuesResponse.items.count == 1)
    #expect(issuesResponse.items[0].title == "Implement feature")

    let issueDetail = try await client.issueDetail(endpoint: endpoint, issueID: IssueID("issue-1"))
    #expect(issueDetail.issue.title == "Implement feature")
    #expect(issueDetail.issue.labels == ["feature", "ui"])
    #expect(issueDetail.recentSessions.count == 1)

    let runDetail = try await client.runDetail(endpoint: endpoint, runID: RunID("run-1"))
    #expect(runDetail.status == "running")
    #expect(runDetail.tokens.inputTokens == 100)
    #expect(runDetail.turnCount == 3)

    let logsResponse = try await client.logs(
      endpoint: endpoint, sessionID: SessionID("session-1"), cursor: nil, limit: 50)
    #expect(logsResponse.items.count == 2)
    #expect(!logsResponse.hasMore)

    let refreshResponse = try await client.refresh(endpoint: endpoint)
    #expect(refreshResponse.queued)

    let stream = try client.logStream(
      endpoint: endpoint, sessionID: SessionID("session-1"), cursor: nil)
    var streamEvents = [AgentRawEvent]()
    for try await event in stream {
      streamEvents.append(event)
    }
    #expect(streamEvents.isEmpty)
  }
}

private final class SynchronizedOutputRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var storage = [String]()

  var lines: [String] {
    lock.lock()
    defer { lock.unlock() }
    return storage
  }

  func append(_ line: String) {
    lock.lock()
    storage.append(line)
    lock.unlock()
  }
}
