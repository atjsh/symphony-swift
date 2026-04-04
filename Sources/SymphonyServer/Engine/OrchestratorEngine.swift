import Foundation
import SymphonyServerCore
import SymphonyShared

// MARK: - Orchestrator Engine

// SAFETY: @unchecked Sendable — all mutable state (_state, _workflow, _loopTask,
// _runtime) is exclusively accessed through `lock.withLock`.
public final class OrchestratorEngine: @unchecked Sendable {
  private let lock = NSLock()
  private var _state: OrchestratorEngineState = .idle
  private var _workflow: WorkflowDefinition
  private var _loopTask: Task<Void, Never>?
  private var _runtime: EngineRuntime?
  private let trackerFactory: @Sendable (TrackerConfig) throws -> any TrackerAdapting
  private let workspaceManagerFactory: @Sendable (WorkspaceConfig) -> any WorkspaceManaging
  private let agentRunnerFactory: (@Sendable (any WorkspaceManaging) -> any AgentRunning)?
  private let observer: any EngineEventObserving
  private let stateStore: SQLiteServerStateStore?

  public var state: OrchestratorEngineState {
    lock.withLock { _state }
  }

  public var config: WorkflowConfig {
    lock.withLock { _workflow.config }
  }

  public init(
    config: WorkflowConfig,
    trackerFactory: @escaping @Sendable (TrackerConfig) throws -> any TrackerAdapting,
    workspaceManagerFactory: @escaping @Sendable (WorkspaceConfig) -> any WorkspaceManaging = {
      WorkspaceManager(root: $0.root)
    },
    agentRunnerFactory: (@Sendable (any WorkspaceManaging) -> any AgentRunning)? = nil,
    promptTemplate: String = "",
    observer: any EngineEventObserving = NoOpEngineEventObserver(),
    stateStore: SQLiteServerStateStore? = nil
  ) {
    self._workflow = WorkflowDefinition(config: config, promptTemplate: promptTemplate)
    self.trackerFactory = trackerFactory
    self.workspaceManagerFactory = workspaceManagerFactory
    self.agentRunnerFactory = agentRunnerFactory
    self.observer = observer
    self.stateStore = stateStore
  }

  // MARK: - Lifecycle

  public func start() throws {
    let shouldStart: Bool = lock.withLock {
      guard _state == .idle || _state == .stopped else { return false }
      _state = .starting
      return true
    }

    guard shouldStart else {
      throw OrchestratorEngineError.alreadyRunning
    }

    let task = Task { [weak self] in
      guard let self else { return }

      let observer = self.observer
      await observer.engineStateChanged(.starting)

      do {
        let runtime = try self.makeRuntime(for: self.workflowDefinition)
        self.storeRuntime(runtime)

        // Startup cleanup (Section 7.5)
        await self.performStartupCleanup(
          tracker: runtime.tracker,
          config: runtime.workflow.config,
          workspaceManager: runtime.workspaceManager
        )

        self.transitionTo(.running)
        await observer.engineStateChanged(.running)

        // Poll loop
        while !Task.isCancelled {
          if let orchestrator = self.activeOrchestrator {
            do {
              let result = try await orchestrator.tick()
              await observer.engineTickCompleted(result)
            } catch {
              await observer.engineError(error, context: "tick")
            }
          }

          do {
            try await Task.sleep(nanoseconds: self.pollingIntervalNanoseconds())
          } catch {
            break
          }
        }
      } catch {
        await observer.engineError(error, context: "startup")
      }

      self.clearRuntime()
      self.transitionTo(.stopped)
      await observer.engineStateChanged(.stopped)
    }

    lock.withLock { _loopTask = task }
  }

  public func stop() {
    lock.lock()
    guard _state == .running || _state == .starting else {
      lock.unlock()
      return
    }
    _state = .stopping
    _loopTask?.cancel()
    _loopTask = nil
    lock.unlock()
  }

  public func requestRefresh() {
    let observer = self.observer
    Task { [weak self] in
      guard let self, let orchestrator = self.activeOrchestrator else { return }
      await self.performRefresh(observer: observer) {
        try await orchestrator.tick()
      }
    }
  }

  func performRefresh(
    observer: any EngineEventObserving,
    operation: @escaping @Sendable () async throws -> TickResult
  ) async {
    do {
      let result = try await operation()
      await observer.engineTickCompleted(result)
    } catch {
      await observer.engineError(error, context: "refresh")
    }
  }

  // MARK: - Config Reload (Section 6.6)

  public func reloadConfig(_ newConfig: WorkflowConfig) {
    let promptTemplate = lock.withLock { _workflow.promptTemplate }
    reloadWorkflow(WorkflowDefinition(config: newConfig, promptTemplate: promptTemplate))
  }

  public func reloadWorkflow(_ workflow: WorkflowDefinition) {
    let previousWorkflow = lock.withLock {
      let previous = _workflow
      _workflow = workflow
      return previous
    }

    do {
      try reconfigureRuntime(for: workflow)
    } catch {
      lock.withLock { _workflow = previousWorkflow }
      RuntimeLogger.log(
        level: .error,
        event: "workflow_reload_failed",
        context: RuntimeLogContext(
          metadata: [
            "polling_interval_ms": String(workflow.config.polling.intervalMS)
          ]
        ),
        error: String(describing: error)
      )
      let observer = self.observer
      Task {
        await observer.engineError(error, context: "reload")
      }
    }
  }

  // MARK: - State Transitions

  private func transitionTo(_ newState: OrchestratorEngineState) {
    lock.withLock { _state = newState }
  }

  private var workflowDefinition: WorkflowDefinition {
    lock.withLock { _workflow }
  }

  private var activeOrchestrator: Orchestrator? {
    lock.withLock { _runtime?.orchestrator }
  }

  private func storeRuntime(_ runtime: EngineRuntime) {
    lock.withLock { _runtime = runtime }
  }

  private func clearRuntime() {
    lock.withLock { _runtime = nil }
  }

  private func pollingIntervalNanoseconds() -> UInt64 {
    UInt64(max(0, config.polling.intervalMS)) * 1_000_000
  }

  private func makeRuntime(for workflow: WorkflowDefinition) throws -> EngineRuntime {
    let tracker = try trackerFactory(workflow.config.tracker)
    let workspaceManager = workspaceManagerFactory(workflow.config.workspace)
    let agentRunner = agentRunnerFactory?(workspaceManager)
    let delegate = EngineOrchestratorDelegate(
      workspaceManager: workspaceManager,
      observer: observer,
      agentRunner: agentRunner,
      config: workflow.config,
      promptTemplate: workflow.promptTemplate,
      stateStore: stateStore
    )
    let orchestrator = Orchestrator(
      tracker: tracker,
      config: workflow.config,
      delegate: delegate
    )
    delegate.attach(orchestrator: orchestrator)
    return EngineRuntime(
      workflow: workflow,
      tracker: tracker,
      workspaceManager: workspaceManager,
      agentRunner: agentRunner,
      delegate: delegate,
      orchestrator: orchestrator
    )
  }

  private func reconfigureRuntime(for workflow: WorkflowDefinition) throws {
    guard let runtime = lock.withLock({ _runtime }) else { return }

    let tracker = try trackerFactory(workflow.config.tracker)
    let workspaceManager = workspaceManagerFactory(workflow.config.workspace)
    let agentRunner = agentRunnerFactory?(workspaceManager)

    runtime.delegate.updateDependencies(
      workspaceManager: workspaceManager,
      agentRunner: agentRunner,
      config: workflow.config,
      promptTemplate: workflow.promptTemplate
    )
    runtime.orchestrator.reload(tracker: tracker, config: workflow.config)
  }

  // MARK: - Startup Cleanup (Section 7.5)

  private func performStartupCleanup(
    tracker: any TrackerAdapting,
    config: WorkflowConfig,
    workspaceManager: any WorkspaceManaging
  ) async {
    do {
      let terminalIssues = try await tracker.fetchIssuesByStates(config.tracker.terminalStates)
      for issue in terminalIssues {
        let key = WorkspaceKey(issue.identifier.rawValue)
        do {
          try workspaceManager.removeWorkspace(for: key, hooks: config.hooks)
        } catch {
          RuntimeLogger.log(
            level: .warning,
            event: "startup_cleanup_workspace_removal_failed",
            context: RuntimeLogContext(
              issueIdentifier: issue.identifier.rawValue,
              metadata: ["workspace_key": key.rawValue]
            ),
            error: String(describing: error)
          )
        }
      }
    } catch {
      await observer.engineError(error, context: "startupCleanup")
    }
  }
}

private struct EngineRuntime {
  let workflow: WorkflowDefinition
  let tracker: any TrackerAdapting
  let workspaceManager: any WorkspaceManaging
  let agentRunner: (any AgentRunning)?
  let delegate: EngineOrchestratorDelegate
  let orchestrator: Orchestrator
}

// MARK: - Engine Orchestrator Delegate

// SAFETY: @unchecked Sendable — all mutable state (_workspaceManager, _agentRunner,
// _config, _promptTemplate, _orchestrator) is exclusively accessed through `lock.withLock`.
final class EngineOrchestratorDelegate: OrchestratorDelegate, @unchecked Sendable {
  private let lock = NSLock()
  private let observer: any EngineEventObserving
  private let stateStore: SQLiteServerStateStore?
  private var _workspaceManager: any WorkspaceManaging
  private var _agentRunner: (any AgentRunning)?
  private var _config: WorkflowConfig
  private var _promptTemplate: String
  private weak var _orchestrator: Orchestrator?

  init(
    workspaceManager: any WorkspaceManaging,
    observer: any EngineEventObserving,
    agentRunner: (any AgentRunning)? = nil,
    config: WorkflowConfig = .defaults,
    promptTemplate: String = "",
    stateStore: SQLiteServerStateStore? = nil
  ) {
    self._workspaceManager = workspaceManager
    self.observer = observer
    self.stateStore = stateStore
    self._agentRunner = agentRunner
    self._config = config
    self._promptTemplate = promptTemplate
  }

  func orchestratorDidSyncIssues(_ issues: [Issue]) async {
    guard let stateStore else { return }
    for issue in issues {
      do {
        try stateStore.upsertIssue(issue)
      } catch {
        RuntimeLogger.log(
          level: .error,
          event: "issue_sync_persistence_failed",
          context: RuntimeLogContext(
            issueID: issue.id.rawValue,
            issueIdentifier: issue.identifier.rawValue
          ),
          error: String(describing: error)
        )
      }
    }
  }

  func orchestratorDidDispatch(issue: Issue) async {
    await executeRun(issue: issue, attempt: 1)
  }

  func orchestratorDidCancel(
    issueID: IssueID, issueIdentifier: IssueIdentifier, reason: String, cleanup: Bool
  ) async {
    let snapshot = dependencySnapshot()
    if cleanup {
      let key = WorkspaceKey(issueIdentifier.rawValue)
      do {
        try snapshot.workspaceManager.removeWorkspace(for: key, hooks: snapshot.config.hooks)
      } catch {
        RuntimeLogger.log(
          level: .warning,
          event: "cancel_workspace_removal_failed",
          context: RuntimeLogContext(
            issueID: issueID.rawValue,
            issueIdentifier: issueIdentifier.rawValue,
            metadata: ["workspace_key": key.rawValue]
          ),
          error: String(describing: error)
        )
      }
    }
    let runID = RunID(UUID().uuidString)
    let context = RunContext(
      issueID: issueID, issueIdentifier: issueIdentifier, runID: runID, attempt: 1)
    await observer.engineRunCompleted(context, success: false)
  }

  func orchestratorDidRefreshSnapshot(issue: Issue) async {
    do {
      try stateStore?.upsertIssue(issue)
    } catch {
      RuntimeLogger.log(
        level: .error,
        event: "snapshot_refresh_persistence_failed",
        context: RuntimeLogContext(
          issueID: issue.id.rawValue,
          issueIdentifier: issue.identifier.rawValue
        ),
        error: String(describing: error)
      )
    }
  }

  func orchestratorDidRetry(issue: Issue, record: RetryRecord) async {
    await executeRun(issue: issue, attempt: record.attempt)
  }

  func attach(orchestrator: Orchestrator) {
    lock.withLock { _orchestrator = orchestrator }
  }

  func updateDependencies(
    workspaceManager: any WorkspaceManaging,
    agentRunner: (any AgentRunning)?,
    config: WorkflowConfig,
    promptTemplate: String
  ) {
    lock.withLock {
      _workspaceManager = workspaceManager
      _agentRunner = agentRunner
      _config = config
      _promptTemplate = promptTemplate
    }
  }

  private func executeRun(issue: Issue, attempt: Int) async {
    let snapshot = dependencySnapshot()
    let runID = RunID(UUID().uuidString)
    let context = RunContext(
      issueID: issue.id,
      issueIdentifier: issue.identifier,
      runID: runID,
      attempt: attempt
    )
    await observer.engineDispatchStarted(context)

    guard let agentRunner = snapshot.agentRunner else { return }

    snapshot.orchestrator?.markRunning(issue: issue)
    let result = await agentRunner.executeRun(
      context: context,
      issue: issue,
      config: snapshot.config,
      promptTemplate: snapshot.promptTemplate
    )
    snapshot.orchestrator?.markCompleted(issueID: issue.id, state: issue.state)

    if result.finalState != .succeeded {
      let delayMS = RetryQueue.backoffDelay(
        attempt: context.attempt,
        maxRetryBackoffMS: snapshot.config.agent.maxRetryBackoffMS
      )
      snapshot.orchestrator?.enqueueRetry(
        issue: issue,
        attempt: context.attempt + 1,
        delayMS: delayMS,
        error: result.error
      )
    }

    await observer.engineRunCompleted(context, success: result.finalState == .succeeded)
  }

  private func dependencySnapshot() -> DependencySnapshot {
    lock.withLock {
      DependencySnapshot(
        workspaceManager: _workspaceManager,
        agentRunner: _agentRunner,
        config: _config,
        promptTemplate: _promptTemplate,
        orchestrator: _orchestrator
      )
    }
  }
}

private struct DependencySnapshot {
  let workspaceManager: any WorkspaceManaging
  let agentRunner: (any AgentRunning)?
  let config: WorkflowConfig
  let promptTemplate: String
  let orchestrator: Orchestrator?
}

extension OrchestratorEngine: OrchestratorEngineRefreshing {}
