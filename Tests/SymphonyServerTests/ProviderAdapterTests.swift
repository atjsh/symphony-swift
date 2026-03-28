import Foundation
import SymphonyShared
import Synchronization
import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore

private func makeIssue(
  id: String = "issue-1",
  owner: String = "org",
  repo: String = "repo",
  number: Int = 1,
  title: String = "Fix bug"
) throws -> SymphonyShared.Issue {
  SymphonyShared.Issue(
    id: IssueID(id),
    identifier: try IssueIdentifier(validating: "\(owner)/\(repo)#\(number)"),
    repository: "\(owner)/\(repo)",
    number: number,
    title: title,
    description: "Description",
    priority: nil,
    state: "In Progress",
    issueState: "OPEN",
    projectItemID: nil,
    url: "https://github.com/\(owner)/\(repo)/issues/\(number)",
    labels: [],
    blockedBy: [],
    createdAt: nil,
    updatedAt: nil
  )
}

private final class ErrorCapture: @unchecked Sendable {
  private let lock = NSLock()
  private var _error: Error?

  func record(_ error: Error) {
    lock.withLock { _error = error }
  }

  var value: Error? {
    lock.withLock { _error }
  }
}

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
  #expect(
    ProviderAdapterError.readTimeout(sessionID: SessionID("s"), readTimeoutMS: 300)
      == .readTimeout(sessionID: SessionID("s"), readTimeoutMS: 300))
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

@Test func codexEventInferenceAndInspectionCoverUnknownItemAndErrorBranches() {
  #expect(
    EventKindInference.inferCodex(
      method: "item/started",
      json: ["params": ["item": ["type": "reasoning"]]]
    ) == nil
  )
  #expect(
    ProviderEventInspection.eventType(
      from: ["error": ["message": "boom"]],
      provider: .codex
    ) == "error"
  )
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

  let recordedMessages = try stubProcess.recordedInputStrings.map(parseJSONObject)
  #expect(recordedMessages.count == 3)
  #expect(
    recordedMessages.map { $0["method"] as? String } == [
      "initialize",
      "initialized",
      "thread/start",
    ])

  let initialize = try #require(recordedMessages.first)
  let initializeParams = try #require(initialize["params"] as? [String: Any])
  let clientInfo = try #require(initializeParams["clientInfo"] as? [String: Any])
  #expect(clientInfo["name"] as? String == "symphony")
  #expect(clientInfo["version"] as? String == "0.0.1")

  let initialized = try #require(recordedMessages.dropFirst().first)
  #expect(initialized["params"] == nil)

  let threadStart = try #require(recordedMessages.last)
  let threadStartParams = try #require(threadStart["params"] as? [String: Any])
  #expect(threadStartParams["cwd"] as? String == "/tmp/workspace")
  #expect(threadStartParams["ephemeral"] as? Bool == true)
  _ = stream
}

@Test func codexAdapterStartSessionIncludesIssueTitleContext() async throws {
  let stubLauncher = StubProcessLauncher()
  let stubProcess = StubLaunchedProcess()
  stubLauncher.setStubProcess(stubProcess)

  let issue = try makeIssue(title: "Plumb the title")
  let adapter = CodexAdapter(config: .defaults, processLauncher: stubLauncher)
  _ = try await adapter.startSession(
    sessionID: SessionID("s-title"),
    issue: issue,
    workspacePath: "/tmp/workspace",
    prompt: "Fix the bug",
    environment: [:]
  )

  stubProcess.simulateOutput(
    #"{"method":"thread/started","params":{"thread":{"id":"thread-title"}}}"# + "\n")

  let recordedMessages = try stubProcess.recordedInputStrings.map(parseJSONObject)
  let turnStart = try #require(recordedMessages.last)
  let turnStartParams = try #require(turnStart["params"] as? [String: Any])
  #expect(turnStartParams["title"] as? String == "\(issue.identifier.rawValue): \(issue.title)")
}

@Test func codexAdapterStartSessionWithEmptyPromptDoesNotWriteInput() async throws {
  let stubLauncher = StubProcessLauncher()
  let stubProcess = StubLaunchedProcess()
  stubLauncher.setStubProcess(stubProcess)

  let adapter = CodexAdapter(config: .defaults, processLauncher: stubLauncher)
  _ = try await adapter.startSession(
    sessionID: SessionID("s-empty"),
    workspacePath: "/tmp/workspace",
    prompt: "",
    environment: [:]
  )

  stubProcess.simulateOutput(
    #"{"method":"thread/started","params":{"thread":{"id":"thread-empty"}}}"# + "\n")

  let recordedMessages = try stubProcess.recordedInputStrings.map(parseJSONObject)
  #expect(recordedMessages.count == 4)
  let turnStart = try #require(recordedMessages.last)
  let turnStartParams = try #require(turnStart["params"] as? [String: Any])
  #expect(turnStartParams["threadId"] as? String == "thread-empty")
  let textInput = try firstInputObject(from: turnStartParams)
  #expect(textInput["type"] as? String == "text")
  #expect(textInput["text"] as? String == "")
}

@Test func codexAdapterStartSessionFailsWhenPromptSubmissionFails() async {
  let stubLauncher = StubProcessLauncher()
  let stubProcess = StubLaunchedProcess()
  stubProcess.setInputError(ProviderAdapterError.processLaunchFailed("stdin failed"))
  stubLauncher.setStubProcess(stubProcess)

  let adapter = CodexAdapter(config: .defaults, processLauncher: stubLauncher)

  await #expect(throws: ProviderAdapterError.self) {
    _ = try await adapter.startSession(
      sessionID: SessionID("s-fail"),
      workspacePath: "/tmp/workspace",
      prompt: "Fix the bug",
      environment: [:]
    )
  }
}

@Test func codexAdapterContinueSessionReusesExistingThreadAndPreservesSequence() async throws {
  let stubLauncher = StubProcessLauncher()
  let stubProcess = StubLaunchedProcess()
  stubLauncher.setStubProcess(stubProcess)

  let adapter = CodexAdapter(config: .defaults, processLauncher: stubLauncher)
  let initialStream = try await adapter.startSession(
    sessionID: SessionID("s-live"),
    workspacePath: "/tmp/workspace",
    prompt: "Fix the bug",
    environment: [:]
  )
  _ = initialStream

  stubProcess.simulateOutput(
    #"{"method":"thread/started","params":{"thread":{"id":"thread-live"}}}"# + "\n")

  let recordedAfterStart = try stubProcess.recordedInputStrings.map(parseJSONObject)
  #expect(recordedAfterStart.count == 4)
  let initialTurnStart = try #require(recordedAfterStart.last)
  let initialTurnStartParams = try #require(initialTurnStart["params"] as? [String: Any])
  #expect(initialTurnStartParams["threadId"] as? String == "thread-live")

  let continuationStream = try await adapter.continueSession(
    sessionID: SessionID("s-live"),
    guidance: "keep going"
  )

  let recordedAfterContinuation = try stubProcess.recordedInputStrings.map(parseJSONObject)
  #expect(recordedAfterContinuation.count == 5)
  let continuationTurnStart = try #require(recordedAfterContinuation.last)
  let continuationTurnStartParams = try #require(
    continuationTurnStart["params"] as? [String: Any])
  #expect(continuationTurnStartParams["threadId"] as? String == "thread-live")
  #expect(try firstInputObject(from: continuationTurnStartParams)["text"] as? String == "keep going")

  stubProcess.simulateOutput(
    #"{"method":"turn/started","params":{"threadId":"thread-live","turn":{"id":"turn-2"}}}"#
      + "\n")
  stubProcess.simulateOutput(#"{"type":"message","content":"continued"}"# + "\n")
  stubProcess.simulateTermination(exitCode: 0)

  var continuationEvents: [AgentRawEvent] = []
  for try await event in continuationStream {
    continuationEvents.append(event)
  }

  #expect(continuationEvents.map(\.providerEventType) == ["turn/started", "message"])
  #expect(continuationEvents.map(\.sequence.rawValue) == [1, 2])
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

@Test func codexAdapterCancelSessionSendsNativeInterruptWhenThreadAndTurnKnown() async throws {
  let stubLauncher = StubProcessLauncher()
  let stubProcess = StubLaunchedProcess()
  stubLauncher.setStubProcess(stubProcess)

  let adapter = CodexAdapter(config: .defaults, processLauncher: stubLauncher)
  _ = try await adapter.startSession(
    sessionID: SessionID("s-interrupt"),
    issue: try makeIssue(title: "Interrupt me"),
    workspacePath: "/tmp",
    prompt: "test",
    environment: [:]
  )

  stubProcess.simulateOutput(
    #"{"method":"thread/started","params":{"thread":{"id":"thread-interrupt"}}}"# + "\n")
  stubProcess.simulateOutput(
    #"{"method":"turn/started","params":{"threadId":"thread-interrupt","turn":{"id":"turn-interrupt"}}}"#
      + "\n")

  try await adapter.cancelSession(sessionID: SessionID("s-interrupt"))
  #expect(stubProcess.interruptCount == 1)
  #expect(stubProcess.terminationCount == 0)
}

@Test func codexAdapterCancelSessionFallsBackToTerminateWithoutTurnIdentity() async throws {
  let stubLauncher = StubProcessLauncher()
  let stubProcess = StubLaunchedProcess()
  stubLauncher.setStubProcess(stubProcess)

  let adapter = CodexAdapter(config: .defaults, processLauncher: stubLauncher)
  _ = try await adapter.startSession(
    sessionID: SessionID("s-fallback"),
    issue: try makeIssue(title: "Fallback"),
    workspacePath: "/tmp",
    prompt: "test",
    environment: [:]
  )

  try await adapter.cancelSession(sessionID: SessionID("s-fallback"))
  #expect(stubProcess.interruptCount == 0)
  #expect(stubProcess.terminationCount == 1)
}

@Test func codexAdapterStartsTurnAfterThreadStartResponse() async throws {
  let stubLauncher = StubProcessLauncher()
  let stubProcess = StubLaunchedProcess()
  stubLauncher.setStubProcess(stubProcess)

  let adapter = CodexAdapter(config: .defaults, processLauncher: stubLauncher)
  _ = try await adapter.startSession(
    sessionID: SessionID("s-response"),
    workspacePath: "/tmp/workspace",
    prompt: "Fix the bug",
    environment: [:]
  )

  stubProcess.simulateOutput(#"{"id":2,"result":{"thread":{"id":"thread-response"}}}"# + "\n")

  let recordedMessages = try stubProcess.recordedInputStrings.map(parseJSONObject)
  #expect(recordedMessages.count == 4)
  let turnStart = try #require(recordedMessages.last)
  #expect(turnStart["method"] as? String == "turn/start")
  let turnStartParams = try #require(turnStart["params"] as? [String: Any])
  #expect(turnStartParams["threadId"] as? String == "thread-response")
  #expect(turnStartParams["cwd"] as? String == "/tmp/workspace")
  let textInput = try firstInputObject(from: turnStartParams)
  #expect(textInput["type"] as? String == "text")
  #expect(textInput["text"] as? String == "Fix the bug")
}

@Test func codexAdapterStartsTurnAfterThreadStartedNotification() async throws {
  let stubLauncher = StubProcessLauncher()
  let stubProcess = StubLaunchedProcess()
  stubLauncher.setStubProcess(stubProcess)

  let adapter = CodexAdapter(config: .defaults, processLauncher: stubLauncher)
  _ = try await adapter.startSession(
    sessionID: SessionID("s-notification"),
    workspacePath: "/tmp/workspace",
    prompt: "Fix the bug",
    environment: [:]
  )

  stubProcess.simulateOutput(
    #"{"method":"thread/started","params":{"thread":{"id":"thread-notification"}}}"# + "\n")

  let recordedMessages = try stubProcess.recordedInputStrings.map(parseJSONObject)
  #expect(recordedMessages.count == 4)
  let turnStart = try #require(recordedMessages.last)
  let turnStartParams = try #require(turnStart["params"] as? [String: Any])
  #expect(turnStartParams["threadId"] as? String == "thread-notification")
}

@Test func codexAdapterThreadStartSubmissionFailureFinishesStreamWithError() async throws {
  let stubLauncher = StubProcessLauncher()
  let stubProcess = StubLaunchedProcess()
  stubLauncher.setStubProcess(stubProcess)

  let adapter = CodexAdapter(config: .defaults, processLauncher: stubLauncher)
  let stream = try await adapter.startSession(
    sessionID: SessionID("s-submit-failure"),
    workspacePath: "/tmp/workspace",
    prompt: "Fix the bug",
    environment: [:]
  )

  stubProcess.setInputError(ProviderAdapterError.processLaunchFailed("turn start failed"))
  stubProcess.simulateOutput(
    #"{"method":"thread/started","params":{"thread":{"id":"thread-submit-failure"}}}"# + "\n")

  do {
    for try await _ in stream {}
    #expect(Bool(false), "Expected the stream to fail when turn/start submission fails")
  } catch {
    guard case .processLaunchFailed = error as? ProviderAdapterError else {
      #expect(Bool(false), "Expected a processLaunchFailed error")
      return
    }
  }
}

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

  try await Task.sleep(nanoseconds: 250_000_000)
  consumer.cancel()
  _ = await consumer.result

  let timeoutError = try #require(errorCapture.value as? ProviderAdapterError)
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

  try await Task.sleep(nanoseconds: 250_000_000)
  consumer.cancel()
  _ = await consumer.result

  let timeoutError = try #require(errorCapture.value as? ProviderAdapterError)
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
  #expect(stubLauncher.invocations[0].workspacePath == "/tmp/ws")

  let recordedMessages = try stubProcess.recordedInputStrings.map(parseJSONObject)
  #expect(recordedMessages.count == 3)
  #expect(
    recordedMessages.map { $0["method"] as? String } == [
      "initialize",
      "session/start",
      "session/prompt",
    ])

  let promptMessage = try #require(recordedMessages.last)
  let promptParams = try #require(promptMessage["params"] as? [String: Any])
  #expect(promptParams["prompt"] as? String == "fix")
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
  #expect(events[0].providerEventType == "update")
}

@Test func copilotCLIAdapterCompletedUpdateStopsStreamingFurtherEvents() async throws {
  let stubProcess = StubLaunchedProcess()
  let adapter = CopilotCLIAdapter(config: .defaults)

  let stream = adapter.makeEventStream(from: stubProcess, sessionID: SessionID("s-acp"))
  stubProcess.simulateOutput(
    "{\"method\":\"session/update\",\"params\":{\"status\":\"completed\"}}\n")
  stubProcess.simulateOutput("{\"event\":\"update\",\"content\":\"late\"}\n")
  stubProcess.simulateTermination(exitCode: 0)

  var events: [AgentRawEvent] = []
  for try await event in stream {
    events.append(event)
  }

  #expect(events.count == 1)
  #expect(events[0].providerEventType == "session/update")
}

@Test func copilotCLIAdapterMissingEnvelopeUsesUnknownEventDescriptor() async throws {
  let stubProcess = StubLaunchedProcess()
  let adapter = CopilotCLIAdapter(config: .defaults)

  let stream = adapter.makeEventStream(
    from: stubProcess, sessionID: SessionID("s-missing-envelope"))
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

@Test func eventKindInferenceCodexThreadStartedStatus() {
  let kind = EventKindInference.infer(from: "{\"method\": \"thread/started\"}", provider: .codex)
  #expect(kind == .status)
}

@Test func eventKindInferenceCodexTurnStartedStatus() {
  let kind = EventKindInference.infer(from: "{\"method\": \"turn/started\"}", provider: .codex)
  #expect(kind == .status)
}

@Test func eventKindInferenceCodexCommandExecutionStartedMapsToolCall() {
  let kind = EventKindInference.infer(
    from:
      #"{"method":"item/started","params":{"item":{"type":"commandExecution","command":"git status --short"}}}"#,
    provider: .codex
  )
  #expect(kind == .toolCall)
}

@Test func eventKindInferenceCodexCommandExecutionCompletedMapsToolResult() {
  let kind = EventKindInference.infer(
    from:
      #"{"method":"item/completed","params":{"item":{"type":"commandExecution","command":"git status --short","status":"completed"}}}"#,
    provider: .codex
  )
  #expect(kind == .toolResult)
}

@Test func eventKindInferenceCodexAgentMessageAndApprovalMethods() {
  let completedMessage = EventKindInference.infer(
    from: #"{"method":"item/completed","params":{"item":{"type":"agentMessage","text":"done"}}}"#,
    provider: .codex
  )
  #expect(completedMessage == .message)

  let deltaMessage = EventKindInference.infer(
    from: #"{"method":"item/agentMessage/delta","params":{"delta":"working"}}"#,
    provider: .codex
  )
  #expect(deltaMessage == .message)

  let approval = EventKindInference.infer(
    from:
      #"{"method":"item/commandExecution/requestApproval","params":{"reason":"allow git rev-parse"}}"#,
    provider: .codex
  )
  #expect(approval == .approvalRequest)
}

@Test func eventKindInferenceCodexThreadStatusAndUsageMethods() {
  let status = EventKindInference.infer(
    from: #"{"method":"thread/status/changed","params":{"status":{"type":"active"}}}"#,
    provider: .codex
  )
  #expect(status == .status)

  let usage = EventKindInference.infer(
    from:
      #"{"method":"thread/tokenUsage/updated","params":{"tokenUsage":{"total":{"totalTokens":42}}}}"#,
    provider: .codex
  )
  #expect(usage == .usage)
}

@Test func eventKindInferenceCodexUnknownMethodFallsBackToType() {
  let kind = EventKindInference.infer(
    from: "{\"method\": \"custom/notification\", \"type\": \"message\"}",
    provider: .codex
  )
  #expect(kind == .message)
}

@Test func eventKindInferenceCodexUsage() {
  let kind = EventKindInference.infer(from: "{\"type\": \"usage\"}", provider: .codex)
  #expect(kind == .usage)
}

@Test func eventKindInferenceCodexApprovalRequest() {
  let kind = EventKindInference.infer(from: "{\"type\": \"approval_request\"}", provider: .codex)
  #expect(kind == .approvalRequest)
}

@Test func eventKindInferenceCodexFileChangePermissionInputAndUnsupportedToolRequests() {
  let fileChange = EventKindInference.infer(
    from:
      #"{"method":"item/fileChange/requestApproval","params":{"request":{"kind":"file_change"}}}"#,
    provider: .codex
  )
  #expect(fileChange == .approvalRequest)

  let permission = EventKindInference.infer(
    from:
      #"{"method":"turn/permissionRequired","params":{"permission":{"kind":"shell"}}}"#,
    provider: .codex
  )
  #expect(permission == .approvalRequest)

  let inputRequired = EventKindInference.infer(
    from:
      #"{"method":"item/started","params":{"item":{"type":"userInputRequired","prompt":"Need confirmation"}}}"#,
    provider: .codex
  )
  #expect(inputRequired == .approvalRequest)

  let unsupportedTool = EventKindInference.infer(
    from:
      #"{"type":"unsupported_tool","params":{"tool":{"kind":"dynamic"}}}"#,
    provider: .codex
  )
  #expect(unsupportedTool == .approvalRequest)
}

@Test func eventKindInferenceCodexError() {
  let kind = EventKindInference.infer(from: "{\"type\": \"error\"}", provider: .codex)
  #expect(kind == .error)
}

@Test func eventKindInferenceCodexJSONRPCErrorResponse() {
  let kind = EventKindInference.infer(
    from: #"{"error":{"code":-32600,"message":"bad request"},"id":1}"#,
    provider: .codex
  )
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

@Test func eventKindInferenceCodexMethodCompletionIsStatus() {
  let kind = EventKindInference.infer(
    from: "{\"method\": \"turn/completed\"}",
    provider: .codex
  )
  #expect(kind == .status)
}

@Test func eventKindInferenceCopilotMethodUpdateIsStatus() {
  let kind = EventKindInference.infer(
    from: "{\"method\": \"session/update\"}",
    provider: .copilotCLI
  )
  #expect(kind == .status)
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

private func parseJSONObject(_ rawJSON: String) throws -> [String: Any] {
  let data = try #require(rawJSON.data(using: .utf8))
  let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
  return object
}

private func firstInputObject(from params: [String: Any]) throws -> [String: Any] {
  let input = try #require(params["input"] as? [Any])
  return try #require(input.first as? [String: Any])
}
