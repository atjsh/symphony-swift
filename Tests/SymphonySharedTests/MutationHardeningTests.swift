import Foundation
import SymphonyShared
import Testing

// MARK: - EventSequence Comparable

@Test func eventSequenceLessThanDistinguishesStrictOrdering() {
  let a = EventSequence(5)
  let b = EventSequence(5)
  let c = EventSequence(6)

  #expect(!(a < b), "Equal values must not satisfy strict less-than")
  #expect(a < c)
  #expect(!(c < a))
}

// MARK: - IssueIdentifier number boundary

@Test func issueIdentifierInitRejectsZeroNumber() throws {
  #expect(throws: SymphonySharedValidationError.self) {
    _ = try IssueIdentifier(owner: "owner", repository: "repo", number: 0)
  }

  _ = try IssueIdentifier(owner: "owner", repository: "repo", number: 1)
}

@Test func issueIdentifierValidatingRejectsZeroNumber() throws {
  #expect(throws: SymphonySharedValidationError.self) {
    _ = try IssueIdentifier(validating: "owner/repo#0")
  }

  let valid = try IssueIdentifier(validating: "owner/repo#1")
  #expect(valid.number == 1)
}

// MARK: - WorkspaceKey sanitization

@Test func workspaceKeySanitizationReplacesDisallowedCharacters() {
  let key = WorkspaceKey("hello/world#42")
  #expect(key.rawValue == "hello_world_42")

  let clean = WorkspaceKey("safe.name-ok_1")
  #expect(clean.rawValue == "safe.name-ok_1")

  let allBad = WorkspaceKey("@!$%^&*()")
  #expect(allBad.rawValue == "_________")
}

// MARK: - TokenUsage validation with matching total

@Test func tokenUsageAcceptsMatchingExplicitTotal() throws {
  let usage = try TokenUsage(inputTokens: 10, outputTokens: 5, totalTokens: 15)
  #expect(usage.inputTokens == 10)
  #expect(usage.outputTokens == 5)
  #expect(usage.totalTokens == 15)
}

@Test func tokenUsageRejectsMismatchedTotal() throws {
  #expect(throws: SymphonySharedValidationError.self) {
    _ = try TokenUsage(inputTokens: 10, outputTokens: 5, totalTokens: 16)
  }
}

// MARK: - JSONValue array subscript boundaries

@Test func jsonValueArraySubscriptBoundaryBehavior() {
  let array = JSONValue.array([.int(10), .int(20), .int(30)])

  #expect(array[0] == .int(10), "First element accessible at index 0")
  #expect(array[2] == .int(30), "Last element accessible at count-1")
  #expect(array[-1] == nil, "Negative index returns nil")
  #expect(array[3] == nil, "Index equal to count returns nil")
}

// MARK: - Data base64URL padding

@Test func base64URLRoundTripWithVariousLengths() {
  // 3 bytes → 4 base64 chars → remainder 0 (no padding needed)
  let threeBytes = Data([0xAA, 0xBB, 0xCC])
  let encoded3 = threeBytes.base64URLEncodedString()
  let decoded3 = Data(base64URLEncoded: encoded3)
  #expect(decoded3 == threeBytes)

  // 1 byte → 2 base64 chars → remainder 2 (needs 2 padding chars)
  let oneByte = Data([0xFF])
  let encoded1 = oneByte.base64URLEncodedString()
  let decoded1 = Data(base64URLEncoded: encoded1)
  #expect(decoded1 == oneByte)

  // 2 bytes → 3 base64 chars → remainder 3 (needs 1 padding char)
  let twoBytes = Data([0xDE, 0xAD])
  let encoded2 = twoBytes.base64URLEncodedString()
  let decoded2 = Data(base64URLEncoded: encoded2)
  #expect(decoded2 == twoBytes)

  // Verify no-remainder case: 6 bytes → 8 base64 chars → remainder 0
  let sixBytes = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06])
  let encoded6 = sixBytes.base64URLEncodedString()
  #expect(encoded6.count % 4 != 0 || Data(base64URLEncoded: encoded6) == sixBytes)
  let decoded6 = Data(base64URLEncoded: encoded6)
  #expect(decoded6 == sixBytes)
}
