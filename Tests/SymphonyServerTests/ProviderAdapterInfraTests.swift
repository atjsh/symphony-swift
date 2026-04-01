import Foundation
import SymphonyShared
import Synchronization
import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore

// MARK: - StubProcessLauncher Tests

@Test func stubProcessLauncherRecordsInvocations() throws {
  let launcher = StubProcessLauncher()
  let process = StubLaunchedProcess()
  launcher.setStubProcess(process)

  _ = try launcher.launch(command: "test", workspacePath: "/tmp", environment: [:])
  #expect(launcher.invocations.count == 1)
  #expect(launcher.invocations[0].command == "test")
}

@Test func stubProcessLauncherThrowsError() {
  let launcher = StubProcessLauncher()
  launcher.setLaunchError(ProviderAdapterError.processLaunchFailed("test error"))

  #expect(throws: ProviderAdapterError.self) {
    _ = try launcher.launch(command: "test", workspacePath: "/tmp", environment: [:])
  }
}

// MARK: - StubLaunchedProcess Tests

@Test func stubLaunchedProcessSimulateOutput() {
  let process = StubLaunchedProcess()
  let received = Mutex<[Data]>([])
  process.onOutput { data in received.withLock { $0.append(data) } }
  process.simulateOutput("hello")
  let result = received.withLock { $0 }
  #expect(result.count == 1)
  #expect(String(data: result[0], encoding: .utf8) == "hello")
}

@Test func stubLaunchedProcessSimulateTermination() {
  let process = StubLaunchedProcess()
  let captured = Mutex<Int32?>(nil)
  process.onTermination { code in captured.withLock { $0 = code } }
  process.simulateTermination(exitCode: 42)
  #expect(captured.withLock { $0 } == 42)
}

@Test func stubLaunchedProcessTerminate() {
  let process = StubLaunchedProcess()
  let captured = Mutex<[Int32]>([])
  process.onTermination { code in captured.withLock { $0.append(code) } }

  process.terminate()
  process.terminate()

  #expect(captured.withLock { $0 } == [15])
}

@Test func stubLaunchedProcessInterruptCountsOnceAndIgnoresAfterTermination() {
  let process = StubLaunchedProcess()

  process.interrupt()
  process.terminate()
  process.interrupt()

  #expect(process.interruptCount == 1)
  #expect(process.terminationCount == 1)
}

// MARK: - ProviderAdapterFactory Tests

@Test func providerAdapterFactoryCreatesCodex() {
  let adapter = ProviderAdapterFactory.makeAdapter(for: .codex, config: .defaults)
  #expect(adapter.providerName == .codex)
}

@Test func providerAdapterFactoryCreatesClaudeCode() {
  let adapter = ProviderAdapterFactory.makeAdapter(for: .claudeCode, config: .defaults)
  #expect(adapter.providerName == .claudeCode)
}

@Test func providerAdapterFactoryCreatesCopilotCLI() {
  let adapter = ProviderAdapterFactory.makeAdapter(for: .copilotCLI, config: .defaults)
  #expect(adapter.providerName == .copilotCLI)
}

@Test func providerAdapterFactoryWithCustomLauncher() {
  let launcher = StubProcessLauncher()
  let adapter = ProviderAdapterFactory.makeAdapter(
    for: .codex, config: .defaults, processLauncher: launcher)
  #expect(adapter.providerName == .codex)
}

// MARK: - ClaudeCode/CopilotCLI Stream Failure Tests

@Test func claudeCodeAdapterMakeEventStreamFailure() async throws {
  let stubProcess = StubLaunchedProcess()
  let adapter = ClaudeCodeAdapter(config: .defaults)

  let stream = adapter.makeEventStream(from: stubProcess, sessionID: SessionID("s2"))
  stubProcess.simulateTermination(exitCode: 1)

  var caughtError: Error?
  do {
    for try await _ in stream {}
  } catch {
    caughtError = error
  }
  #expect(caughtError != nil)
}

@Test func copilotCLIAdapterMakeEventStreamFailure() async throws {
  let stubProcess = StubLaunchedProcess()
  let adapter = CopilotCLIAdapter(config: .defaults)

  let stream = adapter.makeEventStream(from: stubProcess, sessionID: SessionID("s3"))
  stubProcess.simulateTermination(exitCode: 1)

  var caughtError: Error?
  do {
    for try await _ in stream {}
  } catch {
    caughtError = error
  }
  #expect(caughtError != nil)
}

// MARK: - DefaultProcessLauncher Tests

@Test func defaultProcessLauncherLaunchSuccess() throws {
  let launcher = DefaultProcessLauncher()
  let tmpDir = NSTemporaryDirectory()
  let process = try launcher.launch(
    command: "echo hello",
    workspacePath: tmpDir,
    environment: ["TEST_ENV_VAR": "1"]
  )

  let received = Mutex<[Data]>([])
  let terminated = Mutex<Int32?>(.none)
  process.onOutput { data in received.withLock { $0.append(data) } }
  process.onTermination { code in terminated.withLock { $0 = code } }

  // Wait for the process to terminate
  Thread.sleep(forTimeInterval: 1.0)

  #expect(terminated.withLock { $0 } == 0)
}

@Test func defaultProcessLauncherLaunchFailure() {
  let launcher = DefaultProcessLauncher()
  #expect(throws: ProviderAdapterError.self) {
    _ = try launcher.launch(
      command: "/nonexistent_binary_\(UUID().uuidString)",
      workspacePath: "/nonexistent_dir_\(UUID().uuidString)",
      environment: [:]
    )
  }
}

// MARK: - DefaultLaunchedProcess Tests

@Test func defaultLaunchedProcessTerminate() throws {
  let launcher = DefaultProcessLauncher()
  let tmpDir = NSTemporaryDirectory()
  let process = try launcher.launch(
    command: "sleep 60",
    workspacePath: tmpDir,
    environment: [:]
  )
  // Terminate should not crash
  process.terminate()
  Thread.sleep(forTimeInterval: 0.5)
}

@Test func defaultLaunchedProcessInterrupt() throws {
  let launcher = DefaultProcessLauncher()
  let tmpDir = NSTemporaryDirectory()
  let process = try launcher.launch(
    command: "sleep 60",
    workspacePath: tmpDir,
    environment: [:]
  )

  process.interrupt()
  Thread.sleep(forTimeInterval: 0.5)
}

@Test func defaultLaunchedProcessSendInputWritesToProcessStdin() throws {
  // Build a Process directly to avoid bash login-shell profile interference.
  let proc = Process()
  proc.executableURL = URL(fileURLWithPath: "/usr/bin/head")
  proc.arguments = ["-c", "3"]
  proc.currentDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory())

  let stdout = Pipe()
  let stdin = Pipe()
  proc.standardOutput = stdout
  proc.standardInput = stdin
  proc.standardError = FileHandle.nullDevice
  try proc.run()

  let process = DefaultLaunchedProcess(process: proc, stdoutPipe: stdout, stdinPipe: stdin)

  let received = Mutex<[Data]>([])
  let terminated = Mutex<Int32?>(nil)
  process.onOutput { data in received.withLock { $0.append(data) } }
  process.onTermination { code in terminated.withLock { $0 = code } }

  try process.sendInput(Data("abc".utf8))
  Thread.sleep(forTimeInterval: 0.5)

  if terminated.withLock({ $0 }) == nil {
    process.terminate()
    Thread.sleep(forTimeInterval: 0.2)
  }

  let output = received.withLock { data in
    data.compactMap { String(data: $0, encoding: .utf8) }.joined()
  }
  #expect(output.contains("abc"))
  #expect(terminated.withLock { $0 } == 0)
}

@Test func defaultProcessLauncherLaunchesCommand() throws {
  let launcher = DefaultProcessLauncher()
  let process = try launcher.launch(
    command: "echo ok",
    workspacePath: NSTemporaryDirectory(),
    environment: ["TEST_VAR": "1"]
  )
  let received = Mutex<[Data]>([])
  let terminated = Mutex<Int32?>(nil)
  process.onOutput { data in received.withLock { $0.append(data) } }
  process.onTermination { code in terminated.withLock { $0 = code } }
  // echo is fast — just wait for it
  Thread.sleep(forTimeInterval: 1.0)
  if terminated.withLock({ $0 }) == nil {
    process.terminate()
    Thread.sleep(forTimeInterval: 0.2)
  }
  let output = received.withLock { $0 }
    .compactMap { String(data: $0, encoding: .utf8) }
    .joined()
  #expect(output.contains("ok"))
  #expect(terminated.withLock { $0 } == 0)
}

// MARK: - Event Stream Empty Output Handling

@Test func codexAdapterEmptyOutputIgnored() async throws {
  let stubProcess = StubLaunchedProcess()
  let adapter = CodexAdapter(config: .defaults)

  let stream = adapter.makeEventStream(from: stubProcess, sessionID: SessionID("s1"))

  stubProcess.simulateOutput("")
  stubProcess.simulateOutput("   \n")
  stubProcess.simulateOutput("{\"valid\": true}\n")
  stubProcess.simulateTermination(exitCode: 0)

  var events: [AgentRawEvent] = []
  for try await event in stream {
    events.append(event)
  }
  // Empty and whitespace-only lines should be filtered
  #expect(events.count == 1)
}

// MARK: - SessionStore Tests

@Test func sessionStoreStoreAndRemove() {
  let store = SessionStore()
  let process = StubLaunchedProcess()
  let sid = SessionID("s1")

  store.store(sessionID: sid, process: process)
  #expect(store.count == 1)
  #expect(store.process(for: sid) != nil)

  let removed = store.remove(sessionID: sid)
  #expect(removed != nil)
  #expect(store.count == 0)
}

@Test func sessionStoreRemoveReturnsNilForUnknown() {
  let store = SessionStore()
  let result = store.remove(sessionID: SessionID("unknown"))
  #expect(result == nil)
}

@Test func sessionStoreProcessForUnknownID() {
  let store = SessionStore()
  #expect(store.process(for: SessionID("missing")) == nil)
}

// MARK: - SessionSequenceCounter Tests

@Test func sessionSequenceCounterIncrementsMonotonically() {
  let counter = SessionSequenceCounter()
  #expect(counter.next() == EventSequence(0))
  #expect(counter.next() == EventSequence(1))
  #expect(counter.next() == EventSequence(2))
}

// MARK: - Session Tracking Tests

@Test func codexAdapterCancelSessionTerminatesProcess() async throws {
  let stubLauncher = StubProcessLauncher()
  let stubProcess = StubLaunchedProcess()
  stubLauncher.setStubProcess(stubProcess)

  let adapter = CodexAdapter(config: .defaults, processLauncher: stubLauncher)
  _ = try await adapter.startSession(
    sessionID: SessionID("s1"),
    workspacePath: "/tmp",
    prompt: "test",
    environment: [:]
  )

  try await adapter.cancelSession(sessionID: SessionID("s1"))
  // Second cancel should throw sessionNotFound
  do {
    try await adapter.cancelSession(sessionID: SessionID("s1"))
    #expect(Bool(false), "Should have thrown")
  } catch {
    #expect(error is ProviderAdapterError)
  }
}

@Test func claudeCodeAdapterCancelSessionTerminatesProcess() async throws {
  let stubLauncher = StubProcessLauncher()
  let stubProcess = StubLaunchedProcess()
  stubLauncher.setStubProcess(stubProcess)

  let adapter = ClaudeCodeAdapter(config: .defaults, processLauncher: stubLauncher)
  _ = try await adapter.startSession(
    sessionID: SessionID("s1"),
    workspacePath: "/tmp",
    prompt: "test",
    environment: [:]
  )

  try await adapter.cancelSession(sessionID: SessionID("s1"))
  do {
    try await adapter.cancelSession(sessionID: SessionID("s1"))
    #expect(Bool(false), "Should have thrown")
  } catch {
    #expect(error is ProviderAdapterError)
  }
}

@Test func copilotCLIAdapterCancelSessionTerminatesProcess() async throws {
  let stubLauncher = StubProcessLauncher()
  let stubProcess = StubLaunchedProcess()
  stubLauncher.setStubProcess(stubProcess)

  let adapter = CopilotCLIAdapter(config: .defaults, processLauncher: stubLauncher)
  _ = try await adapter.startSession(
    sessionID: SessionID("s1"),
    workspacePath: "/tmp",
    prompt: "test",
    environment: [:]
  )

  try await adapter.cancelSession(sessionID: SessionID("s1"))
  do {
    try await adapter.cancelSession(sessionID: SessionID("s1"))
    #expect(Bool(false), "Should have thrown")
  } catch {
    #expect(error is ProviderAdapterError)
  }
}

// MARK: - Event Sequencing Tests

@Test func codexAdapterEventSequenceIncrementsPerEvent() async throws {
  let stubProcess = StubLaunchedProcess()
  let adapter = CodexAdapter(config: .defaults)

  let stream = adapter.makeEventStream(from: stubProcess, sessionID: SessionID("s1"))
  stubProcess.simulateOutput("{\"type\": \"message\"}\n")
  stubProcess.simulateOutput("{\"type\": \"tool_call\"}\n")
  stubProcess.simulateOutput("{\"type\": \"tool_result\"}\n")
  stubProcess.simulateTermination(exitCode: 0)

  var events: [AgentRawEvent] = []
  for try await event in stream {
    events.append(event)
  }
  #expect(events.count == 3)
  #expect(events[0].sequence == EventSequence(0))
  #expect(events[1].sequence == EventSequence(1))
  #expect(events[2].sequence == EventSequence(2))
  #expect(events[0].normalizedKind == .message)
  #expect(events[1].normalizedKind == .toolCall)
  #expect(events[2].normalizedKind == .toolResult)
}

// MARK: - Claude Code continueSession Tests

@Test func claudeCodeAdapterContinueSessionLaunchesNewProcess() async throws {
  let stubLauncher = StubProcessLauncher()
  let initialProcess = StubLaunchedProcess()
  let continuedProcess = StubLaunchedProcess()
  stubLauncher.setStubProcesses([initialProcess, continuedProcess])

  let adapter = ClaudeCodeAdapter(config: .defaults, processLauncher: stubLauncher)
  _ = try await adapter.startSession(
    sessionID: SessionID("s1"),
    workspacePath: "/tmp/ws",
    prompt: "fix",
    environment: ["ALPHA": "1"]
  )

  #expect(stubLauncher.invocations.count == 1)

  _ = try await adapter.continueSession(
    sessionID: SessionID("s1"),
    guidance: "keep going"
  )

  #expect(stubLauncher.invocations.count == 2)
  #expect(stubLauncher.invocations[1].command.contains("--continue"))
  #expect(stubLauncher.invocations[1].command.contains("-p --output-format stream-json"))
  #expect(stubLauncher.invocations[1].workspacePath == "/tmp/ws")
  #expect(stubLauncher.invocations[1].environment == ["ALPHA": "1"])
  #expect(continuedProcess.recordedInputStrings == ["keep going"])
}

@Test func claudeCodeAdapterContinueSessionWithPermissionMode() async throws {
  let stubLauncher = StubProcessLauncher()
  let stubProcess = StubLaunchedProcess()
  stubLauncher.setStubProcess(stubProcess)

  let config = ClaudeCodeProviderConfig(permissionMode: "auto")
  let adapter = ClaudeCodeAdapter(config: config, processLauncher: stubLauncher)
  _ = try await adapter.startSession(
    sessionID: SessionID("s1"),
    workspacePath: "/tmp/ws",
    prompt: "fix",
    environment: [:]
  )

  _ = try await adapter.continueSession(
    sessionID: SessionID("s1"),
    guidance: "keep going"
  )

  #expect(stubLauncher.invocations[1].command.contains("--permission-mode auto"))
  #expect(stubLauncher.invocations[1].command.contains("--continue"))
}
