import Foundation
import SymphonyShared

@testable import SymphonySwiftUIApp

struct PassiveSymphonyAPIClient: SymphonyAPIClientProtocol {
  func health(endpoint: ServerEndpoint) async throws -> HealthResponse {
    HealthResponse(status: "ok", serverTime: "", version: "", trackerKind: "")
  }

  func issues(endpoint: ServerEndpoint) async throws -> IssuesResponse {
    IssuesResponse(items: [])
  }

  func issueDetail(endpoint: ServerEndpoint, issueID: IssueID) async throws -> IssueDetail {
    makeIssueDetail()
  }

  func issueProgressReport(endpoint: ServerEndpoint, issueID: IssueID) async throws
    -> IssueProgressReportResponse
  {
    makeIssueProgressReport(issueID: issueID)
  }

  func runDetail(endpoint: ServerEndpoint, runID: RunID) async throws -> RunDetail {
    makeRunDetail()
  }

  func logs(endpoint: ServerEndpoint, sessionID: SessionID, cursor: EventCursor?, limit: Int)
    async throws -> LogEntriesResponse
  {
    LogEntriesResponse(
      sessionID: sessionID, provider: "claude_code", items: [], nextCursor: nil, hasMore: false)
  }

  func refresh(endpoint: ServerEndpoint) async throws -> RefreshResponse {
    RefreshResponse(queued: true, requestedAt: "")
  }

  func logStream(endpoint: ServerEndpoint, sessionID: SessionID, cursor: EventCursor?) throws
    -> AsyncThrowingStream<AgentRawEvent, Error>
  {
    AsyncThrowingStream { continuation in
      continuation.finish()
    }
  }
}
