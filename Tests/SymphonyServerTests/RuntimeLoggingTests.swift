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
