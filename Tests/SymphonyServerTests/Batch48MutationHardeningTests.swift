// Batch 48 — mutation hardening for ProviderEventInspection.eventType
//
// Confirmed gaps in the copilotCLI and claudeCode branches of eventType:
//   - copilotCLI: error → "error" (RemoveSideEffects on the early-return guard)
//   - copilotCLI: method fallback in method ?? type ?? event ?? "unknown"
//   - copilotCLI: type fallback when method is nil
//   - claudeCode: type present (existing test only checked "unknown" fallback)

import Testing

@testable import SymphonyServer

// MARK: - CopilotCLI eventType Branch Coverage

@Suite("ProviderEventInspection.eventType — CopilotCLI")
struct CopilotCLIEventTypeBranchTests {

  @Test func copilotCLIErrorFieldReturnsError() {
    let desc = ProviderEventInspection.describe(
      from: #"{"error":{"message":"fatal"}}"#, provider: .copilotCLI
    )
    #expect(desc.eventType == "error")
  }

  @Test func copilotCLIMethodFallbackReturnsMethod() {
    let desc = ProviderEventInspection.describe(
      from: #"{"method":"session/update"}"#, provider: .copilotCLI
    )
    #expect(desc.eventType == "session/update")
  }

  @Test func copilotCLITypeFallbackWhenMethodNil() {
    let desc = ProviderEventInspection.describe(
      from: #"{"type":"progress"}"#, provider: .copilotCLI
    )
    #expect(desc.eventType == "progress")
  }
}

// MARK: - ClaudeCode eventType Branch Coverage

@Suite("ProviderEventInspection.eventType — ClaudeCode")
struct ClaudeCodeEventTypeBranchTests {

  @Test func claudeCodeTypePresentReturnsType() {
    let desc = ProviderEventInspection.describe(
      from: #"{"type":"assistant"}"#, provider: .claudeCode
    )
    #expect(desc.eventType == "assistant")
  }
}
