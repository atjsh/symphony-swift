import Foundation
import Synchronization
import SymphonyShared
import Testing

@testable import SymphonyServer

// MARK: - ProcessLaunching mutation hardening (StubProcessLauncher/StubLaunchedProcess)

@Test func stubProcessLauncherRecordsInvocationsWithEnvironment() throws {
  let launcher = StubProcessLauncher()
  let proc = StubLaunchedProcess()
  launcher.setStubProcess(proc)

  _ = try launcher.launch(
    command: "echo hello",
    workspacePath: "/tmp/ws",
    environment: ["KEY": "VAL", "KEY2": "VAL2"]
  )

  #expect(launcher.invocations.count == 1)
  #expect(launcher.invocations[0].command == "echo hello")
  #expect(launcher.invocations[0].workspacePath == "/tmp/ws")
  #expect(launcher.invocations[0].environment["KEY"] == "VAL")
  #expect(launcher.invocations[0].environment["KEY2"] == "VAL2")
  #expect(launcher.invocations[0].environment.count == 2)
}

@Test func stubProcessLauncherReturnsCorrectStubFromQueue() throws {
  let launcher = StubProcessLauncher()
  let proc1 = StubLaunchedProcess()
  let proc2 = StubLaunchedProcess()
  launcher.setStubProcesses([proc1, proc2])

  let result1 = try launcher.launch(command: "first", workspacePath: "/", environment: [:])
  let result2 = try launcher.launch(command: "second", workspacePath: "/", environment: [:])

  // Verify by using them — proc1 and proc2 are different instances
  (result1 as! StubLaunchedProcess).simulateOutput("from1\n")
  (result2 as! StubLaunchedProcess).simulateOutput("from2\n")
  #expect(launcher.invocations.count == 2)
}

@Test func stubProcessLauncherEmptyQueueCreatesNewProcess() throws {
  let launcher = StubProcessLauncher()
  // No stub process set — should create a default one
  let process = try launcher.launch(command: "test", workspacePath: "/", environment: [:])
  #expect(process is StubLaunchedProcess)
}

@Test func stubProcessLauncherThrowsOnError() {
  let launcher = StubProcessLauncher()
  launcher.setLaunchError(ProviderAdapterError.processLaunchFailed("test"))

  do {
    _ = try launcher.launch(command: "x", workspacePath: "/", environment: [:])
    Issue.record("Should have thrown")
  } catch {
    #expect(error is ProviderAdapterError)
  }
  // Invocation should still be recorded even though it threw
  #expect(launcher.invocations.count == 1)
}

@Test func stubLaunchedProcessRecordsInputData() throws {
  let process = StubLaunchedProcess()
  try process.sendInput(Data("hello\n".utf8))
  #expect(process.recordedInputStrings == ["hello\n"])
}

@Test func stubLaunchedProcessDoesNotRecordInputWhenErrorSet() {
  let process = StubLaunchedProcess()
  process.setInputError(ProviderAdapterError.processLaunchFailed("broken"))

  do {
    try process.sendInput(Data("data".utf8))
    Issue.record("Should have thrown")
  } catch {
    #expect(error is ProviderAdapterError)
  }
  // Input should NOT be recorded when error is present
  #expect(process.recordedInputStrings.isEmpty)
}

@Test func stubLaunchedProcessInterruptCountIncrements() {
  let process = StubLaunchedProcess()
  #expect(process.interruptCount == 0)
  process.interrupt()
  #expect(process.interruptCount == 1)
  process.interrupt()
  #expect(process.interruptCount == 2)
}

@Test func stubLaunchedProcessTerminateCountIncrements() {
  let process = StubLaunchedProcess()
  #expect(process.terminationCount == 0)
  process.terminate()
  #expect(process.terminationCount == 1)
  // After terminate, further calls are no-ops (guard !_terminated)
  process.terminate()
  #expect(process.terminationCount == 1)
}

@Test func stubLaunchedProcessInterruptUnreachableAfterTermination() {
  let process = StubLaunchedProcess()
  process.terminate()
  #expect(process.terminationCount == 1)
  process.interrupt()
  // interrupt is a no-op after termination (guard !_terminated)
  #expect(process.interruptCount == 0)
}

@Test func stubLaunchedProcessDetectsTurnInterruptMessage() throws {
  let process = StubLaunchedProcess()
  let interruptMsg = #"{"method":"turn/interrupt","params":{"threadId":"t","turnId":"tu"}}"#
  try process.sendInput(Data((interruptMsg + "\n").utf8))
  #expect(process.interruptCount == 1)
}

@Test func stubLaunchedProcessNonInterruptMessageDoesNotCountAsInterrupt() throws {
  let process = StubLaunchedProcess()
  let normalMsg = #"{"method":"turn/start","params":{}}"#
  try process.sendInput(Data((normalMsg + "\n").utf8))
  #expect(process.interruptCount == 0)
}

@Test func stubLaunchedProcessSimulateOutputCallsHandler() {
  let process = StubLaunchedProcess()
  let received = Mutex<String?>(nil)
  process.onOutput { data in
    received.withLock { $0 = String(data: data, encoding: .utf8) }
  }
  process.simulateOutput("test output")
  #expect(received.withLock { $0 } == "test output")
}

@Test func stubLaunchedProcessSimulateTerminationCallsHandler() {
  let process = StubLaunchedProcess()
  let exitCode = Mutex<Int32?>(nil)
  process.onTermination { code in
    exitCode.withLock { $0 = code }
  }
  process.simulateTermination(exitCode: 42)
  #expect(exitCode.withLock { $0 } == 42)
}

// MARK: - ClaudeCodeAdapter mutation hardening

@Test func claudeCodeAdapterContinueSessionTerminatesOldProcess() async throws {
  let stubLauncher = StubProcessLauncher()
  let initialProcess = StubLaunchedProcess()
  let continuedProcess = StubLaunchedProcess()
  stubLauncher.setStubProcesses([initialProcess, continuedProcess])

  let adapter = ClaudeCodeAdapter(config: .defaults, processLauncher: stubLauncher)
  _ = try await adapter.startSession(
    sessionID: SessionID("s1"),
    workspacePath: "/tmp",
    prompt: "fix",
    environment: [:]
  )

  // Verify old process is NOT yet terminated
  #expect(initialProcess.terminationCount == 0)

  _ = try await adapter.continueSession(
    sessionID: SessionID("s1"),
    guidance: "keep going"
  )

  // The old process MUST be terminated during continueSession
  #expect(initialProcess.terminationCount == 1)
}

@Test func claudeCodeAdapterStartSessionIncludesStreamJsonFlag() async throws {
  let stubLauncher = StubProcessLauncher()
  stubLauncher.setStubProcess(StubLaunchedProcess())

  let adapter = ClaudeCodeAdapter(config: .defaults, processLauncher: stubLauncher)
  _ = try await adapter.startSession(
    sessionID: SessionID("s-flag"),
    workspacePath: "/tmp",
    prompt: "test",
    environment: [:]
  )

  #expect(stubLauncher.invocations[0].command.contains("-p"))
  #expect(stubLauncher.invocations[0].command.contains("--output-format stream-json"))
}

@Test func claudeCodeAdapterContinueSessionIncludesContinueFlag() async throws {
  let stubLauncher = StubProcessLauncher()
  let p1 = StubLaunchedProcess()
  let p2 = StubLaunchedProcess()
  stubLauncher.setStubProcesses([p1, p2])

  let adapter = ClaudeCodeAdapter(config: .defaults, processLauncher: stubLauncher)
  _ = try await adapter.startSession(
    sessionID: SessionID("s-cont"),
    workspacePath: "/tmp",
    prompt: "fix",
    environment: [:]
  )

  _ = try await adapter.continueSession(
    sessionID: SessionID("s-cont"),
    guidance: "more"
  )

  #expect(stubLauncher.invocations[1].command.contains("--continue"))
  #expect(stubLauncher.invocations[1].command.contains("-p"))
  #expect(stubLauncher.invocations[1].command.contains("--output-format stream-json"))
}

@Test func claudeCodeAdapterEventStreamUsesClaudeCodeProviderName() async throws {
  let stubProcess = StubLaunchedProcess()
  let adapter = ClaudeCodeAdapter(config: .defaults)

  let stream = adapter.makeEventStream(from: stubProcess, sessionID: SessionID("s-prov"))
  stubProcess.simulateOutput("{\"type\":\"text\",\"content\":\"hi\"}\n")
  stubProcess.simulateTermination(exitCode: 0)

  var events: [AgentRawEvent] = []
  for try await event in stream {
    events.append(event)
  }
  #expect(events.count == 1)
  #expect(events[0].provider == "claude_code")
}

@Test func claudeCodeAdapterEventStreamSequenceIncrements() async throws {
  let stubProcess = StubLaunchedProcess()
  let adapter = ClaudeCodeAdapter(config: .defaults)

  let stream = adapter.makeEventStream(from: stubProcess, sessionID: SessionID("s-seq"))
  stubProcess.simulateOutput("{\"type\":\"text\"}\n")
  stubProcess.simulateOutput("{\"type\":\"text\"}\n")
  stubProcess.simulateOutput("{\"type\":\"text\"}\n")
  stubProcess.simulateTermination(exitCode: 0)

  var events: [AgentRawEvent] = []
  for try await event in stream {
    events.append(event)
  }

  #expect(events.count == 3)
  #expect(events[0].sequence == EventSequence(0))
  #expect(events[1].sequence == EventSequence(1))
  #expect(events[2].sequence == EventSequence(2))
}

@Test func claudeCodeAdapterTerminalEventStopsStream() async throws {
  let stubProcess = StubLaunchedProcess()
  let adapter = ClaudeCodeAdapter(config: .defaults)

  let stream = adapter.makeEventStream(from: stubProcess, sessionID: SessionID("s-term"))
  // "result" type is terminal for claudeCode
  stubProcess.simulateOutput("{\"type\":\"result\"}\n")
  stubProcess.simulateOutput("{\"type\":\"text\"}\n")
  stubProcess.simulateTermination(exitCode: 0)

  var events: [AgentRawEvent] = []
  for try await event in stream {
    events.append(event)
  }

  // Only the terminal event, not the one after
  #expect(events.count == 1)
  #expect(events[0].providerEventType == "result")
}

@Test func claudeCodeAdapterNonZeroExitThrowsProviderError() async throws {
  let stubProcess = StubLaunchedProcess()
  let adapter = ClaudeCodeAdapter(config: .defaults)

  let stream = adapter.makeEventStream(from: stubProcess, sessionID: SessionID("s-exit"))
  stubProcess.simulateTermination(exitCode: 1)

  do {
    for try await _ in stream {}
    Issue.record("Should have thrown")
  } catch let error as ProviderAdapterError {
    if case .processExitedUnexpectedly(let exitCode) = error {
      #expect(exitCode == 1)
    } else {
      Issue.record("Wrong error type: \(error)")
    }
  }
}
