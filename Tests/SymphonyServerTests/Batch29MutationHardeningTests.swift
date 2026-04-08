// Batch 29 — Token-usage guard, engine stop guard, and typename filter tests.
//
// Targets the following surviving mutations:
//
// ProviderSessionSnapshotExtractor.swift — tokenUsageObject guard:
//   guard inputTokens != nil || outputTokens != nil || totalTokens != nil
//   Five mutations swapping ||/&&, flipping != to ==.
//   Killed by providing exactly one token field at a time.
//
// OrchestratorEngine.swift — stop() guard:
//   guard _state == .running || _state == .starting
//   Six mutations (== to !=, || to &&, lock removal, cancel removal).
//   Killed by verifying stop() on idle engine is a no-op.
//
// GitHubTrackerAdapter.swift — normalizeItems typename filter:
//   guard content.typename == "Issue"
//   Mutation flips to typename != "Issue".
//   Killed by a fully-specified PullRequest that passes all other guards.

import Foundation
import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore
@testable import SymphonyShared

// MARK: - Token Usage Guard: Single-Field Extraction

@Suite("TokenUsageObject Single-Field Guard")
struct TokenUsageObjectSingleFieldTests {

  @Test func onlyInputTokensExtractsUsage() {
    let value = JSONValue.object(["input_tokens": .int(100)])
    let usage = ProviderSessionSnapshotExtractor.tokenUsage(from: value)
    #expect(usage != nil)
    #expect(usage?.inputTokens == 100)
    #expect(usage?.outputTokens == nil)
    #expect(usage?.totalTokens == nil)
  }

  @Test func onlyOutputTokensExtractsUsage() {
    let value = JSONValue.object(["output_tokens": .int(200)])
    let usage = ProviderSessionSnapshotExtractor.tokenUsage(from: value)
    #expect(usage != nil)
    #expect(usage?.outputTokens == 200)
    #expect(usage?.inputTokens == nil)
    #expect(usage?.totalTokens == nil)
  }

  @Test func onlyTotalTokensExtractsUsage() {
    let value = JSONValue.object(["total_tokens": .int(500)])
    let usage = ProviderSessionSnapshotExtractor.tokenUsage(from: value)
    #expect(usage != nil)
    #expect(usage?.totalTokens == 500)
    #expect(usage?.inputTokens == nil)
    #expect(usage?.outputTokens == nil)
  }

  @Test func noTokenFieldsReturnsNil() {
    let value = JSONValue.object(["unrelated": .string("data")])
    let usage = ProviderSessionSnapshotExtractor.tokenUsage(from: value)
    #expect(usage == nil)
  }

  @Test func nestedUsageKeyWithSingleField() {
    let value = JSONValue.object([
      "usage": .object(["output_tokens": .int(42)])
    ])
    let usage = ProviderSessionSnapshotExtractor.tokenUsage(from: value)
    #expect(usage != nil)
    #expect(usage?.outputTokens == 42)
  }
}

// MARK: - OrchestratorEngine Stop Guard

@Suite("OrchestratorEngine Stop Guard")
struct OrchestratorEngineStopGuardTests {

  @Test func stopWhenIdleIsNoOp() {
    let engine = OrchestratorEngine(
      config: .defaults,
      trackerFactory: { _ in StubTracker() }
    )
    #expect(engine.state == .idle)

    engine.stop()

    #expect(engine.state == .idle, "stop() on idle engine must not change state")
  }

  @Test func stopWhenStoppedIsNoOp() throws {
    let engine = OrchestratorEngine(
      config: .defaults,
      trackerFactory: { _ in StubTracker() }
    )

    // Start and wait briefly for transition
    try engine.start()
    engine.stop()

    // Allow async stop to settle
    Thread.sleep(forTimeInterval: 0.05)
    let stateAfterFirstStop = engine.state

    // Second stop should be a no-op
    engine.stop()
    Thread.sleep(forTimeInterval: 0.05)

    #expect(stateAfterFirstStop == .stopping || stateAfterFirstStop == .stopped)
    #expect(engine.state == .stopping || engine.state == .stopped)
  }
}

// MARK: - GitHubTrackerAdapter Typename Filter

@Suite("GitHubTrackerAdapter Typename Filter")
struct GitHubTrackerAdapterTypenameFilterTests {

  @Test func pullRequestWithFullFieldsIsExcluded() async throws {
    let transport = StubGraphQLTransport()
    let config = makeTrackerConfig()
    let adapter = GitHubTrackerAdapter(transport: transport, config: config)

    transport.enqueueResponse(projectIDResponse())

    // A PullRequest item that has ALL required Issue fields.
    // Only typename distinguishes it from an Issue.
    let response = """
      {
        "data": {
          "node": {
            "items": {
              "nodes": [
                {
                  "id": "PVTI_PR",
                  "content": {
                    "__typename": "PullRequest",
                    "id": "PR_1",
                    "number": 42,
                    "title": "Full PR",
                    "body": "Description",
                    "state": "OPEN",
                    "url": "https://github.com/test-owner/repo/pull/42",
                    "createdAt": "2026-01-01T00:00:00Z",
                    "updatedAt": "2026-01-02T00:00:00Z",
                    "labels": {"nodes": [{"name": "enhancement"}]},
                    "repository": {"nameWithOwner": "test-owner/repo"},
                    "trackedInIssues": {"nodes": []}
                  },
                  "fieldValueByName": {"name": "In Progress"}
                }
              ],
              "pageInfo": {"hasNextPage": false, "endCursor": null}
            }
          }
        }
      }
      """
    transport.enqueueResponse(response)

    let issues = try await adapter.fetchCandidateIssues()
    #expect(issues.isEmpty, "PullRequest must be excluded even with complete fields")
  }

  @Test func issueWithSameFieldsIsIncluded() async throws {
    let transport = StubGraphQLTransport()
    let config = makeTrackerConfig()
    let adapter = GitHubTrackerAdapter(transport: transport, config: config)

    transport.enqueueResponse(projectIDResponse())
    transport.enqueueResponse(
      candidateItemsResponse(items: [
        (id: "I_1", number: 42, title: "Real issue", repo: "test-owner/repo",
         status: "In Progress")
      ]))

    let issues = try await adapter.fetchCandidateIssues()
    #expect(issues.count == 1)
    #expect(issues[0].title == "Real issue")
  }
}

// MARK: - OrchestratorEngine.updateDependencies Effect

@Suite("EngineOrchestratorDelegate updateDependencies")
struct EngineDelegateUpdateDependenciesTests {

  @Test func updateDependenciesChangesPromptTemplate() async throws {
    let observer = CollectingEngineObserver()
    let wsRoot = NSTemporaryDirectory() + "update_deps_\(UUID().uuidString)"
    let wsManager1 = WorkspaceManager(root: wsRoot)

    let stubRunner = StubAgentRunner(finalState: .succeeded)
    let delegate = EngineOrchestratorDelegate(
      workspaceManager: wsManager1,
      observer: observer,
      agentRunner: stubRunner,
      config: .defaults,
      promptTemplate: "original prompt"
    )
    let orchestrator = Orchestrator(
      tracker: StubTracker(),
      config: .defaults,
      delegate: delegate
    )
    delegate.attach(orchestrator: orchestrator)

    // Update dependencies with a new prompt template
    let wsManager2 = WorkspaceManager(root: wsRoot)
    delegate.updateDependencies(
      workspaceManager: wsManager2,
      agentRunner: stubRunner,
      config: .defaults,
      promptTemplate: "updated prompt"
    )

    // Dispatch should use the updated prompt template
    let issue = Issue(
      id: IssueID("I_1"),
      identifier: try IssueIdentifier(validating: "o/r#1"),
      repository: "o/r", number: 1, title: "Test", description: nil,
      priority: nil, state: "In Progress", issueState: "OPEN",
      projectItemID: nil, url: nil, labels: [], blockedBy: [],
      createdAt: nil, updatedAt: nil
    )

    await delegate.orchestratorDidDispatch(issue: issue)

    #expect(stubRunner.lastPromptTemplate == "updated prompt")
  }
}

// MARK: - EngineOrchestratorDelegate attach Effect

@Suite("EngineOrchestratorDelegate attach")
struct EngineDelegateAttachTests {

  @Test func dispatchWithoutAttachSkipsOrchestratorCalls() async throws {
    let observer = CollectingEngineObserver()
    let wsRoot = NSTemporaryDirectory() + "no_attach_\(UUID().uuidString)"
    let wsManager = WorkspaceManager(root: wsRoot)

    let stubRunner = StubAgentRunner(finalState: .failed)
    let config = WorkflowConfig(agent: AgentConfig(maxRetryBackoffMS: 60_000))
    let delegate = EngineOrchestratorDelegate(
      workspaceManager: wsManager,
      observer: observer,
      agentRunner: stubRunner,
      config: config,
      promptTemplate: ""
    )

    // Deliberately do NOT call delegate.attach(orchestrator:)
    let issue = Issue(
      id: IssueID("I_1"),
      identifier: try IssueIdentifier(validating: "o/r#1"),
      repository: "o/r", number: 1, title: "Test", description: nil,
      priority: nil, state: "In Progress", issueState: "OPEN",
      projectItemID: nil, url: nil, labels: [], blockedBy: [],
      createdAt: nil, updatedAt: nil
    )

    await delegate.orchestratorDidDispatch(issue: issue)

    // Run should still complete (runner was called) but no retry queued
    // because orchestrator is nil
    #expect(observer.dispatches.count == 1)
    #expect(observer.completions.count == 1)
    #expect(observer.completions[0].1 == false, "failed run reports failure")
  }

  @Test func attachEnablesRetryEnqueue() async throws {
    let observer = CollectingEngineObserver()
    let wsRoot = NSTemporaryDirectory() + "attach_retry_\(UUID().uuidString)"
    let wsManager = WorkspaceManager(root: wsRoot)

    let stubRunner = StubAgentRunner(finalState: .failed)
    let config = WorkflowConfig(agent: AgentConfig(maxRetryBackoffMS: 60_000))
    let delegate = EngineOrchestratorDelegate(
      workspaceManager: wsManager,
      observer: observer,
      agentRunner: stubRunner,
      config: config,
      promptTemplate: ""
    )
    let orchestrator = Orchestrator(
      tracker: StubTracker(),
      config: config,
      delegate: delegate
    )
    delegate.attach(orchestrator: orchestrator)

    let issue = Issue(
      id: IssueID("I_1"),
      identifier: try IssueIdentifier(validating: "o/r#1"),
      repository: "o/r", number: 1, title: "Test", description: nil,
      priority: nil, state: "In Progress", issueState: "OPEN",
      projectItemID: nil, url: nil, labels: [], blockedBy: [],
      createdAt: nil, updatedAt: nil
    )

    await delegate.orchestratorDidDispatch(issue: issue)

    // With attach, failed run should enqueue retry
    let retryRecord = orchestrator.queuedRetryRecord(issueID: issue.id)
    #expect(retryRecord != nil, "attach must enable retry enqueue on failure")
    #expect(retryRecord?.attempt == 2)
  }
}
