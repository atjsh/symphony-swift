import Foundation

public enum RepositoryFileCategory: String, Codable, CaseIterable, Sendable {
  case source
  case test
  case other
}

public struct RepositoryGitActivitySummary: Codable, Hashable, Sendable {
  public let changedFileCount: Int
  public let additions: Int
  public let deletions: Int

  public init(changedFileCount: Int, additions: Int, deletions: Int) {
    self.changedFileCount = changedFileCount
    self.additions = additions
    self.deletions = deletions
  }

  private enum CodingKeys: String, CodingKey {
    case changedFileCount = "changed_file_count"
    case additions
    case deletions
  }
}

public struct RepositoryFileSummary: Codable, Hashable, Sendable {
  public let path: String
  public let category: RepositoryFileCategory
  public let lineCount: Int
  public let characterCount: Int
  public let byteCount: Int

  public init(
    path: String,
    category: RepositoryFileCategory,
    lineCount: Int,
    characterCount: Int,
    byteCount: Int
  ) {
    self.path = path
    self.category = category
    self.lineCount = lineCount
    self.characterCount = characterCount
    self.byteCount = byteCount
  }

  private enum CodingKeys: String, CodingKey {
    case path
    case category
    case lineCount = "line_count"
    case characterCount = "character_count"
    case byteCount = "byte_count"
  }
}

public struct RepositoryMetricsSnapshot: Codable, Hashable, Sendable {
  public let fileCount: Int
  public let sourceFileCount: Int
  public let testFileCount: Int
  public let otherFileCount: Int
  public let lineCount: Int
  public let characterCount: Int
  public let byteCount: Int
  public let largestFile: RepositoryFileSummary?
  public let smallestFile: RepositoryFileSummary?
  public let activity: RepositoryGitActivitySummary?

  public init(
    fileCount: Int,
    sourceFileCount: Int,
    testFileCount: Int,
    otherFileCount: Int,
    lineCount: Int,
    characterCount: Int,
    byteCount: Int,
    largestFile: RepositoryFileSummary? = nil,
    smallestFile: RepositoryFileSummary? = nil,
    activity: RepositoryGitActivitySummary? = nil
  ) {
    self.fileCount = fileCount
    self.sourceFileCount = sourceFileCount
    self.testFileCount = testFileCount
    self.otherFileCount = otherFileCount
    self.lineCount = lineCount
    self.characterCount = characterCount
    self.byteCount = byteCount
    self.largestFile = largestFile
    self.smallestFile = smallestFile
    self.activity = activity
  }

  private enum CodingKeys: String, CodingKey {
    case fileCount = "file_count"
    case sourceFileCount = "source_file_count"
    case testFileCount = "test_file_count"
    case otherFileCount = "other_file_count"
    case lineCount = "line_count"
    case characterCount = "character_count"
    case byteCount = "byte_count"
    case largestFile = "largest_file"
    case smallestFile = "smallest_file"
    case activity
  }
}

public struct RepositoryHistoryCommit: Codable, Hashable, Sendable {
  public let commitID: String
  public let shortID: String
  public let subject: String
  public let authorName: String
  public let committedAt: String
  public let metrics: RepositoryMetricsSnapshot
  public let activity: RepositoryGitActivitySummary

  public init(
    commitID: String,
    shortID: String,
    subject: String,
    authorName: String,
    committedAt: String,
    metrics: RepositoryMetricsSnapshot,
    activity: RepositoryGitActivitySummary
  ) {
    self.commitID = commitID
    self.shortID = shortID
    self.subject = subject
    self.authorName = authorName
    self.committedAt = committedAt
    self.metrics = metrics
    self.activity = activity
  }

  private enum CodingKeys: String, CodingKey {
    case commitID = "commit_id"
    case shortID = "short_id"
    case subject
    case authorName = "author_name"
    case committedAt = "committed_at"
    case metrics
    case activity
  }
}

public struct RepositoryMetricsBucket: Codable, Hashable, Sendable {
  public let bucketID: String
  public let label: String
  public let rangeStart: String
  public let rangeEnd: String
  public let metrics: RepositoryMetricsSnapshot

  public init(
    bucketID: String,
    label: String,
    rangeStart: String,
    rangeEnd: String,
    metrics: RepositoryMetricsSnapshot
  ) {
    self.bucketID = bucketID
    self.label = label
    self.rangeStart = rangeStart
    self.rangeEnd = rangeEnd
    self.metrics = metrics
  }

  private enum CodingKeys: String, CodingKey {
    case bucketID = "bucket_id"
    case label
    case rangeStart = "range_start"
    case rangeEnd = "range_end"
    case metrics
  }
}

public struct RepositoryHistoryReport: Codable, Hashable, Sendable {
  public let headCommitID: String
  public let summary: RepositoryMetricsSnapshot
  public let commits: [RepositoryHistoryCommit]
  public let buckets: [RepositoryMetricsBucket]

  public init(
    headCommitID: String,
    summary: RepositoryMetricsSnapshot,
    commits: [RepositoryHistoryCommit],
    buckets: [RepositoryMetricsBucket]
  ) {
    self.headCommitID = headCommitID
    self.summary = summary
    self.commits = commits
    self.buckets = buckets
  }

  private enum CodingKeys: String, CodingKey {
    case headCommitID = "head_commit_id"
    case summary
    case commits
    case buckets
  }
}

public struct RepositorySyntaxDiagnostic: Codable, Hashable, Sendable {
  public let path: String
  public let message: String
  public let severity: String
  public let line: Int?
  public let column: Int?

  public init(path: String, message: String, severity: String, line: Int? = nil, column: Int? = nil)
  {
    self.path = path
    self.message = message
    self.severity = severity
    self.line = line
    self.column = column
  }
}

public enum RepositorySyntaxHealthStatus: String, Codable, Hashable, Sendable {
  case configured
  case unsupported
  case failed
}

public struct RepositorySyntaxHealth: Codable, Hashable, Sendable {
  public let status: RepositorySyntaxHealthStatus
  public let checkedFileCount: Int
  public let diagnosticCount: Int
  public let failureMessage: String?
  public let diagnostics: [RepositorySyntaxDiagnostic]

  public init(
    status: RepositorySyntaxHealthStatus,
    checkedFileCount: Int,
    diagnosticCount: Int,
    failureMessage: String? = nil,
    diagnostics: [RepositorySyntaxDiagnostic] = []
  ) {
    self.status = status
    self.checkedFileCount = checkedFileCount
    self.diagnosticCount = diagnosticCount
    self.failureMessage = failureMessage
    self.diagnostics = diagnostics
  }

  private enum CodingKeys: String, CodingKey {
    case status
    case checkedFileCount = "checked_file_count"
    case diagnosticCount = "diagnostic_count"
    case failureMessage = "failure_message"
    case diagnostics
  }
}
