import Foundation
import SymphonyShared
import SymphonyServerCore

// MARK: - Provider Adapter Error

public enum ProviderAdapterError: Error, Equatable, Sendable {
  case processLaunchFailed(String)
  case sessionNotFound(SessionID)
  case processExitedUnexpectedly(exitCode: Int32)
  case terminalOutcome(sessionID: SessionID, outcome: String)
  case readTimeout(sessionID: SessionID, readTimeoutMS: Int)
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
    issue: Issue?,
    workspacePath: String,
    prompt: String,
    environment: [String: String]
  ) async throws -> AsyncThrowingStream<AgentRawEvent, Error>

  func continueSession(
    sessionID: SessionID,
    guidance: String
  ) async throws -> AsyncThrowingStream<AgentRawEvent, Error>

  func interruptSession(sessionID: SessionID) async throws -> Bool
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

public struct ProviderManagedSession: Sendable {
  public let process: LaunchedProcess
  public let workspacePath: String
  public let environment: [String: String]

  public init(
    process: LaunchedProcess,
    workspacePath: String,
    environment: [String: String]
  ) {
    self.process = process
    self.workspacePath = workspacePath
    self.environment = environment
  }
}
