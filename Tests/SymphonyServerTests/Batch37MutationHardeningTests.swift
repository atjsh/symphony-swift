// Batch 37 — mutation hardening for RepositoryFileClassifier isExcluded chain,
// SymphonyHTTPAPI 405 catch-all branch isolation, and AgentRunner
// finalState log level ternaries.

import Foundation
import SymphonyShared
import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore

// MARK: - RepositoryFileClassifier isExcluded Chain Isolation

@Suite("RepositoryFileClassifier isExcluded Detector Isolation")
struct RepositoryFileClassifierExcludedChainTests {
  private let emptyHistory = AnalysisHistoryConfig(sourcePaths: [], testPaths: [])
  private let emptyContent = Data()

  @Test func configurationPathClassifiedAsOther() throws {
    let detector = StubRepositoryLanguageDetector(
      testPaths: [],
      languagesByPath: [:],
      languageTypes: [:],
      configurationPaths: ["package.json"]
    )
    let classifier = RepositoryFileClassifier(detector: detector)
    let result = try classifier.classify(
      path: "package.json", content: emptyContent, historyConfig: emptyHistory)
    #expect(result == .other)
  }

  @Test func documentationPathClassifiedAsOther() throws {
    let detector = StubRepositoryLanguageDetector(
      testPaths: [],
      languagesByPath: [:],
      languageTypes: [:],
      documentationPaths: ["README.md"]
    )
    let classifier = RepositoryFileClassifier(detector: detector)
    let result = try classifier.classify(
      path: "README.md", content: emptyContent, historyConfig: emptyHistory)
    #expect(result == .other)
  }

  @Test func imagePathClassifiedAsOther() throws {
    let detector = StubRepositoryLanguageDetector(
      testPaths: [],
      languagesByPath: [:],
      languageTypes: [:],
      imagePaths: ["logo.png"]
    )
    let classifier = RepositoryFileClassifier(detector: detector)
    let result = try classifier.classify(
      path: "logo.png", content: emptyContent, historyConfig: emptyHistory)
    #expect(result == .other)
  }

  @Test func generatedPathClassifiedAsOther() throws {
    let detector = StubRepositoryLanguageDetector(
      testPaths: [],
      languagesByPath: [:],
      languageTypes: [:],
      generatedPaths: ["generated.pb.go"]
    )
    let classifier = RepositoryFileClassifier(detector: detector)
    let result = try classifier.classify(
      path: "generated.pb.go", content: emptyContent, historyConfig: emptyHistory)
    #expect(result == .other)
  }
}

// MARK: - SymphonyHTTPAPI 405 Catch-All Branch Isolation

@Suite("SymphonyHTTPAPI 405 Catch-All Prefix Branches")
struct SymphonyHTTPAPI405CatchAllTests {

  @Test func runsPrefix405ForUnsupportedMethod() throws {
    let databaseURL = try makeTemporaryDirectory().appendingPathComponent("api-405-runs.sqlite3")
    let store = try SQLiteServerStateStore(databaseURL: databaseURL)
    let api = SymphonyHTTPAPI(store: store, version: "1.0.0", trackerKind: "github")

    // DELETE on /api/v1/runs (no trailing slash, not caught by /api/v1/runs/ handler)
    let response = try api.respond(
      to: SymphonyAPIRequest(method: "DELETE", path: "/api/v1/runs")
    )
    #expect(response.statusCode == 405)
    let body = try decodeBody(ErrorEnvelope.self, from: response)
    #expect(body.error.code == "method_not_allowed")
  }

  @Test func logsPrefix405ForUnsupportedMethod() throws {
    let databaseURL = try makeTemporaryDirectory().appendingPathComponent("api-405-logs.sqlite3")
    let store = try SQLiteServerStateStore(databaseURL: databaseURL)
    let api = SymphonyHTTPAPI(store: store, version: "1.0.0", trackerKind: "github")

    // DELETE on /api/v1/logs (no trailing slash, not caught by /api/v1/logs/ handler)
    let response = try api.respond(
      to: SymphonyAPIRequest(method: "DELETE", path: "/api/v1/logs")
    )
    #expect(response.statusCode == 405)
    let body = try decodeBody(ErrorEnvelope.self, from: response)
    #expect(body.error.code == "method_not_allowed")
  }

  @Test func runsSubpathPrefix405ForUnsupportedMethod() throws {
    let databaseURL = try makeTemporaryDirectory().appendingPathComponent("api-405-runs2.sqlite3")
    let store = try SQLiteServerStateStore(databaseURL: databaseURL)
    let api = SymphonyHTTPAPI(store: store, version: "1.0.0", trackerKind: "github")

    // PUT on /api/v1/runs-extended (matches prefix but not specific route)
    let response = try api.respond(
      to: SymphonyAPIRequest(method: "PUT", path: "/api/v1/runs-extended")
    )
    #expect(response.statusCode == 405)
  }
}

// MARK: - AgentRunner Final State Log Level

@Suite("AgentRunner Final State Log Level")
struct AgentRunnerFinalStateLogLevelTests {

  @Test func succeededRunLogsAtInfoLevel() async throws {
    let wsManager = StubWorkspaceManager()
    let launcher = StubProcessLauncher()
    let sink = CollectingEventSink()
    let runner = AgentRunner(
      workspaceManager: wsManager, processLauncher: launcher, eventSink: sink)

    let stubProcess = StubLaunchedProcess()
    launcher.setStubProcess(stubProcess)

    let issue = try makeIssue()
    let ctx = try makeRunContext()

    let task = Task {
      try await withCapturedRuntimeLogs {
        await runner.executeRun(
          context: ctx, issue: issue, config: .defaults,
          promptTemplate: "Fix: {{issue.title}}")
      }
    }

    await Task.yield()
    try await bootstrapWaitUntil("runner activates") { runner.activeRunCount > 0 }

    stubProcess.simulateOutput("{\"type\":\"message\"}\n")
    stubProcess.simulateTermination(exitCode: 0)

    let (result, logs) = try await task.value
    #expect(result.finalState == .succeeded)

    let completedLog = logs.first { $0.entry.event == "agent_run_completed" }
    #expect(completedLog != nil)
    #expect(completedLog?.entry.level == "info")
  }

  @Test func failedRunLogsAtErrorLevel() async throws {
    let wsManager = StubWorkspaceManager()
    let launcher = StubProcessLauncher()
    let sink = CollectingEventSink()
    let runner = AgentRunner(
      workspaceManager: wsManager, processLauncher: launcher, eventSink: sink)

    let stubProcess = StubLaunchedProcess()
    launcher.setStubProcess(stubProcess)

    let issue = try makeIssue()
    let ctx = try makeRunContext()

    let task = Task {
      try await withCapturedRuntimeLogs {
        await runner.executeRun(
          context: ctx, issue: issue, config: .defaults,
          promptTemplate: "Fix: {{issue.title}}")
      }
    }

    await Task.yield()
    try await bootstrapWaitUntil("runner activates") { runner.activeRunCount > 0 }

    stubProcess.simulateTermination(exitCode: 1)

    let (result, logs) = try await task.value
    #expect(result.finalState == .failed)

    let failedLog = logs.first { $0.entry.event == "agent_run_failed" }
    #expect(failedLog != nil)
    #expect(failedLog?.entry.level == "error")
  }
}
