import Foundation
import SwiftData
import SymphonyShared

@Model
final class OperatorProgressReportCacheRecord {
  #Index<OperatorProgressReportCacheRecord>(
    [\.issueID],
    [\.workspacePath],
    [\.lastRefreshDate],
    [\.issueID, \.workspacePath]
  )

  @Attribute(.unique) var cacheKey: String
  var issueID: String
  var workspacePath: String
  var headCommitID: String
  var selectedMetricRawValue: String
  var selectedCommitID: String?
  var lastRefreshDate: Date
  @Attribute(.externalStorage) var encodedResponse: Data

  init(
    cacheKey: String,
    issueID: String,
    workspacePath: String,
    headCommitID: String,
    selectedMetricRawValue: String,
    selectedCommitID: String?,
    lastRefreshDate: Date,
    encodedResponse: Data
  ) {
    self.cacheKey = cacheKey
    self.issueID = issueID
    self.workspacePath = workspacePath
    self.headCommitID = headCommitID
    self.selectedMetricRawValue = selectedMetricRawValue
    self.selectedCommitID = selectedCommitID
    self.lastRefreshDate = lastRefreshDate
    self.encodedResponse = encodedResponse
  }
}

@ModelActor
actor OperatorProgressReportCacheStore {
  func loadLatest(issueID: String, workspacePath: String) throws -> CachedOperatorProgressReportSnapshot? {
    var descriptor = FetchDescriptor<OperatorProgressReportCacheRecord>(
      predicate: #Predicate<OperatorProgressReportCacheRecord> { record in
        record.issueID == issueID && record.workspacePath == workspacePath
      },
      sortBy: [SortDescriptor(\.lastRefreshDate, order: .reverse)]
    )
    descriptor.fetchLimit = 1

    guard let record = try modelContext.fetch(descriptor).first else {
      return nil
    }

    return try Self.snapshot(from: record)
  }

  func store(
    snapshot: CachedOperatorProgressReportSnapshot,
    issueID: String,
    workspacePath: String
  ) throws {
    let cacheKey = Self.cacheKey(
      issueID: issueID,
      workspacePath: workspacePath,
      headCommitID: snapshot.response.report.headCommitID
    )
    var descriptor = FetchDescriptor<OperatorProgressReportCacheRecord>(
      predicate: #Predicate<OperatorProgressReportCacheRecord> { record in
        record.cacheKey == cacheKey
      }
    )
    descriptor.fetchLimit = 1

    let encodedResponse = try JSONEncoder().encode(snapshot.response)
    if let existing = try modelContext.fetch(descriptor).first {
      existing.selectedMetricRawValue = snapshot.selectedMetric.rawValue
      existing.selectedCommitID = snapshot.selectedCommitID
      existing.lastRefreshDate = snapshot.lastRefreshDate
      existing.encodedResponse = encodedResponse
      existing.headCommitID = snapshot.response.report.headCommitID
    } else {
      let record = OperatorProgressReportCacheRecord(
        cacheKey: cacheKey,
        issueID: issueID,
        workspacePath: workspacePath,
        headCommitID: snapshot.response.report.headCommitID,
        selectedMetricRawValue: snapshot.selectedMetric.rawValue,
        selectedCommitID: snapshot.selectedCommitID,
        lastRefreshDate: snapshot.lastRefreshDate,
        encodedResponse: encodedResponse
      )
      modelContext.insert(record)
    }

    try modelContext.save()
  }

  private static func snapshot(from record: OperatorProgressReportCacheRecord) throws
    -> CachedOperatorProgressReportSnapshot
  {
    let response = try JSONDecoder().decode(
      IssueProgressReportResponse.self,
      from: record.encodedResponse
    )
    return CachedOperatorProgressReportSnapshot(
      response: response,
      selectedMetric: OperatorProgressMetric(rawValue: record.selectedMetricRawValue) ?? .lines,
      selectedCommitID: record.selectedCommitID,
      lastRefreshDate: record.lastRefreshDate
    )
  }

  private static func cacheKey(issueID: String, workspacePath: String, headCommitID: String) -> String {
    "\(issueID)|\(workspacePath)|\(headCommitID)"
  }
}

struct DefaultOperatorProgressReportCache: OperatorProgressReportCaching {
  private let store: OperatorProgressReportCacheStore

  private init(store: OperatorProgressReportCacheStore) {
    self.store = store
  }

  static func makeDefault(
    containerFactory: () throws -> ModelContainer = {
      try ModelContainer(for: OperatorProgressReportCacheRecord.self)
    }
  ) -> any OperatorProgressReportCaching {
    do {
      let container = try containerFactory()
      return DefaultOperatorProgressReportCache(
        store: OperatorProgressReportCacheStore(modelContainer: container)
      )
    } catch {
      return InMemoryOperatorProgressReportCache()
    }
  }

  func loadLatest(issueID: IssueID, workspacePath: String) async throws
    -> CachedOperatorProgressReportSnapshot?
  {
    try await store.loadLatest(
      issueID: issueID.rawValue,
      workspacePath: workspacePath
    )
  }

  func store(
    snapshot: CachedOperatorProgressReportSnapshot,
    issueID: IssueID,
    workspacePath: String
  ) async throws {
    try await store.store(
      snapshot: snapshot,
      issueID: issueID.rawValue,
      workspacePath: workspacePath
    )
  }
}

struct InMemoryOperatorProgressReportCache: OperatorProgressReportCaching {
  struct CacheKey: Hashable {
    let issueID: String
    let workspacePath: String
    let headCommitID: String
  }

  actor Storage {
    var snapshotsByKey = [CacheKey: CachedOperatorProgressReportSnapshot]()

    func loadLatest(issueID: IssueID, workspacePath: String) -> CachedOperatorProgressReportSnapshot? {
      snapshotsByKey
        .filter { key, _ in
          key.issueID == issueID.rawValue && key.workspacePath == workspacePath
        }
        .map(\.value)
        .sorted { $0.lastRefreshDate > $1.lastRefreshDate }
        .first
    }

    func store(
      snapshot: CachedOperatorProgressReportSnapshot,
      issueID: IssueID,
      workspacePath: String
    ) {
      snapshotsByKey[
        CacheKey(
          issueID: issueID.rawValue,
          workspacePath: workspacePath,
          headCommitID: snapshot.response.report.headCommitID
        )
      ] = snapshot
    }
  }

  private let storage = Storage()

  func loadLatest(issueID: IssueID, workspacePath: String) async throws
    -> CachedOperatorProgressReportSnapshot?
  {
    await storage.loadLatest(issueID: issueID, workspacePath: workspacePath)
  }

  func store(
    snapshot: CachedOperatorProgressReportSnapshot,
    issueID: IssueID,
    workspacePath: String
  ) async throws {
    await storage.store(snapshot: snapshot, issueID: issueID, workspacePath: workspacePath)
  }
}
