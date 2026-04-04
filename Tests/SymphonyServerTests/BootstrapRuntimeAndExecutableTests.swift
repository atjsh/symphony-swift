import CoreFoundation
import Darwin
import Foundation
import SymphonyShared
import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore

@Suite(.serialized)
struct BootstrapRuntimeHooksIsolationTests {
  @Test func keepAlivePolicyCanExitImmediatelyForServerCoverageRuns() {
    withBootstrapRuntimeHooksLock {
      #expect(!BootstrapKeepAlivePolicy.shouldExitAfterStartup(environment: [:]))
      #expect(
        BootstrapKeepAlivePolicy.shouldExitAfterStartup(environment: [
          BootstrapKeepAlivePolicy.exitAfterStartupKey: "1"
        ]))

      let action = BootstrapKeepAlivePolicy.makeKeepAlive(environment: [
        BootstrapKeepAlivePolicy.exitAfterStartupKey: "1"
      ])
      action()

      var didKeepAlive = false
      let previousKeepAlive = BootstrapRuntimeHooks.keepAliveOverride
      BootstrapRuntimeHooks.keepAliveOverride = { didKeepAlive = true }
      defer { BootstrapRuntimeHooks.keepAliveOverride = previousKeepAlive }

      let blockingAction = BootstrapKeepAlivePolicy.makeKeepAlive(environment: [:])
      blockingAction()
      #expect(didKeepAlive)
    }
  }

  @Test func bootstrapServerRunnerRunUsesDefaultHooksAndFallsBackToDefaultPort() throws {
    try withBootstrapRuntimeHooksLock {
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

      try BootstrapServerRunner.run(
        componentName: "DefaultHookServer",
        environment: [
          BootstrapEnvironment.serverPortKey: "abc"
        ],
        processIdentifier: 88,
        launchArguments: ["server"],
        startedAt: Date(timeIntervalSince1970: 1_700_000_400),
        startServer: false
      )

      #expect(didKeepAlive)
      #expect(lines.contains("[DefaultHookServer] endpoint=http://127.0.0.1:8080"))
      #expect(
        BootstrapEnvironment.effectiveServerEndpoint(environment: [:]).host == "127.0.0.1")
      #expect(
        BootstrapEnvironment.effectiveServerEndpoint(environment: [
          BootstrapEnvironment.serverPortKey: "abc"
        ]).port == 8080)
    }
  }

  @Test func bootstrapRuntimeHooksDefaultBranchesAndEndpointFallbacks() {
    withBootstrapRuntimeHooksLock {
      let previousOutput = BootstrapRuntimeHooks.outputOverride
      let previousKeepAliveOverride = BootstrapRuntimeHooks.keepAliveOverride
      let previousRunLoopRunner = BootstrapRuntimeHooks.runLoopRunnerOverride
      BootstrapRuntimeHooks.outputOverride = nil

      var didDefaultRunLoop = false
      var didCustomRunLoop = false
      BootstrapRuntimeHooks.keepAliveOverride = nil
      BootstrapRuntimeHooks.runLoopRunnerOverride = { didCustomRunLoop = true }
      BootstrapRuntimeHooks.withDefaultRunLoopAction { didDefaultRunLoop = true }
      defer {
        BootstrapRuntimeHooks.outputOverride = previousOutput
        BootstrapRuntimeHooks.keepAliveOverride = previousKeepAliveOverride
        BootstrapRuntimeHooks.runLoopRunnerOverride = previousRunLoopRunner
        BootstrapRuntimeHooks.resetDefaultRunLoopAction()
      }

      BootstrapRuntimeHooks.defaultOutput("[SymphonyServer] probe")
      BootstrapRuntimeHooks.keepAlive()
      #expect(didCustomRunLoop)

      BootstrapRuntimeHooks.runLoopRunnerOverride = nil
      BootstrapRuntimeHooks.keepAlive()
      #expect(didDefaultRunLoop)

      let normalized = BootstrapServerEndpoint(scheme: " ", host: " ", port: 0)
      #expect(normalized == .defaultEndpoint)
      #expect(normalized.description == "http://127.0.0.1:8080")
      #expect(BootstrapServerEndpoint.defaultEndpoint.host == "127.0.0.1")

      let fallbackEndpoint = BootstrapServerEndpoint(
        scheme: "http", host: "bad host", port: 8080)
      #expect(fallbackEndpoint.url == nil)
      #expect(fallbackEndpoint.displayString == "http://bad host:8080")
      #expect(fallbackEndpoint.description == "http://bad host:8080")
    }
  }

  @Test func bootstrapRuntimeHooksDefaultRunLoopFallbackCanBeExercisedDirectly() {
    withBootstrapRuntimeHooksLock {
      let previousKeepAliveOverride = BootstrapRuntimeHooks.keepAliveOverride
      let previousRunLoopRunner = BootstrapRuntimeHooks.runLoopRunnerOverride
      BootstrapRuntimeHooks.keepAliveOverride = nil
      BootstrapRuntimeHooks.runLoopRunnerOverride = nil
      defer {
        BootstrapRuntimeHooks.keepAliveOverride = previousKeepAliveOverride
        BootstrapRuntimeHooks.runLoopRunnerOverride = previousRunLoopRunner
      }

      var didReachStopBlock = false
      let runLoop = CFRunLoopGetCurrent()
      CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) {
        didReachStopBlock = true
        CFRunLoopStop(runLoop)
      }
      CFRunLoopWakeUp(runLoop)
      BootstrapRuntimeHooks.keepAlive()

      #expect(didReachStopBlock)
    }
  }

  @Test func bootstrapRuntimeHooksKeepAliveUsesExplicitOverrideFirst() {
    withBootstrapRuntimeHooksLock {
      let previousKeepAliveOverride = BootstrapRuntimeHooks.keepAliveOverride
      let previousRunLoopRunner = BootstrapRuntimeHooks.runLoopRunnerOverride
      var didKeepAlive = false
      var didRunLoop = false
      BootstrapRuntimeHooks.keepAliveOverride = { didKeepAlive = true }
      BootstrapRuntimeHooks.runLoopRunnerOverride = { didRunLoop = true }
      defer {
        BootstrapRuntimeHooks.keepAliveOverride = previousKeepAliveOverride
        BootstrapRuntimeHooks.runLoopRunnerOverride = previousRunLoopRunner
      }

      BootstrapRuntimeHooks.keepAlive()

      #expect(didKeepAlive)
      #expect(!didRunLoop)
    }
  }
}

@Test
func bootstrapEnvironmentSQLitePathFallsBackToHomeDirectoryWhenApplicationSupportIsUnavailable() {
  let fileManager = EmptyApplicationSupportFileManager(
    homeDirectory: URL(fileURLWithPath: "/tmp/bootstrap-home", isDirectory: true))

  let sqlitePath = BootstrapEnvironment.effectiveSQLitePath(
    environment: [:],
    fileManager: fileManager
  )

  #expect(
    sqlitePath.path == "/tmp/bootstrap-home/Library/Application Support/symphony/symphony.sqlite3")
}

@Test func bootstrapEnvironmentSQLitePathPrefersExplicitEnvironmentPath() {
  let sqlitePath = BootstrapEnvironment.effectiveSQLitePath(
    environment: [BootstrapEnvironment.serverSQLitePathKey: "~/custom.sqlite3"],
    fileManager: .default
  )

  #expect(sqlitePath.path.hasSuffix("/custom.sqlite3"))
}

@Test func builtServerExecutableStartsAndExitsWhenRequested() throws {
  let executable = bootstrapBuiltProductsDirectory().appendingPathComponent("symphony-server")
  #expect(FileManager.default.isExecutableFile(atPath: executable.path))

  let process = Process()
  let output = Pipe()
  process.executableURL = executable
  var environment = ProcessInfo.processInfo.environment
  environment[BootstrapKeepAlivePolicy.exitAfterStartupKey] = "1"
  environment[BootstrapEnvironment.serverSchemeKey] = "https"
  environment[BootstrapEnvironment.serverHostKey] = "server.example.com"
  environment[BootstrapEnvironment.serverPortKey] = "9555"
  process.environment = environment
  process.standardOutput = output
  process.standardError = output
  try process.run()
  process.waitUntilExit()

  let transcript = String(
    decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
  #expect(process.terminationStatus == 0)
  #expect(transcript.contains("[SymphonyServer] starting"))
  #expect(transcript.contains("[SymphonyServer] endpoint=https://server.example.com:9555"))
}

@Test func builtServerExecutableServesHealthEndpointUntilTerminated() async throws {
  let executable = bootstrapBuiltProductsDirectory().appendingPathComponent("symphony-server")
  #expect(FileManager.default.isExecutableFile(atPath: executable.path))
  let port = try bootstrapAvailableLoopbackPort()

  let process = Process()
  let output = Pipe()
  process.executableURL = executable
  var environment = ProcessInfo.processInfo.environment
  environment[BootstrapEnvironment.serverHostKey] = "127.0.0.1"
  environment[BootstrapEnvironment.serverPortKey] = String(port)
  process.environment = environment
  process.standardOutput = output
  process.standardError = output
  try process.run()

  do {
    let url = try #require(URL(string: "http://127.0.0.1:\(port)/api/v1/health"))
    let session = URLSession(configuration: .ephemeral)
    var responseData: Data?

    for _ in 0..<30 {
      do {
        let (data, response) = try await session.data(from: url)
        let httpResponse = try #require(response as? HTTPURLResponse)
        if httpResponse.statusCode == 200 {
          responseData = data
          break
        }
      } catch {
        try await Task.sleep(for: .milliseconds(100))
      }
    }

    let data = try #require(responseData)
    let health = try JSONDecoder().decode(HealthResponse.self, from: data)
    #expect(health.status == "ok")
    #expect(health.trackerKind == "github")
  } catch {
    try await bootstrapTerminateProcessIfRunning(process)
    throw error
  }

  try await bootstrapTerminateProcessIfRunning(process)
}

@Test func builtServerExecutablePrintsFailureAndExitsForInvalidSQLitePath() throws {
  let executable = bootstrapBuiltProductsDirectory().appendingPathComponent("symphony-server")
  #expect(FileManager.default.isExecutableFile(atPath: executable.path))

  let invalidDatabaseURL = FileManager.default.temporaryDirectory.appendingPathComponent(
    UUID().uuidString, isDirectory: true)
  try FileManager.default.createDirectory(at: invalidDatabaseURL, withIntermediateDirectories: true)

  let process = Process()
  let output = Pipe()
  process.executableURL = executable
  var environment = ProcessInfo.processInfo.environment
  environment[BootstrapEnvironment.serverSQLitePathKey] = invalidDatabaseURL.path
  process.environment = environment
  process.standardOutput = output
  process.standardError = output
  try process.run()
  process.waitUntilExit()

  let transcript = String(
    decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
  #expect(process.terminationStatus == 1)
  #expect(transcript.contains("[SymphonyServer] failed to start:"))
  #expect(transcript.contains(invalidDatabaseURL.path))
}
