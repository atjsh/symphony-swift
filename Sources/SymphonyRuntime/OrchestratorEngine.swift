import Foundation
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

// MARK: - Orchestrator Engine

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
    observer: any EngineEventObserving = NoOpEngineEventObserver()
  ) {
    self._workflow = WorkflowDefinition(config: config, promptTemplate: promptTemplate)
    self.trackerFactory = trackerFactory
    self.workspaceManagerFactory = workspaceManagerFactory
    self.agentRunnerFactory = agentRunnerFactory
    self.observer = observer
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
          if let orchestrator = self.activeOrchestrator,
            let result = try? await orchestrator.tick()
          {
            await observer.engineTickCompleted(result)
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
      promptTemplate: workflow.promptTemplate
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
        try? workspaceManager.removeWorkspace(for: key, hooks: config.hooks)
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

final class EngineOrchestratorDelegate: OrchestratorDelegate, @unchecked Sendable {
  private let lock = NSLock()
  private let observer: any EngineEventObserving
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
    promptTemplate: String = ""
  ) {
    self._workspaceManager = workspaceManager
    self.observer = observer
    self._agentRunner = agentRunner
    self._config = config
    self._promptTemplate = promptTemplate
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
      try? snapshot.workspaceManager.removeWorkspace(for: key, hooks: snapshot.config.hooks)
    }
    let runID = RunID(UUID().uuidString)
    let context = RunContext(
      issueID: issueID, issueIdentifier: issueIdentifier, runID: runID, attempt: 1)
    await observer.engineRunCompleted(context, success: false)
  }

  func orchestratorDidRefreshSnapshot(issue: Issue) async {
    let runID = RunID(UUID().uuidString)
    let context = RunContext(
      issueID: issue.id, issueIdentifier: issue.identifier, runID: runID, attempt: 1)
    await observer.engineDispatchStarted(context)
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

// MARK: - Workflow Reloader (Section 6.6)

public final class WorkflowReloader: @unchecked Sendable {
  private let lock = NSLock()
  private let workflowPath: String
  private var _lastDefinition: WorkflowDefinition?
  private var _dispatchSource: DispatchSourceFileSystemObject?
  private var _fileDescriptor: Int32 = -1
  private let onChange: @Sendable (WorkflowDefinition) -> Void

  public init(
    workflowPath: String,
    onChange: @escaping @Sendable (WorkflowDefinition) -> Void
  ) {
    self.workflowPath = workflowPath
    self.onChange = onChange
  }

  deinit {
    stopWatching()
  }

  public func startWatching() throws {
    let fd = open(workflowPath, O_EVTONLY)
    guard fd >= 0 else {
      throw OrchestratorEngineError.workflowLoadFailed(
        "Cannot open \(workflowPath) for watching"
      )
    }

    let source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: fd,
      eventMask: [.write, .rename, .delete],
      queue: DispatchQueue.global(qos: .utility)
    )

    source.setEventHandler { [weak self] in
      self?.processFileChange()
    }

    source.setCancelHandler {
      close(fd)
    }

    lock.withLock {
      _fileDescriptor = fd
      _dispatchSource = source
    }

    source.resume()
  }

  public func stopWatching() {
    lock.lock()
    let source = _dispatchSource
    _dispatchSource = nil
    _fileDescriptor = -1
    lock.unlock()

    source?.cancel()
  }

  public func processFileChange() {
    do {
      let content = try String(contentsOfFile: workflowPath, encoding: .utf8)
      let definition = try WorkflowParser.parse(content: content)
      let previousDefinition = lock.withLock { _lastDefinition }
      if previousDefinition != definition {
        lock.withLock { _lastDefinition = definition }
        onChange(definition)
      }
    } catch {
      RuntimeLogger.log(
        level: .error,
        event: "workflow_reload_failed",
        context: RuntimeLogContext(
          metadata: [
            "workflow_path": workflowPath
          ]
        ),
        error: String(describing: error)
      )
      // Invalid reloads must not crash; keep last known good config
    }
  }

  public var isWatching: Bool {
    lock.withLock { _dispatchSource != nil }
  }
}

// MARK: - Collecting Engine Observer (for testing)

public final class CollectingEngineObserver: EngineEventObserving, @unchecked Sendable {
  private let lock = NSLock()
  private var _stateChanges: [OrchestratorEngineState] = []
  private var _tickResults: [TickResult] = []
  private var _dispatches: [RunContext] = []
  private var _completions: [(RunContext, Bool)] = []
  private var _errors: [(String, String)] = []

  public init() {}

  public var stateChanges: [OrchestratorEngineState] {
    lock.withLock { _stateChanges }
  }

  public var tickResults: [TickResult] {
    lock.withLock { _tickResults }
  }

  public var dispatches: [RunContext] {
    lock.withLock { _dispatches }
  }

  public var completions: [(RunContext, Bool)] {
    lock.withLock { _completions }
  }

  public var errors: [(message: String, context: String)] {
    lock.withLock { _errors }
  }

  public nonisolated func engineStateChanged(_ state: OrchestratorEngineState) async {
    lock.withLock { _stateChanges.append(state) }
  }

  public nonisolated func engineTickCompleted(_ result: TickResult) async {
    lock.withLock { _tickResults.append(result) }
  }

  public nonisolated func engineDispatchStarted(_ context: RunContext) async {
    lock.withLock { _dispatches.append(context) }
  }

  public nonisolated func engineRunCompleted(_ context: RunContext, success: Bool) async {
    lock.withLock { _completions.append((context, success)) }
  }

  public nonisolated func engineError(_ error: Error, context: String) async {
    lock.withLock { _errors.append(("\(error)", context)) }
  }
}
