import Foundation
import SymphonyServerCore
import SymphonyShared

// MARK: - Commit Metadata

struct CommitMetadata: Sendable {
  let commitID: String
  let shortID: String
  let subject: String
  let authorName: String
  let committedAt: String
}

// MARK: - Repository Tree Entry

struct RepositoryTreeEntry: Sendable {
  let blobID: String
  let path: String
}

// MARK: - Classification Cache Key

struct ClassificationCacheKey: Hashable, Sendable {
  let path: String
  let blobID: String
}

// MARK: - Blob Metrics

public struct BlobMetrics: Sendable {
  public let textMetrics: TextBlobMetrics?

  static func make(from content: Data) -> BlobMetrics {
    guard !content.contains(0), let string = String(data: content, encoding: .utf8) else {
      return BlobMetrics(textMetrics: nil)
    }
    return BlobMetrics(
      textMetrics: TextBlobMetrics(
        lineCount: Self.lineCount(in: string),
        characterCount: string.count,
        byteCount: content.count,
        contentData: content
      )
    )
  }

  private static func lineCount(in string: String) -> Int {
    guard !string.isEmpty else {
      return 0
    }
    return string.reduce(into: 0) { partialResult, character in
      if character == "\n" {
        partialResult += 1
      }
    } + (string.last == "\n" ? 0 : 1)
  }
}

public struct TextBlobMetrics: Sendable {
  public let lineCount: Int
  public let characterCount: Int
  public let byteCount: Int
  public let contentData: Data
}

// MARK: - Aggregated Commit Metrics

struct AggregatedCommitMetrics: Sendable {
  let fileCount: Int
  let sourceFileCount: Int
  let testFileCount: Int
  let otherFileCount: Int
  let lineCount: Int
  let characterCount: Int
  let byteCount: Int
  let largestFile: RepositoryFileSummary?
  let smallestFile: RepositoryFileSummary?
}

// MARK: - Cache Key Payload

struct CacheKeyPayload: Encodable, Sendable {
  let workspacePath: String
  let headCommitID: String
  let sourcePaths: [String]
  let testPaths: [String]
  let syntaxCommand: String?
  let classifierVersion: String

  init(
    workspacePath: String,
    headCommitID: String,
    analysisConfig: AnalysisConfig,
    classifierVersion: String
  ) {
    self.workspacePath = workspacePath
    self.headCommitID = headCommitID
    self.sourcePaths = analysisConfig.history.sourcePaths
    self.testPaths = analysisConfig.history.testPaths
    self.syntaxCommand = analysisConfig.syntax.command
    self.classifierVersion = classifierVersion
  }
}

// MARK: - Commit Snapshot

struct CommitSnapshot: Sendable {
  let index: Int
  let metadata: CommitMetadata
  let treeEntries: [RepositoryTreeEntry]
  let activity: RepositoryGitActivitySummary
}

// MARK: - Analyzed Commit

struct AnalyzedCommit: Sendable {
  let index: Int
  let metadata: CommitMetadata
  let activity: RepositoryGitActivitySummary
  let metrics: AggregatedCommitMetrics
}

// MARK: - Repository Classification Cache

actor RepositoryClassificationCache {
  private var storage = [ClassificationCacheKey: RepositoryFileCategory]()

  func category(
    for key: ClassificationCacheKey,
    compute: @Sendable () throws -> RepositoryFileCategory
  ) throws -> RepositoryFileCategory {
    if let cached = storage[key] {
      return cached
    }
    let resolved = try compute()
    storage[key] = resolved
    return resolved
  }
}

// MARK: - Blocking Result Box

final class BlockingResultBox<T>: @unchecked Sendable {
  private let lock = NSLock()
  private var result: Result<T, Error>?

  func store(_ result: Result<T, Error>) {
    lock.withLock {
      self.result = result
    }
  }

  func take() -> Result<T, Error> {
    lock.withLock {
      // Semaphore contract guarantees store() is called before take().
      result!
    }
  }
}

// MARK: - Repository History Bucketer

struct RepositoryHistoryBucketer {
  static func makeBuckets(from commits: [RepositoryHistoryCommit]) -> [RepositoryMetricsBucket] {
    let formatter = ISO8601DateFormatter()
    let calendar = Calendar(identifier: .iso8601)
    var buckets = [BucketKey: BucketState]()

    for commit in commits {
      guard let date = formatter.date(from: commit.committedAt) else {
        continue
      }
      let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
      let key = BucketKey(
        yearForWeekOfYear: components.yearForWeekOfYear!,
        weekOfYear: components.weekOfYear!
      )
      let newState = BucketState(
        startDate: min(buckets[key]?.startDate ?? date, date),
        endDate: max(buckets[key]?.endDate ?? date, date),
        latestMetrics: commit.metrics
      )
      buckets[key] = newState
    }

    return buckets.keys.sorted().map { key in
      let state = buckets[key]!  // Keys are from this dictionary; value is always present.
      return RepositoryMetricsBucket(
        bucketID: "\(key.yearForWeekOfYear)-\(key.weekOfYear)",
        label: String(format: "%04d-W%02d", key.yearForWeekOfYear, key.weekOfYear),
        rangeStart: formatter.string(from: state.startDate),
        rangeEnd: formatter.string(from: state.endDate),
        metrics: state.latestMetrics
      )
    }
  }

  private struct BucketKey: Hashable, Comparable {
    let yearForWeekOfYear: Int
    let weekOfYear: Int

    static func < (lhs: BucketKey, rhs: BucketKey) -> Bool {
      if lhs.yearForWeekOfYear == rhs.yearForWeekOfYear {
        return lhs.weekOfYear < rhs.weekOfYear
      }
      return lhs.yearForWeekOfYear < rhs.yearForWeekOfYear
    }
  }

  private struct BucketState {
    let startDate: Date
    let endDate: Date
    let latestMetrics: RepositoryMetricsSnapshot
  }
}
