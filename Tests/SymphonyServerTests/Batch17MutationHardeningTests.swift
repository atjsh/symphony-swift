// Batch 17 – Mutation hardening for BootstrapServerEndpoint normalization,
// CodexSupportTypes (SessionState, Registry, StartupState, OutputBuffer).

import Foundation
import Testing
@testable import SymphonyServer
@testable import SymphonyServerCore
import SymphonyShared

// MARK: - BootstrapServerEndpoint Port Boundary Tests

@Suite("BootstrapServerEndpoint Port Boundaries")
struct BootstrapServerEndpointPortBoundaryTests {

  @Test func portZeroFallsBackToDefault() {
    let endpoint = BootstrapServerEndpoint(scheme: "http", host: "localhost", port: 0)
    #expect(endpoint.port == 8080, "Port 0 must fall back to default 8080")
  }

  @Test func portOneIsValid() {
    let endpoint = BootstrapServerEndpoint(scheme: "http", host: "localhost", port: 1)
    #expect(endpoint.port == 1)
  }

  @Test func port65535IsValid() {
    let endpoint = BootstrapServerEndpoint(scheme: "http", host: "localhost", port: 65535)
    #expect(endpoint.port == 65535)
  }

  @Test func port65536FallsBackToDefault() {
    let endpoint = BootstrapServerEndpoint(scheme: "http", host: "localhost", port: 65536)
    #expect(endpoint.port == 8080, "Port 65536 must fall back to default 8080")
  }

  @Test func negativePortFallsBackToDefault() {
    let endpoint = BootstrapServerEndpoint(scheme: "http", host: "localhost", port: -1)
    #expect(endpoint.port == 8080, "Negative port must fall back to default 8080")
  }
}

// MARK: - BootstrapServerEndpoint Scheme Normalization Tests

@Suite("BootstrapServerEndpoint Scheme Normalization")
struct BootstrapServerEndpointSchemeNormalizationTests {

  @Test func uppercaseSchemeIsLowercased() {
    let endpoint = BootstrapServerEndpoint(scheme: "HTTPS", host: "localhost", port: 443)
    #expect(endpoint.scheme == "https")
  }

  @Test func mixedCaseSchemeIsLowercased() {
    let endpoint = BootstrapServerEndpoint(scheme: "Http", host: "localhost", port: 80)
    #expect(endpoint.scheme == "http")
  }

  @Test func whitespaceOnlySchemeFallsBackToDefault() {
    let endpoint = BootstrapServerEndpoint(scheme: "   ", host: "localhost", port: 80)
    #expect(endpoint.scheme == "http", "Whitespace-only scheme must fall back to default")
  }

  @Test func paddedSchemeIsTrimmedAndLowercased() {
    let endpoint = BootstrapServerEndpoint(scheme: "  HTTPS  ", host: "localhost", port: 443)
    #expect(endpoint.scheme == "https")
  }
}

// MARK: - BootstrapServerEndpoint Host Normalization Tests

@Suite("BootstrapServerEndpoint Host Normalization")
struct BootstrapServerEndpointHostNormalizationTests {

  @Test func whitespaceOnlyHostFallsBackToDefault() {
    let endpoint = BootstrapServerEndpoint(scheme: "http", host: "   ", port: 80)
    #expect(endpoint.host == "127.0.0.1", "Whitespace-only host must fall back to default")
  }

  @Test func paddedHostIsTrimmed() {
    let endpoint = BootstrapServerEndpoint(scheme: "http", host: "  10.0.0.1  ", port: 80)
    #expect(endpoint.host == "10.0.0.1")
  }

  @Test func emptyHostFallsBackToDefault() {
    let endpoint = BootstrapServerEndpoint(scheme: "http", host: "", port: 80)
    #expect(endpoint.host == "127.0.0.1")
  }
}

// MARK: - BootstrapServerEndpoint Resolved from Environment

@Suite("BootstrapServerEndpoint Resolved Environment")
struct BootstrapServerEndpointResolvedEnvTests {

  @Test func uppercaseSchemeFromEnvIsLowercased() {
    let endpoint = BootstrapServerEndpoint.resolved(from: [
      BootstrapEnvironment.serverSchemeKey: "HTTPS",
    ])
    #expect(endpoint.scheme == "https")
  }

  @Test func invalidPortFromEnvKeepsDefault() {
    let endpoint = BootstrapServerEndpoint.resolved(from: [
      BootstrapEnvironment.serverPortKey: "65536",
    ])
    #expect(endpoint.port == 8080)
  }

  @Test func zeroPortFromEnvKeepsDefault() {
    let endpoint = BootstrapServerEndpoint.resolved(from: [
      BootstrapEnvironment.serverPortKey: "0",
    ])
    #expect(endpoint.port == 8080)
  }

  @Test func negativePortFromEnvKeepsDefault() {
    let endpoint = BootstrapServerEndpoint.resolved(from: [
      BootstrapEnvironment.serverPortKey: "-5",
    ])
    #expect(endpoint.port == 8080)
  }

  @Test func whitespaceHostFromEnvKeepsDefault() {
    let endpoint = BootstrapServerEndpoint.resolved(from: [
      BootstrapEnvironment.serverHostKey: "  \t  ",
    ])
    #expect(endpoint.host == "127.0.0.1")
  }

  @Test func paddedPortFromEnvIsTrimmed() {
    let endpoint = BootstrapServerEndpoint.resolved(from: [
      BootstrapEnvironment.serverPortKey: "  9090  ",
    ])
    #expect(endpoint.port == 9090)
  }
}

// MARK: - CodexSessionState RequestID Sequence

@Suite("CodexSessionState RequestID Sequence")
struct CodexSessionStateRequestIDTests {

  @Test func requestIDStartsAt4AndIncrementsBy1() {
    let state = CodexSessionState()
    #expect(state.nextTurnRequestID() == 4)
    #expect(state.nextTurnRequestID() == 5)
    #expect(state.nextTurnRequestID() == 6)
  }
}

// MARK: - CodexSessionRegistry Tests

@Suite("CodexSessionRegistry")
struct CodexSessionRegistryTests {

  @Test func stateCreatedOnFirstAccess() {
    let registry = CodexSessionRegistry()
    let state = registry.state(for: SessionID("new-session"))
    #expect(state.threadID == nil, "Fresh state should have nil threadID")
    #expect(state.issueIdentifier == nil, "Fresh state should have nil issueIdentifier")
  }

  @Test func stateReturnedConsistentlyForSameID() {
    let registry = CodexSessionRegistry()
    let sessionID = SessionID("test-session")
    let first = registry.state(for: sessionID)
    first.recordThreadID("thread-1")
    let second = registry.state(for: sessionID)
    #expect(second.threadID == "thread-1", "Must return the same instance")
  }

  @Test func removeSessionClearsState() {
    let registry = CodexSessionRegistry()
    let sessionID = SessionID("remove-test")
    let state = registry.state(for: sessionID)
    state.recordThreadID("thread-remove")
    registry.remove(sessionID: sessionID)
    // Fresh state after removal should have nil values
    let fresh = registry.state(for: sessionID)
    #expect(fresh.threadID == nil)
  }

  @Test func threadIDReturnsNilForUnknownSession() {
    let registry = CodexSessionRegistry()
    #expect(registry.threadID(for: SessionID("unknown")) == nil)
  }

  @Test func turnIDReturnsNilForUnknownSession() {
    let registry = CodexSessionRegistry()
    #expect(registry.turnID(for: SessionID("unknown")) == nil)
  }

  @Test func threadIDReturnsRecordedValue() {
    let registry = CodexSessionRegistry()
    let sessionID = SessionID("t-session")
    let state = registry.state(for: sessionID)
    state.recordThreadID("thread-abc")
    #expect(registry.threadID(for: sessionID) == "thread-abc")
  }
}

// MARK: - CodexStartupState TurnStart Guard

@Suite("CodexStartupState TurnStart Guard")
struct CodexStartupStateTurnStartTests {

  private func makeStartupState() -> CodexStartupState {
    CodexStartupState(
      issue: nil,
      workspacePath: "/tmp/ws",
      prompt: "Fix the bug",
      config: CodexProviderConfig.defaults
    )
  }

  @Test func firstCallReturnsTurnStartMessage() {
    let state = makeStartupState()
    let message = state.turnStartMessageIfNeeded(threadID: "t-1")
    #expect(message != nil, "First call must return a turn start message")
  }

  @Test func secondCallReturnsNil() {
    let state = makeStartupState()
    _ = state.turnStartMessageIfNeeded(threadID: "t-1")
    let second = state.turnStartMessageIfNeeded(threadID: "t-1")
    #expect(second == nil, "Subsequent calls must return nil (already sent)")
  }
}

// MARK: - CodexOutputBuffer Tests

@Suite("CodexOutputBuffer")
struct CodexOutputBufferTests {

  @Test func appendSingleCompleteLine() {
    let buffer = CodexOutputBuffer()
    let lines = buffer.append("hello\n")
    #expect(lines == ["hello"])
  }

  @Test func appendMultipleLines() {
    let buffer = CodexOutputBuffer()
    let lines = buffer.append("line1\nline2\nline3\n")
    #expect(lines == ["line1", "line2", "line3"])
  }

  @Test func appendPartialThenComplete() {
    let buffer = CodexOutputBuffer()
    let partial = buffer.append("part")
    #expect(partial.isEmpty, "Incomplete line yields nothing")
    let completed = buffer.append("ial\n")
    #expect(completed == ["partial"])
  }

  @Test func appendSkipsBlankLines() {
    let buffer = CodexOutputBuffer()
    let lines = buffer.append("a\n\n\nb\n")
    #expect(lines == ["a", "b"], "Blank lines should be skipped")
  }

  @Test func finishReturnsRemainder() {
    let buffer = CodexOutputBuffer()
    _ = buffer.append("remaining")
    let lines = buffer.finish()
    #expect(lines == ["remaining"])
  }

  @Test func finishWithWhitespaceOnlyReturnsEmpty() {
    let buffer = CodexOutputBuffer()
    _ = buffer.append("   \n")
    let remainder = buffer.finish()
    #expect(remainder.isEmpty, "Whitespace-only remainder should yield nothing")
  }

  @Test func finishClearsBuffer() {
    let buffer = CodexOutputBuffer()
    _ = buffer.append("data")
    _ = buffer.finish()
    let second = buffer.finish()
    #expect(second.isEmpty, "Buffer should be empty after finish")
  }
}

// MARK: - CodexSessionState Issue Context

@Suite("CodexSessionState Issue Context")
struct CodexSessionStateIssueContextTests {

  @Test func issueContextInitiallyNil() {
    let state = CodexSessionState()
    #expect(state.issueIdentifier == nil)
    #expect(state.issueTitle == nil)
  }

  @Test func recordIssueContextPreservesValues() {
    let state = CodexSessionState()
    state.recordIssueContext(identifier: "owner/repo#42", title: "Bug fix")
    #expect(state.issueIdentifier == "owner/repo#42")
    #expect(state.issueTitle == "Bug fix")
  }

  @Test func recordTurnIDPreservesValue() {
    let state = CodexSessionState()
    state.recordTurnID("turn-99")
    #expect(state.turnID == "turn-99")
  }
}
