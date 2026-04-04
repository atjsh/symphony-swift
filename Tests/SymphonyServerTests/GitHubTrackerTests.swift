import Foundation
import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore
@testable import SymphonyShared

// MARK: - Stub GraphQL Transport Tests

@Suite("StubGraphQLTransport")
struct StubGraphQLTransportTests {
  @Test func executeReturnsEnqueuedResponse() async throws {
    let transport = StubGraphQLTransport()
    transport.enqueueResponse(#"{"data":null}"#)

    let data = try await transport.execute(query: "{ test }", variables: nil)
    let str = String(data: data, encoding: .utf8)

    #expect(str == #"{"data":null}"#)
    #expect(transport.executedQueryCount == 1)
  }

  @Test func executeReturnsEnqueuedDataResponse() async throws {
    let transport = StubGraphQLTransport()
    let original = Data(#"{"ok":true}"#.utf8)
    transport.enqueueResponse(original)

    let data = try await transport.execute(query: "query { x }", variables: ["a": 1])
    #expect(data == original)
  }

  @Test func executeThrowsEnqueuedError() async throws {
    let transport = StubGraphQLTransport()
    transport.enqueueError(GitHubTrackerError.missingAPIKey)

    await #expect(throws: GitHubTrackerError.self) {
      _ = try await transport.execute(query: "q", variables: nil)
    }
  }

  @Test func executeThrowsWhenNoResponseEnqueued() async throws {
    let transport = StubGraphQLTransport()

    await #expect(throws: GitHubTrackerError.self) {
      _ = try await transport.execute(query: "q", variables: nil)
    }
  }

  @Test func executedQueriesTracksAllCalls() async throws {
    let transport = StubGraphQLTransport()
    transport.enqueueResponse(#"{}"#)
    transport.enqueueResponse(#"{}"#)

    _ = try await transport.execute(query: "q1", variables: nil)
    _ = try await transport.execute(query: "q2", variables: ["k": "v"])

    #expect(transport.executedQueryCount == 2)
    #expect(transport.executedQueries[0].query == "q1")
    #expect(transport.executedQueries[1].query == "q2")
  }
}

// MARK: - GitHub GraphQL Query Tests

@Suite("GitHubGraphQL Query Construction")
struct GitHubGraphQLQueryTests {
  @Test func projectItemsQueryWithoutCursor() {
    let (query, variables) = GitHubGraphQL.projectItemsQuery(
      projectID: "PVT_123", statusFieldName: "Status", cursor: nil)

    #expect(query.contains("node(id: $projectId)"))
    #expect(query.contains("items(first: 100)"))
    #expect(query.contains("__typename"))
    #expect(query.contains("fieldValueByName(name: \"Status\")"))
    #expect((variables["projectId"] as? String) == "PVT_123")
  }

  @Test func projectItemsQueryWithCursor() {
    let (query, _) = GitHubGraphQL.projectItemsQuery(
      projectID: "PVT_123", statusFieldName: "Status", cursor: "abc123")

    #expect(query.contains(#"after: "abc123""#))
  }

  @Test func issueStatesByIDsQuery() {
    let (query, _) = GitHubGraphQL.issueStatesByIDsQuery(
      issueIDs: ["I_1", "I_2"])

    #expect(query.contains("issue0: node"))
    #expect(query.contains("issue1: node"))
    #expect(query.contains("I_1"))
    #expect(query.contains("I_2"))
  }
}

// MARK: - GitHub Tracker Adapter Tests

@Suite("GitHubTrackerAdapter")
struct GitHubTrackerAdapterTests {
  @Test func fetchCandidateIssuesResolvesProjectAndReturnsIssues() async throws {
    let transport = StubGraphQLTransport()
    let config = makeTrackerConfig()
    let adapter = GitHubTrackerAdapter(transport: transport, config: config)

    transport.enqueueResponse(projectIDResponse())
    transport.enqueueResponse(
      candidateItemsResponse(items: [
        (id: "I_1", number: 1, title: "Fix bug", repo: "test-owner/repo", status: "In Progress")
      ]))

    let issues = try await adapter.fetchCandidateIssues()

    #expect(issues.count == 1)
    #expect(issues[0].id == IssueID("I_1"))
    #expect(issues[0].title == "Fix bug")
    #expect(issues[0].number == 1)
    #expect(issues[0].state == "In Progress")
    #expect(issues[0].issueState == "OPEN")
    #expect(issues[0].repository == "test-owner/repo")
    #expect(issues[0].labels == ["bug"])
  }

  @Test func fetchCandidateIssuesExcludesPullRequestsAndDraftIssues() async throws {
    let transport = StubGraphQLTransport()
    let config = makeTrackerConfig()
    let adapter = GitHubTrackerAdapter(transport: transport, config: config)

    transport.enqueueResponse(projectIDResponse())
    let response = """
      {
        "data": {
          "node": {
            "items": {
              "nodes": [
                {
                  "id": "PVTI_PR",
                  "content": {"__typename": "PullRequest", "id": "PR_1"},
                  "fieldValueByName": {"name": "In Progress"}
                },
                {
                  "id": "PVTI_DRAFT",
                  "content": {"__typename": "DraftIssue", "id": "DI_1"},
                  "fieldValueByName": {"name": "Todo"}
                }
              ],
              "pageInfo": {"hasNextPage": false, "endCursor": null}
            }
          }
        }
      }
      """
    transport.enqueueResponse(response)

    let issues = try await adapter.fetchCandidateIssues()
    #expect(issues.isEmpty)
  }

  @Test func fetchCandidateIssuesFiltersByActiveStates() async throws {
    let transport = StubGraphQLTransport()
    let config = makeTrackerConfig(activeStates: ["In Progress"])
    let adapter = GitHubTrackerAdapter(transport: transport, config: config)

    transport.enqueueResponse(projectIDResponse())
    transport.enqueueResponse(
      candidateItemsResponse(items: [
        (id: "I_1", number: 1, title: "Active", repo: "test-owner/repo", status: "In Progress"),
        (id: "I_2", number: 2, title: "Done", repo: "test-owner/repo", status: "Done"),
      ]))

    let issues = try await adapter.fetchCandidateIssues()
    #expect(issues.count == 1)
    #expect(issues[0].title == "Active")
  }

  @Test func fetchCandidateIssuesRespectsRepoAllowlist() async throws {
    let transport = StubGraphQLTransport()
    let config = makeTrackerConfig(repositoryAllowlist: ["test-owner/allowed"])
    let adapter = GitHubTrackerAdapter(transport: transport, config: config)

    transport.enqueueResponse(projectIDResponse())
    transport.enqueueResponse(
      candidateItemsResponse(items: [
        (id: "I_1", number: 1, title: "Allowed", repo: "test-owner/allowed", status: "In Progress"),
        (
          id: "I_2", number: 2, title: "Blocked", repo: "test-owner/blocked",
          status: "In Progress"
        ),
      ]))

    let issues = try await adapter.fetchCandidateIssues()
    #expect(issues.count == 1)
    #expect(issues[0].title == "Allowed")
  }

  @Test func fetchCandidateIssuesCachesProjectID() async throws {
    let transport = StubGraphQLTransport()
    let config = makeTrackerConfig()
    let adapter = GitHubTrackerAdapter(transport: transport, config: config)

    // First call: project ID + items
    transport.enqueueResponse(projectIDResponse())
    transport.enqueueResponse(candidateItemsResponse(items: []))

    // Second call: items only (project ID cached)
    transport.enqueueResponse(candidateItemsResponse(items: []))

    _ = try await adapter.fetchCandidateIssues()
    _ = try await adapter.fetchCandidateIssues()

    // 3 queries: project ID + items + items (no second project ID query)
    #expect(transport.executedQueryCount == 3)
  }

  @Test func fetchCandidateIssuesUserOwnerType() async throws {
    let transport = StubGraphQLTransport()
    let config = makeTrackerConfig(projectOwnerType: "user")
    let adapter = GitHubTrackerAdapter(transport: transport, config: config)

    transport.enqueueResponse(userProjectIDResponse())
    transport.enqueueResponse(candidateItemsResponse(items: []))

    let issues = try await adapter.fetchCandidateIssues()
    #expect(issues.isEmpty)

    // Verify the first query used "user" not "organization"
    let firstQuery = transport.executedQueries[0].query
    #expect(firstQuery.contains("user(login:"))
  }

  @Test func fetchCandidateIssuesPagination() async throws {
    let transport = StubGraphQLTransport()
    let config = makeTrackerConfig()
    let adapter = GitHubTrackerAdapter(transport: transport, config: config)

    transport.enqueueResponse(projectIDResponse())
    // Page 1
    transport.enqueueResponse(
      candidateItemsResponse(
        items: [
          (id: "I_1", number: 1, title: "Page1", repo: "test-owner/repo", status: "In Progress")
        ],
        hasNextPage: true, endCursor: "cursor1"
      ))
    // Page 2
    transport.enqueueResponse(
      candidateItemsResponse(
        items: [
          (id: "I_2", number: 2, title: "Page2", repo: "test-owner/repo", status: "In Progress")
        ]
      ))

    let issues = try await adapter.fetchCandidateIssues()
    #expect(issues.count == 2)
    #expect(issues[0].title == "Page1")
    #expect(issues[1].title == "Page2")
  }

  @Test func fetchIssuesByStatesFiltersCorrectly() async throws {
    let transport = StubGraphQLTransport()
    let config = makeTrackerConfig()
    let adapter = GitHubTrackerAdapter(transport: transport, config: config)

    transport.enqueueResponse(projectIDResponse())
    transport.enqueueResponse(
      candidateItemsResponse(items: [
        (id: "I_1", number: 1, title: "Done", repo: "test-owner/repo", status: "Done"),
        (id: "I_2", number: 2, title: "Active", repo: "test-owner/repo", status: "In Progress"),
      ]))

    let issues = try await adapter.fetchIssuesByStates(["Done"])
    #expect(issues.count == 1)
    #expect(issues[0].title == "Done")
  }

  @Test func fetchAllIssuesIncludesNonActiveStates() async throws {
    let transport = StubGraphQLTransport()
    let config = makeTrackerConfig(activeStates: ["In Progress"])
    let adapter = GitHubTrackerAdapter(transport: transport, config: config)

    transport.enqueueResponse(projectIDResponse())
    transport.enqueueResponse(
      candidateItemsResponse(items: [
        (id: "I_1", number: 1, title: "Backlog", repo: "test-owner/repo", status: "Backlog"),
        (id: "I_2", number: 2, title: "Done", repo: "test-owner/repo", status: "Done"),
      ]))

    let issues = try await adapter.fetchAllIssues()
    #expect(issues.count == 2)
    #expect(issues.map { $0.state } == ["Backlog", "Done"])
  }

  @Test func fetchIssueStatesByIDsReturnsStates() async throws {
    let transport = StubGraphQLTransport()
    let config = makeTrackerConfig()
    let adapter = GitHubTrackerAdapter(transport: transport, config: config)

    transport.enqueueResponse(
      """
      {
        "data": {
          "issue0": {"id": "I_1", "state": "OPEN"},
          "issue1": {"id": "I_2", "state": "CLOSED"}
        }
      }
      """)

    let states = try await adapter.fetchIssueStatesByIDs([IssueID("I_1"), IssueID("I_2")])
    #expect(states[IssueID("I_1")] == "OPEN")
    #expect(states[IssueID("I_2")] == "CLOSED")
  }

  @Test func fetchIssueStatesByIDsHandlesProjectItemContent() async throws {
    let transport = StubGraphQLTransport()
    let config = makeTrackerConfig()
    let adapter = GitHubTrackerAdapter(transport: transport, config: config)

    transport.enqueueResponse(
      """
      {
        "data": {
          "issue0": {
            "content": {"id": "I_1", "state": "OPEN"}
          }
        }
      }
      """)

    let states = try await adapter.fetchIssueStatesByIDs([IssueID("I_1")])
    #expect(states[IssueID("I_1")] == "OPEN")
  }

  @Test func fetchIssueStatesByIDsEmptyInput() async throws {
    let transport = StubGraphQLTransport()
    let config = makeTrackerConfig()
    let adapter = GitHubTrackerAdapter(transport: transport, config: config)

    let states = try await adapter.fetchIssueStatesByIDs([])
    #expect(states.isEmpty)
    #expect(transport.executedQueryCount == 0)
  }

  @Test func fetchIssueStatesByIDsInvalidResponse() async throws {
    let transport = StubGraphQLTransport()
    let config = makeTrackerConfig()
    let adapter = GitHubTrackerAdapter(transport: transport, config: config)

    transport.enqueueResponse("not json")

    await #expect(throws: GitHubTrackerError.self) {
      _ = try await adapter.fetchIssueStatesByIDs([IssueID("I_1")])
    }
  }

  @Test func missingProjectConfigThrows() async throws {
    let transport = StubGraphQLTransport()
    let config = TrackerConfig()  // No project owner/type/number
    let adapter = GitHubTrackerAdapter(transport: transport, config: config)

    await #expect(throws: GitHubTrackerError.self) {
      _ = try await adapter.fetchCandidateIssues()
    }
  }

  @Test func graphQLErrorsThrow() async throws {
    let transport = StubGraphQLTransport()
    let config = makeTrackerConfig()
    let adapter = GitHubTrackerAdapter(transport: transport, config: config)

    transport.enqueueResponse(projectIDResponse())
    transport.enqueueResponse(
      """
      {"data": null, "errors": [{"message": "Something went wrong"}]}
      """)

    await #expect(throws: GitHubTrackerError.self) {
      _ = try await adapter.fetchCandidateIssues()
    }
  }

  @Test func missingProjectNodeThrows() async throws {
    let transport = StubGraphQLTransport()
    let config = makeTrackerConfig()
    let adapter = GitHubTrackerAdapter(transport: transport, config: config)

    transport.enqueueResponse(projectIDResponse())
    transport.enqueueResponse(
      """
      {"data": {"node": null}}
      """)

    await #expect(throws: GitHubTrackerError.self) {
      _ = try await adapter.fetchCandidateIssues()
    }
  }

  @Test func invalidProjectIDResponseThrows() async throws {
    let transport = StubGraphQLTransport()
    let config = makeTrackerConfig()
    let adapter = GitHubTrackerAdapter(transport: transport, config: config)

    transport.enqueueResponse(
      """
      {"data": {"organization": {"projectV2": null}}}
      """)

    await #expect(throws: GitHubTrackerError.self) {
      _ = try await adapter.fetchCandidateIssues()
    }
  }

  @Test func blockerReferencesAreBuilt() async throws {
    let transport = StubGraphQLTransport()
    let config = makeTrackerConfig()
    let adapter = GitHubTrackerAdapter(transport: transport, config: config)

    transport.enqueueResponse(projectIDResponse())
    let response = """
      {
        "data": {
          "node": {
            "items": {
              "nodes": [{
                "id": "PVTI_1",
                "content": {
                  "__typename": "Issue",
                  "id": "I_1",
                  "number": 1,
                  "title": "Has blockers",
                  "body": null,
                  "state": "OPEN",
                  "url": null,
                  "createdAt": "2026-01-01T00:00:00Z",
                  "updatedAt": null,
                  "labels": {"nodes": []},
                  "repository": {"nameWithOwner": "test-owner/repo"},
                  "trackedInIssues": {
                    "nodes": [{
                      "id": "I_BLOCKER",
                      "number": 99,
                      "state": "OPEN",
                      "repository": {"nameWithOwner": "test-owner/repo"}
                    }]
                  }
                },
                "fieldValueByName": {"name": "In Progress"}
              }],
              "pageInfo": {"hasNextPage": false, "endCursor": null}
            }
          }
        }
      }
      """
    transport.enqueueResponse(response)

    let issues = try await adapter.fetchCandidateIssues()
    #expect(issues.count == 1)
    #expect(issues[0].blockedBy.count == 1)
    #expect(issues[0].blockedBy[0].issueID == IssueID("I_BLOCKER"))
    #expect(issues[0].blockedBy[0].issueState == "OPEN")
  }

}
