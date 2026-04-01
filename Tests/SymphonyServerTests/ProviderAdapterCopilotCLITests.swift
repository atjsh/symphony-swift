import Foundation
import SymphonyShared
import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore

// MARK: - CopilotCLIAdapter Tests

@Test func copilotCLIAdapterCapabilities() {
  let adapter = CopilotCLIAdapter(config: .defaults)
  #expect(adapter.providerName == .copilotCLI)
  #expect(adapter.capabilities.supportsResume)
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
  let stream = try await adapter.startSession(
    sessionID: SessionID("s1"),
    workspacePath: "/tmp/ws",
    prompt: "fix",
    environment: [:]
  )

  #expect(stubLauncher.invocations.count == 1)
  #expect(stubLauncher.invocations[0].command == "copilot --acp --stdio")
  #expect(stubLauncher.invocations[0].workspacePath == "/tmp/ws")

  let recordedMessages = try stubProcess.recordedInputStrings.map(parseJSONObject)
  #expect(recordedMessages.count == 2)
  #expect(
    recordedMessages.map { $0["method"] as? String } == [
      "initialize",
      "newSession",
    ])

  stubProcess.simulateOutput(#"{"id":2,"result":{"sessionId":"copilot-session-1"}}"# + "\n")
  stubProcess.simulateOutput(#"{"id":3,"result":{"stopReason":"end_turn"}}"# + "\n")

  var events: [AgentRawEvent] = []
  for try await event in stream {
    events.append(event)
  }

  let recordedAfterSession = try stubProcess.recordedInputStrings.map(parseJSONObject)
  #expect(recordedAfterSession.count == 3)
  #expect(recordedAfterSession.map { $0["method"] as? String } == [
    "initialize",
    "newSession",
    "prompt",
  ])

  let promptMessage = try #require(recordedAfterSession.last)
  let promptParams = try #require(promptMessage["params"] as? [String: Any])
  #expect(promptParams["sessionId"] as? String == "copilot-session-1")
  let promptBlocks = try #require(promptParams["prompt"] as? [Any])
  let promptBlock = try #require(promptBlocks.first as? [String: Any])
  #expect(promptBlock["type"] as? String == "text")
  #expect(promptBlock["text"] as? String == "fix")
  #expect(events.map(\.providerEventType) == ["result", "result"])
}

@Test func copilotCLIAdapterContinuationEmulatesPromptOnSameSession() async throws {
  let stubLauncher = StubProcessLauncher()
  let stubProcess = StubLaunchedProcess()
  stubLauncher.setStubProcess(stubProcess)

  let adapter = CopilotCLIAdapter(config: .defaults, processLauncher: stubLauncher)
  let initialStream = try await adapter.startSession(
    sessionID: SessionID("s1"),
    workspacePath: "/tmp/ws",
    prompt: "fix",
    environment: [:]
  )

  stubProcess.simulateOutput(#"{"id":2,"result":{"sessionId":"copilot-session-1"}}"# + "\n")
  stubProcess.simulateOutput(#"{"id":3,"result":{"stopReason":"end_turn"}}"# + "\n")

  var initialEvents: [AgentRawEvent] = []
  for try await event in initialStream {
    initialEvents.append(event)
  }

  _ = try await adapter.continueSession(sessionID: SessionID("s1"), guidance: "keep going")

  let recordedMessages = try stubProcess.recordedInputStrings.map(parseJSONObject)
  #expect(recordedMessages.count == 4)
  #expect(recordedMessages.map { $0["method"] as? String } == [
    "initialize",
    "newSession",
    "prompt",
    "prompt",
  ])

  let continuationPrompt = try #require(recordedMessages.last)
  let continuationParams = try #require(continuationPrompt["params"] as? [String: Any])
  #expect(continuationParams["sessionId"] as? String == "copilot-session-1")
  let promptBlocks = try #require(continuationParams["prompt"] as? [Any])
  let promptBlock = try #require(promptBlocks.first as? [String: Any])
  #expect(promptBlock["text"] as? String == "keep going")
  #expect(initialEvents.map(\.providerEventType) == ["result", "result"])
}

@Test func copilotCLIAdapterHandlesRequestPermissionAndSessionUpdate() async throws {
  let stubLauncher = StubProcessLauncher()
  let stubProcess = StubLaunchedProcess()
  stubLauncher.setStubProcess(stubProcess)

  let adapter = CopilotCLIAdapter(config: .defaults, processLauncher: stubLauncher)
  let stream = try await adapter.startSession(
    sessionID: SessionID("s-perm"),
    workspacePath: "/tmp/ws",
    prompt: "fix",
    environment: [:]
  )

  stubProcess.simulateOutput(#"{"id":2,"result":{"sessionId":"copilot-session-1"}}"# + "\n")
  stubProcess.simulateOutput(
    #"{"id":7,"method":"session/request_permission","params":{"sessionId":"copilot-session-1","toolCall":{"kind":"shell","command":"git status"},"options":[{"optionId":"allow-once","name":"Allow once","kind":"allow_once"},{"optionId":"reject-once","name":"Reject once","kind":"reject_once"}]}}"#
      + "\n")
  stubProcess.simulateOutput(
    #"{"method":"session/update","params":{"status":"completed"}}"# + "\n")
  stubProcess.simulateOutput(#"{"id":3,"result":{"stopReason":"end_turn"}}"# + "\n")

  var events: [AgentRawEvent] = []
  for try await event in stream {
    events.append(event)
  }

  #expect(events.map(\.providerEventType) == ["result", "session/request_permission", "session/update", "result"])
  let recordedResponses = try stubProcess.recordedInputStrings.map(parseJSONObject)
  #expect(recordedResponses.count == 4)
  let response = try #require(recordedResponses.last)
  #expect(response["id"] as? Int == 7)
  let result = try #require(response["result"] as? [String: Any])
  let outcome = try #require(result["outcome"] as? [String: Any])
  #expect(outcome["outcome"] as? String == "selected")
  #expect(outcome["optionId"] as? String == "allow-once")
}

@Test func copilotCLIAdapterCancelsPermissionResponseWhenNoSelectableOptionExists() async throws {
  let stubLauncher = StubProcessLauncher()
  let stubProcess = StubLaunchedProcess()
  stubLauncher.setStubProcess(stubProcess)

  let adapter = CopilotCLIAdapter(config: .defaults, processLauncher: stubLauncher)
  let stream = try await adapter.startSession(
    sessionID: SessionID("s-perm-cancel"),
    workspacePath: "/tmp/ws",
    prompt: "fix",
    environment: [:]
  )

  stubProcess.simulateOutput(#"{"id":2,"result":{"sessionId":"copilot-session-2"}}"# + "\n")
  stubProcess.simulateOutput(
    #"{"id":8,"method":"requestPermission","params":{"sessionId":"copilot-session-2","toolCall":{"kind":"shell","command":"git status"},"options":[{"name":"No option id"}]}}"#
      + "\n")
  stubProcess.simulateOutput(#"{"id":3,"result":{"stopReason":"end_turn"}}"# + "\n")

  for try await _ in stream {}

  let recordedResponses = try stubProcess.recordedInputStrings.map(parseJSONObject)
  let response = try #require(recordedResponses.last)
  #expect(response["id"] as? Int == 8)
  let result = try #require(response["result"] as? [String: Any])
  let outcome = try #require(result["outcome"] as? [String: Any])
  #expect(outcome["outcome"] as? String == "cancelled")
  #expect(outcome["optionId"] == nil)
}

@Test func copilotCLIAdapterContinueSessionRequiresExistingSession() async {
  let adapter = CopilotCLIAdapter(config: .defaults)
  do {
    _ = try await adapter.continueSession(sessionID: SessionID("s1"), guidance: "continue")
    #expect(Bool(false), "Should have thrown")
  } catch {
    #expect(error is ProviderAdapterError)
  }
}

@Test func copilotCLIAdapterInterruptSessionAlwaysReturnsFalse() async throws {
  let adapter = CopilotCLIAdapter(config: .defaults)
  let interrupted = try await adapter.interruptSession(sessionID: SessionID("s-copilot-interrupt"))
  #expect(interrupted == false)
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

@Test func copilotCLIAdapterPromptResultStopsStreamingFurtherEvents() async throws {
  let stubProcess = StubLaunchedProcess()
  let adapter = CopilotCLIAdapter(config: .defaults)

  let stream = adapter.makeEventStream(from: stubProcess, sessionID: SessionID("s-acp"))
  stubProcess.simulateOutput(
    "{\"method\":\"session/update\",\"params\":{\"status\":\"completed\"}}\n")
  stubProcess.simulateOutput("{\"id\":3,\"result\":{\"stopReason\":\"end_turn\"}}\n")
  stubProcess.simulateOutput("{\"event\":\"update\",\"content\":\"late\"}\n")

  var events: [AgentRawEvent] = []
  for try await event in stream {
    events.append(event)
  }

  #expect(events.map(\.providerEventType) == ["session/update", "result"])
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

@Test func copilotCLIAdapterRequestPermissionSubmissionFailureFinishesStreamWithError() async throws {
  let stubLauncher = StubProcessLauncher()
  let stubProcess = StubLaunchedProcess()
  stubLauncher.setStubProcess(stubProcess)

  let adapter = CopilotCLIAdapter(config: .defaults, processLauncher: stubLauncher)
  let stream = try await adapter.startSession(
    sessionID: SessionID("s-perm-error"),
    workspacePath: "/tmp/ws",
    prompt: "fix",
    environment: [:]
  )

  stubProcess.simulateOutput(#"{"id":2,"result":{"sessionId":"copilot-session-error"}}"# + "\n")
  stubProcess.setInputError(ProviderAdapterError.processLaunchFailed("permission failed"))
  stubProcess.simulateOutput(
    #"{"id":9,"method":"session/request_permission","params":{"sessionId":"copilot-session-error","options":[{"optionId":"allow-once"}]}}"#
      + "\n")

  var caughtError: Error?
  do {
    for try await _ in stream {}
  } catch {
    caughtError = error
  }

  let adapterError = try #require(caughtError as? ProviderAdapterError)
  guard case .processLaunchFailed = adapterError else {
    #expect(Bool(false), "Expected request_permission submission failure to surface as processLaunchFailed")
    return
  }
}

@Test func copilotCLIAdapterPromptResultNonEndTurnFailsStreamWithTerminalOutcome() async throws {
  let stubProcess = StubLaunchedProcess()
  let adapter = CopilotCLIAdapter(config: .defaults)

  let stream = adapter.makeEventStream(from: stubProcess, sessionID: SessionID("s-acp-stop"))
  stubProcess.simulateOutput(#"{"id":3,"result":{"stopReason":"max_turns"}}"# + "\n")

  var caughtError: Error?
  do {
    for try await _ in stream {}
  } catch {
    caughtError = error
  }

  let adapterError = try #require(caughtError as? ProviderAdapterError)
  #expect(
    adapterError == .terminalOutcome(
      sessionID: SessionID("s-acp-stop"),
      outcome: "max_turns"
    ))
}

@Test func copilotCLIAdapterErrorEnvelopeFailsStreamWithTerminalErrorOutcome() async throws {
  let stubProcess = StubLaunchedProcess()
  let adapter = CopilotCLIAdapter(config: .defaults)

  let stream = adapter.makeEventStream(from: stubProcess, sessionID: SessionID("s-acp-error"))
  stubProcess.simulateOutput(#"{"error":{"message":"boom"}}"# + "\n")

  var events: [AgentRawEvent] = []
  var caughtError: Error?
  do {
    for try await event in stream {
      events.append(event)
    }
  } catch {
    caughtError = error
  }

  #expect(events.map(\.providerEventType) == ["error"])
  let adapterError = try #require(caughtError as? ProviderAdapterError)
  #expect(
    adapterError == .terminalOutcome(
      sessionID: SessionID("s-acp-error"),
      outcome: "error"
    ))
}
