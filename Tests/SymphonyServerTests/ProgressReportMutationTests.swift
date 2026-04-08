import Foundation
import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore
@testable import SymphonyShared

// MARK: - BlobMetrics Mutations

@Suite("BlobMetrics Mutations")
struct BlobMetricsMutationTests {
  @Test func emptyDataProducesEmptyTextMetrics() {
    let metrics = BlobMetrics.make(from: Data())
    // Empty Data has no null bytes and is valid UTF-8 (empty string)
    #expect(metrics.textMetrics != nil)
    #expect(metrics.textMetrics?.lineCount == 0)
    #expect(metrics.textMetrics?.byteCount == 0)
  }

  @Test func emptyStringHasZeroLines() {
    // The string "" (empty) should return lineCount 0 via the isEmpty guard.
    // Mutating !string.isEmpty → string.isEmpty would produce a nonzero count.
    let data = Data("".utf8)
    let metrics = BlobMetrics.make(from: data)
    #expect(metrics.textMetrics != nil, "Empty string is valid UTF-8 with no nulls")
    #expect(metrics.textMetrics?.lineCount == 0)
    #expect(metrics.textMetrics?.characterCount == 0)
    #expect(metrics.textMetrics?.byteCount == 0)
  }

  @Test func singleLineWithTrailingNewlineCountsAsOneLine() {
    let data = Data("hello\n".utf8)
    let metrics = BlobMetrics.make(from: data)
    // "hello\n": one newline character → reduce gives 1, last == "\n" → + 0 = 1
    #expect(metrics.textMetrics?.lineCount == 1)
  }

  @Test func singleLineWithoutTrailingNewlineCountsAsOneLine() {
    let data = Data("hello".utf8)
    let metrics = BlobMetrics.make(from: data)
    // "hello": zero newline characters → reduce gives 0, last != "\n" → + 1 = 1
    #expect(metrics.textMetrics?.lineCount == 1)
  }

  @Test func multiLineWithTrailingNewline() {
    let data = Data("a\nb\nc\n".utf8)
    let metrics = BlobMetrics.make(from: data)
    // 3 newlines → reduce gives 3, last == "\n" → + 0 = 3
    #expect(metrics.textMetrics?.lineCount == 3)
  }

  @Test func multiLineWithoutTrailingNewline() {
    let data = Data("a\nb\nc".utf8)
    let metrics = BlobMetrics.make(from: data)
    // 2 newlines → reduce gives 2, last != "\n" → + 1 = 3
    #expect(metrics.textMetrics?.lineCount == 3)
  }

  @Test func binaryContentContainingNullProducesNilTextMetrics() {
    var data = Data("text".utf8)
    data.append(0)
    data.append(Data("more".utf8))
    let metrics = BlobMetrics.make(from: data)
    #expect(metrics.textMetrics == nil, "Null byte signals binary content")
  }

  @Test func characterCountAndByteCountDifferForMultibyte() {
    let data = Data("café".utf8)
    let metrics = BlobMetrics.make(from: data)
    #expect(metrics.textMetrics?.characterCount == 4)
    #expect(metrics.textMetrics?.byteCount == 5, "é is 2 bytes in UTF-8")
  }
}

// MARK: - RepositoryHistoryBucketer Mutations

@Suite("RepositoryHistoryBucketer Mutations")
struct RepositoryHistoryBucketerMutationTests {
  private func makeCommit(
    committedAt: String,
    fileCount: Int = 1,
    sourceFileCount: Int = 1
  ) -> RepositoryHistoryCommit {
    RepositoryHistoryCommit(
      commitID: "abc\(committedAt.hashValue)",
      shortID: "abc",
      subject: "commit",
      authorName: "dev",
      committedAt: committedAt,
      metrics: RepositoryMetricsSnapshot(
        fileCount: fileCount,
        sourceFileCount: sourceFileCount,
        testFileCount: 0,
        otherFileCount: 0,
        lineCount: 100,
        characterCount: 500,
        byteCount: 600,
        largestFile: nil,
        smallestFile: nil,
        activity: nil
      ),
      activity: RepositoryGitActivitySummary(
        changedFileCount: 1, additions: 10, deletions: 0
      )
    )
  }

  @Test func singleCommitProducesOneBucket() {
    let commits = [makeCommit(committedAt: "2026-03-18T12:00:00Z")]
    let buckets = RepositoryHistoryBucketer.makeBuckets(from: commits)
    #expect(buckets.count == 1)
    #expect(buckets[0].rangeStart == buckets[0].rangeEnd)
    #expect(buckets[0].metrics.fileCount == 1)
  }

  @Test func twoCommitsSameWeekMergeWithMinMaxDates() {
    let early = makeCommit(committedAt: "2026-03-16T08:00:00Z", fileCount: 1)
    let late = makeCommit(committedAt: "2026-03-18T20:00:00Z", fileCount: 3)
    let buckets = RepositoryHistoryBucketer.makeBuckets(from: [early, late])

    #expect(buckets.count == 1, "Same ISO week → single bucket")
    // min(start) should be the earlier date
    #expect(buckets[0].rangeStart.contains("2026-03-16"))
    // max(end) should be the later date
    #expect(buckets[0].rangeEnd.contains("2026-03-18"))
    // Latest commit's metrics should be used (last wins)
    #expect(buckets[0].metrics.fileCount == 3)
  }

  @Test func differentWeeksProduceSortedBuckets() {
    let week12 = makeCommit(committedAt: "2026-03-18T12:00:00Z", fileCount: 2)
    let week13 = makeCommit(committedAt: "2026-03-25T12:00:00Z", fileCount: 5)
    let buckets = RepositoryHistoryBucketer.makeBuckets(from: [week13, week12])

    #expect(buckets.count == 2)
    // Buckets must be sorted chronologically (BucketKey.< comparison)
    #expect(buckets[0].rangeStart < buckets[1].rangeStart)
  }

  @Test func differentYearsProduceSortedBuckets() {
    let year2025 = makeCommit(committedAt: "2025-12-29T12:00:00Z", fileCount: 1)
    let year2026 = makeCommit(committedAt: "2026-01-05T12:00:00Z", fileCount: 2)
    let buckets = RepositoryHistoryBucketer.makeBuckets(from: [year2026, year2025])

    #expect(buckets.count == 2)
    // Year comparison in BucketKey.< must use yearForWeekOfYear
    #expect(buckets[0].rangeStart < buckets[1].rangeStart)
  }

  @Test func invalidDateSkipsCommit() {
    let valid = makeCommit(committedAt: "2026-03-18T12:00:00Z")
    let invalid = makeCommit(committedAt: "not-a-date")
    let buckets = RepositoryHistoryBucketer.makeBuckets(from: [valid, invalid])

    #expect(buckets.count == 1, "Invalid date must be skipped by guard-continue")
  }

  @Test func emptyCommitsProducesNoBuckets() {
    let buckets = RepositoryHistoryBucketer.makeBuckets(from: [])
    #expect(buckets.isEmpty)
  }
}

// MARK: - AggregateMetrics Boundary Tests (via Generator)

@Suite("AggregateMetrics Mutations")
struct AggregateMetricsMutationTests {
  @Test func largestAndSmallestFileTrackingWithSingleFile() throws {
    let cacheDir = try makeTemporaryDirectory()
    let gitRunner = StubGitCommandRunner(
      headCommitID: "aaa111",
      commitMetadata: [
        .init(
          commitID: "aaa111", shortID: "aaa", subject: "one",
          authorName: "dev", committedAt: "2026-03-18T12:00:00Z"
        )
      ],
      treeEntriesByCommit: [
        "aaa111": [.init(blobID: "blob1", path: "Sources/Main.swift")]
      ],
      activitiesByCommit: [
        "aaa111": .init(changedFileCount: 1, additions: 5, deletions: 0)
      ],
      blobMetricsByID: [
        "blob1": .make(from: Data("print(1)\n".utf8))
      ]
    )
    let detector = StubRepositoryLanguageDetector(
      testPaths: [],
      languagesByPath: ["Sources/Main.swift": "Swift"],
      languageTypes: ["Swift": "programming"]
    )
    let generator = CachedIssueProgressReportGenerator(
      cacheDirectoryURL: cacheDir,
      analysisConfigProvider: { .defaults },
      gitRunner: gitRunner,
      fileClassifier: RepositoryFileClassifier(detector: detector),
      syntaxRunner: StubRepositorySyntaxHealthRunner(
        health: RepositorySyntaxHealth(
          status: .unsupported, checkedFileCount: 0, diagnosticCount: 0
        )
      )
    )

    let report = try generator.issueProgressReport(
      issueID: IssueID("I1"), workspacePath: "/tmp/ws"
    )
    let summary = report.report.summary
    // Single file must be both largest AND smallest
    #expect(summary.largestFile?.path == "Sources/Main.swift")
    #expect(summary.smallestFile?.path == "Sources/Main.swift")
    #expect(summary.largestFile?.byteCount == summary.smallestFile?.byteCount)
  }

  @Test func largestAndSmallestFileWithDifferentSizes() throws {
    let cacheDir = try makeTemporaryDirectory()
    let smallContent = Data("x\n".utf8)     // 2 bytes
    let largeContent = Data(String(repeating: "x", count: 100).utf8)  // 100 bytes
    let gitRunner = StubGitCommandRunner(
      headCommitID: "bbb222",
      commitMetadata: [
        .init(
          commitID: "bbb222", shortID: "bbb", subject: "two",
          authorName: "dev", committedAt: "2026-03-18T12:00:00Z"
        )
      ],
      treeEntriesByCommit: [
        "bbb222": [
          .init(blobID: "small", path: "Sources/Small.swift"),
          .init(blobID: "large", path: "Sources/Large.swift"),
        ]
      ],
      activitiesByCommit: [
        "bbb222": .init(changedFileCount: 2, additions: 10, deletions: 0)
      ],
      blobMetricsByID: [
        "small": .make(from: smallContent),
        "large": .make(from: largeContent),
      ]
    )
    let detector = StubRepositoryLanguageDetector(
      testPaths: [],
      languagesByPath: [
        "Sources/Small.swift": "Swift",
        "Sources/Large.swift": "Swift",
      ],
      languageTypes: ["Swift": "programming"]
    )
    let generator = CachedIssueProgressReportGenerator(
      cacheDirectoryURL: cacheDir,
      analysisConfigProvider: { .defaults },
      gitRunner: gitRunner,
      fileClassifier: RepositoryFileClassifier(detector: detector),
      syntaxRunner: StubRepositorySyntaxHealthRunner(
        health: RepositorySyntaxHealth(
          status: .unsupported, checkedFileCount: 0, diagnosticCount: 0
        )
      )
    )

    let report = try generator.issueProgressReport(
      issueID: IssueID("I2"), workspacePath: "/tmp/ws"
    )
    let summary = report.report.summary
    #expect(summary.largestFile?.byteCount == 100)
    #expect(summary.smallestFile?.byteCount == 2)
    #expect(summary.largestFile?.path != summary.smallestFile?.path)
  }

  @Test func equalSizedFilesAreHandledByStrictComparison() throws {
    let cacheDir = try makeTemporaryDirectory()
    let content = Data("abc\n".utf8)  // 4 bytes each
    let gitRunner = StubGitCommandRunner(
      headCommitID: "ccc333",
      commitMetadata: [
        .init(
          commitID: "ccc333", shortID: "ccc", subject: "eq",
          authorName: "dev", committedAt: "2026-03-18T12:00:00Z"
        )
      ],
      treeEntriesByCommit: [
        "ccc333": [
          .init(blobID: "eq1", path: "Sources/A.swift"),
          .init(blobID: "eq2", path: "Sources/B.swift"),
        ]
      ],
      activitiesByCommit: [
        "ccc333": .init(changedFileCount: 2, additions: 4, deletions: 0)
      ],
      blobMetricsByID: [
        "eq1": .make(from: content),
        "eq2": .make(from: content),
      ]
    )
    let detector = StubRepositoryLanguageDetector(
      testPaths: [],
      languagesByPath: [
        "Sources/A.swift": "Swift",
        "Sources/B.swift": "Swift",
      ],
      languageTypes: ["Swift": "programming"]
    )
    let generator = CachedIssueProgressReportGenerator(
      cacheDirectoryURL: cacheDir,
      analysisConfigProvider: { .defaults },
      gitRunner: gitRunner,
      fileClassifier: RepositoryFileClassifier(detector: detector),
      syntaxRunner: StubRepositorySyntaxHealthRunner(
        health: RepositorySyntaxHealth(
          status: .unsupported, checkedFileCount: 0, diagnosticCount: 0
        )
      )
    )

    let report = try generator.issueProgressReport(
      issueID: IssueID("I3"), workspacePath: "/tmp/ws"
    )
    let summary = report.report.summary
    // Both files have equal size. The > (strict) means first file stays largest
    // and < (strict) means first file stays smallest. Neither should be nil.
    #expect(summary.largestFile != nil)
    #expect(summary.smallestFile != nil)
    #expect(summary.largestFile?.byteCount == summary.smallestFile?.byteCount)
  }

  @Test func emptyWorkspacePathThrows() throws {
    let cacheDir = try makeTemporaryDirectory()
    let gitRunner = StubGitCommandRunner(
      headCommitID: "xxx",
      commitMetadata: [],
      treeEntriesByCommit: [:],
      activitiesByCommit: [:],
      blobMetricsByID: [:]
    )
    let generator = CachedIssueProgressReportGenerator(
      cacheDirectoryURL: cacheDir,
      analysisConfigProvider: { .defaults },
      gitRunner: gitRunner,
      syntaxRunner: StubRepositorySyntaxHealthRunner(
        health: RepositorySyntaxHealth(
          status: .unsupported, checkedFileCount: 0, diagnosticCount: 0
        )
      )
    )

    #expect(throws: IssueProgressReportError.self) {
      try generator.issueProgressReport(issueID: IssueID("I0"), workspacePath: "   ")
    }
  }

  @Test func whitespaceOnlyWorkspacePathThrows() throws {
    let cacheDir = try makeTemporaryDirectory()
    let gitRunner = StubGitCommandRunner(
      headCommitID: "xxx",
      commitMetadata: [],
      treeEntriesByCommit: [:],
      activitiesByCommit: [:],
      blobMetricsByID: [:]
    )
    let generator = CachedIssueProgressReportGenerator(
      cacheDirectoryURL: cacheDir,
      analysisConfigProvider: { .defaults },
      gitRunner: gitRunner,
      syntaxRunner: StubRepositorySyntaxHealthRunner(
        health: RepositorySyntaxHealth(
          status: .unsupported, checkedFileCount: 0, diagnosticCount: 0
        )
      )
    )

    #expect(throws: IssueProgressReportError.self) {
      try generator.issueProgressReport(issueID: IssueID("I0"), workspacePath: "\t\n")
    }
  }
}

// MARK: - BlockingResultBox Mutations

@Suite("BlockingResultBox Mutations")
struct BlockingResultBoxMutationTests {
  @Test func storeAndTakeSuccessValue() throws {
    let box = BlockingResultBox<Int>()
    box.store(.success(42))
    let value = try box.take().get()
    #expect(value == 42)
  }

  @Test func storeAndTakeFailureValue() {
    struct TestError: Error {}
    let box = BlockingResultBox<Int>()
    box.store(.failure(TestError()))
    let result = box.take()
    #expect(throws: TestError.self) { try result.get() }
  }
}

// MARK: - RepositoryClassificationCache Mutations

@Suite("RepositoryClassificationCache Mutations")
struct RepositoryClassificationCacheMutationTests {
  @Test func cachesResultOnSecondLookup() async throws {
    let cache = RepositoryClassificationCache()
    let key = ClassificationCacheKey(path: "Test.swift", blobID: "blob1")
    nonisolated(unsafe) var computeCount = 0

    let first = try await cache.category(for: key) {
      computeCount += 1
      return .test
    }
    let second = try await cache.category(for: key) {
      computeCount += 1
      return .source  // Should NOT be called
    }

    #expect(first == .test)
    #expect(second == .test, "Second lookup must return cached value")
    #expect(computeCount == 1, "Compute closure must only be called once")
  }

  @Test func differentKeysComputeIndependently() async throws {
    let cache = RepositoryClassificationCache()
    let key1 = ClassificationCacheKey(path: "A.swift", blobID: "blob1")
    let key2 = ClassificationCacheKey(path: "B.swift", blobID: "blob2")

    let cat1 = try await cache.category(for: key1) { .source }
    let cat2 = try await cache.category(for: key2) { .test }

    #expect(cat1 == .source)
    #expect(cat2 == .test)
  }
}
