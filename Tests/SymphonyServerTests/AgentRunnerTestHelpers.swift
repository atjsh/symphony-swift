import Foundation
import SymphonyShared
import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore

// MARK: - Test Helpers

func makeIssue(
  id: String = "I_1",
  owner: String = "org",
  repo: String = "repo",
  number: Int = 1,
  title: String = "Fix bug",
  description: String? = "Description",
  state: String = "In Progress",
  issueState: String = "OPEN"
) throws -> SymphonyShared.Issue {
  SymphonyShared.Issue(
    id: IssueID(id),
    identifier: try IssueIdentifier(validating: "\(owner)/\(repo)#\(number)"),
    repository: "\(owner)/\(repo)",
    number: number,
    title: title,
    description: description,
    priority: nil,
    state: state,
    issueState: issueState,
    projectItemID: nil,
    url: "https://github.com/\(owner)/\(repo)/issues/\(number)",
    labels: [],
    blockedBy: [],
    createdAt: nil,
    updatedAt: nil
  )
}

func makeRunContext(
  issueID: String = "I_1",
  runID: String = "R_1",
  attempt: Int = 1
) throws -> RunContext {
  RunContext(
    issueID: IssueID(issueID),
    issueIdentifier: try IssueIdentifier(validating: "org/repo#1"),
    runID: RunID(runID),
    attempt: attempt
  )
}

// MARK: - Stub Workspace Manager

final class StubWorkspaceManager: WorkspaceManaging, @unchecked Sendable {
  private let lock = NSLock()
  private var _ensuredKeys: [WorkspaceKey] = []
  private var _removedKeys: [WorkspaceKey] = []
  private var _ensureError: Error?
  let root: String

  init(root: String = "/tmp/test_workspaces") {
    self.root = root
  }

  var ensuredKeys: [WorkspaceKey] {
    lock.withLock { _ensuredKeys }
  }

  var removedKeys: [WorkspaceKey] {
    lock.withLock { _removedKeys }
  }

  func setEnsureError(_ error: Error?) {
    lock.withLock { _ensureError = error }
  }

  func workspacePath(for key: WorkspaceKey) -> String {
    "\(root)/\(key.rawValue)"
  }

  func ensureWorkspace(for key: WorkspaceKey, hooks: HooksConfig) throws -> String {
    let error = lock.withLock {
      _ensuredKeys.append(key)
      return _ensureError
    }
    if let error { throw error }
    return workspacePath(for: key)
  }

  func removeWorkspace(for key: WorkspaceKey, hooks: HooksConfig) throws {
    lock.withLock { _removedKeys.append(key) }
  }

  func validateContainment(path: String) throws {
    guard path.hasPrefix(root) else {
      throw WorkspaceError.rootContainmentViolation(path: path, root: root)
    }
  }
}

// MARK: - Collecting Event Sink

final class CollectingEventSink: AgentRunEventSink, @unchecked Sendable {
  private let lock = NSLock()
  private var _starts: [AgentRunStartInfo] = []
  private var _transitions: [(RunContext, RunLifecycleState)] = []
  private var _events: [AgentRawEvent] = []
  private var _completions: [AgentRunResult] = []

  var starts: [AgentRunStartInfo] {
    lock.withLock { _starts }
  }

  var transitions: [(RunContext, RunLifecycleState)] {
    lock.withLock { _transitions }
  }

  var transitionStates: [RunLifecycleState] {
    lock.withLock { _transitions.map(\.1) }
  }

  var events: [AgentRawEvent] {
    lock.withLock { _events }
  }

  var completions: [AgentRunResult] {
    lock.withLock { _completions }
  }

  func runDidStart(_ startInfo: AgentRunStartInfo) {
    lock.withLock { _starts.append(startInfo) }
  }

  func runDidTransition(_ context: RunContext, to state: RunLifecycleState) {
    lock.withLock { _transitions.append((context, state)) }
  }

  func runDidReceiveEvent(_ event: AgentRawEvent) {
    lock.withLock { _events.append(event) }
  }

  func runDidComplete(_ result: AgentRunResult) {
    lock.withLock { _completions.append(result) }
  }
}

// MARK: - AgentRunResult Tests
