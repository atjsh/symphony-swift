import Foundation
import SymphonyShared

// MARK: - Provider Adapter Error

public enum ProviderAdapterError: Error, Equatable, Sendable {
  case processLaunchFailed(String)
  case sessionNotFound(SessionID)
  case processExitedUnexpectedly(exitCode: Int32)
  case stallDetected(sessionID: SessionID, stallTimeoutMS: Int)
  case turnTimeout(sessionID: SessionID, turnTimeoutMS: Int)
  case unsupportedProvider(ProviderName)
}

// MARK: - Provider Adapter Protocol (Section 10.2)

public protocol ProviderAdapting: Sendable {
  var providerName: ProviderName { get }
  var capabilities: ProviderCapabilities { get }

  func startSession(
    sessionID: SessionID,
    workspacePath: String,
    prompt: String,
    environment: [String: String]
  ) async throws -> AsyncThrowingStream<AgentRawEvent, Error>

  func continueSession(
    sessionID: SessionID,
    guidance: String
  ) async throws -> AsyncThrowingStream<AgentRawEvent, Error>

  func cancelSession(sessionID: SessionID) async throws
}

// MARK: - Session Metadata (Section 10.4)

public struct ProviderSessionMetadata: Equatable, Sendable {
  public let sessionID: SessionID
  public let provider: ProviderName
  public let providerSessionID: String?
  public let providerThreadID: String?
  public let providerTurnID: String?
  public let providerRunID: String?

  public init(
    sessionID: SessionID,
    provider: ProviderName,
    providerSessionID: String? = nil,
    providerThreadID: String? = nil,
    providerTurnID: String? = nil,
    providerRunID: String? = nil
  ) {
    self.sessionID = sessionID
    self.provider = provider
    self.providerSessionID = providerSessionID
    self.providerThreadID = providerThreadID
    self.providerTurnID = providerTurnID
    self.providerRunID = providerRunID
  }
}

// MARK: - Codex Adapter (Section 10.7)

public final class CodexAdapter: ProviderAdapting, @unchecked Sendable {
  public let providerName: ProviderName = .codex
  public let capabilities = ProviderCapabilities(
    supportsResume: false,
    supportsInterrupt: true,
    supportsUsageTotals: true,
    supportsRateLimits: false,
    supportsExplicitApprovals: true,
    supportsStructuredToolEvents: true,
    toolExecutionMode: .mixed
  )

  private let config: CodexProviderConfig
  private let processLauncher: ProcessLaunching

  public init(config: CodexProviderConfig, processLauncher: ProcessLaunching? = nil) {
    self.config = config
    self.processLauncher = processLauncher ?? DefaultProcessLauncher()
  }

  public func startSession(
    sessionID: SessionID,
    workspacePath: String,
    prompt: String,
    environment: [String: String]
  ) async throws -> AsyncThrowingStream<AgentRawEvent, Error> {
    let process = try processLauncher.launch(
      command: config.command,
      workspacePath: workspacePath,
      environment: environment
    )
    return makeEventStream(from: process, sessionID: sessionID)
  }

  public func continueSession(
    sessionID: SessionID,
    guidance: String
  ) async throws -> AsyncThrowingStream<AgentRawEvent, Error> {
    throw ProviderAdapterError.unsupportedProvider(.codex)
  }

  public func cancelSession(sessionID: SessionID) async throws {
    // Cancel handled by process termination
  }

  func makeEventStream(
    from process: LaunchedProcess,
    sessionID: SessionID
  ) -> AsyncThrowingStream<AgentRawEvent, Error> {
    AsyncThrowingStream { continuation in
      process.onOutput { data in
        guard
          let line = String(data: data, encoding: .utf8)?.trimmingCharacters(
            in: .whitespacesAndNewlines),
          !line.isEmpty
        else { return }

        let event = AgentRawEvent(
          sessionID: sessionID,
          provider: "codex",
          sequence: EventSequence(0),
          timestamp: ISO8601DateFormatter().string(from: Date()),
          rawJSON: line,
          providerEventType: "codex_event",
          normalizedEventKind: NormalizedEventKind.message.rawValue
        )
        continuation.yield(event)
      }
      process.onTermination { exitCode in
        if exitCode == 0 {
          continuation.finish()
        } else {
          continuation.finish(
            throwing: ProviderAdapterError.processExitedUnexpectedly(exitCode: exitCode))
        }
      }
    }
  }
}

// MARK: - Claude Code CLI Adapter (Section 10.8)

public final class ClaudeCodeAdapter: ProviderAdapting, @unchecked Sendable {
  public let providerName: ProviderName = .claudeCode
  public let capabilities = ProviderCapabilities(
    supportsResume: true,
    supportsInterrupt: false,
    supportsUsageTotals: true,
    supportsRateLimits: false,
    supportsExplicitApprovals: false,
    supportsStructuredToolEvents: true,
    toolExecutionMode: .providerManaged
  )

  private let config: ClaudeCodeProviderConfig
  private let processLauncher: ProcessLaunching

  public init(config: ClaudeCodeProviderConfig, processLauncher: ProcessLaunching? = nil) {
    self.config = config
    self.processLauncher = processLauncher ?? DefaultProcessLauncher()
  }

  public func startSession(
    sessionID: SessionID,
    workspacePath: String,
    prompt: String,
    environment: [String: String]
  ) async throws -> AsyncThrowingStream<AgentRawEvent, Error> {
    var args = config.command
    args += " -p --output-format stream-json"
    if let permissionMode = config.permissionMode {
      args += " --permission-mode \(permissionMode)"
    }

    let process = try processLauncher.launch(
      command: args,
      workspacePath: workspacePath,
      environment: environment
    )
    return makeEventStream(from: process, sessionID: sessionID)
  }

  public func continueSession(
    sessionID: SessionID,
    guidance: String
  ) async throws -> AsyncThrowingStream<AgentRawEvent, Error> {
    // Claude Code supports --continue for session continuation
    throw ProviderAdapterError.unsupportedProvider(.claudeCode)
  }

  public func cancelSession(sessionID: SessionID) async throws {
    // Cancel handled by process termination
  }

  func makeEventStream(
    from process: LaunchedProcess,
    sessionID: SessionID
  ) -> AsyncThrowingStream<AgentRawEvent, Error> {
    AsyncThrowingStream { continuation in
      process.onOutput { data in
        guard
          let line = String(data: data, encoding: .utf8)?.trimmingCharacters(
            in: .whitespacesAndNewlines),
          !line.isEmpty
        else { return }

        let event = AgentRawEvent(
          sessionID: sessionID,
          provider: "claude_code",
          sequence: EventSequence(0),
          timestamp: ISO8601DateFormatter().string(from: Date()),
          rawJSON: line,
          providerEventType: "stream_json",
          normalizedEventKind: NormalizedEventKind.message.rawValue
        )
        continuation.yield(event)
      }
      process.onTermination { exitCode in
        if exitCode == 0 {
          continuation.finish()
        } else {
          continuation.finish(
            throwing: ProviderAdapterError.processExitedUnexpectedly(exitCode: exitCode))
        }
      }
    }
  }
}

// MARK: - Copilot CLI Adapter (Section 10.9)

public final class CopilotCLIAdapter: ProviderAdapting, @unchecked Sendable {
  public let providerName: ProviderName = .copilotCLI
  public let capabilities = ProviderCapabilities(
    supportsResume: false,
    supportsInterrupt: false,
    supportsUsageTotals: false,
    supportsRateLimits: false,
    supportsExplicitApprovals: false,
    supportsStructuredToolEvents: false,
    toolExecutionMode: .providerManaged
  )

  private let config: CopilotCLIProviderConfig
  private let processLauncher: ProcessLaunching

  public init(config: CopilotCLIProviderConfig, processLauncher: ProcessLaunching? = nil) {
    self.config = config
    self.processLauncher = processLauncher ?? DefaultProcessLauncher()
  }

  public func startSession(
    sessionID: SessionID,
    workspacePath: String,
    prompt: String,
    environment: [String: String]
  ) async throws -> AsyncThrowingStream<AgentRawEvent, Error> {
    let process = try processLauncher.launch(
      command: config.command,
      workspacePath: workspacePath,
      environment: environment
    )
    return makeEventStream(from: process, sessionID: sessionID)
  }

  public func continueSession(
    sessionID: SessionID,
    guidance: String
  ) async throws -> AsyncThrowingStream<AgentRawEvent, Error> {
    throw ProviderAdapterError.unsupportedProvider(.copilotCLI)
  }

  public func cancelSession(sessionID: SessionID) async throws {
    // Cancel handled by process termination
  }

  func makeEventStream(
    from process: LaunchedProcess,
    sessionID: SessionID
  ) -> AsyncThrowingStream<AgentRawEvent, Error> {
    AsyncThrowingStream { continuation in
      process.onOutput { data in
        guard
          let line = String(data: data, encoding: .utf8)?.trimmingCharacters(
            in: .whitespacesAndNewlines),
          !line.isEmpty
        else { return }

        let event = AgentRawEvent(
          sessionID: sessionID,
          provider: "copilot_cli",
          sequence: EventSequence(0),
          timestamp: ISO8601DateFormatter().string(from: Date()),
          rawJSON: line,
          providerEventType: "acp_event",
          normalizedEventKind: NormalizedEventKind.message.rawValue
        )
        continuation.yield(event)
      }
      process.onTermination { exitCode in
        if exitCode == 0 {
          continuation.finish()
        } else {
          continuation.finish(
            throwing: ProviderAdapterError.processExitedUnexpectedly(exitCode: exitCode))
        }
      }
    }
  }
}

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
    process.standardOutput = stdout
    process.standardError = FileHandle.nullDevice

    do {
      try process.run()
    } catch {
      throw ProviderAdapterError.processLaunchFailed(error.localizedDescription)
    }

    return DefaultLaunchedProcess(process: process, stdoutPipe: stdout)
  }
}

// MARK: - Default Launched Process

final class DefaultLaunchedProcess: LaunchedProcess, @unchecked Sendable {
  private let process: Process
  private let stdoutPipe: Pipe

  init(process: Process, stdoutPipe: Pipe) {
    self.process = process
    self.stdoutPipe = stdoutPipe
  }

  func onOutput(_ handler: @escaping @Sendable (Data) -> Void) {
    stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
      let data = handle.availableData
      if !data.isEmpty {
        handler(data)
      }
    }
  }

  func onTermination(_ handler: @escaping @Sendable (Int32) -> Void) {
    process.terminationHandler = { proc in
      handler(proc.terminationStatus)
    }
  }

  func terminate() {
    process.terminate()
  }
}

// MARK: - Stub Process Launcher (for testing)

public final class StubProcessLauncher: ProcessLaunching, @unchecked Sendable {
  private let lock = NSLock()
  private var _invocations: [(command: String, workspacePath: String)] = []
  private var _stubProcess: StubLaunchedProcess?
  private var _launchError: Error?

  public init() {}

  public var invocations: [(command: String, workspacePath: String)] {
    lock.lock()
    defer { lock.unlock() }
    return _invocations
  }

  public func setStubProcess(_ process: StubLaunchedProcess) {
    lock.lock()
    _stubProcess = process
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
    _invocations.append((command: command, workspacePath: workspacePath))
    let error = _launchError
    let process = _stubProcess ?? StubLaunchedProcess()
    lock.unlock()

    if let error { throw error }
    return process
  }
}

public final class StubLaunchedProcess: LaunchedProcess, @unchecked Sendable {
  private let lock = NSLock()
  private var _outputHandler: (@Sendable (Data) -> Void)?
  private var _terminationHandler: (@Sendable (Int32) -> Void)?

  public init() {}

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

  public func terminate() {}

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
    let handler = _terminationHandler
    lock.unlock()
    handler?(exitCode)
  }
}

// MARK: - Provider Adapter Factory

public enum ProviderAdapterFactory {
  public static func makeAdapter(
    for provider: ProviderName,
    config: ProvidersConfig,
    processLauncher: ProcessLaunching? = nil
  ) -> any ProviderAdapting {
    switch provider {
    case .codex:
      return CodexAdapter(config: config.codex, processLauncher: processLauncher)
    case .claudeCode:
      return ClaudeCodeAdapter(config: config.claudeCode, processLauncher: processLauncher)
    case .copilotCLI:
      return CopilotCLIAdapter(config: config.copilotCLI, processLauncher: processLauncher)
    }
  }
}
