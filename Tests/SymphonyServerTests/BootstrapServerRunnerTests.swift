import Foundation
import Testing
@testable import SymphonyRuntime

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

@Test func bootstrapServerRunnerRunUsesDefaultHooksAndFallsBackToDefaultPort() {
    withBootstrapRuntimeHooksLock {
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

private func builtProductsDirectory() -> URL {
    Bundle(for: BundleLocator.self).bundleURL.deletingLastPathComponent()
}

private final class BundleLocator {}

private let bootstrapRuntimeHooksLock = NSLock()

private func withBootstrapRuntimeHooksLock(_ body: () -> Void) {
    bootstrapRuntimeHooksLock.lock()
    defer { bootstrapRuntimeHooksLock.unlock() }
    body()
}
