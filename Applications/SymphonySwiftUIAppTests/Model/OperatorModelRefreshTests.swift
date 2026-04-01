import Foundation
import SymphonyShared
import Testing

@testable import SymphonySwiftUIApp

@MainActor
@Suite("OperatorModel – Refresh", .tags(.model))
struct OperatorModelRefreshTests {
  @Test func RefreshReloadsIssuesAndRetainsSelection() async throws {
    let client = MockSymphonyAPIClient()
    let issueSummary = makeIssueSummary()
    client.healthResponse = HealthResponse(
      status: "ok", serverTime: "2026-03-24T12:00:00Z", version: "1.0.0", trackerKind: "github")
    client.issuesResponse = IssuesResponse(items: [issueSummary])
    client.issueDetailResponse = makeIssueDetail()
    client.runDetailResponse = makeRunDetail()
    client.logsResponse = LogEntriesResponse(
      sessionID: SessionID("session-42"),
      provider: "claude_code",
      items: [],
      nextCursor: nil,
      hasMore: false
    )

    let model = SymphonyOperatorModel(client: client)
    await model.connect()
    await model.selectIssue(issueSummary)

    client.issuesResponse = IssuesResponse(items: [
      issueSummary,
      IssueSummary(
        issueID: IssueID("issue-84"),
        identifier: try IssueIdentifier(validating: "atjsh/example#84"),
        title: "Second issue",
        state: "queued",
        issueState: "OPEN",
        priority: 2,
        currentProvider: nil,
        currentRunID: nil,
        currentSessionID: nil
      ),
    ])

    await model.refresh()

    #expect(client.refreshCallCount == 1)
    #expect(model.issues.map(\.issueID.rawValue) == ["issue-42", "issue-84"])
    #expect(model.selectedIssueID?.rawValue == "issue-42")
  }

  @Test func RefreshWithMatchingSelectionReloadsSelectedIssueDetail() async throws {
    let client = MockSymphonyAPIClient()
    let issueSummary = makeIssueSummary()
    client.issuesResponse = IssuesResponse(items: [issueSummary])
    client.issueDetailResponse = makeIssueDetail()
    client.runDetailResponse = makeRunDetail()
    client.logsResponse = LogEntriesResponse(
      sessionID: SessionID("session-42"),
      provider: "claude_code",
      items: [],
      nextCursor: nil,
      hasMore: false
    )

    let model = SymphonyOperatorModel(client: client)
    model.selectedIssueID = issueSummary.issueID

    await model.refresh()
    try await waitUntil {
      model.issueDetail?.issue.id == issueSummary.issueID && model.liveStatus == "Ended"
    }

    #expect(client.issueDetailRequests == [issueSummary.issueID])
    #expect(model.runDetail?.runID == RunID("run-42"))
  }

  @Test func RefreshWithMissingSelectionDoesNotReloadIssueDetail() async {
    let client = MockSymphonyAPIClient()
    client.issuesResponse = IssuesResponse(items: [
      IssueSummary(
        issueID: IssueID("issue-84"),
        identifier: try! IssueIdentifier(validating: "atjsh/example#84"),
        title: "Other issue",
        state: "queued",
        issueState: "OPEN",
        priority: 2,
        currentProvider: nil,
        currentRunID: nil,
        currentSessionID: nil
      )
    ])

    let model = SymphonyOperatorModel(client: client)
    model.selectedIssueID = IssueID("issue-42")

    await model.refresh()

    #expect(client.issueDetailRequests.isEmpty)
    #expect(model.selectedIssueID == IssueID("issue-42"))
  }

  @Test func RefreshReusesLastDeliveredCursorForSelectedRun() async throws {
    let client = MockSymphonyAPIClient()
    let issueSummary = makeIssueSummary()
    let firstCursor = EventCursor(
      sessionID: SessionID("session-42"), lastDeliveredSequence: EventSequence(2))
    let secondCursor = EventCursor(
      sessionID: SessionID("session-42"), lastDeliveredSequence: EventSequence(3))
    let firstEvent = makeEvent(sequence: 1, kind: "message")
    let secondEvent = makeEvent(sequence: 2, kind: "tool_call")
    let thirdEvent = makeEvent(sequence: 3, kind: "tool_result")
    let fourthEvent = makeEvent(sequence: 4, kind: "status")

    client.healthResponse = HealthResponse(
      status: "ok", serverTime: "2026-03-24T12:00:00Z", version: "1.0.0", trackerKind: "github")
    client.issuesResponse = IssuesResponse(items: [issueSummary])
    client.issueDetailResponse = makeIssueDetail()
    client.runDetailResponse = makeRunDetail()
    client.logsResponse = LogEntriesResponse(
      sessionID: SessionID("session-42"),
      provider: "claude_code",
      items: [firstEvent, secondEvent],
      nextCursor: firstCursor,
      hasMore: false
    )

    let model = SymphonyOperatorModel(client: client)
    await model.connect()
    await model.selectIssue(issueSummary)
    try await waitUntil {
      model.logEvents.map(\.sequence.rawValue) == [1, 2] && model.liveStatus == "Ended"
    }

    client.logsResponse = LogEntriesResponse(
      sessionID: SessionID("session-42"),
      provider: "claude_code",
      items: [thirdEvent],
      nextCursor: secondCursor,
      hasMore: false
    )
    client.liveEvents = [fourthEvent]

    await model.refresh()
    try await waitUntil {
      model.logEvents.map(\.sequence.rawValue) == [1, 2, 3, 4] && model.liveStatus == "Ended"
    }

    #expect(client.logRequests.count == 2)
    #expect(client.logRequests[0].cursor == nil)
    #expect(client.logRequests[1].cursor == firstCursor)
    #expect(client.streamRequests.count == 2)
    #expect(client.streamRequests[0].cursor == firstCursor)
    #expect(client.streamRequests[1].cursor == secondCursor)
  }

  @Test func RefreshStartedBeforeSelectionDoesNotRerequestIssueDetail() async throws {
    let client = MockSymphonyAPIClient()
    let issueSummary = makeIssueSummary()
    client.healthResponse = HealthResponse(
      status: "ok", serverTime: "2026-03-24T12:00:00Z", version: "1.0.0", trackerKind: "github")
    client.issuesResponse = IssuesResponse(items: [issueSummary])
    client.issueDetailResponse = makeIssueDetail()
    client.runDetailResponse = makeRunDetail()
    client.logsResponse = LogEntriesResponse(
      sessionID: SessionID("session-42"),
      provider: "claude_code",
      items: [],
      nextCursor: nil,
      hasMore: false
    )
    client.suspendRefresh = true

    let model = SymphonyOperatorModel(client: client)
    await model.connect()

    let refreshTask = Task {
      await model.refresh()
    }

    try await waitUntil {
      client.refreshCallCount == 1 && model.isRefreshing
    }

    await model.selectIssue(issueSummary)
    client.resumeRefresh()
    await refreshTask.value

    try await waitUntil {
      model.issueDetail?.issue.id == IssueID("issue-42")
        && model.runDetail?.runID == RunID("run-42")
        && model.liveStatus == "Ended"
    }

    #expect(client.issueDetailRequests == [IssueID("issue-42")])
  }
}
