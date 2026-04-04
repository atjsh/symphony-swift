import Foundation
import SymphonyServerCore
import SymphonyShared

// MARK: - Issue Progress Report Error

public enum IssueProgressReportError: Error, Equatable, Sendable {
  case workspaceUnavailable
  case repositoryHistoryUnavailable(String)
}

// MARK: - Issue Progress Report Protocol

public protocol IssueProgressReportGenerating: Sendable {
  func issueProgressReport(issueID: IssueID, workspacePath: String) throws
    -> IssueProgressReportResponse
}

// MARK: - Workflow Analysis Config Store

// SAFETY: @unchecked Sendable — `config` accessed through `lock.withLock`.
public final class WorkflowAnalysisConfigStore: @unchecked Sendable {
  private let lock = NSLock()
  private var config: AnalysisConfig

  public init(config: AnalysisConfig) {
    self.config = config
  }

  public var current: AnalysisConfig {
    lock.withLock { config }
  }

  public func update(_ config: AnalysisConfig) {
    lock.withLock {
      self.config = config
    }
  }
}
