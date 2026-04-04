import Foundation

public enum ProcessStream: String, Sendable {
  case stdout
  case stderr
}

public struct CommandResult: Sendable {
  public let exitStatus: Int32
  public let stdout: String
  public let stderr: String
  public let timedOut: Bool

  public init(exitStatus: Int32, stdout: String, stderr: String, timedOut: Bool = false) {
    self.exitStatus = exitStatus
    self.stdout = stdout
    self.stderr = stderr
    self.timedOut = timedOut
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
  public let maxStaleInterval: TimeInterval?
  public let onStaleSignal: (@Sendable (String) -> Void)?
  public let onLine: (@Sendable (ProcessStream, String) -> Void)?

  public init(
    label: String,
    staleInterval: TimeInterval = 15,
    maxStaleInterval: TimeInterval? = nil,
    onStaleSignal: (@Sendable (String) -> Void)? = nil,
    onLine: (@Sendable (ProcessStream, String) -> Void)? = nil
  ) {
    self.label = label
    self.staleInterval = staleInterval
    self.maxStaleInterval = maxStaleInterval
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
    observation: ProcessObservation?,
    timeout: TimeInterval?
  ) throws -> CommandResult

  func startDetached(
    executablePath: String,
    arguments: [String],
    environment: [String: String],
    currentDirectory: URL?,
    output: URL
  ) throws -> Int32
}

extension ProcessRunning {
  public func run(
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
      observation: nil,
      timeout: nil
    )
  }

  public func run(
    command: String,
    arguments: [String],
    environment: [String: String],
    currentDirectory: URL?,
    observation: ProcessObservation?
  ) throws -> CommandResult {
    try run(
      command: command,
      arguments: arguments,
      environment: environment,
      currentDirectory: currentDirectory,
      observation: observation,
      timeout: nil
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
    observation: ProcessObservation? = nil,
    timeout: TimeInterval? = nil
  ) throws -> CommandResult {
    let process = Process()
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.executableURL = executableURL(for: command)
    process.arguments = executableArguments(for: command, arguments: arguments)
    process.currentDirectoryURL = currentDirectory
    if !environment.isEmpty {
      var mergedEnvironment = ProcessInfo.processInfo.environment
      for (key, value) in environment {
        mergedEnvironment[key] = value
      }
      process.environment = mergedEnvironment
    }
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe
    let stdoutCollector = DataCollector()
    let stderrCollector = DataCollector()
    let staleController = observation.map {
      StaleSignalController(observation: $0, collector: stderrCollector, process: process)
    }
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

    var didTimeout = false
    var timeoutTimer: DispatchSourceTimer?
    if let timeout {
      let timer = DispatchSource.makeTimerSource(
        queue: DispatchQueue(label: "com.symphony.process-timeout"))
      timer.schedule(deadline: .now() + timeout)
      timer.setEventHandler {
        didTimeout = true
        process.terminate()
        DispatchQueue(label: "com.symphony.process-kill").asyncAfter(deadline: .now() + 5) {
          if process.isRunning {
            process.interrupt()
          }
        }
      }
      timeoutTimer = timer
      timer.resume()
    }

    try process.run()
    process.waitUntilExit()
    timeoutTimer?.cancel()
    stdoutLineEmitter.finish()
    stderrLineEmitter.finish()
    staleController?.stop()
    _ = completionGroup.wait(timeout: .now() + 5)

    let stdout = String(decoding: stdoutCollector.data, as: UTF8.self)
    let stderr = String(decoding: stderrCollector.data, as: UTF8.self)
    return CommandResult(
      exitStatus: process.terminationStatus, stdout: stdout, stderr: stderr, timedOut: didTimeout)
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
    try fileManager.createDirectory(
      at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
    let outputHandle = try FileHandle(forWritingTo: ensureFileExists(at: output))
    try outputHandle.truncate(atOffset: 0)
    process.executableURL = executableURL(for: executablePath)
    process.arguments = executableArguments(for: executablePath, arguments: arguments)
    process.currentDirectoryURL = currentDirectory
    if !environment.isEmpty {
      var mergedEnvironment = ProcessInfo.processInfo.environment
      for (key, value) in environment {
        mergedEnvironment[key] = value
      }
      process.environment = mergedEnvironment
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

// SAFETY: @unchecked Sendable — `storage` is exclusively accessed through `lock`.
final class DataCollector: @unchecked Sendable {
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

// SAFETY: @unchecked Sendable — `buffer` is exclusively accessed through `lock`.
// Immutable fields (`stream`, `observation`) are assigned once at init.
final class LineEmitter: @unchecked Sendable {
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

// SAFETY: @unchecked Sendable — mutable state (`lastOutputAt`, `emittedCount`, `timer`,
// `didEscalate`) is exclusively accessed through `lock` or the serial `queue`.
final class StaleSignalController: @unchecked Sendable {
  private let observation: ProcessObservation
  private let collector: DataCollector
  private let process: Process
  private let lock = NSLock()
  private var lastOutputAt = Date()
  private var emittedCount = 0
  private var timer: DispatchSourceTimer?
  private var didEscalate = false

  init(observation: ProcessObservation, collector: DataCollector, process: Process) {
    self.observation = observation
    self.collector = collector
    self.process = process
  }

  private let queue = DispatchQueue(label: "com.symphony.stale-signal")

  func start() {
    let timer = DispatchSource.makeTimerSource(queue: queue)
    timer.schedule(
      deadline: .now() + observation.staleInterval, repeating: observation.staleInterval)
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

  func signalIfNeeded() {
    let message: String?
    var shouldKill = false

    lock.lock()
    let elapsed = Date().timeIntervalSince(lastOutputAt)
    let thresholdCount = Int(elapsed / observation.staleInterval)
    if thresholdCount > emittedCount {
      emittedCount = thresholdCount
      message =
        "[harness] \(observation.label) still running with no new output for \(Int(elapsed))s"
    } else {
      message = nil
    }
    if let maxStale = observation.maxStaleInterval, elapsed >= maxStale, !didEscalate {
      didEscalate = true
      shouldKill = true
    }
    lock.unlock()

    if shouldKill {
      let killMessage =
        "[harness] \(observation.label) exceeded max stale interval (\(Int(observation.maxStaleInterval!))s) — terminating process"
      collector.append(Data((killMessage + "\n").utf8))
      if let onStaleSignal = observation.onStaleSignal {
        onStaleSignal(killMessage)
      } else if let data = (killMessage + "\n").data(using: .utf8) {
        FileHandle.standardError.write(data)
      }
      process.terminate()
      DispatchQueue(label: "com.symphony.stale-kill").asyncAfter(deadline: .now() + 5) { [weak self] in
        guard let self, self.process.isRunning else { return }
        self.process.interrupt()
      }
      return
    }

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
