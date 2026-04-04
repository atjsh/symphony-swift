import Foundation
import SymphonyServerCore
import SymphonyShared

// MARK: - Agent Runner Error

public enum AgentRunnerError: Error, Equatable, Sendable {
  case workspacePreparationFailed(String)
  case promptRenderFailed(String)
  case hookFailed(hook: String, reason: String)
  case runAlreadyActive(RunID)
  case runNotFound(RunID)
}

// MARK: - Agent Run Result

public struct AgentRunResult: Equatable, Sendable {
  public let context: RunContext
  public let sessionID: SessionID
  public let finalState: RunLifecycleState
  public let eventCount: Int
  public let error: String?

  public init(
    context: RunContext,
    sessionID: SessionID,
    finalState: RunLifecycleState,
    eventCount: Int,
    error: String?
  ) {
    self.context = context
    self.sessionID = sessionID
    self.finalState = finalState
    self.eventCount = eventCount
    self.error = error
  }
}

public struct AgentRunStartInfo: Equatable, Sendable {
  public let context: RunContext
  public let issue: Issue
  public let provider: String
  public let sessionID: SessionID
  public let workspacePath: String

  public init(
    context: RunContext,
    issue: Issue,
    provider: String,
    sessionID: SessionID,
    workspacePath: String
  ) {
    self.context = context
    self.issue = issue
    self.provider = provider
    self.sessionID = sessionID
    self.workspacePath = workspacePath
  }
}

// MARK: - Agent Run Event Sink

public protocol AgentRunEventSink: Sendable {
  func runDidStart(_ startInfo: AgentRunStartInfo)
  func runDidTransition(_ context: RunContext, to state: RunLifecycleState)
  func runDidReceiveEvent(_ event: AgentRawEvent)
  func runDidComplete(_ result: AgentRunResult)
}

// MARK: - Agent Running Protocol

public protocol AgentRunning: Sendable {
  func executeRun(
    context: RunContext,
    issue: Issue,
    config: WorkflowConfig,
    promptTemplate: String
  ) async -> AgentRunResult

  func cancelRun(runID: RunID) async throws
}

// MARK: - No-Op Event Sink

public struct NoOpAgentRunEventSink: AgentRunEventSink, Sendable {
  public init() {}
  public func runDidStart(_ startInfo: AgentRunStartInfo) {}
  public func runDidTransition(_ context: RunContext, to state: RunLifecycleState) {}
  public func runDidReceiveEvent(_ event: AgentRawEvent) {}
  public func runDidComplete(_ result: AgentRunResult) {}
}
