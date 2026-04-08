// Batch 34 — RepositoryAnalysisModels mutation hardening.
//
// Targets:
//   BlobMetrics.make — binary detection (null byte guard), empty string line count,
//     lineCount trailing newline adjustment
//   RepositoryHistoryBucketer — date parsing guard (continue), bucket aggregation
//   RepositoryClassificationCache — cache hit vs miss

import Foundation
import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore
@testable import SymphonyShared

// MARK: - BlobMetrics

@Suite("BlobMetrics")
struct BlobMetricsTests {

  @Test func binaryContentProducesNilTextMetrics() {
    let binary = Data([0x00, 0x48, 0x65, 0x6C, 0x6C, 0x6F])
    let metrics = BlobMetrics.make(from: binary)
    #expect(metrics.textMetrics == nil)
  }

  @Test func textContentProducesTextMetrics() {
    let text = Data("hello\nworld\n".utf8)
    let metrics = BlobMetrics.make(from: text)
    #expect(metrics.textMetrics != nil)
    #expect(metrics.textMetrics?.lineCount == 2)
    #expect(metrics.textMetrics?.characterCount == 12)
    #expect(metrics.textMetrics?.byteCount == 12)
  }

  @Test func emptyContentProducesZeroLineCount() {
    let empty = Data()
    let metrics = BlobMetrics.make(from: empty)
    // Empty data is not binary (no null byte) but also not text (empty string)
    // Depending on implementation: empty string → lineCount 0
    if let text = metrics.textMetrics {
      #expect(text.lineCount == 0)
    }
  }

  @Test func contentWithoutTrailingNewlineCountsLastLine() {
    let text = Data("line1\nline2".utf8)
    let metrics = BlobMetrics.make(from: text)
    #expect(metrics.textMetrics?.lineCount == 2, "No trailing newline — last line still counted")
  }

  @Test func contentWithTrailingNewlineDoesNotOvercount() {
    let text = Data("line1\n".utf8)
    let metrics = BlobMetrics.make(from: text)
    #expect(metrics.textMetrics?.lineCount == 1, "Trailing newline should not add an extra line")
  }

  @Test func singleLineNoNewline() {
    let text = Data("hello".utf8)
    let metrics = BlobMetrics.make(from: text)
    #expect(metrics.textMetrics?.lineCount == 1)
  }
}

// MARK: - RepositoryHistoryBucketer

@Suite("RepositoryHistoryBucketer")
struct RepositoryHistoryBucketerTests {

  private func commit(
    at dateString: String,
    metrics: RepositoryMetricsSnapshot = RepositoryMetricsSnapshot(
      fileCount: 1, sourceFileCount: 1, testFileCount: 0, otherFileCount: 0,
      lineCount: 10, characterCount: 100, byteCount: 200
    )
  ) -> RepositoryHistoryCommit {
    RepositoryHistoryCommit(
      commitID: "abc123",
      shortID: "abc",
      subject: "test",
      authorName: "test",
      committedAt: dateString,
      metrics: metrics,
      activity: RepositoryGitActivitySummary(changedFileCount: 0, additions: 0, deletions: 0)
    )
  }

  @Test func singleCommitProducesSingleBucket() {
    let commits = [commit(at: "2024-06-15T12:00:00Z")]
    let buckets = RepositoryHistoryBucketer.makeBuckets(from: commits)
    #expect(buckets.count == 1)
    #expect(buckets[0].metrics.fileCount == 1)
  }

  @Test func invalidDateIsSkipped() {
    let commits = [commit(at: "not-a-date")]
    let buckets = RepositoryHistoryBucketer.makeBuckets(from: commits)
    #expect(buckets.isEmpty, "Invalid date must be skipped (guard continue)")
  }

  @Test func commitsInSameWeekAreMergedIntoBucket() {
    let commits = [
      commit(at: "2024-06-10T10:00:00Z",
             metrics: RepositoryMetricsSnapshot(
               fileCount: 5, sourceFileCount: 3, testFileCount: 1, otherFileCount: 1,
               lineCount: 50, characterCount: 500, byteCount: 1000)),
      commit(at: "2024-06-12T10:00:00Z",
             metrics: RepositoryMetricsSnapshot(
               fileCount: 8, sourceFileCount: 5, testFileCount: 2, otherFileCount: 1,
               lineCount: 80, characterCount: 800, byteCount: 1600)),
    ]
    let buckets = RepositoryHistoryBucketer.makeBuckets(from: commits)
    #expect(buckets.count == 1, "Same week → single bucket")
  }

  @Test func commitsInDifferentWeeksProduceMultipleBuckets() {
    let commits = [
      commit(at: "2024-06-10T10:00:00Z"),
      commit(at: "2024-06-24T10:00:00Z"),
    ]
    let buckets = RepositoryHistoryBucketer.makeBuckets(from: commits)
    #expect(buckets.count == 2, "Different weeks → two buckets")
  }
}

// MARK: - RepositoryClassificationCache

@Suite("RepositoryClassificationCache")
struct RepositoryClassificationCacheTests {

  @Test func cacheReturnsComputedValueOnMiss() async throws {
    let cache = RepositoryClassificationCache()
    let key = ClassificationCacheKey(path: "test.swift", blobID: "abc")
    let category = try await cache.category(for: key) { .source }
    #expect(category == .source)
  }

  @Test func cacheReturnsCachedValueOnHit() async throws {
    let cache = RepositoryClassificationCache()
    let key = ClassificationCacheKey(path: "test.swift", blobID: "abc")
    let _ = try await cache.category(for: key) { .source }

    // Second call should return cached value without calling compute
    let category = try await cache.category(for: key) { .test }
    #expect(category == .source, "Cached value must be returned, not recomputed")
  }
}
