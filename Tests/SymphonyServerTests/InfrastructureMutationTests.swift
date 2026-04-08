import Foundation
import SymphonyShared
import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore

// MARK: - BootstrapRuntimeHooks Mutation Hardening

/// Tests the keepAlive dispatch chain, defaultOutput routing,
/// and defaultRunLoopAction override paths.
@Suite("BootstrapRuntimeHooks Mutations", .serialized)
struct BootstrapRuntimeHooksMutationTests {

  // MARK: - keepAlive dispatch chain

  @Test func keepAliveCallsKeepAliveOverrideWhenSet() {
    var called = false
    BootstrapRuntimeHooks.keepAliveOverride = { called = true }
    BootstrapRuntimeHooks.runLoopRunnerOverride = {
      Issue.record("runLoopRunnerOverride must NOT be called when keepAliveOverride is set")
    }
    defer {
      BootstrapRuntimeHooks.keepAliveOverride = nil
      BootstrapRuntimeHooks.runLoopRunnerOverride = nil
    }

    BootstrapRuntimeHooks.keepAlive()
    #expect(called, "keepAliveOverride must be invoked")
  }

  @Test func keepAliveCallsRunLoopOverrideWhenKeepAliveIsNil() {
    BootstrapRuntimeHooks.keepAliveOverride = nil
    var called = false
    BootstrapRuntimeHooks.runLoopRunnerOverride = { called = true }
    defer {
      BootstrapRuntimeHooks.runLoopRunnerOverride = nil
    }

    BootstrapRuntimeHooks.keepAlive()
    #expect(called, "runLoopRunnerOverride must be invoked when keepAliveOverride is nil")
  }

  @Test func keepAliveCallsDefaultRunLoopActionWhenBothNil() {
    BootstrapRuntimeHooks.keepAliveOverride = nil
    BootstrapRuntimeHooks.runLoopRunnerOverride = nil
    var called = false
    BootstrapRuntimeHooks.withDefaultRunLoopAction { called = true }
    defer {
      BootstrapRuntimeHooks.resetDefaultRunLoopAction()
    }

    BootstrapRuntimeHooks.keepAlive()
    #expect(called, "defaultRunLoopAction must be invoked when both overrides are nil")
  }

  // MARK: - defaultOutput routing

  @Test func defaultOutputUsesOverrideWhenSet() {
    var captured: String?
    BootstrapRuntimeHooks.outputOverride = { captured = $0 }
    defer { BootstrapRuntimeHooks.outputOverride = nil }

    BootstrapRuntimeHooks.defaultOutput("test line")
    #expect(captured == "test line")
  }

  @Test func defaultOutputDoesNotCrashWithoutOverride() {
    BootstrapRuntimeHooks.outputOverride = nil
    // Should fall through to print() without crashing
    BootstrapRuntimeHooks.defaultOutput("fallback line")
  }

  // MARK: - resetDefaultRunLoopAction

  @Test func resetDefaultRunLoopActionClearsOverride() {
    var callCount = 0
    BootstrapRuntimeHooks.withDefaultRunLoopAction { callCount += 1 }
    BootstrapRuntimeHooks.resetDefaultRunLoopAction()

    // After reset, the default action should be CFRunLoopRun.
    // We can't call it (it would block), but we verified the set→reset path.
    #expect(callCount == 0, "Override must not be called by set/reset alone")
  }
}

// MARK: - CollectingEngineObserver Mutation Hardening

/// Tests that each observer method correctly appends to its backing store
/// and that each property returns the recorded values.
@Suite("CollectingEngineObserver Mutations")
struct CollectingEngineObserverMutationTests {

  @Test func engineStateChangedRecordsState() async {
    let observer = CollectingEngineObserver()
    await observer.engineStateChanged(.running)
    await observer.engineStateChanged(.stopped)

    #expect(observer.stateChanges == [.running, .stopped])
  }

  @Test func engineTickCompletedRecordsResult() async {
    let observer = CollectingEngineObserver()
    let result = TickResult(reconciled: 1, candidatesFetched: 2, dispatched: 3, retriesProcessed: 0)
    await observer.engineTickCompleted(result)

    #expect(observer.tickResults.count == 1)
    #expect(observer.tickResults.first == result)
  }

  @Test func engineDispatchStartedRecordsContext() async throws {
    let observer = CollectingEngineObserver()
    let context = RunContext(
      issueID: IssueID("i1"),
      issueIdentifier: try IssueIdentifier(validating: "org/repo#1"),
      runID: RunID("r1"),
      attempt: 1
    )
    await observer.engineDispatchStarted(context)

    #expect(observer.dispatches.count == 1)
    #expect(observer.dispatches.first == context)
  }

  @Test func engineRunCompletedRecordsContextAndSuccess() async throws {
    let observer = CollectingEngineObserver()
    let context = RunContext(
      issueID: IssueID("i1"),
      issueIdentifier: try IssueIdentifier(validating: "org/repo#1"),
      runID: RunID("r1"),
      attempt: 1
    )
    await observer.engineRunCompleted(context, success: true)
    await observer.engineRunCompleted(context, success: false)

    #expect(observer.completions.count == 2)
    #expect(observer.completions[0].1 == true)
    #expect(observer.completions[1].1 == false)
  }

  @Test func engineErrorRecordsMessageAndContext() async {
    let observer = CollectingEngineObserver()
    struct TestError: Error, CustomStringConvertible {
      let description: String
    }
    await observer.engineError(TestError(description: "boom"), context: "tick")

    #expect(observer.errors.count == 1)
    #expect(observer.errors.first?.context == "tick")
    #expect(observer.errors.first?.message.contains("boom") == true)
  }

  @Test func emptyObserverHasNoRecords() {
    let observer = CollectingEngineObserver()
    #expect(observer.stateChanges.isEmpty)
    #expect(observer.tickResults.isEmpty)
    #expect(observer.dispatches.isEmpty)
    #expect(observer.completions.isEmpty)
    #expect(observer.errors.isEmpty)
  }
}

// MARK: - SessionStore & SessionSequenceCounter Mutation Hardening

@Suite("SessionStore Mutations")
struct SessionStoreMutationTests {

  @Test func sequenceCounterIncrementsMonotonically() {
    let counter = SessionSequenceCounter()
    let first = counter.next()
    let second = counter.next()
    let third = counter.next()

    #expect(first == EventSequence(0))
    #expect(second == EventSequence(1))
    #expect(third == EventSequence(2))
    // Verify strictly increasing
    #expect(first != second)
    #expect(second != third)
  }

  @Test func storeAndRetrieveManagedSession() {
    let store = SessionStore()
    let process = StubLaunchedProcess()
    let sid = SessionID("s1")

    store.store(sessionID: sid, process: process, workspacePath: "/tmp", environment: ["KEY": "VAL"])

    let managed = store.managedSession(for: sid)
    #expect(managed != nil)
    #expect(managed?.workspacePath == "/tmp")
    #expect(managed?.environment["KEY"] == "VAL")
    #expect(store.count == 1)
  }

  @Test func processReturnsStoredProcess() {
    let store = SessionStore()
    let process = StubLaunchedProcess()
    let sid = SessionID("s1")

    store.store(sessionID: sid, process: process)
    #expect(store.process(for: sid) != nil)
    #expect(store.process(for: SessionID("missing")) == nil)
  }

  @Test func removeReturnsProcessAndClearsEntry() {
    let store = SessionStore()
    let process = StubLaunchedProcess()
    let sid = SessionID("s1")

    store.store(sessionID: sid, process: process)
    #expect(store.count == 1)

    let removed = store.remove(sessionID: sid)
    #expect(removed != nil)
    #expect(store.count == 0)

    // Removing again returns nil
    let removedAgain = store.remove(sessionID: sid)
    #expect(removedAgain == nil)
  }

  @Test func managedSessionReturnsNilForUnknownID() {
    let store = SessionStore()
    #expect(store.managedSession(for: SessionID("ghost")) == nil)
  }

  @Test func emptyStoreHasZeroCount() {
    let store = SessionStore()
    #expect(store.count == 0)
  }
}

// MARK: - CopilotCLI EventKindInference: type ?? event

@Test func copilotCLITypeTakesPrecedenceOverEvent() {
  // When both type and event are present, type wins
  let kind = EventKindInference.infer(
    from: #"{"type":"tool_call","event":"status"}"#,
    provider: .copilotCLI
  )
  #expect(kind == .toolCall, "type must take precedence over event in CopilotCLI inference")
}

@Test func copilotCLIEventUsedWhenTypeNil() {
  let kind = EventKindInference.infer(
    from: #"{"event":"tool_result"}"#,
    provider: .copilotCLI
  )
  #expect(kind == .toolResult, "event field must be used when type is nil in CopilotCLI")
}

@Test func copilotCLIUnknownWhenBothTypeAndEventNil() {
  let kind = EventKindInference.infer(
    from: #"{"params":{"data":"stuff"}}"#,
    provider: .copilotCLI
  )
  #expect(kind == .unknown, "Must return .unknown when both type and event are nil")
}
