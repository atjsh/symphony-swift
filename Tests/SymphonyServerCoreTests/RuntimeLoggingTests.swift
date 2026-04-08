import Foundation
import Testing

@testable import SymphonyServerCore

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

@Suite("RuntimeLogging", .serialized)
struct RuntimeLoggingTests {
  @Test func runtimeLoggerWritesStructuredJSONToSinkOverrideAndRedactsSensitiveData() throws {
    let originalSink = RuntimeLogHooks.sinkOverride
    defer { RuntimeLogHooks.sinkOverride = originalSink }

    let capturedLines = LockedStringBox()
    RuntimeLogHooks.sinkOverride = { capturedLines.append($0) }

    RuntimeLogger.log(
      level: .error,
      event: "provider.turn_failed",
      context: RuntimeLogContext(
        issueID: "issue-secret",
        issueIdentifier: "ISSUE-123",
        runID: "run-1",
        sessionID: "session-1",
        provider: "copilot",
        providerSessionID: "provider-session-1",
        metadata: [
          "authorization": "Bearer topsecret-token",
          "note": "contains topsecret-token",
          "provider": "ignored-provider",
          "token": "ghp_exampleSecret123",
        ]
      ),
      error: "api_key=topsecret-token sk-exampleSecret123",
      sensitiveValues: [" topsecret-token ", "issue-secret"]
    )

    #expect(capturedLines.values.count == 1)
    let payload = try runtimeLogPayload(from: capturedLines.values[0])
    #expect(payload["event"] == "provider.turn_failed")
    #expect(payload["level"] == "error")
    #expect(payload["issue_id"] == "[REDACTED]")
    #expect(payload["issue_identifier"] == "ISSUE-123")
    #expect(payload["run_id"] == "run-1")
    #expect(payload["session_id"] == "session-1")
    #expect(payload["provider"] == "copilot")
    #expect(payload["provider_session_id"] == "provider-session-1")
    #expect(payload["authorization"] == "Bearer [REDACTED]")
    #expect(payload["note"] == "contains [REDACTED]")
    #expect(payload["token"] == "[REDACTED]")
    #expect(payload["error"] == "api_key=[REDACTED]")
    #expect(payload["timestamp"] != nil)
  }

  @Test func runtimeLoggerFallsBackToStandardErrorWhenNoSinkOverrideExists() throws {
    let originalSink = RuntimeLogHooks.sinkOverride
    defer { RuntimeLogHooks.sinkOverride = originalSink }
    RuntimeLogHooks.sinkOverride = nil

    let output = try captureStandardError {
      RuntimeLogger.log(level: .info, event: "stderr.fallback")
    }

    #expect(output.hasSuffix("\n"))
    let payload = try runtimeLogPayload(fromCapturedOutput: output)
    #expect(payload["event"] == "stderr.fallback")
    #expect(payload["level"] == "info")
  }

  @Test func metadataDoesNotOverwriteContextFields() throws {
    let originalSink = RuntimeLogHooks.sinkOverride
    defer { RuntimeLogHooks.sinkOverride = originalSink }

    let capturedLines = LockedStringBox()
    RuntimeLogHooks.sinkOverride = { capturedLines.append($0) }

    RuntimeLogger.log(
      level: .info,
      event: "test.metadata_guard",
      context: RuntimeLogContext(
        runID: "context-run",
        metadata: [
          "run_id": "metadata-run",
          "custom_key": "custom_value",
        ]
      )
    )

    #expect(capturedLines.values.count == 1)
    let payload = try runtimeLogPayload(from: capturedLines.values[0])
    #expect(payload["run_id"] == "context-run", "Context run_id must not be overwritten by metadata")
    #expect(
      payload["custom_key"] == "custom_value", "Non-conflicting metadata must be preserved")
  }

  @Test func sensitiveValuesRedactedLongestFirst() throws {
    let originalSink = RuntimeLogHooks.sinkOverride
    defer { RuntimeLogHooks.sinkOverride = originalSink }

    let capturedLines = LockedStringBox()
    RuntimeLogHooks.sinkOverride = { capturedLines.append($0) }

    RuntimeLogger.log(
      level: .info,
      event: "test.redact_order",
      context: RuntimeLogContext(
        metadata: ["value": "topsecret"]
      ),
      sensitiveValues: ["secret", "topsecret"]
    )

    #expect(capturedLines.values.count == 1)
    let payload = try runtimeLogPayload(from: capturedLines.values[0])
    #expect(
      payload["value"] == "[REDACTED]",
      "Longest secret must be redacted first to fully replace overlapping values")
  }

  // MARK: - Mutation Hardening: Boundary Tests

  @Test func nilErrorNotIncludedInPayload() throws {
    let original = RuntimeLogHooks.sinkOverride
    defer { RuntimeLogHooks.sinkOverride = original }

    let captured = LockedStringBox()
    RuntimeLogHooks.sinkOverride = { captured.append($0) }

    RuntimeLogger.log(level: .info, event: "test.nil_error", error: nil)

    #expect(captured.values.count == 1)
    let payload = try runtimeLogPayload(from: captured.values[0])
    #expect(payload["error"] == nil, "nil error must not appear in payload")
  }

  @Test func emptyErrorNotIncludedInPayload() throws {
    let original = RuntimeLogHooks.sinkOverride
    defer { RuntimeLogHooks.sinkOverride = original }

    let captured = LockedStringBox()
    RuntimeLogHooks.sinkOverride = { captured.append($0) }

    RuntimeLogger.log(level: .info, event: "test.empty_error", error: "")

    #expect(captured.values.count == 1)
    let payload = try runtimeLogPayload(from: captured.values[0])
    #expect(payload["error"] == nil, "Empty error must not appear in payload (tests !error.isEmpty)")
  }

  @Test func nilContextFieldOmitsKey() throws {
    let original = RuntimeLogHooks.sinkOverride
    defer { RuntimeLogHooks.sinkOverride = original }

    let captured = LockedStringBox()
    RuntimeLogHooks.sinkOverride = { captured.append($0) }

    RuntimeLogger.log(
      level: .info,
      event: "test.nil_field",
      context: RuntimeLogContext(issueID: nil, runID: "r1")
    )

    #expect(captured.values.count == 1)
    let payload = try runtimeLogPayload(from: captured.values[0])
    #expect(payload["issue_id"] == nil, "nil context field must be omitted")
    #expect(payload["run_id"] == "r1")
  }

  @Test func emptyContextFieldOmitsKey() throws {
    let original = RuntimeLogHooks.sinkOverride
    defer { RuntimeLogHooks.sinkOverride = original }

    let captured = LockedStringBox()
    RuntimeLogHooks.sinkOverride = { captured.append($0) }

    RuntimeLogger.log(
      level: .info,
      event: "test.empty_field",
      context: RuntimeLogContext(issueID: "", runID: "r1")
    )

    #expect(captured.values.count == 1)
    let payload = try runtimeLogPayload(from: captured.values[0])
    #expect(payload["issue_id"] == nil, "Empty context field must be omitted (tests !value.isEmpty)")
    #expect(payload["run_id"] == "r1")
  }

  @Test func whitespaceOnlySensitiveValuesFiltered() throws {
    let original = RuntimeLogHooks.sinkOverride
    defer { RuntimeLogHooks.sinkOverride = original }

    let captured = LockedStringBox()
    RuntimeLogHooks.sinkOverride = { captured.append($0) }

    RuntimeLogger.log(
      level: .info,
      event: "test.ws_sensitive",
      context: RuntimeLogContext(metadata: ["key": "value secret123"]),
      sensitiveValues: ["  ", "\t", "secret123"]
    )

    #expect(captured.values.count == 1)
    let payload = try runtimeLogPayload(from: captured.values[0])
    #expect(
      payload["key"] == "value [REDACTED]",
      "Whitespace-only sensitive values must be filtered, real secrets still redacted"
    )
  }

  @Test func nonEmptyErrorIsRedacted() throws {
    let original = RuntimeLogHooks.sinkOverride
    defer { RuntimeLogHooks.sinkOverride = original }

    let captured = LockedStringBox()
    RuntimeLogHooks.sinkOverride = { captured.append($0) }

    RuntimeLogger.log(
      level: .error,
      event: "test.redact_error",
      error: "ghp_mySecretToken123",
      sensitiveValues: []
    )

    #expect(captured.values.count == 1)
    let payload = try runtimeLogPayload(from: captured.values[0])
    #expect(
      payload["error"] == "[REDACTED]",
      "GitHub token in error field must be redacted by tokenLikeValueRule"
    )
  }

  @Test func bearerTokenRedacted() throws {
    let original = RuntimeLogHooks.sinkOverride
    defer { RuntimeLogHooks.sinkOverride = original }

    let captured = LockedStringBox()
    RuntimeLogHooks.sinkOverride = { captured.append($0) }

    RuntimeLogger.log(
      level: .info,
      event: "test.bearer",
      context: RuntimeLogContext(metadata: ["auth": "Bearer abc123.xyz"])
    )

    #expect(captured.values.count == 1)
    let payload = try runtimeLogPayload(from: captured.values[0])
    #expect(payload["auth"] == "Bearer [REDACTED]")
  }

  @Test func keyValueSecretRedacted() throws {
    let original = RuntimeLogHooks.sinkOverride
    defer { RuntimeLogHooks.sinkOverride = original }

    let captured = LockedStringBox()
    RuntimeLogHooks.sinkOverride = { captured.append($0) }

    RuntimeLogger.log(
      level: .info,
      event: "test.kvredact",
      context: RuntimeLogContext(
        metadata: ["log": "api_key=supersecret123"]
      )
    )

    #expect(captured.values.count == 1)
    let payload = try runtimeLogPayload(from: captured.values[0])
    #expect(payload["log"]?.contains("supersecret123") == false, "Key-value secret must be redacted")
  }

  @Test func redactionRulesCompile() {
    // This test verifies the try! NSRegularExpression(...) calls don't crash.
    // The patterns are compile-time constants, so this is a smoke test.
    RuntimeLogger.log(level: .info, event: "test.compile_check")
  }
}

private func runtimeLogPayload(from line: String) throws -> [String: String] {
  let data = Data(line.utf8)
  return try JSONDecoder().decode([String: String].self, from: data)
}

private func runtimeLogPayload(fromCapturedOutput output: String) throws -> [String: String] {
  for line in output.split(whereSeparator: \.isNewline).reversed() {
    if let payload = try? runtimeLogPayload(from: String(line)) {
      return payload
    }
  }

  struct MissingStructuredRuntimeLog: Error {}
  throw MissingStructuredRuntimeLog()
}

private func captureStandardError(_ operation: () -> Void) throws -> String {
  let pipe = Pipe()
  let originalStandardError = dup(STDERR_FILENO)
  #expect(originalStandardError >= 0)
  guard originalStandardError >= 0 else { return "" }

  fflush(stderr)
  dup2(pipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO)

  operation()
  fflush(stderr)
  dup2(originalStandardError, STDERR_FILENO)
  close(originalStandardError)
  pipe.fileHandleForWriting.closeFile()
  let data = pipe.fileHandleForReading.readDataToEndOfFile()
  return String(decoding: data, as: UTF8.self)
}

private final class LockedStringBox: @unchecked Sendable {
  private let lock = NSLock()
  private var storage = [String]()

  func append(_ value: String) {
    lock.lock()
    storage.append(value)
    lock.unlock()
  }

  var values: [String] {
    lock.lock()
    defer { lock.unlock() }
    return storage
  }
}
