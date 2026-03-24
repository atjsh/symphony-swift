import XCTest
@testable import XcodeSupport

final class BootstrapServerRunnerTests: XCTestCase {
    func testStartupStateUsesProvidedLaunchArguments() {
        let state = BootstrapServerRunner.startupState(
            componentName: "SymphonyServer",
            environment: [:],
            processIdentifier: 4321,
            launchArguments: ["server", "--port", "8080"],
            startedAt: Date(timeIntervalSince1970: 1_700_000_123)
        )

        XCTAssertEqual(state.launchArguments, ["server", "--port", "8080"])
        XCTAssertTrue(state.description.contains("[SymphonyServer] starting"))
        XCTAssertTrue(state.description.contains("[SymphonyServer] arguments=server --port 8080"))
    }

    func testStartupStateUsesEnvironmentOverridesAndDescription() {
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

        XCTAssertEqual(state.endpoint.displayString, "https://worker.example.com:8443")
        XCTAssertTrue(state.description.contains("[WorkerServer] endpoint=https://worker.example.com:8443"))
    }

    func testKeepAlivePolicyCanExitImmediatelyForServerCoverageRuns() {
        XCTAssertFalse(BootstrapKeepAlivePolicy.shouldExitAfterStartup(environment: [:]))
        XCTAssertTrue(BootstrapKeepAlivePolicy.shouldExitAfterStartup(environment: [BootstrapKeepAlivePolicy.exitAfterStartupKey: "1"]))

        let action = BootstrapKeepAlivePolicy.makeKeepAlive(environment: [BootstrapKeepAlivePolicy.exitAfterStartupKey: "1"])
        action()

        var didKeepAlive = false
        let previousKeepAlive = BootstrapRuntimeHooks.keepAliveOverride
        BootstrapRuntimeHooks.keepAliveOverride = { didKeepAlive = true }
        defer { BootstrapRuntimeHooks.keepAliveOverride = previousKeepAlive }

        let blockingAction = BootstrapKeepAlivePolicy.makeKeepAlive(environment: [:])
        blockingAction()
        XCTAssertTrue(didKeepAlive)
    }

    func testBootstrapServerRunnerRunUsesDefaultHooksAndFallsBackToDefaultPort() {
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
            componentName: "DefaultHookServer",
            environment: [
                BootstrapEnvironment.serverPortKey: "abc",
            ],
            processIdentifier: 88,
            launchArguments: ["server"],
            startedAt: Date(timeIntervalSince1970: 1_700_000_400)
        )

        XCTAssertTrue(didKeepAlive)
        XCTAssertTrue(lines.contains("[DefaultHookServer] endpoint=http://localhost:8080"))
        XCTAssertEqual(BootstrapEnvironment.effectiveServerEndpoint(environment: [BootstrapEnvironment.serverPortKey: "abc"]).port, 8080)
    }

    func testBootstrapRuntimeHooksDefaultBranchesAndEndpointFallbacks() {
        BootstrapRuntimeHooks.defaultOutput("[SymphonyServer] probe")

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

        let normalized = BootstrapServerEndpoint(scheme: " ", host: " ", port: 0)
        XCTAssertEqual(normalized, .defaultEndpoint)
        XCTAssertEqual(normalized.description, "http://localhost:8080")

        let fallbackEndpoint = BootstrapServerEndpoint(scheme: "http", host: "bad host", port: 8080)
        XCTAssertNil(fallbackEndpoint.url)
        XCTAssertEqual(fallbackEndpoint.displayString, "http://bad host:8080")
        XCTAssertEqual(fallbackEndpoint.description, "http://bad host:8080")
    }

    func testBuiltServerExecutableStartsAndExitsWhenRequested() throws {
        let executable = builtProductsDirectory().appendingPathComponent("SymphonyServer")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: executable.path))

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
        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertTrue(transcript.contains("[SymphonyServer] starting"))
        XCTAssertTrue(transcript.contains("[SymphonyServer] endpoint=https://server.example.com:9555"))
    }

    private func builtProductsDirectory() -> URL {
        Bundle(for: Self.self).bundleURL.deletingLastPathComponent()
    }
}
