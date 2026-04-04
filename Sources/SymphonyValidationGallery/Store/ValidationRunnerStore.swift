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

  // MARK: - Internal

  private(set) var activeRunID: RunID?
  private var pollingTask: Task<Void, Never>?
  private let client: any ValidationServerConnecting
  private let pollingInterval: Duration

  // MARK: - Init

  public init(
    client: any ValidationServerConnecting,
    pollingInterval: Duration = .seconds(2)
  ) {
    self.client = client
    self.pollingInterval = pollingInterval
  }

  public convenience init(
    serverURL: URL,
    pollingInterval: Duration = .seconds(2)
  ) {
    let client = URLSessionValidationServerClient(baseURL: serverURL)
    self.init(client: client, pollingInterval: pollingInterval)
    self.serverURL = serverURL
  }

  // MARK: - Actions

  public func checkConnection() async {
    do {
      isConnected = try await client.healthCheck()
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
      let runID = try await client.startRun(request)
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
      try await client.cancelRun(runID)
    } catch {
      // Best effort — run may have already ended.
    }
    runStatus = .failed
    errorMessage = "Cancelled by user."
  }

  public func fetchSummary() async {
    guard let runID = activeRunID else { return }
    do {
      let response = try await client.fetchSummary(runID)
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
          let status = try await self.client.pollStatus(runID, afterLine: lastLineIndex)

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
}
