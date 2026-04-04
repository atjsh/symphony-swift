#if os(macOS)

import Foundation
import SymphonyXcodeValidation
import SymphonyXcodeValidationServerCore

/// Manages the lifecycle of validation runs.
///
/// Enforces single-run-at-a-time. Maps cross-platform ``ValidationRunConfiguration``
/// to macOS-only ``ValidationRequest``, captures log output, and tracks run state.
public actor RunManager {
  // MARK: - State

  private enum State {
    case idle
    case running(ActiveRun)
    case completed(RunID, ValidationSummary)
    case failed(RunID, String)
  }

  private struct ActiveRun {
    let id: RunID
    let task: Task<Void, Never>
    let startedAt: Date
    var logLines: [LogLine] = []
    var currentPhase: RunPhase?
  }

  private var state: State = .idle
  private let processExecutor: ValidationProcessExecuting
  private let defaultProjectRoot: URL
  private let now: @Sendable () -> Date

  // MARK: - Init

  public init(
    defaultProjectRoot: URL,
    processExecutor: ValidationProcessExecuting = SystemValidationProcessExecutor(),
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    self.defaultProjectRoot = defaultProjectRoot
    self.processExecutor = processExecutor
    self.now = now
  }

  // MARK: - Run Lifecycle

  /// Starts a new validation run. Throws if a run is already active.
  public func start(_ request: StartRunRequest) throws -> RunID {
    guard case .idle = state else {
      throw RunManagerError.runAlreadyActive
    }

    let runID = RunID(UUID().uuidString)
    let validationRequest = makeValidationRequest(from: request)

    let manager = self
    let task = Task {
      await manager.executeRun(id: runID, request: validationRequest)
    }

    state = .running(ActiveRun(
      id: runID,
      task: task,
      startedAt: now()
    ))

    return runID
  }

  /// Returns the current status and log lines after the given cursor.
  public func status(for runID: RunID, afterLine: Int?) -> RunStatusResponse {
    switch state {
    case .idle:
      return RunStatusResponse(runID: runID, status: .idle, logLines: [])

    case .running(let run) where run.id == runID:
      let startIndex = afterLine.map { $0 + 1 } ?? 0
      let lines = startIndex < run.logLines.count
        ? Array(run.logLines[startIndex...])
        : []
      return RunStatusResponse(
        runID: runID,
        status: .running,
        logLines: lines,
        currentPhase: run.currentPhase,
        startedAt: run.startedAt
      )

    case .completed(let id, _) where id == runID:
      return RunStatusResponse(runID: runID, status: .completed, logLines: [])

    case .failed(let id, let error) where id == runID:
      return RunStatusResponse(runID: runID, status: .failed, logLines: [], error: error)

    default:
      return RunStatusResponse(runID: runID, status: .idle, logLines: [])
    }
  }

  /// Returns the final summary for a completed run.
  public func summary(for runID: RunID) -> ValidationSummary? {
    if case .completed(let id, let summary) = state, id == runID {
      return summary
    }
    return nil
  }

  /// Cancels the active run.
  public func cancel(_ runID: RunID) -> Bool {
    guard case .running(let run) = state, run.id == runID else {
      return false
    }
    run.task.cancel()
    state = .failed(runID, "Cancelled by user.")
    return true
  }

  /// Resets state to idle. Call after inspecting a completed/failed run.
  public func reset() {
    switch state {
    case .completed, .failed:
      state = .idle
    case .idle, .running:
      break
    }
  }

  // MARK: - Internal

  func appendLog(_ text: String) {
    guard case .running(var run) = state else { return }
    let line = LogLine(index: run.logLines.count, text: text)
    run.logLines.append(line)
    state = .running(run)
  }

  func updatePhase(_ phase: RunPhase) {
    guard case .running(var run) = state else { return }
    run.currentPhase = phase
    state = .running(run)
  }

  // MARK: - Private

  private func executeRun(id: RunID, request: ValidationRequest) async {
    let manager = self

    let runner = XcodeValidationRunner(
      processExecutor: processExecutor,
      logSink: { text in
        Task { await manager.appendLog(text) }
      }
    )

    do {
      let summary = try await Task.detached(priority: .userInitiated) {
        try runner.run(request)
      }.value
      await manager.completeRun(id: id, summary: summary)
    } catch {
      if Task.isCancelled {
        await manager.failRun(id: id, error: "Cancelled by user.")
      } else {
        await manager.failRun(id: id, error: String(describing: error))
      }
    }
  }

  private func completeRun(id: RunID, summary: ValidationSummary) {
    guard case .running(let run) = state, run.id == id else { return }
    state = .completed(id, summary)
  }

  private func failRun(id: RunID, error: String) {
    guard case .running(let run) = state, run.id == id else { return }
    state = .failed(id, error)
  }

  private func makeValidationRequest(from request: StartRunRequest) -> ValidationRequest {
    let config = request.configuration
    let projectRoot: URL
    if let override = request.projectRoot {
      projectRoot = URL(fileURLWithPath: override)
    } else {
      projectRoot = defaultProjectRoot
    }

    return ValidationRequest(
      projectRoot: projectRoot,
      subject: config.subject,
      outputRoot: config.outputRoot.map { URL(fileURLWithPath: $0) },
      artifactRetention: config.artifactRetention,
      buildProfile: config.buildProfile,
      executionProfile: config.executionProfile,
      concurrency: config.concurrency,
      logLevel: config.logLevel,
      skipRichCapture: config.skipRichCapture,
      skipFullMatrix: config.skipFullMatrix
    )
  }
}

/// Errors specific to ``RunManager``.
public enum RunManagerError: Error, Sendable {
  case runAlreadyActive
}

#endif
