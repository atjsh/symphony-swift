import Foundation
import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore
@testable import SymphonyShared

struct StubRepositorySyntaxHealthRunner: RepositorySyntaxHealthRunning {
  let health: RepositorySyntaxHealth

  func syntaxHealth(in workspacePath: String, syntaxConfig: AnalysisSyntaxConfig)
    -> RepositorySyntaxHealth
  {
    health
  }
}

final class StubGitCommandRunner: GitCommandRunning, @unchecked Sendable {
  var headCommitID: String
  var commitMetadata: [StubCommitMetadata]
  var treeEntriesByCommit: [String: [StubTreeEntry]]
  var activitiesByCommit: [String: RepositoryGitActivitySummary]
  var blobMetricsByID: [String: BlobMetrics]
  private(set) var loadedBlobBatches = [[String]]()

  init(
    headCommitID: String,
    commitMetadata: [StubCommitMetadata],
    treeEntriesByCommit: [String: [StubTreeEntry]],
    activitiesByCommit: [String: RepositoryGitActivitySummary],
    blobMetricsByID: [String: BlobMetrics]
  ) {
    self.headCommitID = headCommitID
    self.commitMetadata = commitMetadata
    self.treeEntriesByCommit = treeEntriesByCommit
    self.activitiesByCommit = activitiesByCommit
    self.blobMetricsByID = blobMetricsByID
  }

  func run(in workspacePath: String, arguments: [String]) throws -> Data {
    if arguments == ["rev-parse", "HEAD"] {
      return Data("\(headCommitID)\n".utf8)
    }
    if arguments.prefix(4) == ["log", "--first-parent", "--reverse", "--date-order"] {
      let output = commitMetadata
        .map {
          [
            $0.commitID,
            $0.shortID,
            $0.subject,
            $0.authorName,
            $0.committedAt,
          ].joined(separator: "\u{1F}")
        }
        .joined(separator: "\n")
      return Data(output.utf8)
    }
    if arguments.prefix(3) == ["ls-tree", "-rz", "-r"], let commitID = arguments.last {
      let data = treeEntriesByCommit[commitID, default: []].reduce(into: Data()) { partialResult, entry in
        partialResult.append(Data("100644 blob \(entry.blobID)\t\(entry.path)".utf8))
        partialResult.append(0)
      }
      return data
    }
    if arguments.prefix(5) == ["diff-tree", "--numstat", "--root", "--no-commit-id", "-r"],
      let commitID = arguments.last,
      let activity = activitiesByCommit[commitID]
    {
      let output = "\(activity.additions)\t\(activity.deletions)\tfile.swift\n"
      return Data(output.utf8)
    }
    Issue.record("Unexpected git arguments: \(arguments)")
    return Data()
  }

  func loadBlobMetrics(in workspacePath: String, blobIDs: [String]) throws -> [String: BlobMetrics] {
    loadedBlobBatches.append(blobIDs)
    return blobIDs.reduce(into: [:]) { partialResult, blobID in
      partialResult[blobID] = blobMetricsByID[blobID]
    }
  }
}

struct StubCommitMetadata {
  let commitID: String
  let shortID: String
  let subject: String
  let authorName: String
  let committedAt: String
}

struct StubTreeEntry {
  let blobID: String
  let path: String
}

struct StubRepositoryLanguageDetector: RepositoryLanguageDetecting {
  let testPaths: Set<String>
  let languagesByPath: [String: String]
  let languageTypes: [String: String]
  var documentationPaths = Set<String>()
  var configurationPaths = Set<String>()
  var generatedPaths = Set<String>()
  var vendorPaths = Set<String>()
  var imagePaths = Set<String>()
  var dotFiles = Set<String>()
  var version = "stub"

  func isBinary(content: Data) throws -> Bool {
    false
  }

  func isConfiguration(path: String) throws -> Bool {
    configurationPaths.contains(path)
  }

  func isDocumentation(path: String) throws -> Bool {
    documentationPaths.contains(path)
  }

  func isDotFile(path: String) throws -> Bool {
    dotFiles.contains(path)
  }

  func isImage(path: String) throws -> Bool {
    imagePaths.contains(path)
  }

  func isVendor(path: String) throws -> Bool {
    vendorPaths.contains(path)
  }

  func isGenerated(path: String, content: Data) throws -> Bool {
    generatedPaths.contains(path)
  }

  func isTest(path: String) throws -> Bool {
    testPaths.contains(path)
  }

  func language(path: String, content: Data) throws -> String? {
    languagesByPath[path]
  }

  func languageType(language: String) throws -> String? {
    languageTypes[language]
  }
}

final class ConcurrencyTrackingGitCommandRunner: GitCommandRunning, @unchecked Sendable {
  private let lock = NSLock()
  private(set) var maxConcurrentGitLoads = 0
  private var activeGitLoads = 0

  func run(in workspacePath: String, arguments: [String]) throws -> Data {
    if arguments == ["rev-parse", "HEAD"] {
      return Data("dddddddd44444444\n".utf8)
    }
    if arguments.prefix(4) == ["log", "--first-parent", "--reverse", "--date-order"] {
      let commits = [
        ("aaaaaaaa11111111", "aaaaaaa", "Initial import", "Taylor", "2026-03-18T12:00:00Z"),
        ("bbbbbbbb22222222", "bbbbbbb", "Add tests", "Taylor", "2026-03-20T12:00:00Z"),
        ("cccccccc33333333", "ccccccc", "Refine metrics", "Taylor", "2026-03-22T12:00:00Z"),
        ("dddddddd44444444", "ddddddd", "Ship progress", "Taylor", "2026-03-24T12:00:00Z"),
      ]
      let output = commits
        .map { $0.0 + "\u{1F}" + $0.1 + "\u{1F}" + $0.2 + "\u{1F}" + $0.3 + "\u{1F}" + $0.4 }
        .joined(separator: "\n")
      return Data(output.utf8)
    }
    if arguments.prefix(3) == ["ls-tree", "-rz", "-r"], let commitID = arguments.last {
      beginConcurrentLoad()
      defer { endConcurrentLoad() }
      Thread.sleep(forTimeInterval: 0.05)
      var data = Data()
      data.append(Data("100644 blob blob-\(commitID)\tSources/App/Main.swift".utf8))
      data.append(0)
      return data
    }
    if arguments.prefix(5) == ["diff-tree", "--numstat", "--root", "--no-commit-id", "-r"] {
      beginConcurrentLoad()
      defer { endConcurrentLoad() }
      Thread.sleep(forTimeInterval: 0.05)
      return Data("10\t1\tSources/App/Main.swift\n".utf8)
    }
    Issue.record("Unexpected git arguments: \(arguments)")
    return Data()
  }

  func loadBlobMetrics(in workspacePath: String, blobIDs: [String]) throws -> [String: BlobMetrics] {
    blobIDs.reduce(into: [:]) { partialResult, blobID in
      partialResult[blobID] = .make(from: Data("print(\"hello\")\n".utf8))
    }
  }

  private func beginConcurrentLoad() {
    lock.lock()
    activeGitLoads += 1
    maxConcurrentGitLoads = max(maxConcurrentGitLoads, activeGitLoads)
    lock.unlock()
  }

  private func endConcurrentLoad() {
    lock.lock()
    activeGitLoads -= 1
    lock.unlock()
  }
}

// MARK: - Custom Activity Output Git Runner

final class StubGitCommandRunnerWithCustomActivity: GitCommandRunning, @unchecked Sendable {
  private let headCommitID: String
  private let commitMetadata: [StubCommitMetadata]
  private let treeEntriesByCommit: [String: [StubTreeEntry]]
  private let activityOutput: String
  private let blobMetricsByID: [String: BlobMetrics]

  init(
    headCommitID: String,
    commitMetadata: [StubCommitMetadata],
    treeEntriesByCommit: [String: [StubTreeEntry]],
    activityOutput: String,
    blobMetricsByID: [String: BlobMetrics]
  ) {
    self.headCommitID = headCommitID
    self.commitMetadata = commitMetadata
    self.treeEntriesByCommit = treeEntriesByCommit
    self.activityOutput = activityOutput
    self.blobMetricsByID = blobMetricsByID
  }

  func run(in workspacePath: String, arguments: [String]) throws -> Data {
    if arguments == ["rev-parse", "HEAD"] {
      return Data("\(headCommitID)\n".utf8)
    }
    if arguments.prefix(4) == ["log", "--first-parent", "--reverse", "--date-order"] {
      let output = commitMetadata
        .map {
          [$0.commitID, $0.shortID, $0.subject, $0.authorName, $0.committedAt]
            .joined(separator: "\u{1F}")
        }
        .joined(separator: "\n")
      return Data(output.utf8)
    }
    if arguments.prefix(3) == ["ls-tree", "-rz", "-r"], let commitID = arguments.last {
      let data = treeEntriesByCommit[commitID, default: []].reduce(into: Data()) { partialResult, entry in
        partialResult.append(Data("100644 blob \(entry.blobID)\t\(entry.path)".utf8))
        partialResult.append(0)
      }
      return data
    }
    if arguments.prefix(5) == ["diff-tree", "--numstat", "--root", "--no-commit-id", "-r"] {
      return Data(activityOutput.utf8)
    }
    return Data()
  }

  func loadBlobMetrics(in workspacePath: String, blobIDs: [String]) throws -> [String: BlobMetrics] {
    blobIDs.reduce(into: [:]) { partialResult, blobID in
      partialResult[blobID] = blobMetricsByID[blobID]
    }
  }
}

// MARK: - Custom Tree Output Git Runner

final class StubGitCommandRunnerWithCustomTreeOutput: GitCommandRunning, @unchecked Sendable {
  private let headCommitID: String
  private let commitMetadata: [StubCommitMetadata]
  private let treeOutput: Data
  private let activityOutput: String
  private let blobMetricsByID: [String: BlobMetrics]

  init(
    headCommitID: String,
    commitMetadata: [StubCommitMetadata],
    treeOutput: Data,
    activityOutput: String,
    blobMetricsByID: [String: BlobMetrics]
  ) {
    self.headCommitID = headCommitID
    self.commitMetadata = commitMetadata
    self.treeOutput = treeOutput
    self.activityOutput = activityOutput
    self.blobMetricsByID = blobMetricsByID
  }

  func run(in workspacePath: String, arguments: [String]) throws -> Data {
    if arguments == ["rev-parse", "HEAD"] {
      return Data("\(headCommitID)\n".utf8)
    }
    if arguments.prefix(4) == ["log", "--first-parent", "--reverse", "--date-order"] {
      let output = commitMetadata
        .map {
          [$0.commitID, $0.shortID, $0.subject, $0.authorName, $0.committedAt]
            .joined(separator: "\u{1F}")
        }
        .joined(separator: "\n")
      return Data(output.utf8)
    }
    if arguments.prefix(3) == ["ls-tree", "-rz", "-r"] {
      return treeOutput
    }
    if arguments.prefix(5) == ["diff-tree", "--numstat", "--root", "--no-commit-id", "-r"] {
      return Data(activityOutput.utf8)
    }
    return Data()
  }

  func loadBlobMetrics(in workspacePath: String, blobIDs: [String]) throws -> [String: BlobMetrics] {
    blobIDs.reduce(into: [:]) { partialResult, blobID in
      partialResult[blobID] = blobMetricsByID[blobID]
    }
  }
}

// MARK: - Custom Raw Log Output Git Runner

/// Injects raw string output for `git log` to test malformed commit metadata parsing.
final class StubGitCommandRunnerWithRawLogOutput: GitCommandRunning, @unchecked Sendable {
  private let headCommitID: String
  private let rawLogOutput: String

  init(headCommitID: String, rawLogOutput: String) {
    self.headCommitID = headCommitID
    self.rawLogOutput = rawLogOutput
  }

  func run(in workspacePath: String, arguments: [String]) throws -> Data {
    if arguments == ["rev-parse", "HEAD"] {
      return Data("\(headCommitID)\n".utf8)
    }
    if arguments.prefix(4) == ["log", "--first-parent", "--reverse", "--date-order"] {
      return Data(rawLogOutput.utf8)
    }
    return Data()
  }

  func loadBlobMetrics(in workspacePath: String, blobIDs: [String]) throws -> [String: BlobMetrics] {
    [:]
  }
}

// MARK: - Throwing Git Runner (for runBlocking error path)

/// Returns valid commit metadata but throws during ls-tree, exercising
/// the `resultBox.store(.failure(error))` path in `runBlocking`.
final class StubThrowingTreeGitCommandRunner: GitCommandRunning, @unchecked Sendable {
  struct TreeLoadFailure: Error {}

  private let headCommitID: String
  private let commitMetadata: [StubCommitMetadata]

  init(headCommitID: String, commitMetadata: [StubCommitMetadata]) {
    self.headCommitID = headCommitID
    self.commitMetadata = commitMetadata
  }

  func run(in workspacePath: String, arguments: [String]) throws -> Data {
    if arguments == ["rev-parse", "HEAD"] {
      return Data("\(headCommitID)\n".utf8)
    }
    if arguments.prefix(4) == ["log", "--first-parent", "--reverse", "--date-order"] {
      let output = commitMetadata
        .map { [$0.commitID, $0.shortID, $0.subject, $0.authorName, $0.committedAt].joined(separator: "\u{1F}") }
        .joined(separator: "\n")
      return Data(output.utf8)
    }
    if arguments.prefix(3) == ["ls-tree", "-rz", "-r"] {
      throw TreeLoadFailure()
    }
    return Data()
  }

  func loadBlobMetrics(in workspacePath: String, blobIDs: [String]) throws -> [String: BlobMetrics] {
    [:]
  }
}
