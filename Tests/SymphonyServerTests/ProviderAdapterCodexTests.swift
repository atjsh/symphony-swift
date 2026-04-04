import Foundation
import SymphonyShared
import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore

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
  let unknownItemJSON = #"{"method":"item/started","params":{"item":{"type":"reasoning"}}}"#
  #expect(
    EventKindInference.infer(
      from: unknownItemJSON,
      provider: .codex
    ) == .unknown
  )

  let errorJSON = #"{"error":{"message":"boom"}}"#
  let descriptor = ProviderEventInspection.describe(from: errorJSON, provider: .codex)
  #expect(descriptor.eventType == "error")
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

@Test func codexAdapterContinueSessionThrowsWhenNoSession() async {
  let adapter = CodexAdapter(config: .defaults)

  await #expect(throws: ProviderAdapterError.self) {
    _ = try await adapter.continueSession(sessionID: SessionID("s-missing"), guidance: "keep going")
  }
}

@Test func codexAdapterContinueSessionSubmissionFailureRemovesSessionAndTerminatesProcess() async throws {
  let stubLauncher = StubProcessLauncher()
  let stubProcess = StubLaunchedProcess()
  stubLauncher.setStubProcess(stubProcess)

  let adapter = CodexAdapter(config: .defaults, processLauncher: stubLauncher)
  _ = try await adapter.startSession(
    sessionID: SessionID("s-submit-error"),
    issue: try makeIssue(title: "Continue"),
    workspacePath: "/tmp/workspace",
    prompt: "Fix the bug",
    environment: [:]
  )

  stubProcess.simulateOutput(
    #"{"method":"thread/started","params":{"thread":{"id":"thread-submit-error"}}}"# + "\n")
  stubProcess.setInputError(ProviderAdapterError.processLaunchFailed("continue failed"))

  await #expect(throws: ProviderAdapterError.self) {
    _ = try await adapter.continueSession(
      sessionID: SessionID("s-submit-error"),
      guidance: "keep going"
    )
  }

  #expect(stubProcess.terminationCount == 1)
  await #expect(throws: ProviderAdapterError.self) {
    _ = try await adapter.continueSession(
      sessionID: SessionID("s-submit-error"),
      guidance: "second try"
    )
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

@Test func codexAdapterInterruptSessionReturnsFalseWhenInterruptSubmissionFails() async throws {
  let stubLauncher = StubProcessLauncher()
  let stubProcess = StubLaunchedProcess()
  stubLauncher.setStubProcess(stubProcess)

  let adapter = CodexAdapter(config: .defaults, processLauncher: stubLauncher)
  _ = try await adapter.startSession(
    sessionID: SessionID("s-interrupt-failure"),
    issue: try makeIssue(title: "Interrupt failure"),
    workspacePath: "/tmp",
    prompt: "test",
    environment: [:]
  )

  stubProcess.simulateOutput(
    #"{"method":"thread/started","params":{"thread":{"id":"thread-interrupt-failure"}}}"# + "\n")
  stubProcess.simulateOutput(
    #"{"method":"turn/started","params":{"threadId":"thread-interrupt-failure","turn":{"id":"turn-interrupt-failure"}}}"#
      + "\n")
  stubProcess.setInputError(ProviderAdapterError.processLaunchFailed("interrupt failed"))

  let interrupted = try await adapter.interruptSession(sessionID: SessionID("s-interrupt-failure"))
  #expect(interrupted == false)
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
