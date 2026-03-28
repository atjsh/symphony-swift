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
