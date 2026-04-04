import Foundation
import SymphonyXcodeValidation

// MARK: - Run Identity

/// Opaque identifier for a validation run.
public struct RunID: Codable, Equatable, Hashable, Sendable {
  public let rawValue: String

  public init(_ rawValue: String) {
    self.rawValue = rawValue
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    rawValue = try container.decode(String.self)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

// MARK: - Run Status

/// Lifecycle state of a validation run.
public enum RunStatus: String, Codable, Sendable {
  case idle
  case running
  case completed
  case failed
}

// MARK: - Log Line

/// A single line of output captured from the validation runner.
public struct LogLine: Codable, Equatable, Sendable {
  public let index: Int
  public let text: String

  public init(index: Int, text: String) {
    self.index = index
    self.text = text
  }
}

// MARK: - Request DTOs

/// HTTP request body for starting a new validation run.
public struct StartRunRequest: Codable, Sendable {
  public var configuration: ValidationRunConfiguration
  public var projectRoot: String?

  public init(
    configuration: ValidationRunConfiguration,
    projectRoot: String? = nil
  ) {
    self.configuration = configuration
    self.projectRoot = projectRoot
  }
}

// MARK: - Response DTOs

/// HTTP response for polling run status and recent log output.
public struct RunStatusResponse: Codable, Sendable {
  public let runID: RunID
  public let status: RunStatus
  public let logLines: [LogLine]
  public let currentPhase: RunPhase?
  public let startedAt: Date?
  public let error: String?

  public init(
    runID: RunID,
    status: RunStatus,
    logLines: [LogLine],
    currentPhase: RunPhase? = nil,
    startedAt: Date? = nil,
    error: String? = nil
  ) {
    self.runID = runID
    self.status = status
    self.logLines = logLines
    self.currentPhase = currentPhase
    self.startedAt = startedAt
    self.error = error
  }
}

/// HTTP response wrapping a completed validation summary.
public struct RunSummaryResponse: Codable, Sendable {
  public let runID: RunID
  public let summary: ValidationSummary

  public init(runID: RunID, summary: ValidationSummary) {
    self.runID = runID
    self.summary = summary
  }
}

/// Lightweight response returned when a run is successfully started.
public struct StartRunResponse: Codable, Sendable {
  public let runID: RunID

  public init(runID: RunID) {
    self.runID = runID
  }
}

/// Health check response.
public struct HealthResponse: Codable, Sendable {
  public let status: String

  public init(status: String = "ok") {
    self.status = status
  }
}
