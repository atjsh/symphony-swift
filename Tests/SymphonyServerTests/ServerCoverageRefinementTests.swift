import Foundation
import SymphonyShared
import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore

// MARK: - BucketKey Comparable: Same Year, Different Weeks

@Test func bucketerSortsSameYearDifferentWeeks() {
  let activity = RepositoryGitActivitySummary(changedFileCount: 1, additions: 1, deletions: 0)
  let snapshot = RepositoryMetricsSnapshot(
    fileCount: 1, sourceFileCount: 1, testFileCount: 0, otherFileCount: 0,
    lineCount: 1, characterCount: 1, byteCount: 1
  )
  // Two commits in the same year but different ISO weeks.
  let commits = [
    RepositoryHistoryCommit(
      commitID: "a", shortID: "a", subject: "W10", authorName: "Dev",
      committedAt: "2026-03-02T12:00:00Z", metrics: snapshot, activity: activity
    ),
    RepositoryHistoryCommit(
      commitID: "b", shortID: "b", subject: "W12", authorName: "Dev",
      committedAt: "2026-03-16T12:00:00Z", metrics: snapshot, activity: activity
    ),
  ]
  let buckets = RepositoryHistoryBucketer.makeBuckets(from: commits)
  #expect(buckets.count == 2)
  #expect(buckets[0].label < buckets[1].label)
}

// MARK: - BucketKey Comparable: Different Years

@Test func bucketerSortsDifferentYears() {
  let activity = RepositoryGitActivitySummary(changedFileCount: 1, additions: 1, deletions: 0)
  let snapshot = RepositoryMetricsSnapshot(
    fileCount: 1, sourceFileCount: 1, testFileCount: 0, otherFileCount: 0,
    lineCount: 1, characterCount: 1, byteCount: 1
  )
  // Two commits in different ISO years to exercise the yearForWeekOfYear < comparison.
  let commits = [
    RepositoryHistoryCommit(
      commitID: "a", shortID: "a", subject: "Y2025", authorName: "Dev",
      committedAt: "2025-06-15T12:00:00Z", metrics: snapshot, activity: activity
    ),
    RepositoryHistoryCommit(
      commitID: "b", shortID: "b", subject: "Y2026", authorName: "Dev",
      committedAt: "2026-06-15T12:00:00Z", metrics: snapshot, activity: activity
    ),
  ]
  let buckets = RepositoryHistoryBucketer.makeBuckets(from: commits)
  #expect(buckets.count == 2)
  #expect(buckets[0].label < buckets[1].label)
}

// MARK: - GlobPattern: Invalid Regex Returns No Match

@Test func fileClassifierHandlesInvalidGlobPatternGracefully() throws {
  let detector = StubRepositoryLanguageDetector(
    testPaths: [],
    languagesByPath: ["file.swift": "Swift"],
    languageTypes: ["Swift": "programming"]
  )
  let classifier = RepositoryFileClassifier(detector: detector)
  // The invalid glob "[" produces nil regex via try?, so matches() returns false.
  // Classifier falls through to language detector which returns "programming" → .source
  let category = try classifier.classify(
    path: "file.swift",
    content: Data("code".utf8),
    historyConfig: AnalysisHistoryConfig(sourcePaths: ["["], testPaths: [])
  )
  #expect(category == .source)
}

// MARK: - FileClassifier Returns .other for Non-Programming Language Type

@Test func fileClassifierReturnsOtherForDataLanguageType() throws {
  let detector = StubRepositoryLanguageDetector(
    testPaths: [],
    languagesByPath: ["data.json": "JSON"],
    languageTypes: ["JSON": "data"]
  )
  let classifier = RepositoryFileClassifier(detector: detector)
  let category = try classifier.classify(
    path: "data.json",
    content: Data("{}".utf8),
    historyConfig: .defaults
  )
  #expect(category == .other)
}

// MARK: - Generator Coverage Refinement (serialized to avoid semaphore thread exhaustion)

@Suite("Generator Coverage Refinement", .serialized)
struct GeneratorCoverageRefinementTests {

@Test func issueProgressReportCountsOtherCategoryFiles() throws {
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
        .init(blobID: "blob-data", path: "config.yaml")
      ]
    ],
    activitiesByCommit: [
      "aaaa1111": .init(changedFileCount: 1, additions: 1, deletions: 0)
    ],
    blobMetricsByID: [
      "blob-data": .make(from: Data("key: value\n".utf8))
    ]
  )
  let generator = CachedIssueProgressReportGenerator(
    cacheDirectoryURL: cacheDirectory,
    analysisConfigProvider: { .defaults },
    gitRunner: gitRunner,
    fileClassifier: RepositoryFileClassifier(
      detector: StubRepositoryLanguageDetector(
        testPaths: [],
        languagesByPath: ["config.yaml": "YAML"],
        languageTypes: ["YAML": "data"]
      )
    ),
    syntaxRunner: StubRepositorySyntaxHealthRunner(
      health: RepositorySyntaxHealth(status: .unsupported, checkedFileCount: 0, diagnosticCount: 0)
    )
  )

  let report = try generator.issueProgressReport(
    issueID: IssueID("test"), workspacePath: "/tmp/workspace"
  )
  #expect(report.report.summary.otherFileCount == 1)
  #expect(report.report.summary.sourceFileCount == 0)
  #expect(report.report.summary.testFileCount == 0)
}

// MARK: - Generator: Multi-File Commit Updates smallestFile

@Test func issueProgressReportTracksSmallestAndLargestFile() throws {
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
        .init(blobID: "blob-large", path: "Sources/Large.swift"),
        .init(blobID: "blob-small", path: "Sources/Small.swift"),
      ]
    ],
    activitiesByCommit: [
      "aaaa1111": .init(changedFileCount: 2, additions: 20, deletions: 0)
    ],
    blobMetricsByID: [
      "blob-large": .make(from: Data(String(repeating: "x", count: 500).utf8)),
      "blob-small": .make(from: Data("a\n".utf8)),
    ]
  )
  let generator = CachedIssueProgressReportGenerator(
    cacheDirectoryURL: cacheDirectory,
    analysisConfigProvider: { .defaults },
    gitRunner: gitRunner,
    fileClassifier: RepositoryFileClassifier(
      detector: StubRepositoryLanguageDetector(
        testPaths: [],
        languagesByPath: [
          "Sources/Large.swift": "Swift",
          "Sources/Small.swift": "Swift",
        ],
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
  #expect(report.report.summary.fileCount == 2)
  #expect(report.report.summary.largestFile?.path == "Sources/Large.swift")
  #expect(report.report.summary.smallestFile?.path == "Sources/Small.swift")
  #expect(report.report.summary.largestFile!.byteCount > report.report.summary.smallestFile!.byteCount)
}

// MARK: - Generator: Task Group Refill With concurrencyLimit=1

@Test func issueProgressReportRefillsTaskGroupWithLowConcurrency() throws {
  let cacheDirectory = try makeTemporaryDirectory()
  let gitRunner = StubGitCommandRunner(
    headCommitID: "bbbb2222",
    commitMetadata: [
      .init(
        commitID: "aaaa1111", shortID: "aaaa111", subject: "First",
        authorName: "Dev", committedAt: "2026-03-18T12:00:00Z"
      ),
      .init(
        commitID: "bbbb2222", shortID: "bbbb222", subject: "Second",
        authorName: "Dev", committedAt: "2026-03-20T12:00:00Z"
      ),
    ],
    treeEntriesByCommit: [
      "aaaa1111": [.init(blobID: "b1", path: "A.swift")],
      "bbbb2222": [.init(blobID: "b2", path: "B.swift")],
    ],
    activitiesByCommit: [
      "aaaa1111": .init(changedFileCount: 1, additions: 1, deletions: 0),
      "bbbb2222": .init(changedFileCount: 1, additions: 1, deletions: 0),
    ],
    blobMetricsByID: [
      "b1": .make(from: Data("a\n".utf8)),
      "b2": .make(from: Data("b\n".utf8)),
    ]
  )
  let generator = CachedIssueProgressReportGenerator(
    cacheDirectoryURL: cacheDirectory,
    analysisConfigProvider: { .defaults },
    gitRunner: gitRunner,
    fileClassifier: RepositoryFileClassifier(
      detector: StubRepositoryLanguageDetector(
        testPaths: [],
        languagesByPath: ["A.swift": "Swift", "B.swift": "Swift"],
        languageTypes: ["Swift": "programming"]
      )
    ),
    syntaxRunner: StubRepositorySyntaxHealthRunner(
      health: RepositorySyntaxHealth(status: .unsupported, checkedFileCount: 0, diagnosticCount: 0)
    ),
    analysisConcurrencyLimit: 1
  )

  let report = try generator.issueProgressReport(
    issueID: IssueID("test"), workspacePath: "/tmp/workspace"
  )
  #expect(report.report.commits.count == 2)
}

// MARK: - Generator: Malformed Numstat Lines Skipped

@Test func issueProgressReportSkipsMalformedNumstatLines() throws {
  let cacheDirectory = try makeTemporaryDirectory()
  let gitRunner = StubGitCommandRunnerWithCustomActivity(
    headCommitID: "aaaa1111",
    commitMetadata: [
      .init(
        commitID: "aaaa1111", shortID: "aaaa111", subject: "Init",
        authorName: "Dev", committedAt: "2026-03-20T12:00:00Z"
      )
    ],
    treeEntriesByCommit: [
      "aaaa1111": [.init(blobID: "blob1", path: "App.swift")]
    ],
    activityOutput: "10\t5\n3\t1\tApp.swift\n",
    blobMetricsByID: [
      "blob1": .make(from: Data("x\n".utf8))
    ]
  )
  let generator = CachedIssueProgressReportGenerator(
    cacheDirectoryURL: cacheDirectory,
    analysisConfigProvider: { .defaults },
    gitRunner: gitRunner,
    fileClassifier: RepositoryFileClassifier(
      detector: StubRepositoryLanguageDetector(
        testPaths: [],
        languagesByPath: ["App.swift": "Swift"],
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
  let activity = report.report.commits.last!.activity
  #expect(activity.changedFileCount == 1)
  #expect(activity.additions == 3)
  #expect(activity.deletions == 1)
}

// MARK: - Generator: Malformed Tree Entries Are Skipped

@Test func issueProgressReportSkipsMalformedTreeEntries() throws {
  let cacheDirectory = try makeTemporaryDirectory()
  // Build tree output with one valid entry and one malformed entry (no tab separator).
  var treeData = Data()
  // Valid: "100644 blob <hash>\t<path>"
  treeData.append(Data("100644 blob blobOK\tGood.swift".utf8))
  treeData.append(0)
  // Malformed: missing tab → firstIndex(of: 9) returns nil → return nil
  treeData.append(Data("malformed-no-tab".utf8))
  treeData.append(0)
  // Malformed: tab present but < 3 space-separated components → return nil
  treeData.append(Data("short\tpath.txt".utf8))
  treeData.append(0)

  let gitRunner = StubGitCommandRunnerWithCustomTreeOutput(
    headCommitID: "aaaa1111",
    commitMetadata: [
      .init(
        commitID: "aaaa1111", shortID: "aaaa111", subject: "Init",
        authorName: "Dev", committedAt: "2026-03-20T12:00:00Z"
      )
    ],
    treeOutput: treeData,
    activityOutput: "1\t0\tGood.swift\n",
    blobMetricsByID: [
      "blobOK": .make(from: Data("ok\n".utf8))
    ]
  )
  let generator = CachedIssueProgressReportGenerator(
    cacheDirectoryURL: cacheDirectory,
    analysisConfigProvider: { .defaults },
    gitRunner: gitRunner,
    fileClassifier: RepositoryFileClassifier(
      detector: StubRepositoryLanguageDetector(
        testPaths: [],
        languagesByPath: ["Good.swift": "Swift"],
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
  // Only the valid entry survives; malformed entries are silently skipped.
  #expect(report.report.summary.fileCount == 1)
}

// MARK: - Generator: Malformed Commit Metadata Causes repositoryHistoryUnavailable

@Test func issueProgressReportThrowsWhenAllCommitMetadataIsMalformed() throws {
  let cacheDirectory = try makeTemporaryDirectory()
  // Inject raw log output with only malformed lines (< 5 fields).
  // compactMap filters them all → empty commits → throw .repositoryHistoryUnavailable
  // The throw propagates through runBlocking's catch path.
  let gitRunner = StubGitCommandRunnerWithRawLogOutput(
    headCommitID: "aaaa1111",
    rawLogOutput: "bad-line-only-one-field\nalso-bad\ttwo-fields"
  )
  let generator = CachedIssueProgressReportGenerator(
    cacheDirectoryURL: cacheDirectory,
    analysisConfigProvider: { .defaults },
    gitRunner: gitRunner,
    fileClassifier: RepositoryFileClassifier(
      detector: StubRepositoryLanguageDetector(
        testPaths: [],
        languagesByPath: [:],
        languageTypes: [:]
      )
    ),
    syntaxRunner: StubRepositorySyntaxHealthRunner(
      health: RepositorySyntaxHealth(status: .unsupported, checkedFileCount: 0, diagnosticCount: 0)
    )
  )

  #expect(throws: IssueProgressReportError.self) {
    _ = try generator.issueProgressReport(
      issueID: IssueID("test"), workspacePath: "/tmp/workspace"
    )
  }
}

// MARK: - Generator: runBlocking Error Path

@Test func runBlockingErrorPathStoresFailure() throws {
  let cacheDirectory = try makeTemporaryDirectory()
  // Valid commit metadata so buildReport proceeds past the isEmpty guard,
  // but ls-tree throws → loadCommitSnapshots → runBlocking catches → resultBox.store(.failure)
  let gitRunner = StubThrowingTreeGitCommandRunner(
    headCommitID: "aaaa1111",
    commitMetadata: [
      .init(
        commitID: "aaaa1111", shortID: "aaaa111", subject: "Init",
        authorName: "Dev", committedAt: "2026-03-20T12:00:00Z"
      )
    ]
  )
  let generator = CachedIssueProgressReportGenerator(
    cacheDirectoryURL: cacheDirectory,
    analysisConfigProvider: { .defaults },
    gitRunner: gitRunner,
    fileClassifier: RepositoryFileClassifier(
      detector: StubRepositoryLanguageDetector(
        testPaths: [],
        languagesByPath: [:],
        languageTypes: [:]
      )
    ),
    syntaxRunner: StubRepositorySyntaxHealthRunner(
      health: RepositorySyntaxHealth(status: .unsupported, checkedFileCount: 0, diagnosticCount: 0)
    )
  )

  #expect(throws: (any Error).self) {
    _ = try generator.issueProgressReport(
      issueID: IssueID("test"), workspacePath: "/tmp/workspace"
    )
  }
}

} // end GeneratorCoverageRefinementTests
