import Foundation
import SymphonyShared

enum OperatorProgressMetric: String, CaseIterable, Codable, Sendable {
  case files
  case lines
  case characters
  case bytes

  var title: String {
    switch self {
    case .files:
      "Files"
    case .lines:
      "Lines"
    case .characters:
      "Characters"
    case .bytes:
      "Bytes"
    }
  }

  var systemImage: String {
    switch self {
    case .files:
      "doc.on.doc"
    case .lines:
      "text.alignleft"
    case .characters:
      "character.cursor.ibeam"
    case .bytes:
      "internaldrive"
    }
  }

  func value(for snapshot: RepositoryMetricsSnapshot) -> Int {
    switch self {
    case .files:
      snapshot.fileCount
    case .lines:
      snapshot.lineCount
    case .characters:
      snapshot.characterCount
    case .bytes:
      snapshot.byteCount
    }
  }
}

enum OperatorProgressReportStatus: Equatable, Sendable {
  case idle
  case noWorkspace
  case loading
  case loaded
  case failed(String)
}

struct OperatorProgressBucketPoint: Identifiable, Equatable, Sendable {
  let id: String
  let label: String
  let date: Date
  let value: Int
}

struct CachedOperatorProgressReportSnapshot: Equatable, Sendable {
  let response: IssueProgressReportResponse
  let selectedMetric: OperatorProgressMetric
  let selectedCommitID: String?
  let lastRefreshDate: Date
}

protocol OperatorProgressReportCaching: Sendable {
  func loadLatest(issueID: IssueID, workspacePath: String) async throws
    -> CachedOperatorProgressReportSnapshot?
  func store(
    snapshot: CachedOperatorProgressReportSnapshot,
    issueID: IssueID,
    workspacePath: String
  ) async throws
}
