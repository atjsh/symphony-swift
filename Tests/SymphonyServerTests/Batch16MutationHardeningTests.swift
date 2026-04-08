import Foundation
import SymphonyShared
import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore

// MARK: - IssueProgressReportGenerator: Malformed Git Output

@Suite("IssueProgressReport Malformed Input")
struct IssueProgressReportMalformedInputTests {
  /// ls-tree record missing tab separator → entry skipped via guard.
  /// Kills mutation: guard tabIndex removal or tab byte constant change.
  @Test func malformedLsTreeEntryWithoutTabIsSkipped() throws {
    let cacheDirectory = try makeTemporaryDirectory()
    let gitRunner = MalformedLsTreeGitRunner(headCommitID: "aaa111")
    let detector = StubRepositoryLanguageDetector(
      testPaths: [],
      languagesByPath: ["Sources/Main.swift": "Swift"],
      languageTypes: ["Swift": "programming"]
    )
    let generator = CachedIssueProgressReportGenerator(
      cacheDirectoryURL: cacheDirectory,
      analysisConfigProvider: { .defaults },
      gitRunner: gitRunner,
      fileClassifier: RepositoryFileClassifier(detector: detector),
      syntaxRunner: StubRepositorySyntaxHealthRunner(
        health: RepositorySyntaxHealth(status: .unsupported, checkedFileCount: 0, diagnosticCount: 0)
      )
    )

    let report = try generator.issueProgressReport(
      issueID: IssueID("I_1"),
      workspacePath: "/tmp/ws"
    )
    // Only the valid entry (with tab) produces metrics
    #expect(report.report.summary.fileCount == 1)
  }

  /// numstat output line with < 3 tab-separated fields → line skipped.
  /// Kills mutation: fields.count >= 3 boundary change.
  @Test func numstatLineWithFewerThanThreeFieldsSkipped() throws {
    let cacheDirectory = try makeTemporaryDirectory()
    let gitRunner = MalformedNumstatGitRunner(headCommitID: "bbb222")
    let detector = StubRepositoryLanguageDetector(
      testPaths: [],
      languagesByPath: ["Sources/Main.swift": "Swift"],
      languageTypes: ["Swift": "programming"]
    )
    let generator = CachedIssueProgressReportGenerator(
      cacheDirectoryURL: cacheDirectory,
      analysisConfigProvider: { .defaults },
      gitRunner: gitRunner,
      fileClassifier: RepositoryFileClassifier(detector: detector),
      syntaxRunner: StubRepositorySyntaxHealthRunner(
        health: RepositorySyntaxHealth(status: .unsupported, checkedFileCount: 0, diagnosticCount: 0)
      )
    )

    let report = try generator.issueProgressReport(
      issueID: IssueID("I_1"),
      workspacePath: "/tmp/ws"
    )
    // Only the well-formed 3-field line contributes additions/deletions
    let activity = try #require(report.report.commits.first?.activity)
    #expect(activity.additions == 10)
    #expect(activity.deletions == 2)
    #expect(activity.changedFileCount == 1)
  }

  /// ls-tree record with < 3 space-separated components → entry skipped.
  /// Kills mutation: components.count >= 3 guard.
  @Test func lsTreeEntryWithFewerThanThreeComponentsSkipped() throws {
    let cacheDirectory = try makeTemporaryDirectory()
    let gitRunner = MalformedLsTreeComponentsGitRunner(headCommitID: "ccc333")
    let detector = StubRepositoryLanguageDetector(
      testPaths: [],
      languagesByPath: ["Sources/Main.swift": "Swift"],
      languageTypes: ["Swift": "programming"]
    )
    let generator = CachedIssueProgressReportGenerator(
      cacheDirectoryURL: cacheDirectory,
      analysisConfigProvider: { .defaults },
      gitRunner: gitRunner,
      fileClassifier: RepositoryFileClassifier(detector: detector),
      syntaxRunner: StubRepositorySyntaxHealthRunner(
        health: RepositorySyntaxHealth(status: .unsupported, checkedFileCount: 0, diagnosticCount: 0)
      )
    )

    let report = try generator.issueProgressReport(
      issueID: IssueID("I_1"),
      workspacePath: "/tmp/ws"
    )
    // Only valid entry counted
    #expect(report.report.summary.fileCount == 1)
  }

  /// Concurrency limit of 0 clamped to 1 via max(1, ...).
  /// Kills mutation: max(1,...) → min(1,...) or constant change.
  @Test func zeroConcurrencyLimitClampedToOne() throws {
    let cacheDirectory = try makeTemporaryDirectory()
    let gitRunner = StubGitCommandRunner(
      headCommitID: "ddd444",
      commitMetadata: [
        .init(commitID: "ddd444", shortID: "ddd444", subject: "init",
              authorName: "A", committedAt: "2026-01-01T00:00:00Z")
      ],
      treeEntriesByCommit: [
        "ddd444": [.init(blobID: "b1", path: "Sources/Main.swift")]
      ],
      activitiesByCommit: [
        "ddd444": .init(changedFileCount: 1, additions: 5, deletions: 0)
      ],
      blobMetricsByID: [
        "b1": .make(from: Data("print(1)\n".utf8))
      ]
    )
    let detector = StubRepositoryLanguageDetector(
      testPaths: [],
      languagesByPath: ["Sources/Main.swift": "Swift"],
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
      analysisConcurrencyLimit: 0
    )

    // Should not crash — limit clamped to 1
    let report = try generator.issueProgressReport(
      issueID: IssueID("I_1"),
      workspacePath: "/tmp/ws"
    )
    #expect(report.report.commits.count == 1)
    #expect(report.report.summary.fileCount == 1)
  }

  /// Commit metadata line with fewer than 5 fields → skipped by compactMap.
  /// Kills mutation: fields.count == 5 guard.
  @Test func commitMetadataLineMissingFieldsSkipped() throws {
    let cacheDirectory = try makeTemporaryDirectory()
    let gitRunner = MalformedCommitMetadataGitRunner(headCommitID: "eee555")
    let detector = StubRepositoryLanguageDetector(
      testPaths: [],
      languagesByPath: ["Sources/Main.swift": "Swift"],
      languageTypes: ["Swift": "programming"]
    )
    let generator = CachedIssueProgressReportGenerator(
      cacheDirectoryURL: cacheDirectory,
      analysisConfigProvider: { .defaults },
      gitRunner: gitRunner,
      fileClassifier: RepositoryFileClassifier(detector: detector),
      syntaxRunner: StubRepositorySyntaxHealthRunner(
        health: RepositorySyntaxHealth(status: .unsupported, checkedFileCount: 0, diagnosticCount: 0)
      )
    )

    let report = try generator.issueProgressReport(
      issueID: IssueID("I_1"),
      workspacePath: "/tmp/ws"
    )
    // Only the valid 5-field line creates a commit
    #expect(report.report.commits.count == 1)
    #expect(report.report.commits[0].shortID == "eee555")
  }

  /// Empty HEAD commit → throws repositoryHistoryUnavailable.
  /// Kills mutation: guard !commitID.isEmpty removal.
  @Test func emptyHeadCommitThrows() throws {
    let cacheDirectory = try makeTemporaryDirectory()
    let gitRunner = StubGitCommandRunner(
      headCommitID: "  ",
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
        detector: StubRepositoryLanguageDetector(testPaths: [], languagesByPath: [:], languageTypes: [:])
      ),
      syntaxRunner: StubRepositorySyntaxHealthRunner(
        health: RepositorySyntaxHealth(status: .unsupported, checkedFileCount: 0, diagnosticCount: 0)
      )
    )

    #expect(throws: IssueProgressReportError.self) {
      _ = try generator.issueProgressReport(
        issueID: IssueID("I_1"),
        workspacePath: "/tmp/ws"
      )
    }
  }
}

// MARK: - GitHubTrackerAdapter: Repository Allowlist Filtering

@Suite("GitHubTracker Allowlist Filtering")
struct GitHubTrackerAllowlistFilteringTests {
  /// Non-empty allowlist blocks items from unlisted repos.
  /// Kills mutation: !allowlist.isEmpty inversion or allowlist.contains removal.
  @Test func nonEmptyAllowlistFiltersOutUnlistedRepositories() async throws {
    let transport = StubGraphQLTransport()
    let config = makeTrackerConfig(
      activeStates: ["Todo"],
      repositoryAllowlist: ["allowed-owner/allowed-repo"]
    )
    let adapter = GitHubTrackerAdapter(transport: transport, config: config)

    transport.enqueueResponse(projectIDResponse())
    transport.enqueueResponse(
      candidateItemsResponse(
        items: [
          ("I_1", 1, "Allowed", "allowed-owner/allowed-repo", "Todo"),
          ("I_2", 2, "Blocked", "other-owner/other-repo", "Todo"),
        ],
        hasNextPage: false
      )
    )

    let issues = try await adapter.fetchCandidateIssues()
    #expect(issues.count == 1)
    #expect(issues[0].identifier.description == "allowed-owner/allowed-repo#1")
  }

  /// Empty allowlist admits all repositories.
  /// Kills mutation: allowlist.isEmpty branch always taken.
  @Test func emptyAllowlistAdmitsAllRepositories() async throws {
    let transport = StubGraphQLTransport()
    let config = makeTrackerConfig(
      activeStates: ["Todo"],
      repositoryAllowlist: []
    )
    let adapter = GitHubTrackerAdapter(transport: transport, config: config)

    transport.enqueueResponse(projectIDResponse())
    transport.enqueueResponse(
      candidateItemsResponse(
        items: [
          ("I_1", 1, "Repo A", "owner-a/repo-a", "Todo"),
          ("I_2", 2, "Repo B", "owner-b/repo-b", "Todo"),
        ],
        hasNextPage: false
      )
    )

    let issues = try await adapter.fetchCandidateIssues()
    #expect(issues.count == 2)
  }
}

// MARK: - GitHubTrackerAdapter: State Extraction Paths

@Suite("GitHubTracker State Extraction")
struct GitHubTrackerStateExtractionTests {
  /// Response with mixed direct and content-nested state data.
  /// Kills mutation: else-if → if (both branches execute).
  @Test func fetchIssueStatesByIDsExercisesBothExtractionPaths() async throws {
    let transport = StubGraphQLTransport()
    let config = makeTrackerConfig()
    let adapter = GitHubTrackerAdapter(transport: transport, config: config)

    // One node has direct id+state, another has nested content.id+content.state
    let response = """
      {
        "data": {
          "node0": {"id": "I_DIRECT", "state": "OPEN"},
          "node1": {"content": {"id": "I_NESTED", "state": "CLOSED"}}
        }
      }
      """
    transport.enqueueResponse(response)

    let states = try await adapter.fetchIssueStatesByIDs(
      [IssueID("I_DIRECT"), IssueID("I_NESTED")]
    )
    #expect(states[IssueID("I_DIRECT")] == "OPEN")
    #expect(states[IssueID("I_NESTED")] == "CLOSED")
  }
}

// MARK: - GitHubTrackerAdapter: GraphQL Error Handling

@Suite("GitHubTracker GraphQL Errors")
struct GitHubTrackerGraphQLErrorTests {
  /// Response with GraphQL errors array triggers decodingFailed.
  /// Kills mutation: errors check removal or message join.
  @Test func responseWithGraphQLErrorsThrows() async throws {
    let transport = StubGraphQLTransport()
    let config = makeTrackerConfig(activeStates: ["Todo"])
    let adapter = GitHubTrackerAdapter(transport: transport, config: config)

    transport.enqueueResponse(projectIDResponse())
    transport.enqueueResponse("""
      {
        "data": null,
        "errors": [{"message": "rate limited"}, {"message": "try again"}]
      }
      """)

    await #expect(throws: GitHubTrackerError.self) {
      _ = try await adapter.fetchCandidateIssues()
    }
  }
}

// MARK: - IssueProgressReportGenerator: numstat Binary Entries

@Suite("IssueProgressReport Activity Parsing")
struct IssueProgressReportActivityParsingTests {
  /// numstat output with non-integer additions/deletions (binary file mark "-").
  /// Kills mutation: Int(fields[0]) nil coalescing.
  @Test func binaryFileNumstatLineCountsChangedFileOnly() throws {
    let cacheDirectory = try makeTemporaryDirectory()
    let gitRunner = BinaryNumstatGitRunner(headCommitID: "fff666")
    let detector = StubRepositoryLanguageDetector(
      testPaths: [],
      languagesByPath: ["Sources/Main.swift": "Swift"],
      languageTypes: ["Swift": "programming"]
    )
    let generator = CachedIssueProgressReportGenerator(
      cacheDirectoryURL: cacheDirectory,
      analysisConfigProvider: { .defaults },
      gitRunner: gitRunner,
      fileClassifier: RepositoryFileClassifier(detector: detector),
      syntaxRunner: StubRepositorySyntaxHealthRunner(
        health: RepositorySyntaxHealth(status: .unsupported, checkedFileCount: 0, diagnosticCount: 0)
      )
    )

    let report = try generator.issueProgressReport(
      issueID: IssueID("I_1"),
      workspacePath: "/tmp/ws"
    )
    let activity = try #require(report.report.commits.first?.activity)
    // Binary lines ("-\t-\tfile") count as changed file but 0 additions/deletions
    #expect(activity.changedFileCount == 2)
    #expect(activity.additions == 5)
    #expect(activity.deletions == 1)
  }
}

// MARK: - ProviderSessionSnapshotExtractor: Double-Valued Token Fields

@Suite("SnapshotExtractor Token Edge Cases")
struct SnapshotExtractorTokenEdgeTests {
  /// Token usage reported as double values (e.g. from non-integer JSON).
  /// Kills mutation: Int(doubleVal) path in intValue(from:).
  @Test func tokenUsageFromDoubleValues() {
    let rawJSON = """
      {"usage": {"input_tokens": 100.0, "output_tokens": 50.0}}
      """
    let event = AgentRawEvent(
      sessionID: SessionID("s1"),
      provider: "codex",
      sequence: EventSequence(1),
      timestamp: "2026-01-01T00:00:00Z",
      rawJSON: rawJSON,
      providerEventType: "usage",
      normalizedEventKind: "usage"
    )
    let update = ProviderSessionSnapshotExtractor.update(
      from: event, storedSequence: EventSequence(1)
    )
    #expect(update.tokenUsage?.inputTokens == 100)
    #expect(update.tokenUsage?.outputTokens == 50)
  }

  /// Token usage reported as string values (e.g. "100").
  /// Kills mutation: Int(string) path in intValue(from:).
  @Test func tokenUsageFromStringValues() {
    let rawJSON = """
      {"token_usage": {"input_tokens": "200", "output_tokens": "75"}}
      """
    let event = AgentRawEvent(
      sessionID: SessionID("s2"),
      provider: "codex",
      sequence: EventSequence(1),
      timestamp: "2026-01-01T00:00:00Z",
      rawJSON: rawJSON,
      providerEventType: "usage",
      normalizedEventKind: "usage"
    )
    let update = ProviderSessionSnapshotExtractor.update(
      from: event, storedSequence: EventSequence(1)
    )
    #expect(update.tokenUsage?.inputTokens == 200)
    #expect(update.tokenUsage?.outputTokens == 75)
  }

  /// Token usage with only totalTokens field.
  /// Kills mutation: totalTokens extraction key removal.
  @Test func tokenUsageWithOnlyTotalTokens() {
    let rawJSON = """
      {"usage": {"total_tokens": 500}}
      """
    let event = AgentRawEvent(
      sessionID: SessionID("s3"),
      provider: "codex",
      sequence: EventSequence(1),
      timestamp: "2026-01-01T00:00:00Z",
      rawJSON: rawJSON,
      providerEventType: "usage",
      normalizedEventKind: "usage"
    )
    let update = ProviderSessionSnapshotExtractor.update(
      from: event, storedSequence: EventSequence(1)
    )
    #expect(update.tokenUsage != nil)
  }
}

// MARK: - Custom Git Runner Stubs

/// Returns ls-tree output with one record missing tab and one valid.
private final class MalformedLsTreeGitRunner: GitCommandRunning, @unchecked Sendable {
  let headCommitID: String
  init(headCommitID: String) { self.headCommitID = headCommitID }

  func run(in workspacePath: String, arguments: [String]) throws -> Data {
    if arguments == ["rev-parse", "HEAD"] {
      return Data("\(headCommitID)\n".utf8)
    }
    if arguments.prefix(3) == ["ls-tree", "-rz", "-r"] {
      // First record: no tab (malformed), second: valid with tab
      var data = Data("100644 blob blobX NOTAB/path.swift".utf8)
      data.append(0)
      data.append(Data("100644 blob blob1\tSources/Main.swift".utf8))
      data.append(0)
      return data
    }
    if arguments.prefix(4) == ["log", "--first-parent", "--reverse", "--date-order"] {
      return Data("\(headCommitID)\u{1F}\(headCommitID)\u{1F}init\u{1F}A\u{1F}2026-01-01T00:00:00Z".utf8)
    }
    if arguments.prefix(5) == ["diff-tree", "--numstat", "--root", "--no-commit-id", "-r"] {
      return Data("1\t0\tSources/Main.swift\n".utf8)
    }
    return Data()
  }

  func loadBlobMetrics(in workspacePath: String, blobIDs: [String]) throws -> [String: BlobMetrics] {
    ["blob1": .make(from: Data("print(1)\n".utf8))]
  }
}

/// Returns numstat output with one malformed line (< 3 fields) and one valid.
private final class MalformedNumstatGitRunner: GitCommandRunning, @unchecked Sendable {
  let headCommitID: String
  init(headCommitID: String) { self.headCommitID = headCommitID }

  func run(in workspacePath: String, arguments: [String]) throws -> Data {
    if arguments == ["rev-parse", "HEAD"] {
      return Data("\(headCommitID)\n".utf8)
    }
    if arguments.prefix(3) == ["ls-tree", "-rz", "-r"] {
      var data = Data("100644 blob blob1\tSources/Main.swift".utf8)
      data.append(0)
      return data
    }
    if arguments.prefix(4) == ["log", "--first-parent", "--reverse", "--date-order"] {
      return Data("\(headCommitID)\u{1F}\(headCommitID)\u{1F}init\u{1F}A\u{1F}2026-01-01T00:00:00Z".utf8)
    }
    if arguments.prefix(5) == ["diff-tree", "--numstat", "--root", "--no-commit-id", "-r"] {
      // Line 1: only 2 fields (malformed), Line 2: valid 3 fields
      return Data("incomplete\n10\t2\tSources/Main.swift\n".utf8)
    }
    return Data()
  }

  func loadBlobMetrics(in workspacePath: String, blobIDs: [String]) throws -> [String: BlobMetrics] {
    ["blob1": .make(from: Data("print(1)\n".utf8))]
  }
}

/// Returns ls-tree with one record having < 3 space components before tab.
private final class MalformedLsTreeComponentsGitRunner: GitCommandRunning, @unchecked Sendable {
  let headCommitID: String
  init(headCommitID: String) { self.headCommitID = headCommitID }

  func run(in workspacePath: String, arguments: [String]) throws -> Data {
    if arguments == ["rev-parse", "HEAD"] {
      return Data("\(headCommitID)\n".utf8)
    }
    if arguments.prefix(3) == ["ls-tree", "-rz", "-r"] {
      // First record: only 2 space-separated components (missing blobID)
      var data = Data("100644 blob\tbad.swift".utf8)
      data.append(0)
      // Second record: valid 3+ components
      data.append(Data("100644 blob blob1\tSources/Main.swift".utf8))
      data.append(0)
      return data
    }
    if arguments.prefix(4) == ["log", "--first-parent", "--reverse", "--date-order"] {
      return Data("\(headCommitID)\u{1F}\(headCommitID)\u{1F}init\u{1F}A\u{1F}2026-01-01T00:00:00Z".utf8)
    }
    if arguments.prefix(5) == ["diff-tree", "--numstat", "--root", "--no-commit-id", "-r"] {
      return Data("1\t0\tSources/Main.swift\n".utf8)
    }
    return Data()
  }

  func loadBlobMetrics(in workspacePath: String, blobIDs: [String]) throws -> [String: BlobMetrics] {
    ["blob1": .make(from: Data("print(1)\n".utf8))]
  }
}

/// Returns commit metadata with one malformed line (3 fields) and one valid (5 fields).
private final class MalformedCommitMetadataGitRunner: GitCommandRunning, @unchecked Sendable {
  let headCommitID: String
  init(headCommitID: String) { self.headCommitID = headCommitID }

  func run(in workspacePath: String, arguments: [String]) throws -> Data {
    if arguments == ["rev-parse", "HEAD"] {
      return Data("\(headCommitID)\n".utf8)
    }
    if arguments.prefix(4) == ["log", "--first-parent", "--reverse", "--date-order"] {
      let malformedLine = "bad\u{1F}data\u{1F}only3"
      let validLine = "\(headCommitID)\u{1F}eee555\u{1F}init\u{1F}A\u{1F}2026-01-01T00:00:00Z"
      return Data("\(malformedLine)\n\(validLine)".utf8)
    }
    if arguments.prefix(3) == ["ls-tree", "-rz", "-r"] {
      var data = Data("100644 blob blob1\tSources/Main.swift".utf8)
      data.append(0)
      return data
    }
    if arguments.prefix(5) == ["diff-tree", "--numstat", "--root", "--no-commit-id", "-r"] {
      return Data("1\t0\tSources/Main.swift\n".utf8)
    }
    return Data()
  }

  func loadBlobMetrics(in workspacePath: String, blobIDs: [String]) throws -> [String: BlobMetrics] {
    ["blob1": .make(from: Data("print(1)\n".utf8))]
  }
}

/// Returns numstat with mixed binary ("-") and normal entries.
private final class BinaryNumstatGitRunner: GitCommandRunning, @unchecked Sendable {
  let headCommitID: String
  init(headCommitID: String) { self.headCommitID = headCommitID }

  func run(in workspacePath: String, arguments: [String]) throws -> Data {
    if arguments == ["rev-parse", "HEAD"] {
      return Data("\(headCommitID)\n".utf8)
    }
    if arguments.prefix(3) == ["ls-tree", "-rz", "-r"] {
      var data = Data("100644 blob blob1\tSources/Main.swift".utf8)
      data.append(0)
      return data
    }
    if arguments.prefix(4) == ["log", "--first-parent", "--reverse", "--date-order"] {
      return Data("\(headCommitID)\u{1F}\(headCommitID)\u{1F}init\u{1F}A\u{1F}2026-01-01T00:00:00Z".utf8)
    }
    if arguments.prefix(5) == ["diff-tree", "--numstat", "--root", "--no-commit-id", "-r"] {
      // Binary file: "-\t-\timage.png" (Int("-") → nil)
      // Normal file: "5\t1\tSources/Main.swift"
      return Data("-\t-\timage.png\n5\t1\tSources/Main.swift\n".utf8)
    }
    return Data()
  }

  func loadBlobMetrics(in workspacePath: String, blobIDs: [String]) throws -> [String: BlobMetrics] {
    ["blob1": .make(from: Data("print(1)\n".utf8))]
  }
}
