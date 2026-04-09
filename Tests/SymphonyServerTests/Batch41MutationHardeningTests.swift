// Batch41MutationHardeningTests.swift
// -----------------------------------------------------------------
// Mutation targets:
//
// CodexHelpers.swift — makeCodexTurnStartMessage optional policy keys:
//   Mutation removes the if-let guards that conditionally set
//   approvalPolicy and sandboxPolicy keys in the params dict.
//   Killed by verifying keys are absent when config has nil policies.
//
// CodexAdapter.swift — interruptSession guard:
//   Mutation removes the compound guard that checks managedSession,
//   threadID, and turnID. Killed by calling interruptSession with
//   an unknown sessionID and verifying it returns false.
//
// ProviderConfigs.swift — CodexProviderConfig init coalescing:
//   Mutation removes the ?? sessionApprovalPolicy fallback in the
//   turnApprovalPolicy assignment. Killed by creating a config with
//   sessionApprovalPolicy set and turnApprovalPolicy nil, verifying
//   turnApprovalPolicy inherits the session value.
//
// -----------------------------------------------------------------

import Foundation
import SymphonyShared
import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore

// MARK: - makeCodexTurnStartMessage nil-policy key absence

@Suite("makeCodexTurnStartMessage nil-policy key absence")
struct MakeCodexTurnStartMessageNilPolicyTests {

  /// When turnApprovalPolicy is nil, the params dict must NOT contain
  /// an "approvalPolicy" key. Kills mutation that removes the if-let guard.
  @Test func nilTurnApprovalPolicyOmitsKey() throws {
    let config = CodexProviderConfig()  // defaults: turnApprovalPolicy = nil
    let msg = makeCodexTurnStartMessage(
      id: 1,
      threadID: "t1",
      issueIdentifier: "org/repo#1",
      issueTitle: "Test",
      workspacePath: "/tmp",
      input: "prompt",
      config: config
    )
    let params = try #require(msg["params"] as? [String: Any])
    #expect(
      params["approvalPolicy"] == nil,
      "approvalPolicy key must be absent when turnApprovalPolicy is nil"
    )
  }

  /// When turnSandboxPolicy is nil, the params dict must NOT contain
  /// a "sandboxPolicy" key. Kills mutation that removes the if-let guard.
  @Test func nilTurnSandboxPolicyOmitsKey() throws {
    let config = CodexProviderConfig()  // defaults: turnSandboxPolicy = nil
    let msg = makeCodexTurnStartMessage(
      id: 1,
      threadID: "t1",
      issueIdentifier: "org/repo#1",
      issueTitle: "Test",
      workspacePath: "/tmp",
      input: "prompt",
      config: config
    )
    let params = try #require(msg["params"] as? [String: Any])
    #expect(
      params["sandboxPolicy"] == nil,
      "sandboxPolicy key must be absent when turnSandboxPolicy is nil"
    )
  }
}

// MARK: - CodexAdapter interruptSession unknown session

@Suite("CodexAdapter interruptSession guard")
struct CodexAdapterInterruptSessionGuardTests {

  /// Calling interruptSession on a fresh adapter with no started sessions
  /// must return false. The guard checks managedSession, threadID, and
  /// turnID — all nil for an unknown session.
  @Test func interruptSessionReturnsFalseForUnknownSession() async throws {
    let adapter = CodexAdapter(config: .defaults, processLauncher: StubProcessLauncher())
    let result = try await adapter.interruptSession(sessionID: SessionID("nonexistent"))
    #expect(result == false)
  }
}

// MARK: - CodexProviderConfig turnApprovalPolicy coalescing

@Suite("CodexProviderConfig turnApprovalPolicy inheritance")
struct CodexProviderConfigTurnApprovalPolicyCoalescingTests {

  /// When turnApprovalPolicy is nil and sessionApprovalPolicy is set,
  /// turnApprovalPolicy must inherit from sessionApprovalPolicy.
  /// Kills mutation that removes the ?? sessionApprovalPolicy fallback.
  @Test func turnApprovalPolicyInheritsFromSession() {
    let config = CodexProviderConfig(
      sessionApprovalPolicy: "auto-edit"
    )
    #expect(
      config.turnApprovalPolicy == "auto-edit",
      "turnApprovalPolicy must inherit from sessionApprovalPolicy when nil"
    )
  }

  /// When both are nil, turnApprovalPolicy must remain nil.
  @Test func turnApprovalPolicyRemainsNilWhenBothNil() {
    let config = CodexProviderConfig()
    #expect(config.turnApprovalPolicy == nil)
  }

  /// When turnApprovalPolicy is explicitly set, it takes precedence
  /// over sessionApprovalPolicy.
  @Test func explicitTurnApprovalPolicyOverridesSession() {
    let config = CodexProviderConfig(
      sessionApprovalPolicy: "auto-edit",
      turnApprovalPolicy: "never"
    )
    #expect(
      config.turnApprovalPolicy == "never",
      "Explicit turnApprovalPolicy must override sessionApprovalPolicy"
    )
  }
}
