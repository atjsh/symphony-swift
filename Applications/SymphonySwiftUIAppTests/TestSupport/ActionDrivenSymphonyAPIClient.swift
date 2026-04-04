import Foundation
import SymphonyShared

@testable import SymphonySwiftUIApp

// SAFETY: @unchecked Sendable — all mutable recording state protected by `lock`.
final class ActionDrivenSymphonyAPIClient: SymphonyAPIClientProtocol, @unchecked Sendable {
  private let lock = NSLock()
  private var _healthCount = 0
  private var _issuesCount = 0
  private var _refreshCount = 0
  private var _issueDetailRequests = [IssueID]()
  private var _runDetailRequests = [RunID]()
  private var _logRequests = [(sessionID: SessionID, cursor: EventCursor?, limit: Int)]()

  var healthCount: Int { lock.withLock { _healthCount } }
  var issuesCount: Int { lock.withLock { _issuesCount } }
  var refreshCount: Int { lock.withLock { _refreshCount } }
  var issueDetailRequests: [IssueID] { lock.withLock { _issueDetailRequests } }
  var runDetailRequests: [RunID] { lock.withLock { _runDetailRequests } }
  var logRequests: [(sessionID: SessionID, cursor: EventCursor?, limit: Int)] {
    lock.withLock { _logRequests }
  }

  func health(endpoint: ServerEndpoint) async throws -> HealthResponse {
    lock.withLock { _healthCount += 1 }
    return HealthResponse(
      status: "ok", serverTime: "2026-03-24T00:00:00Z", version: "1.0.0", trackerKind: "github")
  }

  func issues(endpoint: ServerEndpoint) async throws -> IssuesResponse {
    lock.withLock { _issuesCount += 1 }
    return IssuesResponse(items: [makeIssueSummary()])
  }

  func issueDetail(endpoint: ServerEndpoint, issueID: IssueID) async throws -> IssueDetail {
    lock.withLock { _issueDetailRequests.append(issueID) }
    return makeIssueDetail()
  }

  func issueProgressReport(endpoint: ServerEndpoint, issueID: IssueID) async throws
    -> IssueProgressReportResponse
  {
    lock.withLock { _issueDetailRequests.append(issueID) }
    return makeIssueProgressReport(issueID: issueID)
  }

  func runDetail(endpoint: ServerEndpoint, runID: RunID) async throws -> RunDetail {
    lock.withLock { _runDetailRequests.append(runID) }
    return makeRunDetail()
  }

  func logs(endpoint: ServerEndpoint, sessionID: SessionID, cursor: EventCursor?, limit: Int)
    async throws -> LogEntriesResponse
  {
    lock.withLock { _logRequests.append((sessionID, cursor, limit)) }
    return LogEntriesResponse(
      sessionID: sessionID,
      provider: "claude_code",
      items: [makeEvent(sequence: 1, kind: "message", rawJSON: #"{"message":"hello"}"#)],
      nextCursor: EventCursor(sessionID: sessionID, lastDeliveredSequence: EventSequence(1)),
      hasMore: false
    )
  }

  func refresh(endpoint: ServerEndpoint) async throws -> RefreshResponse {
    lock.withLock { _refreshCount += 1 }
    return RefreshResponse(queued: true, requestedAt: "2026-03-24T00:00:02Z")
  }

  func logStream(endpoint: ServerEndpoint, sessionID: SessionID, cursor: EventCursor?) throws
    -> AsyncThrowingStream<AgentRawEvent, Error>
  {
    AsyncThrowingStream { continuation in
      continuation.yield(makeEvent(sequence: 2, kind: "tool_result", rawJSON: #"{"result":"ok"}"#))
      continuation.finish()
    }
  }
}
