// Batch 28 — Sort-order assertions for multi-commit progress reports.
//
// Targets the following surviving mutations:
//
// IssueProgressReportGenerator.swift:
//   - loadCommitSnapshots: snapshots.sorted { $0.index < $1.index }
//                                → $0.index > $1.index (reverse)
//   - analyzeCommits:     analyzedCommits.sorted { $0.index < $1.index }
//                                → $0.index > $1.index (reverse)
//   Both produce wrong summary (commits.last → oldest instead of newest)
//   and wrong report.commits ordering.

import Foundation
import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore
@testable import SymphonyShared

// MARK: - Multi-Commit Report Ordering

@Suite("Multi-Commit Report Ordering")
struct MultiCommitReportOrderingTests {
  /// Two commits with different metrics. The summary must reflect the
  /// LATEST commit (highest index). If snapshots.sorted is reversed,
  /// commits.last would be the oldest commit with the wrong metrics.
  @Test func reportSummaryUsesLatestCommitMetrics() throws {
    let cacheDirectory = try makeTemporaryDirectory()
    let earlyContent = Data("line1\n".utf8)            // 6 bytes, 1 file
    let lateContent = Data("line1\nline2\nline3\n".utf8)  // 18 bytes, 1 file

    let gitRunner = StubGitCommandRunner(
      headCommitID: "bbb222",
      commitMetadata: [
        StubCommitMetadata(
          commitID: "aaa111", shortID: "aaa", subject: "initial",
          authorName: "dev", committedAt: "2026-03-17T12:00:00Z"
        ),
        StubCommitMetadata(
          commitID: "bbb222", shortID: "bbb", subject: "update",
          authorName: "dev", committedAt: "2026-03-18T12:00:00Z"
        ),
      ],
      treeEntriesByCommit: [
        "aaa111": [StubTreeEntry(blobID: "early", path: "Sources/A.swift")],
        "bbb222": [StubTreeEntry(blobID: "late", path: "Sources/A.swift")],
      ],
      activitiesByCommit: [
        "aaa111": RepositoryGitActivitySummary(changedFileCount: 1, additions: 1, deletions: 0),
        "bbb222": RepositoryGitActivitySummary(changedFileCount: 1, additions: 3, deletions: 0),
      ],
      blobMetricsByID: [
        "early": .make(from: earlyContent),
        "late": .make(from: lateContent),
      ]
    )
    let detector = StubRepositoryLanguageDetector(
      testPaths: [],
      languagesByPath: ["Sources/A.swift": "Swift"],
      languageTypes: ["Swift": "programming"]
    )
    let generator = CachedIssueProgressReportGenerator(
      cacheDirectoryURL: cacheDirectory,
      analysisConfigProvider: { .defaults },
      gitRunner: gitRunner,
      fileClassifier: RepositoryFileClassifier(detector: detector),
      syntaxRunner: StubRepositorySyntaxHealthRunner(
        health: RepositorySyntaxHealth(
          status: .unsupported, checkedFileCount: 0, diagnosticCount: 0
        )
      )
    )

    let response = try generator.issueProgressReport(
      issueID: IssueID("I_order"), workspacePath: "/tmp/ws"
    )
    let commits = response.report.commits
    let summary = response.report.summary

    // commits must be sorted by index (oldest → newest)
    #expect(commits.count == 2)
    #expect(commits[0].shortID == "aaa", "First commit should be the earliest")
    #expect(commits[1].shortID == "bbb", "Last commit should be the latest")

    // Summary uses commits.last (latest commit), which has 18 bytes / 3 lines
    #expect(summary.byteCount == lateContent.count, "Summary must match latest commit metrics")
    #expect(summary.lineCount == 3, "Summary line count must come from the latest commit")
  }

  /// When commits are fed in reverse index order, the sort must still
  /// produce ascending order. This kills $0.index > $1.index mutations.
  @Test func commitsReversedInputStillProducesAscendingOrder() throws {
    let cacheDirectory = try makeTemporaryDirectory()
    let content = Data("x\n".utf8)

    // Feed 3 commits where metadata order matches --reverse (oldest first),
    // but we verify the output is still sorted by index ascending.
    let gitRunner = StubGitCommandRunner(
      headCommitID: "ccc333",
      commitMetadata: [
        StubCommitMetadata(
          commitID: "aaa111", shortID: "aaa", subject: "first",
          authorName: "dev", committedAt: "2026-03-16T12:00:00Z"
        ),
        StubCommitMetadata(
          commitID: "bbb222", shortID: "bbb", subject: "second",
          authorName: "dev", committedAt: "2026-03-17T12:00:00Z"
        ),
        StubCommitMetadata(
          commitID: "ccc333", shortID: "ccc", subject: "third",
          authorName: "dev", committedAt: "2026-03-18T12:00:00Z"
        ),
      ],
      treeEntriesByCommit: [
        "aaa111": [StubTreeEntry(blobID: "b1", path: "Sources/A.swift")],
        "bbb222": [StubTreeEntry(blobID: "b1", path: "Sources/A.swift")],
        "ccc333": [StubTreeEntry(blobID: "b1", path: "Sources/A.swift")],
      ],
      activitiesByCommit: [
        "aaa111": RepositoryGitActivitySummary(changedFileCount: 1, additions: 1, deletions: 0),
        "bbb222": RepositoryGitActivitySummary(changedFileCount: 1, additions: 2, deletions: 0),
        "ccc333": RepositoryGitActivitySummary(changedFileCount: 1, additions: 3, deletions: 0),
      ],
      blobMetricsByID: ["b1": .make(from: content)]
    )
    let detector = StubRepositoryLanguageDetector(
      testPaths: [],
      languagesByPath: ["Sources/A.swift": "Swift"],
      languageTypes: ["Swift": "programming"]
    )
    let generator = CachedIssueProgressReportGenerator(
      cacheDirectoryURL: cacheDirectory,
      analysisConfigProvider: { .defaults },
      gitRunner: gitRunner,
      fileClassifier: RepositoryFileClassifier(detector: detector),
      syntaxRunner: StubRepositorySyntaxHealthRunner(
        health: RepositorySyntaxHealth(
          status: .unsupported, checkedFileCount: 0, diagnosticCount: 0
        )
      )
    )

    let response = try generator.issueProgressReport(
      issueID: IssueID("I_order2"), workspacePath: "/tmp/ws2"
    )
    let commits = response.report.commits
    #expect(commits.count == 3)

    // Verify ascending commit order by shortID
    #expect(commits[0].shortID == "aaa")
    #expect(commits[1].shortID == "bbb")
    #expect(commits[2].shortID == "ccc")

    // Summary (commits.last) must have the third commit's activity
    #expect(response.report.summary.activity?.additions == 3)
  }
}
