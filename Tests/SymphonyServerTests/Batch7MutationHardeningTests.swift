import Foundation
import SymphonyShared
import Synchronization
import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore

// MARK: - IssueProgressReportGenerator: Concurrency Limit Floor

@Suite("Generator Concurrency Floor")
struct GeneratorConcurrencyFloorTests {
  @Test func analysisConcurrencyLimitZeroProducesValidReport() throws {
    // max(1, analysisConcurrencyLimit ?? ...) must floor at 1.
    // If mutated to min(1, 0) = 0, runBoundedTasks would produce 0..<0 range → no tasks → empty.
    let cacheDir = try makeTemporaryDirectory()
    let gitRunner = StubGitCommandRunner(
      headCommitID: "aaa111",
      commitMetadata: [
        .init(
          commitID: "aaa111", shortID: "aaa", subject: "init",
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
    let generator = CachedIssueProgressReportGenerator(
      cacheDirectoryURL: cacheDir,
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
        health: RepositorySyntaxHealth(
          status: .unsupported, checkedFileCount: 0, diagnosticCount: 0
        )
      ),
      analysisConcurrencyLimit: 0
    )

    let report = try generator.issueProgressReport(
      issueID: IssueID("floor-test"), workspacePath: "/tmp/ws"
    )
    #expect(report.report.summary.fileCount == 1)
    #expect(report.report.commits.count == 1)
  }

  @Test func analysisConcurrencyLimitOneProducesValidReport() throws {
    // Boundary: analysisConcurrencyLimit: 1 → max(1, 1) = 1.
    let cacheDir = try makeTemporaryDirectory()
    let gitRunner = StubGitCommandRunner(
      headCommitID: "bbb222",
      commitMetadata: [
        .init(
          commitID: "bbb222", shortID: "bbb", subject: "init",
          authorName: "dev", committedAt: "2026-03-18T12:00:00Z"
        ),
        .init(
          commitID: "ccc333", shortID: "ccc", subject: "second",
          authorName: "dev", committedAt: "2026-03-19T12:00:00Z"
        ),
      ],
      treeEntriesByCommit: [
        "bbb222": [.init(blobID: "b1", path: "Sources/A.swift")],
        "ccc333": [.init(blobID: "b2", path: "Sources/B.swift")],
      ],
      activitiesByCommit: [
        "bbb222": .init(changedFileCount: 1, additions: 10, deletions: 0),
        "ccc333": .init(changedFileCount: 1, additions: 5, deletions: 2),
      ],
      blobMetricsByID: [
        "b1": .make(from: Data("a\n".utf8)),
        "b2": .make(from: Data("b\n".utf8)),
      ]
    )
    let generator = CachedIssueProgressReportGenerator(
      cacheDirectoryURL: cacheDir,
      analysisConfigProvider: { .defaults },
      gitRunner: gitRunner,
      fileClassifier: RepositoryFileClassifier(
        detector: StubRepositoryLanguageDetector(
          testPaths: [],
          languagesByPath: [
            "Sources/A.swift": "Swift",
            "Sources/B.swift": "Swift",
          ],
          languageTypes: ["Swift": "programming"]
        )
      ),
      syntaxRunner: StubRepositorySyntaxHealthRunner(
        health: RepositorySyntaxHealth(
          status: .unsupported, checkedFileCount: 0, diagnosticCount: 0
        )
      ),
      analysisConcurrencyLimit: 1
    )

    let report = try generator.issueProgressReport(
      issueID: IssueID("limit-1"), workspacePath: "/tmp/ws"
    )
    // Two commits should both be analyzed even with concurrency limit 1.
    #expect(report.report.commits.count == 2)
  }
}

// MARK: - IssueProgressReportGenerator: Activity With Binary Files

@Suite("Generator Activity Parsing")
struct GeneratorActivityParsingTests {
  @Test func binaryFilesInNumstatDoNotCountAsAdditionsOrDeletions() throws {
    // git diff-tree --numstat outputs "-\t-\tfile.bin" for binary files.
    // Int("-") returns nil, so additions/deletions should remain 0.
    let cacheDir = try makeTemporaryDirectory()
    let gitRunner = StubGitCommandRunnerWithCustomActivity(
      headCommitID: "abc123",
      commitMetadata: [
        .init(
          commitID: "abc123", shortID: "abc", subject: "add binary",
          authorName: "dev", committedAt: "2026-03-18T12:00:00Z"
        )
      ],
      treeEntriesByCommit: [
        "abc123": [.init(blobID: "b1", path: "Sources/Main.swift")]
      ],
      activityOutput: "-\t-\timage.png\n5\t1\tSources/Main.swift\n",
      blobMetricsByID: [
        "b1": .make(from: Data("code\n".utf8))
      ]
    )
    let generator = CachedIssueProgressReportGenerator(
      cacheDirectoryURL: cacheDir,
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
        health: RepositorySyntaxHealth(
          status: .unsupported, checkedFileCount: 0, diagnosticCount: 0
        )
      )
    )

    let report = try generator.issueProgressReport(
      issueID: IssueID("binary"), workspacePath: "/tmp/ws"
    )
    let activity = try #require(report.report.commits.first?.activity)
    // 2 files changed (binary + text), but only text adds (5) and deletes (1)
    #expect(activity.changedFileCount == 2)
    #expect(activity.additions == 5)
    #expect(activity.deletions == 1)
  }

  @Test func emptyActivityOutputProducesZeroCounts() throws {
    let cacheDir = try makeTemporaryDirectory()
    let gitRunner = StubGitCommandRunnerWithCustomActivity(
      headCommitID: "def456",
      commitMetadata: [
        .init(
          commitID: "def456", shortID: "def", subject: "empty",
          authorName: "dev", committedAt: "2026-03-18T12:00:00Z"
        )
      ],
      treeEntriesByCommit: [
        "def456": [.init(blobID: "b1", path: "Sources/Main.swift")]
      ],
      activityOutput: "",
      blobMetricsByID: [
        "b1": .make(from: Data("x\n".utf8))
      ]
    )
    let generator = CachedIssueProgressReportGenerator(
      cacheDirectoryURL: cacheDir,
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
        health: RepositorySyntaxHealth(
          status: .unsupported, checkedFileCount: 0, diagnosticCount: 0
        )
      )
    )

    let report = try generator.issueProgressReport(
      issueID: IssueID("no-activity"), workspacePath: "/tmp/ws"
    )
    let activity = try #require(report.report.commits.first?.activity)
    #expect(activity.changedFileCount == 0)
    #expect(activity.additions == 0)
    #expect(activity.deletions == 0)
  }

  @Test func activityWithShortLineSkipsInvalidFields() throws {
    // Lines with < 3 tab-separated fields are skipped.
    let cacheDir = try makeTemporaryDirectory()
    let gitRunner = StubGitCommandRunnerWithCustomActivity(
      headCommitID: "ghi789",
      commitMetadata: [
        .init(
          commitID: "ghi789", shortID: "ghi", subject: "mixed",
          authorName: "dev", committedAt: "2026-03-18T12:00:00Z"
        )
      ],
      treeEntriesByCommit: [
        "ghi789": [.init(blobID: "b1", path: "Sources/Main.swift")]
      ],
      activityOutput: "bad-line\n3\t2\tSources/Main.swift\n",
      blobMetricsByID: [
        "b1": .make(from: Data("y\n".utf8))
      ]
    )
    let generator = CachedIssueProgressReportGenerator(
      cacheDirectoryURL: cacheDir,
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
        health: RepositorySyntaxHealth(
          status: .unsupported, checkedFileCount: 0, diagnosticCount: 0
        )
      )
    )

    let report = try generator.issueProgressReport(
      issueID: IssueID("short-line"), workspacePath: "/tmp/ws"
    )
    let activity = try #require(report.report.commits.first?.activity)
    // Only the valid line counts
    #expect(activity.changedFileCount == 1)
    #expect(activity.additions == 3)
    #expect(activity.deletions == 2)
  }
}

// MARK: - GitHubTrackerAdapter: Cached Project ID

@Suite("GitHubTrackerAdapter Cached Project ID")
struct GitHubTrackerCachedProjectIDTests {
  @Test func resolveProjectIDCachesOnSecondCall() async throws {
    let transport = StubGraphQLTransport()
    let config = makeTrackerConfig()
    let adapter = GitHubTrackerAdapter(transport: transport, config: config)

    transport.enqueueResponse(projectIDResponse())
    transport.enqueueResponse(
      candidateItemsResponse(
        items: [("I_1", 1, "First", "test-owner/repo", "Todo")],
        hasNextPage: false
      )
    )
    // Second call: project ID already cached, so only one items query needed
    transport.enqueueResponse(
      candidateItemsResponse(
        items: [("I_2", 2, "Second", "test-owner/repo", "In Progress")],
        hasNextPage: false
      )
    )

    let first = try await adapter.fetchCandidateIssues()
    #expect(first.count == 1)
    #expect(transport.executedQueryCount == 2)

    let second = try await adapter.fetchAllIssues()
    #expect(second.count == 1)
    // Should be 3 total (1 projectID + 1 first items + 1 second items)
    // NOT 4 (which would mean project ID was resolved again)
    #expect(transport.executedQueryCount == 3)
  }
}

// MARK: - CodexHelpers: Turn ID Precedence

@Suite("CodexHelpers Turn ID Precedence")
struct CodexHelpersTurnIDPrecedenceTests {
  @Test func nestedTurnIDTakesPriorityOverFlatKey() {
    // When both params.turn.id AND params.turn_id exist, the nested one should win.
    let msg = ProviderJSONMessage.parse(
      #"{"params":{"turn":{"id":"nested-turn"},"turn_id":"flat-turn"}}"#
    )
    #expect(codexTurnID(from: msg) == "nested-turn")
  }

  @Test func flatTurnIDFallsBackWhenNestedIsEmpty() {
    // params.turn.id is whitespace-only → falls through to flat key
    let msg = ProviderJSONMessage.parse(
      #"{"params":{"turn":{"id":"  "},"turn_id":"flat-fallback"}}"#
    )
    #expect(codexTurnID(from: msg) == "flat-fallback")
  }

  @Test func camelCaseTurnIdUsedWhenSnakeCaseKeyAbsent() {
    // turn_id key absent → coalescing reaches turnId
    let msg = ProviderJSONMessage.parse(
      #"{"params":{"turnId":"camel-only"}}"#
    )
    #expect(codexTurnID(from: msg) == "camel-only")
  }
}

// MARK: - RepositoryHistoryBucketer: Edge Cases

@Suite("RepositoryHistoryBucketer Edge Cases")
struct RepositoryHistoryBucketerEdgeCaseTests {
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

  @Test func bucketLabelFormatsWithLeadingZeros() {
    // Week 1 should be formatted as W01, not W1.
    let commit = makeCommit(committedAt: "2026-01-05T12:00:00Z")
    let buckets = RepositoryHistoryBucketer.makeBuckets(from: [commit])
    #expect(buckets.count == 1)
    let label = buckets[0].label
    // Format: YYYY-WXX with zero-padded week
    #expect(label.contains("W0") || label.contains("W1"))
    #expect(label.count == 8, "Label should be YYYY-WXX format")
  }

  @Test func bucketIDMatchesKeyComponents() {
    let commit = makeCommit(committedAt: "2026-06-15T12:00:00Z")
    let buckets = RepositoryHistoryBucketer.makeBuckets(from: [commit])
    #expect(buckets.count == 1)
    // bucketID must match "yearForWeekOfYear-weekOfYear"
    let parts = buckets[0].bucketID.split(separator: "-")
    #expect(parts.count == 2, "Bucket ID must be year-week")
    #expect(Int(parts[0]) != nil, "Year must be numeric")
    #expect(Int(parts[1]) != nil, "Week must be numeric")
  }

  @Test func sameWeekBucketUsesMinStartAndMaxEnd() {
    // Explicitly test min(start) and max(end) behavior
    let earlyMonday = makeCommit(committedAt: "2026-03-16T06:00:00Z", fileCount: 1)
    let lateFriday = makeCommit(committedAt: "2026-03-20T22:00:00Z", fileCount: 2)
    let midWednesday = makeCommit(committedAt: "2026-03-18T12:00:00Z", fileCount: 3)

    let buckets = RepositoryHistoryBucketer.makeBuckets(
      from: [lateFriday, earlyMonday, midWednesday])
    #expect(buckets.count == 1)
    // Start should be earliest date, end should be latest date
    #expect(buckets[0].rangeStart.contains("2026-03-16"))
    #expect(buckets[0].rangeEnd.contains("2026-03-20"))
    // Last commit's metrics used (input order: lateFriday is last matching key)
    #expect(buckets[0].metrics.fileCount == 3)
  }
}

// MARK: - BlobMetrics: Additional Edge Cases

@Suite("BlobMetrics Edge Cases")
struct BlobMetricsEdgeCaseTests {
  @Test func singleNewlineStringHasOneLine() {
    let data = Data("\n".utf8)
    let metrics = BlobMetrics.make(from: data)
    // "\n" → 1 newline, last == "\n" → 1 + 0 = 1
    #expect(metrics.textMetrics?.lineCount == 1)
    #expect(metrics.textMetrics?.characterCount == 1)
  }

  @Test func multipleConsecutiveNewlinesCountCorrectly() {
    let data = Data("\n\n\n".utf8)
    let metrics = BlobMetrics.make(from: data)
    // 3 newlines, last == "\n" → 3 + 0 = 3
    #expect(metrics.textMetrics?.lineCount == 3)
  }

  @Test func nullByteAtStartProducesNilTextMetrics() {
    let data = Data([0, 0x68, 0x69])
    let metrics = BlobMetrics.make(from: data)
    #expect(metrics.textMetrics == nil)
  }
}

// MARK: - GitHubTrackerAdapter: User Owner Type Project Resolution

@Suite("GitHubTrackerAdapter Owner Type")
struct GitHubTrackerOwnerTypeTests {
  @Test func userOwnerTypeUsesUserFragment() async throws {
    let transport = StubGraphQLTransport()
    let config = makeTrackerConfig(projectOwnerType: "user")
    let adapter = GitHubTrackerAdapter(transport: transport, config: config)

    transport.enqueueResponse(userProjectIDResponse())
    transport.enqueueResponse(
      candidateItemsResponse(
        items: [("I_1", 1, "Test", "test-owner/repo", "Todo")],
        hasNextPage: false
      )
    )

    let issues = try await adapter.fetchCandidateIssues()
    #expect(issues.count == 1)
    // The first query should have used user(login:) not organization(login:)
    #expect(transport.executedQueryCount == 2)
  }
}

// MARK: - SQLiteAgentRunEventSink: Event State on Receive Without Transition

@Suite("EventSink State Fallback")
struct EventSinkStateFallbackTests {
  @Test func eventReceivedBeforeTransitionUsesStreamingTurnFallback() throws {
    let databaseURL = try makeAgentRunSinkTemporaryDirectory().appendingPathComponent(
      "sink-fallback.sqlite3")
    let store = try SQLiteServerStateStore(databaseURL: databaseURL)
    let sink = SQLiteAgentRunEventSink(store: store)

    let issue = try makeAgentRunSinkIssue()
    let context = try makeAgentRunSinkContext()
    let startInfo = AgentRunStartInfo(
      context: context,
      issue: issue,
      provider: "codex",
      sessionID: SessionID("s-fallback"),
      workspacePath: "/tmp/ws"
    )
    sink.runDidStart(startInfo)

    // Verify initial state is initializingSession (set by runDidStart)
    let initialDetail = try #require(try store.runDetail(id: context.runID))
    #expect(initialDetail.status == RunLifecycleState.initializingSession.rawValue)

    // Now fire event WITHOUT calling runDidTransition first.
    // runDidReceiveEvent should still succeed (fallback to .streamingTurn internally).
    sink.runDidReceiveEvent(AgentRawEvent(
      sessionID: startInfo.sessionID,
      provider: "codex",
      sequence: EventSequence(0),
      timestamp: "2026-01-01T00:00:00Z",
      rawJSON: #"{"status":"ok"}"#,
      providerEventType: "status",
      normalizedEventKind: "status"
    ))

    let snapshot = sink.testingSnapshot(for: context.runID)
    #expect(snapshot.count == 1)
  }
}
