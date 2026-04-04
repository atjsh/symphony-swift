import Foundation
import SymphonyShared
import Testing

@testable import SymphonySwiftUIApp

@MainActor
@Suite("OperatorModel – Connection", .tags(.model))
struct OperatorModelConnectionTests {
  @Test func DefaultInitializerUsesOverviewTabAllLogFilterAndEmptySearch() {
    let model = SymphonyOperatorModel()

    #expect(model.issueSearchText == "")
    #expect(model.selectedDetailTab == .overview)
    #expect(model.selectedLogFilter == .all)
    #expect(model.filteredIssues.isEmpty)
    #expect(model.filteredVisibleLogEvents.isEmpty)
  }

  @Test func DefaultInitializerUsesDefaultEndpointAndIdleState() {
    let model = SymphonyOperatorModel()

    #expect(model.host == "localhost")
    #expect(model.portText == "8080")
    #expect(model.health == nil)
    #expect(model.issues.isEmpty)
    #expect(model.logEvents.isEmpty)
    #expect(model.isConnecting == false)
    #expect(model.isRefreshing == false)
    #expect(model.liveStatus == "Idle")
  }

  @Test func ConnectLoadsHealthAndIssuesFromConfiguredEndpoint() async throws {
    let client = MockSymphonyAPIClient()
    client.healthResponse = HealthResponse(
      status: "ok", serverTime: "2026-03-24T12:00:00Z", version: "1.0.0", trackerKind: "github")
    client.issuesResponse = IssuesResponse(items: [makeIssueSummary()])

    let model = SymphonyOperatorModel(
      client: client,
      initialEndpoint: try ServerEndpoint(host: "localhost", port: 8080)
    )

    await model.connect()

    #expect(client.recordedHosts == ["localhost", "localhost"])
    #expect(model.health?.trackerKind == "github")
    #expect(model.issues.map(\.issueID.rawValue) == ["issue-42"])
    #expect(model.connectionError == nil)
  }

  @Test func InitialStateServerEndpointResolutionAndConnectCanRestoreSelection() async throws {
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

    let model = SymphonyOperatorModel(
      client: client,
      initialEndpoint: try ServerEndpoint(scheme: "https", host: "example.com", port: 9443)
    )

    #expect(model.host == "example.com")
    #expect(model.portText == "9443")
    #expect(model.health == nil)
    #expect(model.issues.isEmpty)
    #expect(model.logEvents.isEmpty)
    #expect(model.liveStatus == "Idle")
    try #expect(model.serverEndpoint == ServerEndpoint(host: "example.com", port: 9443))

    model.selectedIssueID = issueSummary.issueID
    await model.connect()
    try await waitUntil("model loads detail") { model.liveStatus == "Ended" }

    #expect(client.issueDetailRequests == [IssueID("issue-42")])
    #expect(model.issueDetail?.issue.id == IssueID("issue-42"))
    #expect(model.runDetail?.runID == RunID("run-42"))
    #expect(model.liveStatus == "Ended")

    model.host = ""
    #expect(model.serverEndpoint == nil)
  }

  @Test func InvalidEndpointAndFailuresUpdateConnectionState() async throws {
    let client = MockSymphonyAPIClient()
    client.healthError = TestModelFailure.failed("health")

    let model = SymphonyOperatorModel(
      client: client,
      initialEndpoint: try ServerEndpoint(host: "localhost", port: 8080)
    )
    model.portText = "invalid"

    await model.connect()
    #expect(model.connectionError == SymphonyClientError.invalidEndpoint.localizedDescription)

    model.portText = "8080"
    await model.connect()
    #expect(model.health == nil)
    #expect(model.issues.isEmpty)
    #expect(model.connectionError == "health")

    client.healthError = nil
    client.refreshError = TestModelFailure.failed("refresh")
    await model.refresh()
    #expect(model.connectionError == "refresh")
  }

  @Test func ConnectSurfacesServerEnvelopeMessage() async throws {
    let client = MockSymphonyAPIClient()
    client.healthError = SymphonyClientError.serverEnvelope(
      statusCode: 404,
      code: "issue_not_found",
      message: "Issue issue-42 was not found."
    )

    let model = SymphonyOperatorModel(
      client: client,
      initialEndpoint: try ServerEndpoint(host: "localhost", port: 8080)
    )

    await model.connect()

    #expect(model.connectionError == "Issue issue-42 was not found.")
  }

  @Test func ConnectAndRefreshFailuresClearStateAndRespectInvalidEndpoints() async throws {
    let client = MockSymphonyAPIClient()
    client.healthResponse = HealthResponse(
      status: "ok", serverTime: "2026-03-24T12:00:00Z", version: "1.0.0", trackerKind: "github")
    client.issuesError = TestModelFailure.failed("issues")

    let model = SymphonyOperatorModel(
      client: client,
      initialEndpoint: try ServerEndpoint(host: "localhost", port: 8080)
    )
    model.health = HealthResponse(
      status: "stale", serverTime: "2026-03-24T00:00:00Z", version: "0.9.0", trackerKind: "github")
    model.issues = [makeIssueSummary()]

    await model.connect()

    #expect(model.health == nil)
    #expect(model.issues.isEmpty)
    #expect(model.connectionError == "issues")
    #expect(model.isConnecting == false)

    model.portText = "invalid"
    await model.refresh()
    #expect(model.connectionError == SymphonyClientError.invalidEndpoint.localizedDescription)
    #expect(model.isRefreshing == false)

    model.portText = "8080"
    client.issuesError = TestModelFailure.failed("refresh issues")
    await model.refresh()
    #expect(model.connectionError == "refresh issues")
    #expect(model.isRefreshing == false)
  }
}
