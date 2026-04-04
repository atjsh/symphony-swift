import Foundation
import SymphonyShared

// MARK: - Process Launching Abstraction

public protocol ProcessLaunching: Sendable {
  func launch(
    command: String,
    workspacePath: String,
    environment: [String: String]
  ) throws -> LaunchedProcess
}

// MARK: - Launched Process

public protocol LaunchedProcess: Sendable {
  func onOutput(_ handler: @escaping @Sendable (Data) -> Void)
  func onTermination(_ handler: @escaping @Sendable (Int32) -> Void)
  func sendInput(_ data: Data) throws
  func interrupt()
  func terminate()
}

// MARK: - Default Process Launcher

public final class DefaultProcessLauncher: ProcessLaunching, Sendable {
  public init() {}

  public func launch(
    command: String,
    workspacePath: String,
    environment: [String: String]
  ) throws -> LaunchedProcess {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = ["-lc", command]
    process.currentDirectoryURL = URL(fileURLWithPath: workspacePath)

    var env = ProcessInfo.processInfo.environment
    for (key, value) in environment {
      env[key] = value
    }
    process.environment = env

    let stdout = Pipe()
    let stdin = Pipe()
    process.standardOutput = stdout
    process.standardInput = stdin
    process.standardError = FileHandle.nullDevice

    do {
      try process.run()
    } catch {
      throw ProviderAdapterError.processLaunchFailed(error.localizedDescription)
    }

    return DefaultLaunchedProcess(process: process, stdoutPipe: stdout, stdinPipe: stdin)
  }
}

// MARK: - Default Launched Process

final class DefaultLaunchedProcess: LaunchedProcess, @unchecked Sendable {
  private let process: Process
  private let stdoutPipe: Pipe
  private let stdinPipe: Pipe

  init(process: Process, stdoutPipe: Pipe, stdinPipe: Pipe) {
    self.process = process
    self.stdoutPipe = stdoutPipe
    self.stdinPipe = stdinPipe
  }

  func onOutput(_ handler: @escaping @Sendable (Data) -> Void) {
    stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
      let data = handle.availableData
      if data.isEmpty {
        handle.readabilityHandler = nil
      } else {
        handler(data)
      }
    }
  }

  func onTermination(_ handler: @escaping @Sendable (Int32) -> Void) {
    process.terminationHandler = { proc in
      handler(proc.terminationStatus)
    }
  }

  func sendInput(_ data: Data) throws {
    try stdinPipe.fileHandleForWriting.write(contentsOf: data)
  }

  func interrupt() {
    process.interrupt()
  }

  func terminate() {
    process.terminate()
  }
}

// MARK: - Stub Process Launcher (for testing)

public final class StubProcessLauncher: ProcessLaunching, @unchecked Sendable {
  private let lock = NSLock()
  private var _invocations:
    [(command: String, workspacePath: String, environment: [String: String])] = []
  private var _stubProcesses: [StubLaunchedProcess] = []
  private var _launchError: Error?

  public init() {}

  public var invocations: [(command: String, workspacePath: String, environment: [String: String])]
  {
    lock.lock()
    defer { lock.unlock() }
    return _invocations
  }

  public func setStubProcess(_ process: StubLaunchedProcess) {
    lock.lock()
    _stubProcesses = [process]
    lock.unlock()
  }

  public func setStubProcesses(_ processes: [StubLaunchedProcess]) {
    lock.lock()
    _stubProcesses = processes
    lock.unlock()
  }

  public func setLaunchError(_ error: Error) {
    lock.lock()
    _launchError = error
    lock.unlock()
  }

  public func launch(
    command: String,
    workspacePath: String,
    environment: [String: String]
  ) throws -> LaunchedProcess {
    lock.lock()
    _invocations.append(
      (
        command: command,
        workspacePath: workspacePath,
        environment: environment
      ))
    let error = _launchError
    let process = _stubProcesses.isEmpty ? StubLaunchedProcess() : _stubProcesses.removeFirst()
    lock.unlock()

    if let error { throw error }
    return process
  }
}

public final class StubLaunchedProcess: LaunchedProcess, @unchecked Sendable {
  private let lock = NSLock()
  private var _outputHandler: (@Sendable (Data) -> Void)?
  private var _terminationHandler: (@Sendable (Int32) -> Void)?
  private var _recordedInputs: [Data] = []
  private var _inputError: Error?
  private var _interruptCount = 0
  private var _terminationCount = 0
  private var _terminated = false

  public init() {}

  public var recordedInputStrings: [String] {
    lock.withLock {
      _recordedInputs.compactMap { String(data: $0, encoding: .utf8) }
    }
  }

  public var interruptCount: Int {
    lock.withLock { _interruptCount }
  }

  public var terminationCount: Int {
    lock.withLock { _terminationCount }
  }

  public func onOutput(_ handler: @escaping @Sendable (Data) -> Void) {
    lock.lock()
    _outputHandler = handler
    lock.unlock()
  }

  public func onTermination(_ handler: @escaping @Sendable (Int32) -> Void) {
    lock.lock()
    _terminationHandler = handler
    lock.unlock()
  }

  public func sendInput(_ data: Data) throws {
    lock.lock()
    let inputError = _inputError
    if inputError == nil {
      _recordedInputs.append(data)
      if
        let string = String(data: data, encoding: .utf8)?
          .trimmingCharacters(in: .whitespacesAndNewlines),
        let messageData = string.data(using: .utf8),
        let json = try? JSONDecoder().decode(ProviderJSONMessage.self, from: messageData),
        json.method == "turn/interrupt"
      {
        _interruptCount += 1
      }
    }
    lock.unlock()
    if let inputError {
      throw inputError
    }
  }

  public func setInputError(_ error: Error?) {
    lock.lock()
    _inputError = error
    lock.unlock()
  }

  public func interrupt() {
    lock.lock()
    guard !_terminated else {
      lock.unlock()
      return
    }
    _interruptCount += 1
    lock.unlock()
  }

  public func terminate() {
    lock.lock()
    guard !_terminated else {
      lock.unlock()
      return
    }
    _terminated = true
    _terminationCount += 1
    let handler = _terminationHandler
    lock.unlock()
    handler?(15)
  }

  public func simulateOutput(_ string: String) {
    lock.lock()
    let handler = _outputHandler
    lock.unlock()
    if let data = string.data(using: .utf8) {
      handler?(data)
    }
  }

  public func simulateTermination(exitCode: Int32) {
    lock.lock()
    guard !_terminated else {
      lock.unlock()
      return
    }
    _terminated = true
    _terminationCount += 1
    let handler = _terminationHandler
    lock.unlock()
    handler?(exitCode)
  }
}
