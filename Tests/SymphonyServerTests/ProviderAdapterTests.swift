import Foundation
import SymphonyShared
import Synchronization
import Testing

@testable import SymphonyRuntime

// MARK: - ProviderAdapterError Tests

@Test func providerAdapterErrorEquatable() {
  #expect(ProviderAdapterError.processLaunchFailed("x") == .processLaunchFailed("x"))
  #expect(ProviderAdapterError.processLaunchFailed("x") != .processLaunchFailed("y"))
  #expect(ProviderAdapterError.sessionNotFound(SessionID("a")) == .sessionNotFound(SessionID("a")))
  #expect(
    ProviderAdapterError.processExitedUnexpectedly(exitCode: 1)
      == .processExitedUnexpectedly(exitCode: 1))
  #expect(
    ProviderAdapterError.processExitedUnexpectedly(exitCode: 1)
      != .processExitedUnexpectedly(exitCode: 2))
  #expect(
    ProviderAdapterError.stallDetected(sessionID: SessionID("s"), stallTimeoutMS: 100)
      == .stallDetected(sessionID: SessionID("s"), stallTimeoutMS: 100))
  #expect(
    ProviderAdapterError.turnTimeout(sessionID: SessionID("s"), turnTimeoutMS: 200)
      == .turnTimeout(sessionID: SessionID("s"), turnTimeoutMS: 200))
  #expect(ProviderAdapterError.unsupportedProvider(.codex) == .unsupportedProvider(.codex))
}

// MARK: - ProviderSessionMetadata Tests

@Test func providerSessionMetadataInit() {
  let meta = ProviderSessionMetadata(
    sessionID: SessionID("s1"),
    provider: .codex,
    providerSessionID: "ps1",
    providerThreadID: "pt1",
    providerTurnID: "ptu1",
    providerRunID: "pr1"
  )
  #expect(meta.sessionID == SessionID("s1"))
  #expect(meta.provider == .codex)
  #expect(meta.providerSessionID == "ps1")
  #expect(meta.providerThreadID == "pt1")
  #expect(meta.providerTurnID == "ptu1")
  #expect(meta.providerRunID == "pr1")
}

@Test func providerSessionMetadataDefaultNils() {
  let meta = ProviderSessionMetadata(sessionID: SessionID("s1"), provider: .claudeCode)
  #expect(meta.providerSessionID == nil)
  #expect(meta.providerThreadID == nil)
  #expect(meta.providerTurnID == nil)
  #expect(meta.providerRunID == nil)
}

@Test func providerSessionMetadataEquatable() {
  let a = ProviderSessionMetadata(sessionID: SessionID("s1"), provider: .codex)
  let b = ProviderSessionMetadata(sessionID: SessionID("s1"), provider: .codex)
  let c = ProviderSessionMetadata(sessionID: SessionID("s2"), provider: .codex)
  #expect(a == b)
  #expect(a != c)
}

// MARK: - CodexAdapter Tests

@Test func codexAdapterCapabilities() {
  let adapter = CodexAdapter(config: .defaults)
  #expect(adapter.providerName == .codex)
  #expect(adapter.capabilities.supportsInterrupt)
  #expect(adapter.capabilities.supportsUsageTotals)
  #expect(adapter.capabilities.supportsExplicitApprovals)
  #expect(adapter.capabilities.supportsStructuredToolEvents)
  #expect(adapter.capabilities.toolExecutionMode == .mixed)
  #expect(!adapter.capabilities.supportsResume)
  #expect(!adapter.capabilities.supportsRateLimits)
}

@Test func codexAdapterStartSession() async throws {
  let stubLauncher = StubProcessLauncher()
  let stubProcess = StubLaunchedProcess()
  stubLauncher.setStubProcess(stubProcess)

  let adapter = CodexAdapter(config: .defaults, processLauncher: stubLauncher)
  let stream = try await adapter.startSession(
    sessionID: SessionID("s1"),
    workspacePath: "/tmp/workspace",
    prompt: "Fix the bug",
    environment: [:]
  )

  #expect(stubLauncher.invocations.count == 1)
  #expect(stubLauncher.invocations[0].command == "codex app-server")
  #expect(stubLauncher.invocations[0].workspacePath == "/tmp/workspace")
  _ = stream
}

@Test func codexAdapterContinueSessionThrows() async {
  let adapter = CodexAdapter(config: .defaults)
  do {
    _ = try await adapter.continueSession(sessionID: SessionID("s1"), guidance: "continue")
    #expect(Bool(false), "Should have thrown")
  } catch {
    #expect(error is ProviderAdapterError)
  }
}

@Test func codexAdapterCancelSessionThrowsWhenNoSession() async {
  let adapter = CodexAdapter(config: .defaults)
  do {
    try await adapter.cancelSession(sessionID: SessionID("s1"))
    #expect(Bool(false), "Should have thrown")
  } catch {
    #expect(error is ProviderAdapterError)
  }
}

@Test func codexAdapterMakeEventStream() async throws {
  let stubProcess = StubLaunchedProcess()
  let adapter = CodexAdapter(config: .defaults)

  let stream = adapter.makeEventStream(from: stubProcess, sessionID: SessionID("s1"))

  // Simulate output
  stubProcess.simulateOutput("{\"type\": \"message\"}\n")
  stubProcess.simulateTermination(exitCode: 0)

  var events: [AgentRawEvent] = []
  for try await event in stream {
    events.append(event)
  }
  #expect(events.count == 1)
  #expect(events[0].provider == "codex")
  #expect(events[0].providerEventType == "codex_event")
  #expect(events[0].normalizedKind == .message)
  #expect(events[0].sequence == EventSequence(0))
}

@Test func codexAdapterMakeEventStreamFailure() async throws {
  let stubProcess = StubLaunchedProcess()
  let adapter = CodexAdapter(config: .defaults)

  let stream = adapter.makeEventStream(from: stubProcess, sessionID: SessionID("s1"))

  stubProcess.simulateTermination(exitCode: 1)

  var caughtError: Error?
  do {
    for try await _ in stream {}
  } catch {
    caughtError = error
  }
  #expect(caughtError != nil)
}

// MARK: - ClaudeCodeAdapter Tests

@Test func claudeCodeAdapterCapabilities() {
  let adapter = ClaudeCodeAdapter(config: .defaults)
  #expect(adapter.providerName == .claudeCode)
  #expect(adapter.capabilities.supportsResume)
  #expect(adapter.capabilities.supportsUsageTotals)
  #expect(adapter.capabilities.supportsStructuredToolEvents)
  #expect(adapter.capabilities.toolExecutionMode == .providerManaged)
  #expect(!adapter.capabilities.supportsInterrupt)
  #expect(!adapter.capabilities.supportsRateLimits)
  #expect(!adapter.capabilities.supportsExplicitApprovals)
}

@Test func claudeCodeAdapterStartSession() async throws {
  let stubLauncher = StubProcessLauncher()
  let stubProcess = StubLaunchedProcess()
  stubLauncher.setStubProcess(stubProcess)

  let adapter = ClaudeCodeAdapter(config: .defaults, processLauncher: stubLauncher)
  _ = try await adapter.startSession(
    sessionID: SessionID("s1"),
    workspacePath: "/tmp/ws",
    prompt: "fix",
    environment: [:]
  )

  #expect(stubLauncher.invocations.count == 1)
  #expect(stubLauncher.invocations[0].command.contains("claude"))
  #expect(stubLauncher.invocations[0].command.contains("-p --output-format stream-json"))
}

@Test func claudeCodeAdapterStartSessionWithPermissionMode() async throws {
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

  #expect(stubLauncher.invocations[0].command.contains("--permission-mode auto"))
}

@Test func claudeCodeAdapterContinueSessionThrowsWhenNoSession() async {
  let adapter = ClaudeCodeAdapter(config: .defaults)
  do {
    _ = try await adapter.continueSession(sessionID: SessionID("s1"), guidance: "continue")
    #expect(Bool(false), "Should have thrown")
  } catch {
    #expect(error is ProviderAdapterError)
  }
}

@Test func claudeCodeAdapterCancelSessionThrowsWhenNoSession() async {
  let adapter = ClaudeCodeAdapter(config: .defaults)
  do {
    try await adapter.cancelSession(sessionID: SessionID("s1"))
    #expect(Bool(false), "Should have thrown")
  } catch {
    #expect(error is ProviderAdapterError)
  }
}

@Test func claudeCodeAdapterMakeEventStream() async throws {
  let stubProcess = StubLaunchedProcess()
  let adapter = ClaudeCodeAdapter(config: .defaults)

  let stream = adapter.makeEventStream(from: stubProcess, sessionID: SessionID("s2"))
  stubProcess.simulateOutput("{\"type\": \"text\"}\n")
  stubProcess.simulateTermination(exitCode: 0)

  var events: [AgentRawEvent] = []
  for try await event in stream {
    events.append(event)
  }
  #expect(events.count == 1)
  #expect(events[0].provider == "claude_code")
  #expect(events[0].providerEventType == "stream_json")
}

// MARK: - CopilotCLIAdapter Tests

@Test func copilotCLIAdapterCapabilities() {
  let adapter = CopilotCLIAdapter(config: .defaults)
  #expect(adapter.providerName == .copilotCLI)
  #expect(!adapter.capabilities.supportsResume)
  #expect(!adapter.capabilities.supportsInterrupt)
  #expect(!adapter.capabilities.supportsUsageTotals)
  #expect(!adapter.capabilities.supportsRateLimits)
  #expect(!adapter.capabilities.supportsExplicitApprovals)
  #expect(!adapter.capabilities.supportsStructuredToolEvents)
  #expect(adapter.capabilities.toolExecutionMode == .providerManaged)
}

@Test func copilotCLIAdapterStartSession() async throws {
  let stubLauncher = StubProcessLauncher()
  let stubProcess = StubLaunchedProcess()
  stubLauncher.setStubProcess(stubProcess)

  let adapter = CopilotCLIAdapter(config: .defaults, processLauncher: stubLauncher)
  _ = try await adapter.startSession(
    sessionID: SessionID("s1"),
    workspacePath: "/tmp/ws",
    prompt: "fix",
    environment: [:]
  )

  #expect(stubLauncher.invocations.count == 1)
  #expect(stubLauncher.invocations[0].command == "copilot --acp --stdio")
}

@Test func copilotCLIAdapterContinueSessionThrows() async {
  let adapter = CopilotCLIAdapter(config: .defaults)
  do {
    _ = try await adapter.continueSession(sessionID: SessionID("s1"), guidance: "continue")
    #expect(Bool(false), "Should have thrown")
  } catch {
    #expect(error is ProviderAdapterError)
  }
}

@Test func copilotCLIAdapterCancelSessionThrowsWhenNoSession() async {
  let adapter = CopilotCLIAdapter(config: .defaults)
  do {
    try await adapter.cancelSession(sessionID: SessionID("s1"))
    #expect(Bool(false), "Should have thrown")
  } catch {
    #expect(error is ProviderAdapterError)
  }
}

@Test func copilotCLIAdapterMakeEventStream() async throws {
  let stubProcess = StubLaunchedProcess()
  let adapter = CopilotCLIAdapter(config: .defaults)

  let stream = adapter.makeEventStream(from: stubProcess, sessionID: SessionID("s3"))
  stubProcess.simulateOutput("{\"event\": \"update\"}\n")
  stubProcess.simulateTermination(exitCode: 0)

  var events: [AgentRawEvent] = []
  for try await event in stream {
    events.append(event)
  }
  #expect(events.count == 1)
  #expect(events[0].provider == "copilot_cli")
  #expect(events[0].providerEventType == "acp_event")
}

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

// MARK: - Event Kind Inference Tests

@Test func eventKindInferenceCodexMessage() {
  let kind = EventKindInference.infer(from: "{\"type\": \"message\"}", provider: .codex)
  #expect(kind == .message)
}

@Test func eventKindInferenceCodexToolCall() {
  let kind = EventKindInference.infer(from: "{\"type\": \"tool_call\"}", provider: .codex)
  #expect(kind == .toolCall)
}

@Test func eventKindInferenceCodexToolResult() {
  let kind = EventKindInference.infer(from: "{\"type\": \"tool_result\"}", provider: .codex)
  #expect(kind == .toolResult)
}

@Test func eventKindInferenceCodexStatus() {
  let kind = EventKindInference.infer(from: "{\"type\": \"status\"}", provider: .codex)
  #expect(kind == .status)
}

@Test func eventKindInferenceCodexUsage() {
  let kind = EventKindInference.infer(from: "{\"type\": \"usage\"}", provider: .codex)
  #expect(kind == .usage)
}

@Test func eventKindInferenceCodexApprovalRequest() {
  let kind = EventKindInference.infer(from: "{\"type\": \"approval_request\"}", provider: .codex)
  #expect(kind == .approvalRequest)
}

@Test func eventKindInferenceCodexError() {
  let kind = EventKindInference.infer(from: "{\"type\": \"error\"}", provider: .codex)
  #expect(kind == .error)
}

@Test func eventKindInferenceCodexUnknown() {
  let kind = EventKindInference.infer(from: "{\"type\": \"custom_thing\"}", provider: .codex)
  #expect(kind == .unknown)
}

@Test func eventKindInferenceCodexText() {
  let kind = EventKindInference.infer(from: "{\"type\": \"text\"}", provider: .codex)
  #expect(kind == .message)
}

@Test func eventKindInferenceClaudeAssistant() {
  let kind = EventKindInference.infer(from: "{\"type\": \"assistant\"}", provider: .claudeCode)
  #expect(kind == .message)
}

@Test func eventKindInferenceClaudeText() {
  let kind = EventKindInference.infer(from: "{\"type\": \"text\"}", provider: .claudeCode)
  #expect(kind == .message)
}

@Test func eventKindInferenceClaudeMessage() {
  let kind = EventKindInference.infer(from: "{\"type\": \"message\"}", provider: .claudeCode)
  #expect(kind == .message)
}

@Test func eventKindInferenceClaudeResult() {
  let kind = EventKindInference.infer(from: "{\"type\": \"result\"}", provider: .claudeCode)
  #expect(kind == .message)
}

@Test func eventKindInferenceClaudeToolUse() {
  let kind = EventKindInference.infer(from: "{\"type\": \"tool_use\"}", provider: .claudeCode)
  #expect(kind == .toolCall)
}

@Test func eventKindInferenceClaudeToolResult() {
  let kind = EventKindInference.infer(from: "{\"type\": \"tool_result\"}", provider: .claudeCode)
  #expect(kind == .toolResult)
}

@Test func eventKindInferenceClaudeSystem() {
  let kind = EventKindInference.infer(from: "{\"type\": \"system\"}", provider: .claudeCode)
  #expect(kind == .status)
}

@Test func eventKindInferenceClaudeStatus() {
  let kind = EventKindInference.infer(from: "{\"type\": \"status\"}", provider: .claudeCode)
  #expect(kind == .status)
}

@Test func eventKindInferenceClaudeUsage() {
  let kind = EventKindInference.infer(from: "{\"type\": \"usage\"}", provider: .claudeCode)
  #expect(kind == .usage)
}

@Test func eventKindInferenceClaudeError() {
  let kind = EventKindInference.infer(from: "{\"type\": \"error\"}", provider: .claudeCode)
  #expect(kind == .error)
}

@Test func eventKindInferenceClaudeUnknown() {
  let kind = EventKindInference.infer(from: "{\"type\": \"custom\"}", provider: .claudeCode)
  #expect(kind == .unknown)
}

@Test func eventKindInferenceCopilotMessage() {
  let kind = EventKindInference.infer(from: "{\"type\": \"message\"}", provider: .copilotCLI)
  #expect(kind == .message)
}

@Test func eventKindInferenceCopilotUpdate() {
  let kind = EventKindInference.infer(from: "{\"type\": \"update\"}", provider: .copilotCLI)
  #expect(kind == .message)
}

@Test func eventKindInferenceCopilotText() {
  let kind = EventKindInference.infer(from: "{\"type\": \"text\"}", provider: .copilotCLI)
  #expect(kind == .message)
}

@Test func eventKindInferenceCopilotEventFallback() {
  let kind = EventKindInference.infer(from: "{\"event\": \"status\"}", provider: .copilotCLI)
  #expect(kind == .status)
}

@Test func eventKindInferenceCopilotToolCall() {
  let kind = EventKindInference.infer(from: "{\"type\": \"tool_call\"}", provider: .copilotCLI)
  #expect(kind == .toolCall)
}

@Test func eventKindInferenceCopilotToolResult() {
  let kind = EventKindInference.infer(from: "{\"type\": \"tool_result\"}", provider: .copilotCLI)
  #expect(kind == .toolResult)
}

@Test func eventKindInferenceCopilotUsage() {
  let kind = EventKindInference.infer(from: "{\"type\": \"usage\"}", provider: .copilotCLI)
  #expect(kind == .usage)
}

@Test func eventKindInferenceCopilotError() {
  let kind = EventKindInference.infer(from: "{\"type\": \"error\"}", provider: .copilotCLI)
  #expect(kind == .error)
}

@Test func eventKindInferenceCopilotUnknown() {
  let kind = EventKindInference.infer(from: "{\"type\": \"custom\"}", provider: .copilotCLI)
  #expect(kind == .unknown)
}

@Test func eventKindInferenceInvalidJSON() {
  let kind = EventKindInference.infer(from: "not json", provider: .codex)
  #expect(kind == .unknown)
}

@Test func eventKindInferenceMissingType() {
  let kind = EventKindInference.infer(from: "{\"data\": \"hello\"}", provider: .codex)
  #expect(kind == .unknown)
}

@Test func eventKindInferenceMissingTypeClaudeCode() {
  let kind = EventKindInference.infer(from: "{\"data\": \"hello\"}", provider: .claudeCode)
  #expect(kind == .unknown)
}

@Test func eventKindInferenceMissingTypeCopilot() {
  let kind = EventKindInference.infer(from: "{\"data\": \"hello\"}", provider: .copilotCLI)
  #expect(kind == .unknown)
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
  let stubProcess = StubLaunchedProcess()
  stubLauncher.setStubProcess(stubProcess)

  let adapter = ClaudeCodeAdapter(config: .defaults, processLauncher: stubLauncher)
  _ = try await adapter.startSession(
    sessionID: SessionID("s1"),
    workspacePath: "/tmp/ws",
    prompt: "fix",
    environment: [:]
  )

  #expect(stubLauncher.invocations.count == 1)

  _ = try await adapter.continueSession(
    sessionID: SessionID("s1"),
    guidance: "keep going"
  )

  #expect(stubLauncher.invocations.count == 2)
  #expect(stubLauncher.invocations[1].command.contains("--continue"))
  #expect(stubLauncher.invocations[1].command.contains("-p --output-format stream-json"))
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
