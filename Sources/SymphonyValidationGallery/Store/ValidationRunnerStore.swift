import Foundation
import Observation
import SymphonyXcodeValidation
import SymphonyXcodeValidationServerCore

/// Manages the lifecycle of a remote validation run, including
/// configuration, polling, and result retrieval.
@MainActor @Observable
public final class ValidationRunnerStore {
  // MARK: - Published State

  public var serverURL: URL?
  public var isConnected: Bool = false
  public var configuration: ValidationRunConfiguration = .init()
  public var runStatus: RunStatus = .idle
  public var logLines: [LogLine] = []
  public var currentPhase: RunPhase?
  public var startedAt: Date?
  public var errorMessage: String?
  public var completedSummary: ValidationSummary?

  // MARK: - Server Lifecycle State

  public var serverLaunchState: ValidationServerLaunchState = .idle
  public var serverTranscript: [String] = []
  public var serverHostname: String = "127.0.0.1"
  public var serverPort: String = "8090"
  public var serverFailureDescription: String?
  public private(set) var serverManager: (any ValidationServerLifecycleManaging)?

  public var hasServerSupport: Bool {
    serverManager != nil
  }

  public var isServerRunning: Bool {
    serverLaunchState == .running
  }

  // MARK: - Internal

  private(set) var activeRunID: RunID?
  private var pollingTask: Task<Void, Never>?
  private let _startRun: @Sendable (StartRunRequest) async throws -> RunID
  private let _pollStatus: @Sendable (RunID, Int?) async throws -> RunStatusResponse
  private let _fetchSummary: @Sendable (RunID) async throws -> RunSummaryResponse
  private let _cancelRun: @Sendable (RunID) async throws -> Void
  private let _healthCheck: @Sendable () async throws -> Bool
  private let pollingInterval: Duration

  // MARK: - Init

  public init<Client: ValidationServerConnecting>(
    client: Client,
    pollingInterval: Duration = .seconds(2),
    serverManager: (any ValidationServerLifecycleManaging)? = nil
  ) {
    self._startRun = { try await client.startRun($0) }
    self._pollStatus = { try await client.pollStatus($0, afterLine: $1) }
    self._fetchSummary = { try await client.fetchSummary($0) }
    self._cancelRun = { try await client.cancelRun($0) }
    self._healthCheck = { try await client.healthCheck() }
    self.pollingInterval = pollingInterval
    self.serverManager = serverManager
    configureServerManagerCallback()
  }

  public convenience init(
    serverURL: URL,
    pollingInterval: Duration = .seconds(2),
    serverManager: (any ValidationServerLifecycleManaging)? = nil
  ) {
    let client = URLSessionValidationServerClient(baseURL: serverURL)
    self.init(client: client, pollingInterval: pollingInterval, serverManager: serverManager)
    self.serverURL = serverURL
  }

  // MARK: - Actions

  public func checkConnection() async {
    do {
      isConnected = try await _healthCheck()
    } catch {
      isConnected = false
    }
  }

  public func startRun(projectRoot: String? = nil) async {
    guard runStatus == .idle else { return }
    resetRunState()

    let request = StartRunRequest(
      configuration: configuration,
      projectRoot: projectRoot
    )

    do {
      let runID = try await _startRun(request)
      activeRunID = runID
      runStatus = .running
      startPolling(for: runID)
    } catch {
      runStatus = .failed
      errorMessage = String(describing: error)
    }
  }

  public func cancelRun() async {
    guard let runID = activeRunID, runStatus == .running else { return }
    pollingTask?.cancel()
    pollingTask = nil
    do {
      try await _cancelRun(runID)
    } catch {
      // Best effort — run may have already ended.
    }
    runStatus = .failed
    errorMessage = "Cancelled by user."
  }

  public func fetchSummary() async {
    guard let runID = activeRunID else { return }
    do {
      let response = try await _fetchSummary(runID)
      completedSummary = response.summary
    } catch {
      errorMessage = "Failed to fetch summary: \(error)"
    }
  }

  public func reset() {
    pollingTask?.cancel()
    pollingTask = nil
    resetRunState()
  }

  // MARK: - Private

  private func resetRunState() {
    runStatus = .idle
    logLines = []
    currentPhase = nil
    startedAt = nil
    errorMessage = nil
    completedSummary = nil
    activeRunID = nil
  }

  private func startPolling(for runID: RunID) {
    pollingTask = Task { [weak self] in
      guard let self else { return }
      var lastLineIndex: Int?

      while !Task.isCancelled {
        do {
          try await Task.sleep(for: self.pollingInterval)
          let status = try await self._pollStatus(runID, lastLineIndex)

          await MainActor.run {
            self.logLines.append(contentsOf: status.logLines)
            if let last = status.logLines.last {
              lastLineIndex = last.index
            }
            self.currentPhase = status.currentPhase ?? self.currentPhase
            self.startedAt = status.startedAt ?? self.startedAt
            self.errorMessage = status.error

            switch status.status {
            case .completed:
              self.runStatus = .completed
            case .failed:
              self.runStatus = .failed
            case .idle, .running:
              break
            }
          }

          if status.status == .completed || status.status == .failed {
            break
          }
        } catch {
          if Task.isCancelled { break }
        }
      }
    }
  }

  // MARK: - Server Lifecycle

  public func startServer() async {
    guard let serverManager else { return }
    guard let projectRoot = resolvedProjectRoot() else { return }
    let hostname = serverHostname.isEmpty ? "127.0.0.1" : serverHostname
    let port = Int(serverPort) ?? 8090
    serverURL = URL(string: "http://\(hostname):\(port)")
    await serverManager.start(hostname: hostname, port: port, projectRoot: projectRoot)
    await checkConnection()
  }

  public func stopServer() async {
    guard let serverManager else { return }
    await serverManager.stop()
    isConnected = false
  }

  private func configureServerManagerCallback() {
    serverManager?.onStatusChange = { [weak self] snapshot in
      self?.applyServerStatus(snapshot)
    }
  }

  private func applyServerStatus(_ snapshot: ValidationServerStatusSnapshot) {
    serverLaunchState = snapshot.state
    serverTranscript = snapshot.transcript
    serverFailureDescription = snapshot.failureDescription
  }

  private func resolvedProjectRoot() -> URL? {
    #if os(macOS)
      let process = Process()
      let pipe = Pipe()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
      process.arguments = ["rev-parse", "--show-toplevel"]
      process.standardOutput = pipe
      process.standardError = FileHandle.nullDevice
      do {
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if !path.isEmpty {
          return URL(fileURLWithPath: path)
        }
      } catch {
        // Fall through to fallback.
      }
    #endif
    return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
  }
}
