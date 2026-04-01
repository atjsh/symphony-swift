import Foundation
import SymphonyShared

@testable import SymphonySwiftUIApp

struct TestProgressReportCache: OperatorProgressReportCaching {
  final actor Storage {
    var snapshots: [CachedOperatorProgressReportSnapshot]
    var loadRequests = [(IssueID, String)]()
    var storedSnapshots = [CachedOperatorProgressReportSnapshot]()

    init(snapshots: [CachedOperatorProgressReportSnapshot]) {
      self.snapshots = snapshots
    }

    func snapshotLoadRequests() -> [(IssueID, String)] {
      loadRequests
    }

    func snapshotStoredSnapshots() -> [CachedOperatorProgressReportSnapshot] {
      storedSnapshots
    }

    func firstSnapshot() -> CachedOperatorProgressReportSnapshot? {
      snapshots.first
    }

    func recordLoad(issueID: IssueID, workspacePath: String) {
      loadRequests.append((issueID, workspacePath))
    }

    func recordStore(_ snapshot: CachedOperatorProgressReportSnapshot) {
      storedSnapshots.append(snapshot)
    }
  }

  private let storage: Storage

  init(snapshots: [CachedOperatorProgressReportSnapshot] = []) {
    self.storage = Storage(snapshots: snapshots)
  }

  var loadRequests: [(IssueID, String)] {
    get async {
      await storage.snapshotLoadRequests()
    }
  }

  var storedSnapshots: [CachedOperatorProgressReportSnapshot] {
    get async {
      await storage.snapshotStoredSnapshots()
    }
  }

  func loadLatest(issueID: IssueID, workspacePath: String) async throws
    -> CachedOperatorProgressReportSnapshot?
  {
    await storage.recordLoad(issueID: issueID, workspacePath: workspacePath)
    return await storage.firstSnapshot()
  }

  func store(
    snapshot: CachedOperatorProgressReportSnapshot,
    issueID _: IssueID,
    workspacePath _: String
  ) async throws {
    await storage.recordStore(snapshot)
  }
}
