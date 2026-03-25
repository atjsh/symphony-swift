import Darwin
import Foundation
import Testing
@testable import SymphonyRuntime
import SymphonyShared

@Test func bootstrapServerRunnerEventObserverPublishesToLiveLogHub() async throws {
    let hub = LiveLogHub()
    let event = AgentRawEvent(
        sessionID: SessionID("session-42"),
        provider: "claude_code",
        sequence: EventSequence(1),
        timestamp: "2026-03-24T03:00:01Z",
        rawJSON: #"{"type":"status","payload":{"message":"starting"}}"#,
        providerEventType: "status",
        normalizedEventKind: "status"
    )
    let stream = await hub.subscribe(to: event.sessionID)
    let observer = BootstrapServerRunner.makeEventObserver(liveLogHub: hub)

    let receiveTask = Task {
        var iterator = stream.makeAsyncIterator()
        return await iterator.next()
    }
    observer(event)

    let received = try #require(await receiveTask.value)
    #expect(received == event)
}

@Test func bootstrapServerRunnerRunStartsServerAndReturnsAfterKeepAlive() async throws {
    let root = try makeTemporaryDirectory()
    let databaseURL = root.appendingPathComponent("bootstrap.sqlite3")
    let port = try availableLoopbackPort()
    let keepAliveEntered = LockedFlag()
    let allowReturn = DispatchSemaphore(value: 0)

    let runTask = Task {
        try BootstrapServerRunner.run(
            componentName: "InProcessServer",
            environment: [
                BootstrapEnvironment.serverHostKey: "127.0.0.1",
                BootstrapEnvironment.serverPortKey: String(port),
                BootstrapEnvironment.serverSQLitePathKey: databaseURL.path,
            ],
            output: { _ in },
            keepAlive: {
                keepAliveEntered.setTrue()
                allowReturn.wait()
            }
        )
    }
    defer { allowReturn.signal() }

    try await waitUntil("bootstrap runner enters keepAlive", timeout: .seconds(5)) {
        keepAliveEntered.value
    }

    let url = try #require(URL(string: "http://127.0.0.1:\(port)/api/v1/health"))
    let (data, response) = try await URLSession(configuration: .ephemeral).data(from: url)
    let httpResponse = try #require(response as? HTTPURLResponse)
    let health = try JSONDecoder().decode(HealthResponse.self, from: data)
    #expect(httpResponse.statusCode == 200)
    #expect(health.status == "ok")

    allowReturn.signal()
    try await runTask.value
}

@Test func bootstrapServerRunnerRunPropagatesStartupFailuresAndSignalOnlyFiresOnce() async throws {
    let firstSignal = ServerStartupSignal()
    Task.detached {
        firstSignal.ready()
        firstSignal.fail(POSIXError(.EIO))
    }
    try firstSignal.wait()

    let secondSignal = ServerStartupSignal()
    let expectedError = POSIXError(.EADDRINUSE)
    Task.detached {
        secondSignal.fail(expectedError)
        secondSignal.ready()
    }

    do {
        try secondSignal.wait()
        Issue.record("Expected startup failure to be reported.")
    } catch let error as POSIXError {
        #expect(error.code == expectedError.code)
    }

    let occupiedSocket = try makeListeningSocket(port: try availableLoopbackPort())
    defer { close(occupiedSocket) }
    let occupiedPort = try listeningPort(for: occupiedSocket)
    let root = try makeTemporaryDirectory()
    let databaseURL = root.appendingPathComponent("bind-failure.sqlite3")

    do {
        try BootstrapServerRunner.run(
            componentName: "BindFailureServer",
            environment: [
                BootstrapEnvironment.serverHostKey: "127.0.0.1",
                BootstrapEnvironment.serverPortKey: String(occupiedPort),
                BootstrapEnvironment.serverSQLitePathKey: databaseURL.path,
            ],
            output: { _ in },
            keepAlive: {}
        )
        Issue.record("Expected startup on an occupied port to fail.")
    } catch {}
}

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

private func makeTemporaryDirectory() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private func availableLoopbackPort() throws -> Int {
    let descriptor = socket(AF_INET, SOCK_STREAM, 0)
    guard descriptor >= 0 else {
        throw POSIXError(.EIO)
    }
    defer { close(descriptor) }

    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.stride)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = in_port_t(0).bigEndian
    address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

    let bindResult = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.stride))
        }
    }
    guard bindResult == 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }

    var length = socklen_t(MemoryLayout<sockaddr_in>.stride)
    let nameResult = withUnsafeMutablePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            getsockname(descriptor, $0, &length)
        }
    }
    guard nameResult == 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }

    return Int(UInt16(bigEndian: address.sin_port))
}

private func makeListeningSocket(port: Int) throws -> Int32 {
    let descriptor = socket(AF_INET, SOCK_STREAM, 0)
    guard descriptor >= 0 else {
        throw POSIXError(.EIO)
    }

    var reuseAddress = 1
    setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR, &reuseAddress, socklen_t(MemoryLayout<Int32>.size))

    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.stride)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = in_port_t(UInt16(port).bigEndian)
    address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

    let bindResult = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.stride))
        }
    }
    guard bindResult == 0 else {
        close(descriptor)
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }

    guard listen(descriptor, 1) == 0 else {
        close(descriptor)
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }

    return descriptor
}

private func listeningPort(for descriptor: Int32) throws -> Int {
    var address = sockaddr_in()
    var length = socklen_t(MemoryLayout<sockaddr_in>.stride)
    let result = withUnsafeMutablePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            getsockname(descriptor, $0, &length)
        }
    }
    guard result == 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }

    return Int(UInt16(bigEndian: address.sin_port))
}

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = false

    var value: Bool {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }

    func setTrue() {
        lock.lock()
        storedValue = true
        lock.unlock()
    }
}

private func waitUntil(
    _ description: String,
    timeout: Duration = .seconds(2),
    interval: Duration = .milliseconds(20),
    condition: @escaping @Sendable () async -> Bool
) async throws {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if await condition() {
            return
        }
        try await Task.sleep(for: interval)
    }

    Issue.record("Timed out waiting for \(description).")
    throw POSIXError(.ETIMEDOUT)
}
