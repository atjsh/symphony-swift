import Foundation
import SymphonyShared
import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore

// MARK: - SymphonyHTTPAPI: Progress Report Error Routes

@Test func progressReportEndpointRejectsNonGETMethod() throws {
  let databaseURL = try makeTemporaryDirectory().appendingPathComponent("api-method.sqlite3")
  let fixture = try makeFixtureRecords()
  let store = try SQLiteServerStateStore(databaseURL: databaseURL)
  try store.upsertRun(fixture.runDetail)

  let api = SymphonyHTTPAPI(
    store: store,
    version: "1.0.0",
    trackerKind: "github",
    progressReports: StubIssueProgressReportGenerator(
      result: .success(makeIssueProgressReport(issueID: fixture.issue.id))
    )
  )

  let response = try api.respond(
    to: SymphonyAPIRequest(
      method: "POST",
      path: "/api/v1/issues/\(fixture.issue.id.rawValue)/progress-report"
    )
  )
  #expect(response.statusCode == 405)
}

@Test func progressReportEndpointReturns404ForUnknownIssue() throws {
  let databaseURL = try makeTemporaryDirectory().appendingPathComponent("api-404.sqlite3")
  let store = try SQLiteServerStateStore(databaseURL: databaseURL)

  let api = SymphonyHTTPAPI(
    store: store,
    version: "1.0.0",
    trackerKind: "github",
    progressReports: StubIssueProgressReportGenerator(
      result: .failure(.workspaceUnavailable)
    )
  )

  let response = try api.respond(
    to: SymphonyAPIRequest(
      method: "GET",
      path: "/api/v1/issues/nonexistent-issue/progress-report"
    )
  )
  #expect(response.statusCode == 404)
  let decoded = try decodeBody(ErrorEnvelope.self, from: response)
  #expect(decoded.error.code == "issue_not_found")
}

@Test func progressReportEndpointReturns409WhenWorkspaceUnavailable() throws {
  let databaseURL = try makeTemporaryDirectory().appendingPathComponent("api-409.sqlite3")
  let fixture = try makeFixtureRecords()
  let store = try SQLiteServerStateStore(databaseURL: databaseURL)
  // Insert issue without a run (no workspace entry created)
  try store.upsertIssue(fixture.issue)

  let api = SymphonyHTTPAPI(
    store: store,
    version: "1.0.0",
    trackerKind: "github",
    progressReports: StubIssueProgressReportGenerator(
      result: .success(makeIssueProgressReport(issueID: fixture.issue.id))
    )
  )

  let response = try api.respond(
    to: SymphonyAPIRequest(
      method: "GET",
      path: "/api/v1/issues/\(fixture.issue.id.rawValue)/progress-report"
    )
  )
  #expect(response.statusCode == 409)
  let decoded = try decodeBody(ErrorEnvelope.self, from: response)
  #expect(decoded.error.code == "workspace_unavailable")
}

@Test func progressReportEndpointReturns503WhenReportsAreNil() throws {
  let databaseURL = try makeTemporaryDirectory().appendingPathComponent("api-503.sqlite3")
  let fixture = try makeFixtureRecords()
  let store = try SQLiteServerStateStore(databaseURL: databaseURL)
  try store.upsertRun(fixture.runDetail)

  let api = SymphonyHTTPAPI(
    store: store,
    version: "1.0.0",
    trackerKind: "github"
  )

  let response = try api.respond(
    to: SymphonyAPIRequest(
      method: "GET",
      path: "/api/v1/issues/\(fixture.issue.id.rawValue)/progress-report"
    )
  )
  #expect(response.statusCode == 503)
  let decoded = try decodeBody(ErrorEnvelope.self, from: response)
  #expect(decoded.error.code == "repository_history_unavailable")
}

// MARK: - IssueProgressReportGenerator Edge Cases

@Test func issueProgressReportThrowsForEmptyWorkspacePath() throws {
  let cacheDirectory = try makeTemporaryDirectory()
  let gitRunner = StubGitCommandRunner(
    headCommitID: "aaa",
    commitMetadata: [],
    treeEntriesByCommit: [:],
    activitiesByCommit: [:],
    blobMetricsByID: [:]
  )
  let generator = CachedIssueProgressReportGenerator(
    cacheDirectoryURL: cacheDirectory,
    analysisConfigProvider: { .defaults },
    gitRunner: gitRunner,
    fileClassifier: RepositoryFileClassifier(
      detector: StubRepositoryLanguageDetector(
        testPaths: [], languagesByPath: [:], languageTypes: [:]
      )
    ),
    syntaxRunner: StubRepositorySyntaxHealthRunner(
      health: RepositorySyntaxHealth(status: .unsupported, checkedFileCount: 0, diagnosticCount: 0)
    )
  )

  #expect(throws: IssueProgressReportError.workspaceUnavailable) {
    _ = try generator.issueProgressReport(issueID: IssueID("test"), workspacePath: "   ")
  }
}

@Test func issueProgressReportThrowsForEmptyCommitHistory() throws {
  let cacheDirectory = try makeTemporaryDirectory()
  let gitRunner = StubGitCommandRunner(
    headCommitID: "abcdef123",
    commitMetadata: [],
    treeEntriesByCommit: [:],
    activitiesByCommit: [:],
    blobMetricsByID: [:]
  )
  let generator = CachedIssueProgressReportGenerator(
    cacheDirectoryURL: cacheDirectory,
    analysisConfigProvider: { .defaults },
    gitRunner: gitRunner,
    fileClassifier: RepositoryFileClassifier(
      detector: StubRepositoryLanguageDetector(
        testPaths: [], languagesByPath: [:], languageTypes: [:]
      )
    ),
    syntaxRunner: StubRepositorySyntaxHealthRunner(
      health: RepositorySyntaxHealth(status: .unsupported, checkedFileCount: 0, diagnosticCount: 0)
    )
  )

  do {
    _ = try generator.issueProgressReport(
      issueID: IssueID("test"), workspacePath: "/tmp/workspace"
    )
    Issue.record("Expected repositoryHistoryUnavailable error.")
  } catch let error as IssueProgressReportError {
    #expect(error == .repositoryHistoryUnavailable("Repository history is unavailable."))
  }
}

@Test func issueProgressReportSkipsEntriesWithMissingBlobMetrics() throws {
  let cacheDirectory = try makeTemporaryDirectory()
  let gitRunner = StubGitCommandRunner(
    headCommitID: "aaaa1111",
    commitMetadata: [
      .init(
        commitID: "aaaa1111", shortID: "aaaa111", subject: "Init",
        authorName: "Dev", committedAt: "2026-03-20T12:00:00Z"
      )
    ],
    treeEntriesByCommit: [
      "aaaa1111": [
        .init(blobID: "known-blob", path: "Sources/App.swift"),
        .init(blobID: "missing-blob", path: "Sources/Unknown.swift"),
      ]
    ],
    activitiesByCommit: [
      "aaaa1111": .init(changedFileCount: 2, additions: 10, deletions: 0)
    ],
    blobMetricsByID: [
      "known-blob": .make(from: Data("let x = 1\n".utf8))
      // "missing-blob" intentionally absent
    ]
  )
  let generator = CachedIssueProgressReportGenerator(
    cacheDirectoryURL: cacheDirectory,
    analysisConfigProvider: { .defaults },
    gitRunner: gitRunner,
    fileClassifier: RepositoryFileClassifier(
      detector: StubRepositoryLanguageDetector(
        testPaths: [],
        languagesByPath: ["Sources/App.swift": "Swift"],
        languageTypes: ["Swift": "programming"]
      )
    ),
    syntaxRunner: StubRepositorySyntaxHealthRunner(
      health: RepositorySyntaxHealth(status: .unsupported, checkedFileCount: 0, diagnosticCount: 0)
    )
  )

  let report = try generator.issueProgressReport(
    issueID: IssueID("test"), workspacePath: "/tmp/workspace"
  )
  // Only 1 file counted (the missing blob entry is skipped)
  #expect(report.report.summary.fileCount == 1)
}

// MARK: - UnavailableRepositoryLanguageDetector

@Test func unavailableRepositoryLanguageDetectorReturnsStubValues() throws {
  let detector = UnavailableRepositoryLanguageDetector()

  #expect(detector.version == "unavailable")
  #expect(try detector.isConfiguration(path: "config.json") == false)
  #expect(try detector.isDocumentation(path: "README.md") == false)
  #expect(try detector.isDotFile(path: ".gitignore") == false)
  #expect(try detector.isImage(path: "logo.png") == false)
  #expect(try detector.isVendor(path: "vendor/lib.js") == false)
  #expect(try detector.isGenerated(path: "generated.swift", content: Data()) == false)
  #expect(try detector.isTest(path: "Tests/Test.swift") == false)
  #expect(try detector.language(path: "Main.swift", content: Data()) == nil)
  #expect(try detector.languageType(language: "Swift") == nil)
}

// MARK: - ProcessRepositorySyntaxHealthRunner: Unsupported Path

@Test func processRepositorySyntaxHealthRunnerReturnsUnsupportedForNilCommand() {
  let runner = ProcessRepositorySyntaxHealthRunner()
  let health = runner.syntaxHealth(
    in: "/tmp",
    syntaxConfig: AnalysisSyntaxConfig(command: nil)
  )
  #expect(health.status == .unsupported)
  #expect(health.checkedFileCount == 0)
}

// MARK: - BlobMetrics: Binary & Empty Content

@Test func blobMetricsReturnNilTextMetricsForBinaryContent() {
  let binaryData = Data([0x89, 0x50, 0x4E, 0x47, 0x00, 0xFF])
  let metrics = BlobMetrics.make(from: binaryData)
  #expect(metrics.textMetrics == nil)
}

@Test func blobMetricsReturnZeroLinesForEmptyContent() {
  let metrics = BlobMetrics.make(from: Data())
  #expect(metrics.textMetrics != nil)
  #expect(metrics.textMetrics?.lineCount == 0)
  #expect(metrics.textMetrics?.characterCount == 0)
}
