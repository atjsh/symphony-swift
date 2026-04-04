import CryptoKit
import Foundation
import SymphonyServerCore
import SymphonyShared

// MARK: - Cached Issue Progress Report Generator

// SAFETY: @unchecked Sendable — all stored fields are immutable (`let`).
public final class CachedIssueProgressReportGenerator: IssueProgressReportGenerating, @unchecked Sendable {
  private let cacheDirectoryURL: URL
  private let analysisConfigProvider: @Sendable () -> AnalysisConfig
  private let gitRunner: any GitCommandRunning
  private let fileClassifier: RepositoryFileClassifying
  private let syntaxRunner: any RepositorySyntaxHealthRunning
  private let now: @Sendable () -> Date
  private let analysisConcurrencyLimit: Int
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  public init(
    cacheDirectoryURL: URL,
    analysisConfigProvider: @escaping @Sendable () -> AnalysisConfig,
    gitRunner: any GitCommandRunning = ProcessGitCommandRunner(),
    fileClassifier: RepositoryFileClassifying = RepositoryFileClassifier(
      detector: GoEnryRepositoryLanguageDetector()
    ),
    syntaxRunner: any RepositorySyntaxHealthRunning = ProcessRepositorySyntaxHealthRunner(),
    now: @escaping @Sendable () -> Date = Date.init,
    analysisConcurrencyLimit: Int? = nil
  ) {
    self.cacheDirectoryURL = cacheDirectoryURL
    self.analysisConfigProvider = analysisConfigProvider
    self.gitRunner = gitRunner
    self.fileClassifier = fileClassifier
    self.syntaxRunner = syntaxRunner
    self.now = now
    self.analysisConcurrencyLimit = max(
      1,
      analysisConcurrencyLimit ?? min(4, ProcessInfo.processInfo.activeProcessorCount)
    )
    self.encoder = JSONEncoder()
    self.encoder.outputFormatting = [.sortedKeys]
    self.decoder = JSONDecoder()
  }

  public func issueProgressReport(issueID: IssueID, workspacePath: String) throws
    -> IssueProgressReportResponse
  {
    let trimmedWorkspacePath = workspacePath.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedWorkspacePath.isEmpty else {
      throw IssueProgressReportError.workspaceUnavailable
    }

    let analysisConfig = analysisConfigProvider()
    let headCommitID = try resolveHeadCommitID(workspacePath: trimmedWorkspacePath)
    let cacheURL = try cacheURL(
      workspacePath: trimmedWorkspacePath,
      headCommitID: headCommitID,
      analysisConfig: analysisConfig
    )

    if let cached = try loadCachedReport(from: cacheURL) {
      return cached
    }

    let report = try buildReport(
      issueID: issueID,
      workspacePath: trimmedWorkspacePath,
      headCommitID: headCommitID,
      analysisConfig: analysisConfig
    )
    try persist(report: report, to: cacheURL)
    return report
  }

  private func resolveHeadCommitID(workspacePath: String) throws -> String {
    let output = try gitRunner.runString(
      in: workspacePath,
      arguments: ["rev-parse", "HEAD"]
    )
    let commitID = output.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !commitID.isEmpty else {
      throw IssueProgressReportError.repositoryHistoryUnavailable("Repository has no HEAD commit.")
    }
    return commitID
  }

  private func buildReport(
    issueID: IssueID,
    workspacePath: String,
    headCommitID: String,
    analysisConfig: AnalysisConfig
  ) throws -> IssueProgressReportResponse {
    let commitMetadata = try loadCommitMetadata(workspacePath: workspacePath)
    guard !commitMetadata.isEmpty else {
      throw IssueProgressReportError.repositoryHistoryUnavailable("Repository history is unavailable.")
    }

    let commitSnapshots = try loadCommitSnapshots(
      workspacePath: workspacePath,
      commitMetadata: commitMetadata
    )
    let allBlobIDs = Array(
      Set(commitSnapshots.flatMap { $0.treeEntries.map(\.blobID) })
    ).sorted()
    let blobMetricsCache = try gitRunner.loadBlobMetrics(
      in: workspacePath,
      blobIDs: allBlobIDs
    )
    let analyzedCommits = try analyzeCommits(
      commitSnapshots: commitSnapshots,
      analysisConfig: analysisConfig,
      blobMetricsCache: blobMetricsCache
    )
    let commits = analyzedCommits.map { analyzedCommit in
      RepositoryHistoryCommit(
        commitID: analyzedCommit.metadata.commitID,
        shortID: analyzedCommit.metadata.shortID,
        subject: analyzedCommit.metadata.subject,
        authorName: analyzedCommit.metadata.authorName,
        committedAt: analyzedCommit.metadata.committedAt,
        metrics: RepositoryMetricsSnapshot(
          fileCount: analyzedCommit.metrics.fileCount,
          sourceFileCount: analyzedCommit.metrics.sourceFileCount,
          testFileCount: analyzedCommit.metrics.testFileCount,
          otherFileCount: analyzedCommit.metrics.otherFileCount,
          lineCount: analyzedCommit.metrics.lineCount,
          characterCount: analyzedCommit.metrics.characterCount,
          byteCount: analyzedCommit.metrics.byteCount,
          largestFile: analyzedCommit.metrics.largestFile,
          smallestFile: analyzedCommit.metrics.smallestFile,
          activity: analyzedCommit.activity
        ),
        activity: analyzedCommit.activity
      )
    }

    // commitMetadata is guaranteed non-empty by the guard in buildReport(),
    // so analyzedCommits → commits is also non-empty.
    guard let summaryCommit = commits.last else {
      preconditionFailure("commits must be non-empty; buildReport() guards commitMetadata")
    }

    let syntaxHealth = syntaxRunner.syntaxHealth(
      in: workspacePath,
      syntaxConfig: analysisConfig.syntax
    )
    let buckets = RepositoryHistoryBucketer.makeBuckets(from: commits)
    return IssueProgressReportResponse(
      issueID: issueID,
      generatedAt: Self.iso8601(now()),
      report: RepositoryHistoryReport(
        headCommitID: headCommitID,
        summary: summaryCommit.metrics,
        commits: commits,
        buckets: buckets
      ),
      syntaxHealth: syntaxHealth
    )
  }

  private func aggregateMetrics(
    treeEntries: [RepositoryTreeEntry],
    analysisConfig: AnalysisConfig,
    blobMetricsCache: [String: BlobMetrics],
    classificationCache: RepositoryClassificationCache
  ) async throws -> AggregatedCommitMetrics {
    var fileCount = 0
    var sourceFileCount = 0
    var testFileCount = 0
    var otherFileCount = 0
    var lineCount = 0
    var characterCount = 0
    var byteCount = 0
    var largestFile: RepositoryFileSummary?
    var smallestFile: RepositoryFileSummary?

    for entry in treeEntries {
      guard let blobMetrics = blobMetricsCache[entry.blobID], let textMetrics = blobMetrics.textMetrics else {
        continue
      }

      let cacheKey = ClassificationCacheKey(path: entry.path, blobID: entry.blobID)
      let category = try await classificationCache.category(for: cacheKey) {
        try fileClassifier.classify(
          path: entry.path,
          content: textMetrics.contentData,
          historyConfig: analysisConfig.history
        )
      }

      fileCount += 1
      lineCount += textMetrics.lineCount
      characterCount += textMetrics.characterCount
      byteCount += textMetrics.byteCount

      switch category {
      case .source:
        sourceFileCount += 1
      case .test:
        testFileCount += 1
      case .other:
        otherFileCount += 1
      }

      let summary = RepositoryFileSummary(
        path: entry.path,
        category: category,
        lineCount: textMetrics.lineCount,
        characterCount: textMetrics.characterCount,
        byteCount: textMetrics.byteCount
      )
      if summary.byteCount > (largestFile?.byteCount ?? -1) {
        largestFile = summary
      }
      if summary.byteCount < (smallestFile?.byteCount ?? .max) {
        smallestFile = summary
      }
    }

    return AggregatedCommitMetrics(
      fileCount: fileCount,
      sourceFileCount: sourceFileCount,
      testFileCount: testFileCount,
      otherFileCount: otherFileCount,
      lineCount: lineCount,
      characterCount: characterCount,
      byteCount: byteCount,
      largestFile: largestFile,
      smallestFile: smallestFile
    )
  }

  private func loadCommitSnapshots(
    workspacePath: String,
    commitMetadata: [CommitMetadata]
  ) throws -> [CommitSnapshot] {
    try Self.runBlocking { [self] in
      let snapshots = try await Self.runBoundedTasks(
        inputs: Array(commitMetadata.enumerated()),
        maxConcurrentTasks: self.analysisConcurrencyLimit
      ) { indexedMetadata in
        let (index, metadata) = indexedMetadata
        let treeEntries = try self.loadTreeEntries(
          workspacePath: workspacePath,
          commitID: metadata.commitID
        )
        let activity = try self.loadActivity(
          workspacePath: workspacePath,
          commitID: metadata.commitID
        )
        return CommitSnapshot(
          index: index,
          metadata: metadata,
          treeEntries: treeEntries,
          activity: activity
        )
      }
      return snapshots.sorted { $0.index < $1.index }
    }
  }

  private func analyzeCommits(
    commitSnapshots: [CommitSnapshot],
    analysisConfig: AnalysisConfig,
    blobMetricsCache: [String: BlobMetrics]
  ) throws -> [AnalyzedCommit] {
    try Self.runBlocking { [self] in
      let classificationCache = RepositoryClassificationCache()
      let analyzedCommits = try await Self.runBoundedTasks(
        inputs: commitSnapshots,
        maxConcurrentTasks: self.analysisConcurrencyLimit
      ) { snapshot in
        let metrics = try await self.aggregateMetrics(
          treeEntries: snapshot.treeEntries,
          analysisConfig: analysisConfig,
          blobMetricsCache: blobMetricsCache,
          classificationCache: classificationCache
        )
        return AnalyzedCommit(
          index: snapshot.index,
          metadata: snapshot.metadata,
          activity: snapshot.activity,
          metrics: metrics
        )
      }
      return analyzedCommits.sorted { $0.index < $1.index }
    }
  }

  private static func runBlocking<T: Sendable>(
    _ operation: @escaping @Sendable () async throws -> T
  ) throws -> T {
    let semaphore = DispatchSemaphore(value: 0)
    let resultBox = BlockingResultBox<T>()
    Task.detached {
      do {
        resultBox.store(.success(try await operation()))
      } catch {
        resultBox.store(.failure(error))
      }
      semaphore.signal()
    }
    semaphore.wait()
    return try resultBox.take().get()
  }

  private static func runBoundedTasks<Input: Sendable, Output: Sendable>(
    inputs: [Input],
    maxConcurrentTasks: Int,
    operation: @escaping @Sendable (Input) async throws -> Output
  ) async throws -> [Output] {
    let concurrencyLimit = max(1, maxConcurrentTasks)
    var iterator = inputs.makeIterator()
    var outputs = [Output]()
    outputs.reserveCapacity(inputs.count)

    return try await withThrowingTaskGroup(of: Output.self) { group in
      for _ in 0..<min(concurrencyLimit, inputs.count) {
        let input = iterator.next()!
        group.addTask {
          try await operation(input)
        }
      }

      while let nextOutput = try await group.next() {
        outputs.append(nextOutput)
        if let nextInput = iterator.next() {
          group.addTask {
            try await operation(nextInput)
          }
        }
      }

      return outputs
    }
  }

  private func loadCommitMetadata(workspacePath: String) throws -> [CommitMetadata] {
    let output = try gitRunner.runString(
      in: workspacePath,
      arguments: [
        "log",
        "--first-parent",
        "--reverse",
        "--date-order",
        "--format=%H%x1f%h%x1f%s%x1f%an%x1f%cI",
        "HEAD",
      ]
    )
    return output
      .split(whereSeparator: \.isNewline)
      .compactMap { line in
        let fields = line.split(separator: "\u{1F}", omittingEmptySubsequences: false)
        guard fields.count == 5 else {
          return nil
        }
        return CommitMetadata(
          commitID: String(fields[0]),
          shortID: String(fields[1]),
          subject: String(fields[2]),
          authorName: String(fields[3]),
          committedAt: String(fields[4])
        )
      }
  }

  private func loadTreeEntries(workspacePath: String, commitID: String) throws -> [RepositoryTreeEntry] {
    let data = try gitRunner.run(
      in: workspacePath,
      arguments: ["ls-tree", "-rz", "-r", commitID]
    )

    return data.split(separator: 0).compactMap { record in
      guard let tabIndex = record.firstIndex(of: 9) else {
        return nil
      }
      let prefix = record[..<tabIndex]
      let pathData = record[record.index(after: tabIndex)...]
      let components = prefix.split(separator: 32, omittingEmptySubsequences: true)
      guard components.count >= 3 else {
        return nil
      }
      return RepositoryTreeEntry(
        blobID: String(decoding: components[2], as: UTF8.self),
        path: String(decoding: pathData, as: UTF8.self)
      )
    }
  }

  private func loadActivity(workspacePath: String, commitID: String) throws
    -> RepositoryGitActivitySummary
  {
    let output = try gitRunner.runString(
      in: workspacePath,
      arguments: ["diff-tree", "--numstat", "--root", "--no-commit-id", "-r", commitID]
    )
    var changedFileCount = 0
    var additions = 0
    var deletions = 0

    for line in output.split(whereSeparator: \.isNewline) {
      let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
      guard fields.count >= 3 else {
        continue
      }
      changedFileCount += 1
      if let added = Int(fields[0]) {
        additions += added
      }
      if let removed = Int(fields[1]) {
        deletions += removed
      }
    }

    return RepositoryGitActivitySummary(
      changedFileCount: changedFileCount,
      additions: additions,
      deletions: deletions
    )
  }

  private func cacheURL(
    workspacePath: String,
    headCommitID: String,
    analysisConfig: AnalysisConfig
  ) throws -> URL {
    let payload = CacheKeyPayload(
      workspacePath: workspacePath,
      headCommitID: headCommitID,
      analysisConfig: analysisConfig,
      classifierVersion: fileClassifier.version
    )
    let keyData = try encoder.encode(payload)
    let digest = SHA256.hash(data: keyData)
    let fileName = digest.map { String(format: "%02x", $0) }.joined() + ".json"
    return cacheDirectoryURL.appendingPathComponent(fileName)
  }

  private func loadCachedReport(from cacheURL: URL) throws -> IssueProgressReportResponse? {
    guard FileManager.default.fileExists(atPath: cacheURL.path) else {
      return nil
    }
    let data = try Data(contentsOf: cacheURL)
    return try decoder.decode(IssueProgressReportResponse.self, from: data)
  }

  private func persist(report: IssueProgressReportResponse, to cacheURL: URL) throws {
    try FileManager.default.createDirectory(
      at: cacheDirectoryURL,
      withIntermediateDirectories: true
    )
    let data = try encoder.encode(report)
    try data.write(to: cacheURL, options: .atomic)
  }

  private static func iso8601(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.string(from: date)
  }
}
