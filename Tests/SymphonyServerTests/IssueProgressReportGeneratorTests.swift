import Foundation
import SymphonyShared
import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore

@Test func repositoryFileClassifierHonorsOverridesAndDetectorSemantics() throws {
  let detector = StubRepositoryLanguageDetector(
    testPaths: ["integration/e2e.test.ts"],
    languagesByPath: [
      "Sources/App/Main.swift": "Swift",
      "Docs/Guide.md": "Markdown",
      "Scripts/config.json": "JSON",
    ],
    languageTypes: [
      "Swift": "programming",
      "Markdown": "markup",
      "JSON": "data",
    ],
    documentationPaths: ["Docs/Guide.md"],
    configurationPaths: ["Scripts/config.json"]
  )
  let classifier = RepositoryFileClassifier(detector: detector)
  let history = AnalysisHistoryConfig(
    sourcePaths: ["Config/Generated.swift"],
    testPaths: ["Tests/**"]
  )

  #expect(
    try classifier.classify(
      path: "Tests/App/MainTests.swift",
      content: Data("test".utf8),
      historyConfig: history
    ) == .test
  )
  #expect(
    try classifier.classify(
      path: "Config/Generated.swift",
      content: Data("generated".utf8),
      historyConfig: history
    ) == .source
  )
  #expect(
    try classifier.classify(
      path: "Sources/App/Main.swift",
      content: Data("print(1)".utf8),
      historyConfig: history
    ) == .source
  )
  #expect(
    try classifier.classify(
      path: "integration/e2e.test.ts",
      content: Data("test".utf8),
      historyConfig: history
    ) == .test
  )
  #expect(
    try classifier.classify(
      path: "Docs/Guide.md",
      content: Data("# Guide".utf8),
      historyConfig: history
    ) == .other
  )
  #expect(
    try classifier.classify(
      path: "Scripts/config.json",
      content: Data("{\"debug\":true}".utf8),
      historyConfig: history
    ) == .other
  )
}

@Test func cachedIssueProgressReportGeneratorBuildsReportsAndReusesCache() throws {
  let workspacePath = "/tmp/example-workspace"
  let issueID = IssueID("issue-42")
  let cacheDirectory = try makeTemporaryDirectory()
  let gitRunner = StubGitCommandRunner(
    headCommitID: "bbbbbbbb22222222",
    commitMetadata: [
      .init(
        commitID: "aaaaaaaa11111111",
        shortID: "aaaaaaa",
        subject: "Initial import",
        authorName: "Taylor",
        committedAt: "2026-03-18T12:00:00Z"
      ),
      .init(
        commitID: "bbbbbbbb22222222",
        shortID: "bbbbbbb",
        subject: "Add tests",
        authorName: "Taylor",
        committedAt: "2026-03-24T12:00:00Z"
      ),
    ],
    treeEntriesByCommit: [
      "aaaaaaaa11111111": [
        .init(blobID: "blob-main", path: "Sources/App/Main.swift"),
        .init(blobID: "blob-readme", path: "README.md"),
      ],
      "bbbbbbbb22222222": [
        .init(blobID: "blob-main", path: "Sources/App/Main.swift"),
        .init(blobID: "blob-readme", path: "README.md"),
        .init(blobID: "blob-test", path: "Tests/App/MainTests.swift"),
      ],
    ],
    activitiesByCommit: [
      "aaaaaaaa11111111": .init(changedFileCount: 2, additions: 40, deletions: 0),
      "bbbbbbbb22222222": .init(changedFileCount: 1, additions: 18, deletions: 2),
    ],
    blobMetricsByID: [
      "blob-main": .make(from: Data("print(\"hello\")\n".utf8)),
      "blob-readme": .make(from: Data("# README\n".utf8)),
      "blob-test": .make(from: Data("func testMain() {}\n".utf8)),
    ]
  )
  let detector = StubRepositoryLanguageDetector(
    testPaths: [],
    languagesByPath: [
      "Sources/App/Main.swift": "Swift",
      "README.md": "Markdown",
      "Tests/App/MainTests.swift": "Swift",
    ],
    languageTypes: [
      "Swift": "programming",
      "Markdown": "markup",
    ],
    documentationPaths: ["README.md"]
  )
  let generator = CachedIssueProgressReportGenerator(
    cacheDirectoryURL: cacheDirectory,
    analysisConfigProvider: {
      AnalysisConfig(
        history: AnalysisHistoryConfig(
          sourcePaths: ["Sources/**"],
          testPaths: ["Tests/**"]
        ),
        syntax: .defaults
      )
    },
    gitRunner: gitRunner,
    fileClassifier: RepositoryFileClassifier(detector: detector),
    syntaxRunner: StubRepositorySyntaxHealthRunner(
      health: RepositorySyntaxHealth(status: .unsupported, checkedFileCount: 0, diagnosticCount: 0)
    ),
    now: { Date(timeIntervalSince1970: 1_711_281_600) }
  )

  let report = try generator.issueProgressReport(issueID: issueID, workspacePath: workspacePath)

  #expect(report.issueID == issueID)
  #expect(report.report.headCommitID == "bbbbbbbb22222222")
  #expect(report.report.commits.count == 2)
  #expect(report.report.summary.fileCount == 3)
  #expect(report.report.summary.sourceFileCount == 1)
  #expect(report.report.summary.testFileCount == 1)
  #expect(report.report.summary.otherFileCount == 1)
  #expect(report.report.summary.activity?.changedFileCount == 1)
  #expect(report.syntaxHealth.status == .unsupported)
  #expect(gitRunner.loadedBlobBatches.count == 1)
  #expect(Set(gitRunner.loadedBlobBatches[0]) == ["blob-main", "blob-readme", "blob-test"])

  gitRunner.commitMetadata = []
  gitRunner.treeEntriesByCommit = [:]
  gitRunner.activitiesByCommit = [:]
  gitRunner.blobMetricsByID = [:]

  let cached = try generator.issueProgressReport(issueID: issueID, workspacePath: workspacePath)
  #expect(cached == report)
}

@Test func cachedIssueProgressReportGeneratorInvalidatesCacheWhenSyntaxCommandChanges() throws {
  let workspacePath = "/tmp/example-workspace"
  let issueID = IssueID("issue-42")
  let cacheDirectory = try makeTemporaryDirectory()
  let gitRunner = StubGitCommandRunner(
    headCommitID: "bbbbbbbb22222222",
    commitMetadata: [
      .init(
        commitID: "bbbbbbbb22222222",
        shortID: "bbbbbbb",
        subject: "Add tests",
        authorName: "Taylor",
        committedAt: "2026-03-24T12:00:00Z"
      )
    ],
    treeEntriesByCommit: [
      "bbbbbbbb22222222": [
        .init(blobID: "blob-main", path: "Sources/App/Main.swift")
      ]
    ],
    activitiesByCommit: [
      "bbbbbbbb22222222": .init(changedFileCount: 1, additions: 18, deletions: 2)
    ],
    blobMetricsByID: [
      "blob-main": .make(from: Data("print(\"hello\")\n".utf8))
    ]
  )
  let detector = StubRepositoryLanguageDetector(
    testPaths: [],
    languagesByPath: ["Sources/App/Main.swift": "Swift"],
    languageTypes: ["Swift": "programming"]
  )

  let initialGenerator = CachedIssueProgressReportGenerator(
    cacheDirectoryURL: cacheDirectory,
    analysisConfigProvider: { .defaults },
    gitRunner: gitRunner,
    fileClassifier: RepositoryFileClassifier(detector: detector),
    syntaxRunner: StubRepositorySyntaxHealthRunner(
      health: RepositorySyntaxHealth(status: .unsupported, checkedFileCount: 0, diagnosticCount: 0)
    )
  )
  let initial = try initialGenerator.issueProgressReport(issueID: issueID, workspacePath: workspacePath)
  #expect(initial.syntaxHealth.status == .unsupported)

  let refreshedGenerator = CachedIssueProgressReportGenerator(
    cacheDirectoryURL: cacheDirectory,
    analysisConfigProvider: {
      AnalysisConfig(
        history: .defaults,
        syntax: AnalysisSyntaxConfig(command: "echo syntax-health")
      )
    },
    gitRunner: gitRunner,
    fileClassifier: RepositoryFileClassifier(detector: detector),
    syntaxRunner: StubRepositorySyntaxHealthRunner(
      health: RepositorySyntaxHealth(
        status: .configured,
        checkedFileCount: 1,
        diagnosticCount: 1,
        diagnostics: [
          RepositorySyntaxDiagnostic(
            path: "Sources/App/Main.swift",
            message: "Unexpected token",
            severity: "error"
          )
        ]
      )
    )
  )

  let refreshed = try refreshedGenerator.issueProgressReport(
    issueID: issueID,
    workspacePath: workspacePath
  )
  #expect(refreshed.syntaxHealth.status == .configured)
  #expect(gitRunner.loadedBlobBatches.count == 2)
}

@Test func cachedIssueProgressReportGeneratorInvalidatesCacheWhenClassifierVersionChanges() throws {
  let workspacePath = "/tmp/example-workspace"
  let issueID = IssueID("issue-42")
  let cacheDirectory = try makeTemporaryDirectory()
  let gitRunner = StubGitCommandRunner(
    headCommitID: "bbbbbbbb22222222",
    commitMetadata: [
      .init(
        commitID: "bbbbbbbb22222222",
        shortID: "bbbbbbb",
        subject: "Add docs",
        authorName: "Taylor",
        committedAt: "2026-03-24T12:00:00Z"
      )
    ],
    treeEntriesByCommit: [
      "bbbbbbbb22222222": [
        .init(blobID: "blob-main", path: "Sources/App/Main.swift"),
        .init(blobID: "blob-readme", path: "README.md"),
      ]
    ],
    activitiesByCommit: [
      "bbbbbbbb22222222": .init(changedFileCount: 2, additions: 22, deletions: 1)
    ],
    blobMetricsByID: [
      "blob-main": .make(from: Data("print(\"hello\")\n".utf8)),
      "blob-readme": .make(from: Data("# README\n".utf8)),
    ]
  )

  let initialDetector = StubRepositoryLanguageDetector(
    testPaths: [],
    languagesByPath: [
      "Sources/App/Main.swift": "Swift",
      "README.md": "Markdown",
    ],
    languageTypes: [
      "Swift": "programming",
      "Markdown": "markup",
    ],
    documentationPaths: ["README.md"],
    version: "stub-v1"
  )
  let initialGenerator = CachedIssueProgressReportGenerator(
    cacheDirectoryURL: cacheDirectory,
    analysisConfigProvider: { .defaults },
    gitRunner: gitRunner,
    fileClassifier: RepositoryFileClassifier(detector: initialDetector),
    syntaxRunner: StubRepositorySyntaxHealthRunner(
      health: RepositorySyntaxHealth(status: .unsupported, checkedFileCount: 0, diagnosticCount: 0)
    )
  )
  let initial = try initialGenerator.issueProgressReport(issueID: issueID, workspacePath: workspacePath)
  #expect(initial.report.summary.sourceFileCount == 1)
  #expect(initial.report.summary.otherFileCount == 1)

  let refreshedDetector = StubRepositoryLanguageDetector(
    testPaths: [],
    languagesByPath: [
      "Sources/App/Main.swift": "Swift",
      "README.md": "Markdown",
    ],
    languageTypes: [
      "Swift": "programming",
      "Markdown": "markup",
    ],
    version: "stub-v2"
  )
  let refreshedGenerator = CachedIssueProgressReportGenerator(
    cacheDirectoryURL: cacheDirectory,
    analysisConfigProvider: { .defaults },
    gitRunner: gitRunner,
    fileClassifier: RepositoryFileClassifier(detector: refreshedDetector),
    syntaxRunner: StubRepositorySyntaxHealthRunner(
      health: RepositorySyntaxHealth(status: .unsupported, checkedFileCount: 0, diagnosticCount: 0)
    )
  )
  let refreshed = try refreshedGenerator.issueProgressReport(issueID: issueID, workspacePath: workspacePath)

  #expect(refreshed.report.summary.sourceFileCount == 2)
  #expect(refreshed.report.summary.otherFileCount == 0)
  #expect(gitRunner.loadedBlobBatches.count == 2)
}

@Test func processRepositorySyntaxHealthRunnerParsesJSONPayloads() throws {
  let workspacePath = try makeTemporaryDirectory().path
  let runner = ProcessRepositorySyntaxHealthRunner()

  let health = runner.syntaxHealth(
    in: workspacePath,
    syntaxConfig: AnalysisSyntaxConfig(
      command:
        #"printf '{"checked_file_count":2,"diagnostic_count":1,"diagnostics":[{"path":"Sources/App/Main.swift","message":"Unexpected token","severity":"error","line":3,"column":7}]}'"#
    )
  )

  #expect(health.status == .configured)
  #expect(health.checkedFileCount == 2)
  #expect(health.diagnosticCount == 1)
  #expect(health.diagnostics.first?.path == "Sources/App/Main.swift")
}

@Test func processRepositorySyntaxHealthRunnerMarksMalformedPayloadsAsFailed() throws {
  let workspacePath = try makeTemporaryDirectory().path
  let runner = ProcessRepositorySyntaxHealthRunner()

  let health = runner.syntaxHealth(
    in: workspacePath,
    syntaxConfig: AnalysisSyntaxConfig(command: "printf 'not-json'")
  )

  #expect(health.status == .failed)
  #expect(health.failureMessage?.isEmpty == false)
}

@Test func processRepositorySyntaxHealthRunnerMarksCommandFailuresAsFailed() throws {
  let workspacePath = try makeTemporaryDirectory().path
  let runner = ProcessRepositorySyntaxHealthRunner()

  let health = runner.syntaxHealth(
    in: workspacePath,
    syntaxConfig: AnalysisSyntaxConfig(command: "printf 'boom' >&2; exit 7")
  )

  #expect(health.status == .failed)
  #expect(health.failureMessage?.contains("boom") == true)
}

@Test func cachedIssueProgressReportGeneratorUsesBoundedConcurrentCommitAnalysis() throws {
  let workspacePath = "/tmp/example-workspace"
  let issueID = IssueID("issue-42")
  let cacheDirectory = try makeTemporaryDirectory()
  let gitRunner = ConcurrencyTrackingGitCommandRunner()
  let detector = StubRepositoryLanguageDetector(
    testPaths: [],
    languagesByPath: ["Sources/App/Main.swift": "Swift"],
    languageTypes: ["Swift": "programming"]
  )
  let generator = CachedIssueProgressReportGenerator(
    cacheDirectoryURL: cacheDirectory,
    analysisConfigProvider: { .defaults },
    gitRunner: gitRunner,
    fileClassifier: RepositoryFileClassifier(detector: detector),
    syntaxRunner: StubRepositorySyntaxHealthRunner(
      health: RepositorySyntaxHealth(status: .unsupported, checkedFileCount: 0, diagnosticCount: 0)
    ),
    analysisConcurrencyLimit: 2
  )

  let report = try generator.issueProgressReport(issueID: issueID, workspacePath: workspacePath)

  #expect(report.report.commits.count == 4)
  #expect(gitRunner.maxConcurrentGitLoads > 1)
  #expect(gitRunner.maxConcurrentGitLoads <= 2)
}
