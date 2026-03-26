import Testing

@testable import SymphonyRuntime

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

  let matchingLogs = logs.filter { $0.json["run_id"] as? String == "run-42" }
  #expect(matchingLogs.count == 1)
  let log = try #require(matchingLogs.first)
  #expect(log.json["event"] as? String == "agent_run_failed")
  #expect(log.json["level"] as? String == "warning")
  #expect(log.json["issue_id"] as? String == "I_42")
  #expect(log.json["issue_identifier"] as? String == "owner/repo#42")
  #expect(log.json["run_id"] as? String == "run-42")
  #expect(log.json["session_id"] as? String == "session-42")
  #expect(log.json["provider"] as? String == "codex")
  #expect(log.json["provider_session_id"] as? String == "provider-session-42")
  #expect(log.json["component"] as? String == "SymphonyServer")
  #expect(log.json["state"] as? String == "finishing")
  #expect(log.json["error"] as? String == "plain failure")
  #expect(log.json["timestamp"] as? String != nil)
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
      $0.json["event"] as? String == "workflow_reload_failed"
        && $0.json["tracker_api_key"] as? String != nil
    })
  let error = try #require(log.json["error"] as? String)
  #expect(error.contains("[REDACTED]"))
  #expect(!error.contains("ghp_super_secret_token"))
  #expect(!error.contains("github_pat_secret_value"))
  #expect((log.json["authorization"] as? String)?.contains("[REDACTED]") == true)
  #expect((log.json["tracker_api_key"] as? String)?.contains("[REDACTED]") == true)
  #expect(!log.line.contains("ghp_super_secret_token"))
  #expect(!log.line.contains("github_pat_secret_value"))
}
