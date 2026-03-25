import Foundation
import Testing
@testable import SymphonyRuntime
import SymphonyShared

@Test func startupStateUsesProvidedLaunchArguments() {
    let state = BootstrapServerRunner.startupState(
        componentName: "SymphonyServer",
        environment: [:],
        processIdentifier: 4321,
        launchArguments: ["server", "--port", "8080"],
        startedAt: Date(timeIntervalSince1970: 1_700_000_123)
    )

    #expect(state.launchArguments == ["server", "--port", "8080"])
    #expect(state.description.contains("[SymphonyServer] starting"))
    #expect(state.description.contains("[SymphonyServer] arguments=server --port 8080"))
}

@Test func startupStateUsesEnvironmentOverridesAndDescription() {
    let state = BootstrapServerRunner.startupState(
        componentName: "WorkerServer",
        environment: [
            BootstrapEnvironment.serverSchemeKey: "https",
            BootstrapEnvironment.serverHostKey: "worker.example.com",
            BootstrapEnvironment.serverPortKey: "8443",
        ],
        processIdentifier: 777,
        launchArguments: ["server"],
        startedAt: Date(timeIntervalSince1970: 1_700_000_222)
    )

    #expect(state.endpoint.displayString == "https://worker.example.com:8443")
    #expect(state.description.contains("[WorkerServer] endpoint=https://worker.example.com:8443"))
}

@Test func keepAlivePolicyCanExitImmediatelyForServerCoverageRuns() {
    withBootstrapRuntimeHooksLock {
        #expect(!BootstrapKeepAlivePolicy.shouldExitAfterStartup(environment: [:]))
        #expect(BootstrapKeepAlivePolicy.shouldExitAfterStartup(environment: [BootstrapKeepAlivePolicy.exitAfterStartupKey: "1"]))

        let action = BootstrapKeepAlivePolicy.makeKeepAlive(environment: [BootstrapKeepAlivePolicy.exitAfterStartupKey: "1"])
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
                BootstrapEnvironment.serverPortKey: "abc",
            ],
            processIdentifier: 88,
            launchArguments: ["server"],
            startedAt: Date(timeIntervalSince1970: 1_700_000_400),
            startServer: false
        )

        #expect(didKeepAlive)
        #expect(lines.contains("[DefaultHookServer] endpoint=http://localhost:8080"))
        #expect(BootstrapEnvironment.effectiveServerEndpoint(environment: [BootstrapEnvironment.serverPortKey: "abc"]).port == 8080)
    }
}

@Test func bootstrapRuntimeHooksDefaultBranchesAndEndpointFallbacks() {
    withBootstrapRuntimeHooksLock {
        let previousOutput = BootstrapRuntimeHooks.outputOverride
        let previousKeepAliveOverride = BootstrapRuntimeHooks.keepAliveOverride
        let previousRunLoopRunner = BootstrapRuntimeHooks.runLoopRunner
        BootstrapRuntimeHooks.outputOverride = nil

        var didRunLoop = false
        BootstrapRuntimeHooks.keepAliveOverride = nil
        BootstrapRuntimeHooks.runLoopRunner = { didRunLoop = true }
        defer {
            BootstrapRuntimeHooks.outputOverride = previousOutput
            BootstrapRuntimeHooks.keepAliveOverride = previousKeepAliveOverride
            BootstrapRuntimeHooks.runLoopRunner = previousRunLoopRunner
        }

        BootstrapRuntimeHooks.defaultOutput("[SymphonyServer] probe")
        BootstrapRuntimeHooks.keepAlive()
        #expect(didRunLoop)

        let normalized = BootstrapServerEndpoint(scheme: " ", host: " ", port: 0)
        #expect(normalized == .defaultEndpoint)
        #expect(normalized.description == "http://localhost:8080")

        let fallbackEndpoint = BootstrapServerEndpoint(scheme: "http", host: "bad host", port: 8080)
        #expect(fallbackEndpoint.url == nil)
        #expect(fallbackEndpoint.displayString == "http://bad host:8080")
        #expect(fallbackEndpoint.description == "http://bad host:8080")
    }
}

@Test func bootstrapEnvironmentSQLitePathFallsBackToHomeDirectoryWhenApplicationSupportIsUnavailable() {
    let fileManager = EmptyApplicationSupportFileManager(homeDirectory: URL(fileURLWithPath: "/tmp/bootstrap-home", isDirectory: true))

    let sqlitePath = BootstrapEnvironment.effectiveSQLitePath(
        environment: [:],
        fileManager: fileManager
    )

    #expect(sqlitePath.path == "/tmp/bootstrap-home/Library/Application Support/symphony/symphony.sqlite3")
}

@Test func builtServerExecutableStartsAndExitsWhenRequested() throws {
    let executable = builtProductsDirectory().appendingPathComponent("SymphonyServer")
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

    let transcript = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    #expect(process.terminationStatus == 0)
    #expect(transcript.contains("[SymphonyServer] starting"))
    #expect(transcript.contains("[SymphonyServer] endpoint=https://server.example.com:9555"))
}

@Test func builtServerExecutableServesHealthEndpointUntilTerminated() async throws {
    let executable = builtProductsDirectory().appendingPathComponent("SymphonyServer")
    #expect(FileManager.default.isExecutableFile(atPath: executable.path))

    let process = Process()
    let output = Pipe()
    process.executableURL = executable
    var environment = ProcessInfo.processInfo.environment
    environment[BootstrapEnvironment.serverHostKey] = "127.0.0.1"
    environment[BootstrapEnvironment.serverPortKey] = "9556"
    process.environment = environment
    process.standardOutput = output
    process.standardError = output
    try process.run()
    defer {
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
    }

    let url = try #require(URL(string: "http://127.0.0.1:9556/api/v1/health"))
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
}

@Test func builtServerExecutablePrintsFailureAndExitsForInvalidSQLitePath() throws {
    let executable = builtProductsDirectory().appendingPathComponent("SymphonyServer")
    #expect(FileManager.default.isExecutableFile(atPath: executable.path))

    let invalidDatabaseURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
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

    let transcript = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    #expect(process.terminationStatus == 1)
    #expect(transcript.contains("[SymphonyServer] failed to start:"))
    #expect(transcript.contains(invalidDatabaseURL.path))
}

private func builtProductsDirectory() -> URL {
    Bundle(for: BundleLocator.self).bundleURL.deletingLastPathComponent()
}

private final class BundleLocator {}

private let bootstrapRuntimeHooksLock = NSLock()

private func withBootstrapRuntimeHooksLock(_ body: () throws -> Void) rethrows {
    bootstrapRuntimeHooksLock.lock()
    defer { bootstrapRuntimeHooksLock.unlock() }
    try body()
}

private final class EmptyApplicationSupportFileManager: FileManager, @unchecked Sendable {
    private let testHomeDirectory: URL

    init(homeDirectory: URL) {
        self.testHomeDirectory = homeDirectory
        super.init()
    }

    override func urls(for directory: FileManager.SearchPathDirectory, in domainMask: FileManager.SearchPathDomainMask) -> [URL] {
        []
    }

    override var homeDirectoryForCurrentUser: URL {
        testHomeDirectory
    }
}
