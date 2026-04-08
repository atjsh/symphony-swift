import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore

@Test func runtimeLoggerEmitsStructuredJSONLinesWithContext() async throws {
  let (_, logs) = try await withCapturedRuntimeLogs {
    RuntimeLogger.log(
      level: .warning,
      event: "agent_run_failed",
      context: RuntimeLogContext(
        issueID: "I_42",
        issueIdentifier: "owner/repo#42",
        runID: "run-42",
        sessionID: "session-42",
        provider: "codex",
        providerSessionID: "provider-session-42",
        metadata: [
          "component": "SymphonyServer",
          "state": "finishing",
        ]
      ),
      error: "plain failure"
    )
  }

  let matchingLogs = logs.filter { $0.entry.runID == "run-42" }
  #expect(matchingLogs.count == 1)
  let log = try #require(matchingLogs.first)
  #expect(log.entry.event == "agent_run_failed")
  #expect(log.entry.level == "warning")
  #expect(log.entry.issueID == "I_42")
  #expect(log.entry.issueIdentifier == "owner/repo#42")
  #expect(log.entry.runID == "run-42")
  #expect(log.entry.sessionID == "session-42")
  #expect(log.entry.provider == "codex")
  #expect(log.entry.providerSessionID == "provider-session-42")
  #expect(log.entry.component == "SymphonyServer")
  #expect(log.entry.state == "finishing")
  #expect(log.entry.error == "plain failure")
  #expect(log.entry.timestamp != nil)
}

@Test func runtimeLoggerRedactsExplicitSecretsAndTokenLikeSubstrings() async throws {
  let (_, logs) = try await withCapturedRuntimeLogs {
    RuntimeLogger.log(
      level: .error,
      event: "workflow_reload_failed",
      context: RuntimeLogContext(
        metadata: [
          "authorization": "Bearer ghp_super_secret_token",
          "tracker_api_key": "github_pat_secret_value",
        ]
      ),
      error:
        "reload failed for token=ghp_super_secret_token authorization: bearer github_pat_secret_value",
      sensitiveValues: ["ghp_super_secret_token", "github_pat_secret_value"]
    )
  }

  let log = try #require(
    logs.first {
      $0.entry.event == "workflow_reload_failed"
        && $0.entry.trackerAPIKey != nil
    })
  let error = try #require(log.entry.error)
  #expect(error.contains("[REDACTED]"))
  #expect(!error.contains("ghp_super_secret_token"))
  #expect(!error.contains("github_pat_secret_value"))
  #expect(log.entry.authorization?.contains("[REDACTED]") == true)
  #expect(log.entry.trackerAPIKey?.contains("[REDACTED]") == true)
  #expect(!log.line.contains("ghp_super_secret_token"))
  #expect(!log.line.contains("github_pat_secret_value"))
}

// MARK: - Mutation-Targeted Runtime Logging Tests

@Test func runtimeLoggerOmitsEmptyErrorString() async throws {
  let (_, logs) = try await withCapturedRuntimeLogs {
    RuntimeLogger.log(
      level: .info,
      event: "mutation_empty_error",
      context: RuntimeLogContext(),
      error: ""
    )
  }

  let log = try #require(logs.first { $0.entry.event == "mutation_empty_error" })
  #expect(log.entry.error == nil, "Empty error string must not appear in payload")
}

@Test func runtimeLoggerOmitsEmptyContextFields() async throws {
  let (_, logs) = try await withCapturedRuntimeLogs {
    RuntimeLogger.log(
      level: .info,
      event: "mutation_empty_context",
      context: RuntimeLogContext(
        issueID: "",
        runID: "real-run",
        provider: ""
      )
    )
  }

  let log = try #require(logs.first { $0.entry.event == "mutation_empty_context" })
  #expect(log.entry.runID == "real-run")
  #expect(log.entry.issueID == nil, "Empty issueID must not appear in payload")
  #expect(log.entry.provider == nil, "Empty provider must not appear in payload")
}

@Test func runtimeLoggerMetadataDoesNotOverrideBuiltInFields() async throws {
  let (_, logs) = try await withCapturedRuntimeLogs {
    RuntimeLogger.log(
      level: .warning,
      event: "mutation_metadata_conflict",
      context: RuntimeLogContext(
        runID: "real-run",
        metadata: ["run_id": "fake-run", "level": "overridden"]
      )
    )
  }

  let log = try #require(logs.first { $0.entry.event == "mutation_metadata_conflict" })
  #expect(log.entry.runID == "real-run", "Built-in run_id must not be overridden by metadata")
  #expect(log.entry.level == "warning", "Built-in level must not be overridden by metadata")
}

@Test func runtimeLoggerHandlesWhitespaceOnlySensitiveValues() async throws {
  let (_, logs) = try await withCapturedRuntimeLogs {
    RuntimeLogger.log(
      level: .info,
      event: "mutation_whitespace_sensitive",
      context: RuntimeLogContext(),
      error: "token=ghp_real_123",
      sensitiveValues: ["  ", "ghp_real_123", ""]
    )
  }

  let log = try #require(logs.first { $0.entry.event == "mutation_whitespace_sensitive" })
  let error = try #require(log.entry.error)
  #expect(!error.contains("ghp_real_123"))
  #expect(error.contains("[REDACTED]"))
}
