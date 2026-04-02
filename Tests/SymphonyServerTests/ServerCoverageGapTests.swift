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

// MARK: - RepositoryHistoryBucketer Edge Cases

@Test func bucketerSkipsCommitsWithInvalidDates() {
  let activity = RepositoryGitActivitySummary(changedFileCount: 1, additions: 10, deletions: 0)
  let snapshot = RepositoryMetricsSnapshot(
    fileCount: 1, sourceFileCount: 1, testFileCount: 0, otherFileCount: 0,
    lineCount: 10, characterCount: 50, byteCount: 50
  )
  let commits = [
    RepositoryHistoryCommit(
      commitID: "aaa", shortID: "aaa", subject: "Init", authorName: "Dev",
      committedAt: "not-a-date", metrics: snapshot, activity: activity
    ),
  ]
  let buckets = RepositoryHistoryBucketer.makeBuckets(from: commits)
  #expect(buckets.isEmpty)
}

@Test func bucketerSortsAcrossYears() {
  let activity = RepositoryGitActivitySummary(changedFileCount: 1, additions: 10, deletions: 0)
  let snapshot = RepositoryMetricsSnapshot(
    fileCount: 1, sourceFileCount: 1, testFileCount: 0, otherFileCount: 0,
    lineCount: 10, characterCount: 50, byteCount: 50
  )
  let commits = [
    RepositoryHistoryCommit(
      commitID: "a", shortID: "a", subject: "2025", authorName: "Dev",
      committedAt: "2025-12-29T12:00:00Z", metrics: snapshot, activity: activity
    ),
    RepositoryHistoryCommit(
      commitID: "b", shortID: "b", subject: "2026", authorName: "Dev",
      committedAt: "2026-01-05T12:00:00Z", metrics: snapshot, activity: activity
    ),
  ]
  let buckets = RepositoryHistoryBucketer.makeBuckets(from: commits)
  #expect(buckets.count >= 1)
  // If they fall in different ISO weeks, the first bucket should be 2025
  if buckets.count >= 2 {
    #expect(buckets[0].label < buckets[1].label)
  }
}

// MARK: - IssueProgressReportGenerator: Empty Head Commit

@Test func issueProgressReportThrowsForEmptyHeadCommitID() throws {
  let cacheDirectory = try makeTemporaryDirectory()
  let gitRunner = StubGitCommandRunner(
    headCommitID: "  \n  ",
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

  #expect(throws: IssueProgressReportError.self) {
    _ = try generator.issueProgressReport(issueID: IssueID("test"), workspacePath: "/tmp/workspace")
  }
}

// MARK: - IssueProgressReportGenerator: Binary Numstat Activity

@Test func issueProgressReportHandlesBinaryNumstatOutput() throws {
  let cacheDirectory = try makeTemporaryDirectory()
  // Binary files in numstat have "-" for additions/deletions
  let gitRunner = StubGitCommandRunnerWithCustomActivity(
    headCommitID: "aaaa1111",
    commitMetadata: [
      .init(
        commitID: "aaaa1111", shortID: "aaaa111", subject: "Add binary",
        authorName: "Dev", committedAt: "2026-03-20T12:00:00Z"
      )
    ],
    treeEntriesByCommit: [
      "aaaa1111": [
        .init(blobID: "blob1", path: "Sources/App.swift")
      ]
    ],
    activityOutput: "-\t-\timage.png\n5\t2\tSources/App.swift\n",
    blobMetricsByID: [
      "blob1": .make(from: Data("hello\n".utf8))
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
  // Binary file "-" values should be skipped (not parsed as Int), but file still counted
  let lastCommit = report.report.commits.last
  #expect(lastCommit?.activity.changedFileCount == 2)
  #expect(lastCommit?.activity.additions == 5) // Only the non-binary file counted
}

// MARK: - IssueProgressReportGenerator: Malformed Tree Entries

@Test func issueProgressReportSkipsMalformedTreeEntries() throws {
  let cacheDirectory = try makeTemporaryDirectory()
  let gitRunner = StubGitCommandRunnerWithCustomTreeOutput(
    headCommitID: "aaaa1111",
    commitMetadata: [
      .init(
        commitID: "aaaa1111", shortID: "aaaa111", subject: "Init",
        authorName: "Dev", committedAt: "2026-03-20T12:00:00Z"
      )
    ],
    // Tree output with a malformed record (no tab separator) followed by a valid one
    treeOutput: {
      var data = Data()
      // Malformed record: no tab separator
      data.append(Data("100644 blob".utf8))
      data.append(0) // null separator
      // Valid record
      data.append(Data("100644 blob validblob\tSources/Main.swift".utf8))
      data.append(0)
      return data
    }(),
    activityOutput: "1\t0\tSources/Main.swift\n",
    blobMetricsByID: [
      "validblob": .make(from: Data("let x = 1\n".utf8))
    ]
  )
  let generator = CachedIssueProgressReportGenerator(
    cacheDirectoryURL: cacheDirectory,
    analysisConfigProvider: { .defaults },
    gitRunner: gitRunner,
    fileClassifier: RepositoryFileClassifier(
      detector: StubRepositoryLanguageDetector(
        testPaths: [],
        languagesByPath: ["Sources/Main.swift": "Swift"],
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
  // Only the valid entry should be counted
  #expect(report.report.summary.fileCount == 1)
}

// MARK: - WorkflowAnalysisConfigStore

@Test func workflowAnalysisConfigStoreReturnsCurrentConfig() {
  let config = AnalysisConfig.defaults
  let store = WorkflowAnalysisConfigStore(config: config)
  #expect(store.current.history.sourcePaths == config.history.sourcePaths)
  #expect(store.current.history.testPaths == config.history.testPaths)
}

@Test func workflowAnalysisConfigStoreUpdatesConfig() {
  let store = WorkflowAnalysisConfigStore(config: .defaults)
  let updated = AnalysisConfig(
    history: AnalysisHistoryConfig(
      sourcePaths: ["custom/**"],
      testPaths: ["custom_tests/**"]
    ),
    syntax: AnalysisSyntaxConfig(command: "lint")
  )
  store.update(updated)
  #expect(store.current.history.sourcePaths == ["custom/**"])
  #expect(store.current.syntax.command == "lint")
}
