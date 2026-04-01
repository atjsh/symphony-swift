import Foundation
import SymphonyShared
import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore

// MARK: - CodexAdapter Policy and Stream Tests

@Test func codexAdapterMapsApprovalAndSandboxPoliciesIntoCurrentProtocol() async throws {
  let stubLauncher = StubProcessLauncher()
  let stubProcess = StubLaunchedProcess()
  stubLauncher.setStubProcess(stubProcess)

  let config = CodexProviderConfig(
    sessionApprovalPolicy: "never",
    sessionSandbox: "workspace-write",
    turnApprovalPolicy: "never",
    turnSandboxPolicy: "danger-full-access"
  )
  let adapter = CodexAdapter(config: config, processLauncher: stubLauncher)
  _ = try await adapter.startSession(
    sessionID: SessionID("s-config"),
    workspacePath: "/tmp/workspace",
    prompt: "Fix the bug",
    environment: [:]
  )

  stubProcess.simulateOutput(#"{"id":2,"result":{"thread":{"id":"thread-config"}}}"# + "\n")

  let recordedMessages = try stubProcess.recordedInputStrings.map(parseJSONObject)
  let threadStart = try #require(recordedMessages.dropFirst(2).first)
  let threadStartParams = try #require(threadStart["params"] as? [String: Any])
  #expect(threadStartParams["approvalPolicy"] as? String == "never")
  #expect(threadStartParams["sandbox"] as? String == "workspace-write")

  let turnStart = try #require(recordedMessages.last)
  let turnStartParams = try #require(turnStart["params"] as? [String: Any])
  #expect(turnStartParams["approvalPolicy"] as? String == "never")
  #expect(turnStartParams["sandboxPolicy"] as? String == "danger-full-access")
}

@Test func codexAdapterMapsObjectShapedSandboxPoliciesIntoCurrentProtocol() async throws {
  let stubLauncher = StubProcessLauncher()
  let stubProcess = StubLaunchedProcess()
  stubLauncher.setStubProcess(stubProcess)

  let config = CodexProviderConfig(
    sessionSandbox: [
      "mode": "workspace-write",
      "network_access": false,
    ],
    turnSandboxPolicy: [
      "mode": "danger-full-access",
      "writable_roots": ["/tmp/output"],
    ]
  )
  let adapter = CodexAdapter(config: config, processLauncher: stubLauncher)
  _ = try await adapter.startSession(
    sessionID: SessionID("s-object-config"),
    workspacePath: "/tmp/workspace",
    prompt: "Fix the bug",
    environment: [:]
  )

  stubProcess.simulateOutput(#"{"id":2,"result":{"thread":{"id":"thread-object-config"}}}"# + "\n")

  let recordedMessages = try stubProcess.recordedInputStrings.map(parseJSONObject)
  let threadStart = try #require(recordedMessages.dropFirst(2).first)
  let threadStartParams = try #require(threadStart["params"] as? [String: Any])
  let threadSandbox = try #require(threadStartParams["sandbox"] as? [String: Any])
  #expect(threadSandbox["mode"] as? String == "workspace-write")
  #expect(threadSandbox["network_access"] as? Bool == false)

  let turnStart = try #require(recordedMessages.last)
  let turnStartParams = try #require(turnStart["params"] as? [String: Any])
  let turnSandbox = try #require(turnStartParams["sandboxPolicy"] as? [String: Any])
  #expect(turnSandbox["mode"] as? String == "danger-full-access")
  #expect(turnSandbox["writable_roots"] as? [String] == ["/tmp/output"])
}

@Test func codexAdapterReadTimeoutFailsStream() async throws {
  let stubLauncher = StubProcessLauncher()
  let stubProcess = StubLaunchedProcess()
  stubLauncher.setStubProcess(stubProcess)

  let config = CodexProviderConfig(turnTimeoutMS: 5_000, readTimeoutMS: 50)
  let adapter = CodexAdapter(config: config, processLauncher: stubLauncher)
  let stream = try await adapter.startSession(
    sessionID: SessionID("s-read-timeout"),
    issue: try makeIssue(title: "Read timeout"),
    workspacePath: "/tmp/workspace",
    prompt: "Fix the bug",
    environment: [:]
  )

  let errorCapture = ErrorCapture()
  let consumer = Task { @Sendable in
    do {
      for try await _ in stream {}
    } catch {
      errorCapture.record(error)
    }
  }

  let recordedError = await waitForRecordedError(errorCapture)
  consumer.cancel()
  _ = await consumer.result

  let timeoutError = try #require(recordedError as? ProviderAdapterError)
  #expect(timeoutError == .readTimeout(sessionID: SessionID("s-read-timeout"), readTimeoutMS: 50))
}

@Test func codexAdapterTurnTimeoutFailsStream() async throws {
  let stubLauncher = StubProcessLauncher()
  let stubProcess = StubLaunchedProcess()
  stubLauncher.setStubProcess(stubProcess)

  let config = CodexProviderConfig(turnTimeoutMS: 50, readTimeoutMS: 5_000)
  let adapter = CodexAdapter(config: config, processLauncher: stubLauncher)
  let stream = try await adapter.startSession(
    sessionID: SessionID("s-turn-timeout"),
    issue: try makeIssue(title: "Turn timeout"),
    workspacePath: "/tmp/workspace",
    prompt: "Fix the bug",
    environment: [:]
  )

  stubProcess.simulateOutput(
    #"{"method":"thread/started","params":{"thread":{"id":"thread-timeout"}}}"# + "\n")

  let errorCapture = ErrorCapture()
  let consumer = Task { @Sendable in
    do {
      for try await _ in stream {}
    } catch {
      errorCapture.record(error)
    }
  }

  let recordedError = await waitForRecordedError(errorCapture)
  consumer.cancel()
  _ = await consumer.result

  let timeoutError = try #require(recordedError as? ProviderAdapterError)
  #expect(timeoutError == .turnTimeout(sessionID: SessionID("s-turn-timeout"), turnTimeoutMS: 50))
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
  #expect(events[0].providerEventType == "message")
  #expect(events[0].normalizedKind == .message)
  #expect(events[0].sequence == EventSequence(0))
}

@Test func codexAdapterBuffersPartialStdoutLinesBeforeParsing() async throws {
  let stubProcess = StubLaunchedProcess()
  let adapter = CodexAdapter(config: .defaults)

  let stream = adapter.makeEventStream(from: stubProcess, sessionID: SessionID("s-buffer"))
  stubProcess.simulateOutput(#"{"type":"mes"#)
  stubProcess.simulateOutput(#"sage"}"# + "\n")
  stubProcess.simulateTermination(exitCode: 0)

  var events: [AgentRawEvent] = []
  for try await event in stream {
    events.append(event)
  }

  #expect(events.count == 1)
  #expect(events[0].providerEventType == "message")
  #expect(events[0].normalizedKind == .message)
}

@Test func codexAdapterProcessesBufferedTerminationLineWithoutTrailingNewline() async throws {
  let stubProcess = StubLaunchedProcess()
  let adapter = CodexAdapter(config: .defaults)

  let stream = adapter.makeEventStream(from: stubProcess, sessionID: SessionID("s-buffered-exit"))
  stubProcess.simulateOutput(#"{"type":"message","content":"tail"}"#)
  stubProcess.simulateTermination(exitCode: 0)

  var events: [AgentRawEvent] = []
  for try await event in stream {
    events.append(event)
  }

  #expect(events.count == 1)
  #expect(events[0].providerEventType == "message")
  #expect(events[0].normalizedKind == .message)
}

@Test func codexAdapterMakeEventStreamSuppressesSuccessfulJSONRPCResponses() async throws {
  let stubProcess = StubLaunchedProcess()
  let adapter = CodexAdapter(config: .defaults)

  let stream = adapter.makeEventStream(from: stubProcess, sessionID: SessionID("s-suppress"))

  stubProcess.simulateOutput(
    #"{"id":1,"result":{"userAgent":"ua","platformFamily":"unix","platformOs":"macos"}}"# + "\n")
  stubProcess.simulateOutput(#"{"id":2,"result":{"thread":{"id":"thread-1"}}}"# + "\n")
  stubProcess.simulateOutput(
    #"{"method":"thread/started","params":{"thread":{"id":"thread-1"}}}"# + "\n")
  stubProcess.simulateOutput(#"{"id":3,"result":{"turn":{"id":"turn-1"}}}"# + "\n")
  stubProcess.simulateOutput(
    #"{"method":"turn/started","params":{"threadId":"thread-1","turn":{"id":"turn-1"}}}"#
      + "\n")
  stubProcess.simulateTermination(exitCode: 0)

  var events: [AgentRawEvent] = []
  for try await event in stream {
    events.append(event)
  }

  #expect(events.map(\.providerEventType) == ["thread/started", "turn/started"])
  #expect(events.allSatisfy { $0.normalizedKind == .status })
}

@Test func codexAdapterTurnCompletedStopsStreamingFurtherEvents() async throws {
  let stubProcess = StubLaunchedProcess()
  let adapter = CodexAdapter(config: .defaults)

  let stream = adapter.makeEventStream(from: stubProcess, sessionID: SessionID("s-turn"))

  stubProcess.simulateOutput("{\"method\":\"turn/completed\",\"params\":{\"turn_id\":\"t1\"}}\n")
  stubProcess.simulateOutput("{\"type\":\"message\",\"content\":\"late\"}\n")
  stubProcess.simulateTermination(exitCode: 0)

  var events: [AgentRawEvent] = []
  for try await event in stream {
    events.append(event)
  }

  #expect(events.count == 1)
  #expect(events[0].providerEventType == "turn/completed")
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
  #expect(stubLauncher.invocations[0].workspacePath == "/tmp/ws")
  #expect(stubProcess.recordedInputStrings == ["fix"])
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

@Test func claudeCodeAdapterStartSessionFailsWhenPromptSubmissionFails() async {
  let stubLauncher = StubProcessLauncher()
  let stubProcess = StubLaunchedProcess()
  stubProcess.setInputError(ProviderAdapterError.processLaunchFailed("stdin failed"))
  stubLauncher.setStubProcess(stubProcess)

  let adapter = ClaudeCodeAdapter(config: .defaults, processLauncher: stubLauncher)

  await #expect(throws: ProviderAdapterError.self) {
    _ = try await adapter.startSession(
      sessionID: SessionID("s-fail"),
      workspacePath: "/tmp/ws",
      prompt: "fix",
      environment: [:]
    )
  }
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

@Test func claudeCodeAdapterInterruptSessionAlwaysReturnsFalse() async throws {
  let adapter = ClaudeCodeAdapter(config: .defaults)
  let interrupted = try await adapter.interruptSession(sessionID: SessionID("s-claude-interrupt"))
  #expect(interrupted == false)
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
  #expect(events[0].providerEventType == "text")
}

@Test func claudeCodeAdapterResultStopsStreamingFurtherEvents() async throws {
  let stubProcess = StubLaunchedProcess()
  let adapter = ClaudeCodeAdapter(config: .defaults)

  let stream = adapter.makeEventStream(from: stubProcess, sessionID: SessionID("s-result"))
  stubProcess.simulateOutput("{\"type\":\"result\",\"content\":\"done\"}\n")
  stubProcess.simulateOutput("{\"type\":\"text\",\"content\":\"late\"}\n")
  stubProcess.simulateTermination(exitCode: 0)

  var events: [AgentRawEvent] = []
  for try await event in stream {
    events.append(event)
  }

  #expect(events.count == 1)
  #expect(events[0].providerEventType == "result")
}

@Test func claudeCodeAdapterInvalidJSONUsesUnknownEventDescriptor() async throws {
  let stubProcess = StubLaunchedProcess()
  let adapter = ClaudeCodeAdapter(config: .defaults)

  let stream = adapter.makeEventStream(from: stubProcess, sessionID: SessionID("s-invalid"))
  stubProcess.simulateOutput("not-json\n")
  stubProcess.simulateTermination(exitCode: 0)

  var events: [AgentRawEvent] = []
  for try await event in stream {
    events.append(event)
  }

  #expect(events.count == 1)
  #expect(events[0].providerEventType == "unknown")
  #expect(events[0].normalizedKind == .unknown)
}

@Test func claudeCodeAdapterMissingTypeUsesUnknownEventDescriptor() async throws {
  let stubProcess = StubLaunchedProcess()
  let adapter = ClaudeCodeAdapter(config: .defaults)

  let stream = adapter.makeEventStream(from: stubProcess, sessionID: SessionID("s-missing-type"))
  stubProcess.simulateOutput("{\"payload\":\"noop\"}\n")
  stubProcess.simulateTermination(exitCode: 0)

  var events: [AgentRawEvent] = []
  for try await event in stream {
    events.append(event)
  }

  #expect(events.count == 1)
  #expect(events[0].providerEventType == "unknown")
  #expect(events[0].normalizedKind == .unknown)
}
