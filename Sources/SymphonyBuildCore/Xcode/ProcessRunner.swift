import Foundation

public enum ProcessStream: String, Sendable {
    case stdout
    case stderr
}

public struct CommandResult: Sendable {
    public let exitStatus: Int32
    public let stdout: String
    public let stderr: String

    public init(exitStatus: Int32, stdout: String, stderr: String) {
        self.exitStatus = exitStatus
        self.stdout = stdout
        self.stderr = stderr
    }

    public var combinedOutput: String {
        [stdout, stderr]
            .filter { !$0.isEmpty }
            .joined(separator: stdout.isEmpty || stderr.isEmpty ? "" : "\n")
    }
}

public struct ProcessObservation: Sendable {
    public let label: String
    public let staleInterval: TimeInterval
    public let onStaleSignal: (@Sendable (String) -> Void)?
    public let onLine: (@Sendable (ProcessStream, String) -> Void)?

    public init(
        label: String,
        staleInterval: TimeInterval = 15,
        onStaleSignal: (@Sendable (String) -> Void)? = nil,
        onLine: (@Sendable (ProcessStream, String) -> Void)? = nil
    ) {
        self.label = label
        self.staleInterval = staleInterval
        self.onStaleSignal = onStaleSignal
        self.onLine = onLine
    }
}

public protocol ProcessRunning: Sendable {
    func run(
        command: String,
        arguments: [String],
        environment: [String: String],
        currentDirectory: URL?,
        observation: ProcessObservation?
    ) throws -> CommandResult

    func startDetached(
        executablePath: String,
        arguments: [String],
        environment: [String: String],
        currentDirectory: URL?,
        output: URL
    ) throws -> Int32
}

public extension ProcessRunning {
    func run(
        command: String,
        arguments: [String],
        environment: [String: String],
        currentDirectory: URL?
    ) throws -> CommandResult {
        try run(
            command: command,
            arguments: arguments,
            environment: environment,
            currentDirectory: currentDirectory,
            observation: nil
        )
    }
}

public struct SystemProcessRunner: ProcessRunning {
    public init() {}

    public func run(
        command: String,
        arguments: [String],
        environment: [String: String] = [:],
        currentDirectory: URL? = nil,
        observation: ProcessObservation? = nil
    ) throws -> CommandResult {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.executableURL = executableURL(for: command)
        process.arguments = executableArguments(for: command, arguments: arguments)
        process.currentDirectoryURL = currentDirectory
        if !environment.isEmpty {
            process.environment = ProcessInfo.processInfo.environment.merging(environment, uniquingKeysWith: { _, rhs in rhs })
        }
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        let stdoutCollector = DataCollector()
        let stderrCollector = DataCollector()
        let staleController = observation.map { StaleSignalController(observation: $0, collector: stderrCollector) }
        let stdoutLineEmitter = LineEmitter(stream: .stdout, observation: observation)
        let stderrLineEmitter = LineEmitter(stream: .stderr, observation: observation)
        let completionGroup = DispatchGroup()
        completionGroup.enter()
        completionGroup.enter()
        staleController?.start()
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                completionGroup.leave()
                return
            }
            stdoutCollector.append(data)
            staleController?.recordOutput()
            stdoutLineEmitter.append(data)
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                completionGroup.leave()
                return
            }
            stderrCollector.append(data)
            staleController?.recordOutput()
            stderrLineEmitter.append(data)
        }
        try process.run()
        process.waitUntilExit()
        stdoutLineEmitter.finish()
        stderrLineEmitter.finish()
        staleController?.stop()
        completionGroup.wait()

        let stdout = String(decoding: stdoutCollector.data, as: UTF8.self)
        let stderr = String(decoding: stderrCollector.data, as: UTF8.self)
        return CommandResult(exitStatus: process.terminationStatus, stdout: stdout, stderr: stderr)
    }

    public func startDetached(
        executablePath: String,
        arguments: [String],
        environment: [String: String] = [:],
        currentDirectory: URL? = nil,
        output: URL
    ) throws -> Int32 {
        let process = Process()
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        let outputHandle = try FileHandle(forWritingTo: ensureFileExists(at: output))
        try outputHandle.truncate(atOffset: 0)
        process.executableURL = executableURL(for: executablePath)
        process.arguments = executableArguments(for: executablePath, arguments: arguments)
        process.currentDirectoryURL = currentDirectory
        if !environment.isEmpty {
            process.environment = ProcessInfo.processInfo.environment.merging(environment, uniquingKeysWith: { _, rhs in rhs })
        }
        process.standardOutput = outputHandle
        process.standardError = outputHandle
        try process.run()
        return process.processIdentifier
    }

    private func executableURL(for command: String) -> URL {
        if command.hasPrefix("/") {
            return URL(fileURLWithPath: command)
        }
        return URL(fileURLWithPath: "/usr/bin/env")
    }

    private func executableArguments(for command: String, arguments: [String]) -> [String] {
        if command.hasPrefix("/") {
            return arguments
        }
        return [command] + arguments
    }

    private func ensureFileExists(at url: URL) throws -> URL {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: url.path) {
            fileManager.createFile(atPath: url.path, contents: Data())
        }
        return url
    }
}

private final class DataCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    func append(_ data: Data) {
        lock.lock()
        storage.append(data)
        lock.unlock()
    }

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

private final class LineEmitter: @unchecked Sendable {
    private let stream: ProcessStream
    private let observation: ProcessObservation?
    private let lock = NSLock()
    private var buffer = Data()

    init(stream: ProcessStream, observation: ProcessObservation?) {
        self.stream = stream
        self.observation = observation
    }

    func append(_ data: Data) {
        guard !data.isEmpty else {
            return
        }

        lock.lock()
        buffer.append(data)
        let lines = consumeCompleteLines()
        lock.unlock()

        guard let onLine = observation?.onLine else {
            return
        }

        for line in lines {
            onLine(stream, line)
        }
    }

    func finish() {
        lock.lock()
        let remainder = buffer
        buffer.removeAll(keepingCapacity: false)
        lock.unlock()

        guard let onLine = observation?.onLine, !remainder.isEmpty else {
            return
        }

        let line = String(decoding: remainder, as: UTF8.self)
        if !line.isEmpty {
            onLine(stream, line)
        }
    }

    private func consumeCompleteLines() -> [String] {
        var lines = [String]()
        while let newline = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer.prefix(upTo: newline)
            buffer.removeSubrange(...newline)
            let line = String(decoding: lineData, as: UTF8.self)
            lines.append(line)
        }
        return lines
    }
}

private final class StaleSignalController: @unchecked Sendable {
    private let observation: ProcessObservation
    private let collector: DataCollector
    private let lock = NSLock()
    private var lastOutputAt = Date()
    private var emittedCount = 0
    private var timer: DispatchSourceTimer?

    init(observation: ProcessObservation, collector: DataCollector) {
        self.observation = observation
        self.collector = collector
    }

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + observation.staleInterval, repeating: observation.staleInterval)
        timer.setEventHandler { [weak self] in
            self?.signalIfNeeded()
        }
        self.timer = timer
        timer.resume()
    }

    func stop() {
        lock.lock()
        let timer = self.timer
        self.timer = nil
        lock.unlock()
        timer?.cancel()
    }

    func recordOutput() {
        lock.lock()
        lastOutputAt = Date()
        emittedCount = 0
        lock.unlock()
    }

    private func signalIfNeeded() {
        let message: String?

        lock.lock()
        let elapsed = Date().timeIntervalSince(lastOutputAt)
        let thresholdCount = Int(elapsed / observation.staleInterval)
        if thresholdCount > emittedCount {
            emittedCount = thresholdCount
            message = "[symphony-build] \(observation.label) still running with no new output for \(Int(elapsed))s"
        } else {
            message = nil
        }
        lock.unlock()

        guard let message else {
            return
        }

        collector.append(Data((message + "\n").utf8))
        if let onStaleSignal = observation.onStaleSignal {
            onStaleSignal(message)
        } else if let data = (message + "\n").data(using: .utf8) {
            FileHandle.standardError.write(data)
        }
    }
}
