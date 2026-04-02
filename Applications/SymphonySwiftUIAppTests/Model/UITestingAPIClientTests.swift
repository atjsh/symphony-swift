import Foundation
import SymphonyShared
import Testing

@testable import SymphonySwiftUIApp

@Suite("UITestingSymphonyAPIClient", .tags(.model))
struct UITestingAPIClientTests {
  let client = UITestingSymphonyAPIClient()
  let endpoint = try! ServerEndpoint(host: "localhost", port: 8080)

  @Test func healthReturnsOKStatus() async throws {
    let health = try await client.health(endpoint: endpoint)
    #expect(health.status == "ok")
    #expect(health.version == "1.0.0")
    #expect(health.trackerKind == "github")
  }

  @Test func issuesReturnsNonEmptyList() async throws {
    let response = try await client.issues(endpoint: endpoint)
    #expect(!response.items.isEmpty)
    #expect(response.items[0].issueID == IssueID("issue-1"))
  }

  @Test func issueDetailReturnsValidStructure() async throws {
    let detail = try await client.issueDetail(endpoint: endpoint, issueID: IssueID("issue-1"))
    #expect(detail.issue.id == IssueID("issue-1"))
    #expect(detail.workspacePath != nil)
    #expect(!detail.recentSessions.isEmpty)
  }

  @Test func issueProgressReportReturnsValidMetrics() async throws {
    let report = try await client.issueProgressReport(endpoint: endpoint, issueID: IssueID("issue-1"))
    #expect(report.issueID == IssueID("issue-1"))
    #expect(report.report.headCommitID == "abcdef1234567890")
    #expect(report.report.summary.fileCount == 5)
    #expect(report.report.summary.lineCount == 640)
    #expect(!report.report.commits.isEmpty)
    #expect(!report.report.buckets.isEmpty)
    #expect(report.syntaxHealth.diagnosticCount == 1)
  }

  @Test func runDetailReturnsValidStructure() async throws {
    let detail = try await client.runDetail(endpoint: endpoint, runID: RunID("run-1"))
    #expect(detail.runID == RunID("run-1"))
    #expect(detail.provider == "claude_code")
    #expect(detail.turnCount == 3)
  }

  @Test func logsReturnsEvents() async throws {
    let response = try await client.logs(
      endpoint: endpoint,
      sessionID: SessionID("session-1"),
      cursor: nil,
      limit: 50
    )
    #expect(response.items.count == 2)
    #expect(response.hasMore == false)
  }

  @Test func refreshReturnsQueued() async throws {
    let response = try await client.refresh(endpoint: endpoint)
    #expect(response.queued == true)
  }

  @Test func logStreamFinishesImmediately() async throws {
    let stream = try client.logStream(
      endpoint: endpoint,
      sessionID: SessionID("session-1"),
      cursor: nil
    )
    var events = [AgentRawEvent]()
    for try await event in stream {
      events.append(event)
    }
    #expect(events.isEmpty)
  }
}
