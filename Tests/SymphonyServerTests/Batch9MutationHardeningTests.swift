import Foundation
import Synchronization
import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore
@testable import SymphonyShared

// MARK: - StubLaunchedProcess terminate() Handler Tests

@Suite("StubLaunchedProcess Terminate Handler")
struct StubLaunchedProcessTerminateHandlerTests {

  @Test func terminateInvokesHandlerWithSignal15() {
    let process = StubLaunchedProcess()
    let receivedSignal = Mutex<Int32?>(nil)
    process.onTermination { code in
      receivedSignal.withLock { $0 = code }
    }
    process.terminate()
    #expect(receivedSignal.withLock { $0 } == 15, "terminate() must send SIGTERM (15)")
  }

  @Test func terminateDoesNotInvokeHandlerOnSecondCall() {
    let process = StubLaunchedProcess()
    let callCount = Mutex(0)
    process.onTermination { _ in
      callCount.withLock { $0 += 1 }
    }
    process.terminate()
    process.terminate()
    #expect(callCount.withLock { $0 } == 1, "guard !_terminated must prevent double invocation")
  }

  @Test func simulateTerminationDoesNotInvokeHandlerOnSecondCall() {
    let process = StubLaunchedProcess()
    let callCount = Mutex(0)
    process.onTermination { _ in
      callCount.withLock { $0 += 1 }
    }
    process.simulateTermination(exitCode: 42)
    process.simulateTermination(exitCode: 99)
    #expect(callCount.withLock { $0 } == 1, "guard !_terminated must prevent double invocation")
  }

  @Test func terminateBlocksSubsequentSimulateTermination() {
    let process = StubLaunchedProcess()
    let callCount = Mutex(0)
    process.onTermination { _ in
      callCount.withLock { $0 += 1 }
    }
    process.terminate()
    process.simulateTermination(exitCode: 0)
    #expect(callCount.withLock { $0 } == 1, "terminate sets _terminated, blocking simulateTermination")
  }

  @Test func simulateTerminationBlocksSubsequentTerminate() {
    let process = StubLaunchedProcess()
    let callCount = Mutex(0)
    process.onTermination { _ in
      callCount.withLock { $0 += 1 }
    }
    process.simulateTermination(exitCode: 0)
    process.terminate()
    #expect(callCount.withLock { $0 } == 1, "simulateTermination sets _terminated, blocking terminate")
  }

  @Test func terminateWithoutHandlerDoesNotCrash() {
    let process = StubLaunchedProcess()
    // No onTermination handler registered — handler?(15) should be a safe no-op
    process.terminate()
    #expect(process.terminationCount == 1)
  }
}

// MARK: - BootstrapRuntimeHooks keepAlive Priority Tests

@Suite(.serialized)
struct BootstrapRuntimeHooksKeepAlivePriorityTests {

  @Test func keepAliveOverrideTakesPriorityOverRunLoopRunner() {
    withBootstrapRuntimeHooksLock {
      let previousKeepAlive = BootstrapRuntimeHooks.keepAliveOverride
      let previousRunLoop = BootstrapRuntimeHooks.runLoopRunnerOverride
      defer {
        BootstrapRuntimeHooks.keepAliveOverride = previousKeepAlive
        BootstrapRuntimeHooks.runLoopRunnerOverride = previousRunLoop
      }

      var keepAliveCalled = false
      var runLoopCalled = false

      BootstrapRuntimeHooks.keepAliveOverride = { keepAliveCalled = true }
      BootstrapRuntimeHooks.runLoopRunnerOverride = { runLoopCalled = true }

      BootstrapRuntimeHooks.keepAlive()

      #expect(keepAliveCalled, "keepAliveOverride must take priority when both overrides are set")
      #expect(!runLoopCalled, "runLoopRunnerOverride must NOT fire when keepAliveOverride is set")
    }
  }

  @Test func defaultOutputRoutesToOverride() {
    withBootstrapRuntimeHooksLock {
      let previousOutput = BootstrapRuntimeHooks.outputOverride
      defer { BootstrapRuntimeHooks.outputOverride = previousOutput }

      var received: String?
      BootstrapRuntimeHooks.outputOverride = { received = $0 }

      BootstrapRuntimeHooks.defaultOutput("probe-line")
      #expect(received == "probe-line", "defaultOutput must forward exact string to outputOverride")
    }
  }

  @Test func setDefaultRunLoopActionOverrideAndReset() {
    withBootstrapRuntimeHooksLock {
      let previousKeepAlive = BootstrapRuntimeHooks.keepAliveOverride
      let previousRunLoop = BootstrapRuntimeHooks.runLoopRunnerOverride
      defer {
        BootstrapRuntimeHooks.keepAliveOverride = previousKeepAlive
        BootstrapRuntimeHooks.runLoopRunnerOverride = previousRunLoop
        BootstrapRuntimeHooks.resetDefaultRunLoopAction()
      }

      BootstrapRuntimeHooks.keepAliveOverride = nil
      BootstrapRuntimeHooks.runLoopRunnerOverride = nil

      var overrideCalled = false
      BootstrapRuntimeHooks.withDefaultRunLoopAction { overrideCalled = true }

      BootstrapRuntimeHooks.keepAlive()
      #expect(overrideCalled, "withDefaultRunLoopAction closure must be invoked via keepAlive cascade")

      // Reset and verify a second override replaces the first
      overrideCalled = false
      var secondCalled = false
      BootstrapRuntimeHooks.withDefaultRunLoopAction { secondCalled = true }
      BootstrapRuntimeHooks.keepAlive()
      #expect(!overrideCalled, "Original override must be replaced by second withDefaultRunLoopAction")
      #expect(secondCalled, "Second override must be active after replacement")
    }
  }
}

// MARK: - BootstrapRuntimeHooks Getter/Setter Roundtrip

@Suite(.serialized)
struct BootstrapRuntimeHooksRoundtripTests {

  @Test func outputOverrideRoundtrip() {
    withBootstrapRuntimeHooksLock {
      let previous = BootstrapRuntimeHooks.outputOverride
      defer { BootstrapRuntimeHooks.outputOverride = previous }

      // Nil baseline
      BootstrapRuntimeHooks.outputOverride = nil
      #expect(BootstrapRuntimeHooks.outputOverride == nil)

      // Set and read
      var called = false
      BootstrapRuntimeHooks.outputOverride = { _ in called = true }
      #expect(BootstrapRuntimeHooks.outputOverride != nil)
      BootstrapRuntimeHooks.outputOverride?("test")
      #expect(called)
    }
  }

  @Test func keepAliveOverrideRoundtrip() {
    withBootstrapRuntimeHooksLock {
      let previous = BootstrapRuntimeHooks.keepAliveOverride
      defer { BootstrapRuntimeHooks.keepAliveOverride = previous }

      BootstrapRuntimeHooks.keepAliveOverride = nil
      #expect(BootstrapRuntimeHooks.keepAliveOverride == nil)

      var called = false
      BootstrapRuntimeHooks.keepAliveOverride = { called = true }
      #expect(BootstrapRuntimeHooks.keepAliveOverride != nil)
      BootstrapRuntimeHooks.keepAliveOverride?()
      #expect(called)
    }
  }

  @Test func runLoopRunnerOverrideRoundtrip() {
    withBootstrapRuntimeHooksLock {
      let previous = BootstrapRuntimeHooks.runLoopRunnerOverride
      defer { BootstrapRuntimeHooks.runLoopRunnerOverride = previous }

      BootstrapRuntimeHooks.runLoopRunnerOverride = nil
      #expect(BootstrapRuntimeHooks.runLoopRunnerOverride == nil)

      var called = false
      BootstrapRuntimeHooks.runLoopRunnerOverride = { called = true }
      #expect(BootstrapRuntimeHooks.runLoopRunnerOverride != nil)
      BootstrapRuntimeHooks.runLoopRunnerOverride?()
      #expect(called)
    }
  }
}

// MARK: - StubLaunchedProcess Input Error Tests

@Suite("StubLaunchedProcess Input Error")
struct StubLaunchedProcessInputErrorTests {

  @Test func sendInputThrowsWhenInputErrorIsSet() {
    let process = StubLaunchedProcess()
    process.setInputError(StubError.injected)

    #expect(throws: StubError.self) {
      try process.sendInput(Data("test".utf8))
    }
  }

  @Test func sendInputSucceedsWhenNoInputError() throws {
    let process = StubLaunchedProcess()
    try process.sendInput(Data("test".utf8))
    // Should not throw
  }

  @Test func setInputErrorClearsWithNil() throws {
    let process = StubLaunchedProcess()
    process.setInputError(StubError.injected)
    process.setInputError(nil)
    try process.sendInput(Data("test".utf8))
    // Should not throw after clearing
  }
}

private enum StubError: Error {
  case injected
}

// MARK: - SessionStore Field Validation Tests

@Suite("SessionStore Field Validation")
struct SessionStoreFieldValidationTests {

  @Test func storedManagedSessionPreservesAllFields() {
    let store = SessionStore()
    let process = StubLaunchedProcess()
    let sid = SessionID("field-test")

    store.store(
      sessionID: sid,
      process: process,
      workspacePath: "/workspace/path",
      environment: ["API_KEY": "secret", "MODE": "debug"]
    )

    let managed = store.managedSession(for: sid)
    #expect(managed?.workspacePath == "/workspace/path")
    #expect(managed?.environment.count == 2)
    #expect(managed?.environment["API_KEY"] == "secret")
    #expect(managed?.environment["MODE"] == "debug")
  }

  @Test func removeReturnsOriginallyStoredProcess() {
    let store = SessionStore()
    let process = StubLaunchedProcess()
    let sid = SessionID("remove-test")

    // Mark the process before storing
    process.onOutput { _ in }
    store.store(sessionID: sid, process: process)

    let removed = store.remove(sessionID: sid)
    // The removed process should be the same reference
    #expect(removed != nil)
    // Verify by checking it's the same process via terminationCount state
    #expect((removed as? StubLaunchedProcess)?.terminationCount == 0)
    (removed as? StubLaunchedProcess)?.terminate()
    #expect(process.terminationCount == 1, "Removed process must be the same reference")
  }

  @Test func storeOverwritesPreviousSession() {
    let store = SessionStore()
    let firstProcess = StubLaunchedProcess()
    let secondProcess = StubLaunchedProcess()
    let sid = SessionID("overwrite")

    store.store(sessionID: sid, process: firstProcess, workspacePath: "/first")
    store.store(sessionID: sid, process: secondProcess, workspacePath: "/second")

    #expect(store.count == 1)
    let managed = store.managedSession(for: sid)
    #expect(managed?.workspacePath == "/second")
  }
}
