import Foundation
import SymphonyShared
import Testing

// MARK: - RunLifecycleState Tests

@Test func runLifecycleStateTerminalStates() {
  let terminalStates: [RunLifecycleState] = [
    .succeeded, .failed, .timedOut, .stalled, .canceledByReconciliation,
  ]
  for state in terminalStates {
    #expect(state.isTerminal, "Expected \(state) to be terminal")
    #expect(!state.isActive, "Expected \(state) to not be active")
  }
}

@Test func runLifecycleStateActiveStates() {
  let activeStates: [RunLifecycleState] = [
    .preparingWorkspace, .buildingPrompt, .launchingAgentProcess, .initializingSession,
    .streamingTurn, .finishing,
  ]
  for state in activeStates {
    #expect(!state.isTerminal, "Expected \(state) to not be terminal")
    #expect(state.isActive, "Expected \(state) to be active")
  }
}

@Test func runLifecycleStateRawValues() {
  #expect(RunLifecycleState.preparingWorkspace.rawValue == "PreparingWorkspace")
  #expect(RunLifecycleState.buildingPrompt.rawValue == "BuildingPrompt")
  #expect(RunLifecycleState.launchingAgentProcess.rawValue == "LaunchingAgentProcess")
  #expect(RunLifecycleState.initializingSession.rawValue == "InitializingSession")
  #expect(RunLifecycleState.streamingTurn.rawValue == "StreamingTurn")
  #expect(RunLifecycleState.finishing.rawValue == "Finishing")
  #expect(RunLifecycleState.succeeded.rawValue == "Succeeded")
  #expect(RunLifecycleState.failed.rawValue == "Failed")
  #expect(RunLifecycleState.timedOut.rawValue == "TimedOut")
  #expect(RunLifecycleState.stalled.rawValue == "Stalled")
  #expect(RunLifecycleState.canceledByReconciliation.rawValue == "CanceledByReconciliation")
}

@Test func runLifecycleStateAllCases() {
  #expect(RunLifecycleState.allCases.count == 11)
}

@Test func runLifecycleStateCodable() throws {
  let encoder = JSONEncoder()
  let decoder = JSONDecoder()

  for state in RunLifecycleState.allCases {
    let data = try encoder.encode(state)
    let decoded = try decoder.decode(RunLifecycleState.self, from: data)
    #expect(decoded == state)
  }
}

// MARK: - ClaimState Tests

@Test func claimStateRawValues() {
  #expect(ClaimState.unclaimed.rawValue == "Unclaimed")
  #expect(ClaimState.claimed.rawValue == "Claimed")
  #expect(ClaimState.running.rawValue == "Running")
  #expect(ClaimState.retryQueued.rawValue == "RetryQueued")
  #expect(ClaimState.released.rawValue == "Released")
}

@Test func claimStateAllCases() {
  #expect(ClaimState.allCases.count == 5)
}

@Test func claimStateCodable() throws {
  let encoder = JSONEncoder()
  let decoder = JSONDecoder()

  for state in ClaimState.allCases {
    let data = try encoder.encode(state)
    let decoded = try decoder.decode(ClaimState.self, from: data)
    #expect(decoded == state)
  }
}

// MARK: - ToolExecutionMode Tests

@Test func toolExecutionModeRawValues() {
  #expect(ToolExecutionMode.providerManaged.rawValue == "provider_managed")
  #expect(ToolExecutionMode.orchestratorManaged.rawValue == "orchestrator_managed")
  #expect(ToolExecutionMode.mixed.rawValue == "mixed")
}

@Test func toolExecutionModeAllCases() {
  #expect(ToolExecutionMode.allCases.count == 3)
}

@Test func toolExecutionModeCodable() throws {
  let encoder = JSONEncoder()
  let decoder = JSONDecoder()

  for mode in ToolExecutionMode.allCases {
    let data = try encoder.encode(mode)
    let decoded = try decoder.decode(ToolExecutionMode.self, from: data)
    #expect(decoded == mode)
  }
}

// MARK: - ProviderCapabilities Tests

@Test func providerCapabilitiesDefaults() {
  let caps = ProviderCapabilities()
  #expect(!caps.supportsResume)
  #expect(!caps.supportsInterrupt)
  #expect(!caps.supportsUsageTotals)
  #expect(!caps.supportsRateLimits)
  #expect(!caps.supportsExplicitApprovals)
  #expect(!caps.supportsStructuredToolEvents)
  #expect(caps.toolExecutionMode == .providerManaged)
}

@Test func providerCapabilitiesCustom() {
  let caps = ProviderCapabilities(
    supportsResume: true,
    supportsInterrupt: true,
    supportsUsageTotals: true,
    supportsRateLimits: true,
    supportsExplicitApprovals: true,
    supportsStructuredToolEvents: true,
    toolExecutionMode: .mixed
  )
  #expect(caps.supportsResume)
  #expect(caps.supportsInterrupt)
  #expect(caps.supportsUsageTotals)
  #expect(caps.supportsRateLimits)
  #expect(caps.supportsExplicitApprovals)
  #expect(caps.supportsStructuredToolEvents)
  #expect(caps.toolExecutionMode == .mixed)
}

@Test func providerCapabilitiesCodableWithSnakeCaseKeys() throws {
  let caps = ProviderCapabilities(
    supportsResume: true,
    supportsInterrupt: false,
    supportsUsageTotals: true,
    supportsRateLimits: false,
    supportsExplicitApprovals: true,
    supportsStructuredToolEvents: false,
    toolExecutionMode: .orchestratorManaged
  )
  let encoder = JSONEncoder()
  let data = try encoder.encode(caps)
  let json = String(data: data, encoding: .utf8)!

  #expect(json.contains("supports_resume"))
  #expect(json.contains("supports_interrupt"))
  #expect(json.contains("supports_usage_totals"))
  #expect(json.contains("supports_rate_limits"))
  #expect(json.contains("supports_explicit_approvals"))
  #expect(json.contains("supports_structured_tool_events"))
  #expect(json.contains("tool_execution_mode"))

  let decoder = JSONDecoder()
  let decoded = try decoder.decode(ProviderCapabilities.self, from: data)
  #expect(decoded == caps)
}

@Test func providerCapabilitiesEquatable() {
  let a = ProviderCapabilities(supportsResume: true)
  let b = ProviderCapabilities(supportsResume: true)
  let c = ProviderCapabilities(supportsResume: false)
  #expect(a == b)
  #expect(a != c)
}

@Test func providerCapabilitiesHashable() {
  let a = ProviderCapabilities(supportsResume: true)
  let b = ProviderCapabilities(supportsResume: true)
  #expect(a.hashValue == b.hashValue)
}

// MARK: - RetryRecord Tests

@Test func retryRecordCodable() throws {
  let record = RetryRecord(
    issueID: IssueID("issue-1"),
    issueIdentifier: try IssueIdentifier(validating: "owner/repo#1"),
    attempt: 3,
    dueAt: Date(timeIntervalSince1970: 1000),
    error: "test error"
  )

  let encoder = JSONEncoder()
  let data = try encoder.encode(record)
  let json = String(data: data, encoding: .utf8)!

  #expect(json.contains("issue_id"))
  #expect(json.contains("issue_identifier"))
  #expect(json.contains("due_at"))

  let decoder = JSONDecoder()
  let decoded = try decoder.decode(RetryRecord.self, from: data)
  #expect(decoded.issueID == record.issueID)
  #expect(decoded.attempt == 3)
  #expect(decoded.error == "test error")
}

@Test func retryRecordWithNilError() throws {
  let record = RetryRecord(
    issueID: IssueID("issue-2"),
    issueIdentifier: try IssueIdentifier(validating: "owner/repo#2"),
    attempt: 1,
    dueAt: Date(timeIntervalSince1970: 2000),
    error: nil
  )

  let encoder = JSONEncoder()
  let data = try encoder.encode(record)
  let decoder = JSONDecoder()
  let decoded = try decoder.decode(RetryRecord.self, from: data)
  #expect(decoded.error == nil)
}

@Test func retryRecordEquatable() throws {
  let date = Date(timeIntervalSince1970: 1000)
  let a = RetryRecord(
    issueID: IssueID("issue-1"),
    issueIdentifier: try IssueIdentifier(validating: "owner/repo#1"),
    attempt: 1,
    dueAt: date,
    error: nil
  )
  let b = RetryRecord(
    issueID: IssueID("issue-1"),
    issueIdentifier: try IssueIdentifier(validating: "owner/repo#1"),
    attempt: 1,
    dueAt: date,
    error: nil
  )
  #expect(a == b)
}

@Test func retryRecordHashable() throws {
  let date = Date(timeIntervalSince1970: 1000)
  let record = RetryRecord(
    issueID: IssueID("issue-1"),
    issueIdentifier: try IssueIdentifier(validating: "owner/repo#1"),
    attempt: 1,
    dueAt: date,
    error: nil
  )
  let set: Set<RetryRecord> = [record]
  #expect(set.count == 1)
}

// MARK: - ProviderName Tests

@Test func providerNameRawValues() {
  #expect(ProviderName.codex.rawValue == "codex")
  #expect(ProviderName.claudeCode.rawValue == "claude_code")
  #expect(ProviderName.copilotCLI.rawValue == "copilot_cli")
}

@Test func providerNameAllCases() {
  #expect(ProviderName.allCases.count == 3)
}

@Test func providerNameCodable() throws {
  let encoder = JSONEncoder()
  let decoder = JSONDecoder()

  for name in ProviderName.allCases {
    let data = try encoder.encode(name)
    let decoded = try decoder.decode(ProviderName.self, from: data)
    #expect(decoded == name)
  }
}
