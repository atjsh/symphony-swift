// Batch 47 — Mutation hardening: boundary/equality gaps in
//   ConcurrencySlotManager.canDispatch (global slots == 1),
//   IssueProgressReportGenerator (largest/smallest file with equal byte counts).

import Foundation
import Synchronization
import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore
@testable import SymphonyShared

// MARK: - ConcurrencySlotManager: canDispatch with exactly 1 global slot

@Suite("ConcurrencySlotManager Global Slot Boundary")
struct ConcurrencySlotManagerGlobalBoundaryTests {

  /// When exactly 1 global slot is available, canDispatch must return true.
  /// Kills mutation: `availableSlots(currentRunning:) > 0` → `> 1`.
  @Test func canDispatchReturnsTrueWithExactlyOneGlobalSlotAvailable() {
    let config = AgentConfig(maxConcurrentAgents: 2, maxConcurrentAgentsByState: [:])
    let manager = ConcurrencySlotManager(config: config)

    // currentRunning=1 → availableSlots=1 → 1 > 0 = true
    #expect(manager.canDispatch(currentRunning: 1, state: "Todo", currentInState: 0))
  }

  /// When exactly 1 per-state slot is available, canDispatch must return true.
  /// Kills mutation: `availableSlots(forState:currentInState:) > 0` → `> 1`.
  @Test func canDispatchReturnsTrueWithExactlyOneStateSlotAvailable() {
    let config = AgentConfig(maxConcurrentAgents: 10, maxConcurrentAgentsByState: ["Todo": 2])
    let manager = ConcurrencySlotManager(config: config)

    // currentInState=1 → stateSlots=1 → 1 > 0 = true
    #expect(manager.canDispatch(currentRunning: 0, state: "Todo", currentInState: 1))
  }

  /// Both global and per-state slots are exactly 1 each.
  /// Kills both `> 0` → `> 1` mutations simultaneously.
  @Test func canDispatchReturnsTrueWhenBothSlotsExactlyOne() {
    let config = AgentConfig(maxConcurrentAgents: 3, maxConcurrentAgentsByState: ["Todo": 2])
    let manager = ConcurrencySlotManager(config: config)

    // global: 3 - 2 = 1, state: 2 - 1 = 1.  Both == 1 → both pass `> 0`.
    #expect(manager.canDispatch(currentRunning: 2, state: "Todo", currentInState: 1))
  }
}

// MARK: - IssueProgressReportGenerator: largest/smallest tie-breaking

@Suite("Progress Report Largest/Smallest Equal-Size Tie-Breaking")
struct ProgressReportEqualSizeTieBreakingTests {

  /// When two files have identical byte counts, largestFile must be the first
  /// file encountered (strict `>`; equal doesn't replace).
  /// Kills mutation: `summary.byteCount > (largestFile?.byteCount ?? -1)` → `>=`.
  @Test func largestFileIsFirstEncounteredWhenEqualSize() throws {
    let cacheDirectory = try makeTemporaryDirectory()
    // Both blobs produce the same byteCount (5 bytes each).
    let equalContent = Data("hello".utf8)  // 5 bytes
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
          .init(blobID: "blob-first", path: "Sources/First.swift"),
          .init(blobID: "blob-second", path: "Sources/Second.swift"),
        ]
      ],
      activitiesByCommit: [
        "aaaa1111": .init(changedFileCount: 2, additions: 10, deletions: 0)
      ],
      blobMetricsByID: [
        "blob-first": .make(from: equalContent),
        "blob-second": .make(from: equalContent),
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
            "Sources/First.swift": "Swift",
            "Sources/Second.swift": "Swift",
          ],
          languageTypes: ["Swift": "programming"]
        )
      ),
      syntaxRunner: StubRepositorySyntaxHealthRunner(
        health: RepositorySyntaxHealth(
          status: .unsupported, checkedFileCount: 0, diagnosticCount: 0)
      )
    )

    let report = try generator.issueProgressReport(
      issueID: IssueID("test"), workspacePath: "/tmp/workspace"
    )
    // With strict `>`, the first file stays as largest (equal doesn't replace).
    #expect(report.report.summary.largestFile?.path == "Sources/First.swift")
  }

  /// When two files have identical byte counts, smallestFile must be the first
  /// file encountered (strict `<`; equal doesn't replace).
  /// Kills mutation: `summary.byteCount < (smallestFile?.byteCount ?? .max)` → `<=`.
  @Test func smallestFileIsFirstEncounteredWhenEqualSize() throws {
    let cacheDirectory = try makeTemporaryDirectory()
    let equalContent = Data("hello".utf8)  // 5 bytes
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
          .init(blobID: "blob-alpha", path: "Sources/Alpha.swift"),
          .init(blobID: "blob-beta", path: "Sources/Beta.swift"),
        ]
      ],
      activitiesByCommit: [
        "aaaa1111": .init(changedFileCount: 2, additions: 10, deletions: 0)
      ],
      blobMetricsByID: [
        "blob-alpha": .make(from: equalContent),
        "blob-beta": .make(from: equalContent),
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
            "Sources/Alpha.swift": "Swift",
            "Sources/Beta.swift": "Swift",
          ],
          languageTypes: ["Swift": "programming"]
        )
      ),
      syntaxRunner: StubRepositorySyntaxHealthRunner(
        health: RepositorySyntaxHealth(
          status: .unsupported, checkedFileCount: 0, diagnosticCount: 0)
      )
    )

    let report = try generator.issueProgressReport(
      issueID: IssueID("test"), workspacePath: "/tmp/workspace"
    )
    // With strict `<`, the first file stays as smallest (equal doesn't replace).
    #expect(report.report.summary.smallestFile?.path == "Sources/Alpha.swift")
  }
}
