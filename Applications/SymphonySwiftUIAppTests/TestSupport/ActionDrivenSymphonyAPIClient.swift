import Foundation
import SymphonyShared

@testable import SymphonySwiftUIApp

final class ActionDrivenSymphonyAPIClient: SymphonyAPIClientProtocol, @unchecked Sendable {
  private(set) var healthCount = 0
  private(set) var issuesCount = 0
  private(set) var refreshCount = 0
  private(set) var issueDetailRequests = [IssueID]()
  private(set) var runDetailRequests = [RunID]()
  private(set) var logRequests = [(sessionID: SessionID, cursor: EventCursor?, limit: Int)]()

  func health(endpoint: ServerEndpoint) async throws -> HealthResponse {
    healthCount += 1
    return HealthResponse(
      status: "ok", serverTime: "2026-03-24T00:00:00Z", version: "1.0.0", trackerKind: "github")
  }

  func issues(endpoint: ServerEndpoint) async throws -> IssuesResponse {
    issuesCount += 1
    return IssuesResponse(items: [makeIssueSummary()])
  }

  func issueDetail(endpoint: ServerEndpoint, issueID: IssueID) async throws -> IssueDetail {
    issueDetailRequests.append(issueID)
    return makeIssueDetail()
  }

  func issueProgressReport(endpoint: ServerEndpoint, issueID: IssueID) async throws
    -> IssueProgressReportResponse
  {
    issueDetailRequests.append(issueID)
    return makeIssueProgressReport(issueID: issueID)
  }

  func runDetail(endpoint: ServerEndpoint, runID: RunID) async throws -> RunDetail {
    runDetailRequests.append(runID)
    return makeRunDetail()
  }

  func logs(endpoint: ServerEndpoint, sessionID: SessionID, cursor: EventCursor?, limit: Int)
    async throws -> LogEntriesResponse
  {
    logRequests.append((sessionID, cursor, limit))
    return LogEntriesResponse(
      sessionID: sessionID,
      provider: "claude_code",
      items: [makeEvent(sequence: 1, kind: "message", rawJSON: #"{"message":"hello"}"#)],
      nextCursor: EventCursor(sessionID: sessionID, lastDeliveredSequence: EventSequence(1)),
      hasMore: false
    )
  }

  func refresh(endpoint: ServerEndpoint) async throws -> RefreshResponse {
    refreshCount += 1
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
