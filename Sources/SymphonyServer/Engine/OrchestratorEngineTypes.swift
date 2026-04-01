import Foundation
import SymphonyServerCore
import SymphonyShared

// MARK: - Orchestrator Engine Error

public enum OrchestratorEngineError: Error, Equatable, Sendable {
  case workflowLoadFailed(String)
  case trackerCreationFailed(String)
  case alreadyRunning
  case notRunning
}

// MARK: - Orchestrator Engine State

public enum OrchestratorEngineState: String, Equatable, Sendable {
  case idle
  case starting
  case running
  case stopping
  case stopped
}

// MARK: - Run Context

public struct RunContext: Equatable, Sendable {
  public let issueID: IssueID
  public let issueIdentifier: IssueIdentifier
  public let runID: RunID
  public let attempt: Int

  public init(issueID: IssueID, issueIdentifier: IssueIdentifier, runID: RunID, attempt: Int) {
    self.issueID = issueID
    self.issueIdentifier = issueIdentifier
    self.runID = runID
    self.attempt = attempt
  }
}

// MARK: - Engine Event Observer

public protocol EngineEventObserving: Sendable {
  func engineStateChanged(_ state: OrchestratorEngineState) async
  func engineTickCompleted(_ result: TickResult) async
  func engineDispatchStarted(_ context: RunContext) async
  func engineRunCompleted(_ context: RunContext, success: Bool) async
  func engineError(_ error: Error, context: String) async
}

// MARK: - Default No-Op Observer

public struct NoOpEngineEventObserver: EngineEventObserving, Sendable {
  public init() {}

  public func engineStateChanged(_ state: OrchestratorEngineState) async {}
  public func engineTickCompleted(_ result: TickResult) async {}
  public func engineDispatchStarted(_ context: RunContext) async {}
  public func engineRunCompleted(_ context: RunContext, success: Bool) async {}
  public func engineError(_ error: Error, context: String) async {}
}

public protocol OrchestratorEngineRefreshing: Sendable {
  func requestRefresh()
}
