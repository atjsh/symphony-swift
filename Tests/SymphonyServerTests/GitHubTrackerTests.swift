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
  private func makeConfig(
    projectOwner: String = "test-owner",
    projectOwnerType: String = "organization",
    projectNumber: Int = 1,
    activeStates: [String] = ["Todo", "In Progress"],
    terminalStates: [String] = ["Done"],
    repositoryAllowlist: [String] = []
  ) -> TrackerConfig {
    TrackerConfig(
      kind: "github",
      projectOwner: projectOwner,
      projectOwnerType: projectOwnerType,
      projectNumber: projectNumber,
      repositoryAllowlist: repositoryAllowlist,
      activeStates: activeStates,
      terminalStates: terminalStates
    )
  }

  private func projectIDResponse(id: String = "PVT_TEST") -> String {
    """
    {"data":{"organization":{"projectV2":{"id":"\(id)"}}}}
    """
  }

  private func userProjectIDResponse(id: String = "PVT_USER") -> String {
    """
    {"data":{"user":{"projectV2":{"id":"\(id)"}}}}
    """
  }

  private func candidateItemsResponse(
    items: [(id: String, number: Int, title: String, repo: String, status: String)],
    hasNextPage: Bool = false,
    endCursor: String? = nil
  ) -> String {
    let nodes = items.map { item in
      """
      {
        "id": "PVTI_\(item.id)",
        "content": {
          "__typename": "Issue",
          "id": "\(item.id)",
          "number": \(item.number),
          "title": "\(item.title)",
          "body": "Description for \(item.title)",
          "state": "OPEN",
          "url": "https://github.com/\(item.repo)/issues/\(item.number)",
          "createdAt": "2026-01-01T00:00:00Z",
          "updatedAt": "2026-01-02T00:00:00Z",
          "labels": {"nodes": [{"name": "bug"}]},
          "repository": {"nameWithOwner": "\(item.repo)"},
          "trackedInIssues": {"nodes": []}
        },
        "fieldValueByName": {"name": "\(item.status)"}
      }
      """
    }
    let cursor = endCursor.map { #""endCursor": "\#($0)""# } ?? #""endCursor": null"#
    return """
      {
        "data": {
          "node": {
            "items": {
              "nodes": [\(nodes.joined(separator: ","))],
              "pageInfo": {"hasNextPage": \(hasNextPage), \(cursor)}
            }
          }
        }
      }
      """
  }

  @Test func fetchCandidateIssuesResolvesProjectAndReturnsIssues() async throws {
    let transport = StubGraphQLTransport()
    let config = makeConfig()
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
    let config = makeConfig()
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
    let config = makeConfig(activeStates: ["In Progress"])
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
    let config = makeConfig(repositoryAllowlist: ["test-owner/allowed"])
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
    let config = makeConfig()
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
    let config = makeConfig(projectOwnerType: "user")
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
    let config = makeConfig()
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
    let config = makeConfig()
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
    let config = makeConfig(activeStates: ["In Progress"])
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
    let config = makeConfig()
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
    let config = makeConfig()
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
    let config = makeConfig()
    let adapter = GitHubTrackerAdapter(transport: transport, config: config)

    let states = try await adapter.fetchIssueStatesByIDs([])
    #expect(states.isEmpty)
    #expect(transport.executedQueryCount == 0)
  }

  @Test func fetchIssueStatesByIDsInvalidResponse() async throws {
    let transport = StubGraphQLTransport()
    let config = makeConfig()
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
    let config = makeConfig()
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
    let config = makeConfig()
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
    let config = makeConfig()
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
    let config = makeConfig()
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

  @Test func contentWithNullFieldsReturnsNoStatus() async throws {
    let transport = StubGraphQLTransport()
    let config = makeConfig(activeStates: [""])
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
                  "title": "No status",
                  "body": null,
                  "state": "OPEN",
                  "url": null,
                  "createdAt": null,
                  "updatedAt": null,
                  "labels": null,
                  "repository": {"nameWithOwner": "test-owner/repo"},
                  "trackedInIssues": null
                },
                "fieldValueByName": null
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
    #expect(issues[0].state == "")
    #expect(issues[0].labels.isEmpty)
    #expect(issues[0].blockedBy.isEmpty)
  }

  @Test func fetchIssuesByStatesMissingProjectNodeThrows() async throws {
    let transport = StubGraphQLTransport()
    let config = makeConfig()
    let adapter = GitHubTrackerAdapter(transport: transport, config: config)

    transport.enqueueResponse(projectIDResponse())
    transport.enqueueResponse(#"{"data": {"node": null}}"#)

    await #expect(throws: GitHubTrackerError.self) {
      _ = try await adapter.fetchIssuesByStates(["Todo"])
    }
  }

  @Test func fetchIssuesByStatesPagination() async throws {
    let transport = StubGraphQLTransport()
    let config = makeConfig(activeStates: ["Todo"])
    let adapter = GitHubTrackerAdapter(transport: transport, config: config)

    transport.enqueueResponse(projectIDResponse())
    // Page 1 with hasNextPage=true
    transport.enqueueResponse(
      candidateItemsResponse(
        items: [("I_P1", 1, "Page1", "test-owner/repo", "Todo")],
        hasNextPage: true, endCursor: "cursor1"))
    // Page 2 with hasNextPage=false
    transport.enqueueResponse(
      candidateItemsResponse(
        items: [("I_P2", 2, "Page2", "test-owner/repo", "Todo")],
        hasNextPage: false))

    let issues = try await adapter.fetchIssuesByStates(["Todo"])
    #expect(issues.count == 2)
    #expect(transport.executedQueryCount == 3)
  }

  @Test func fetchIssueStatesByIDsCannotParseStateResponse() async throws {
    let transport = StubGraphQLTransport()
    let config = makeConfig()
    let adapter = GitHubTrackerAdapter(transport: transport, config: config)

    // Valid JSON but data is not a dict
    transport.enqueueResponse(#"{"data": "not_a_dict"}"#)

    await #expect(throws: GitHubTrackerError.self) {
      _ = try await adapter.fetchIssueStatesByIDs([IssueID("I_1")])
    }
  }

  @Test func fetchIssueStatesByIDsMissingDataKey() async throws {
    let transport = StubGraphQLTransport()
    let config = makeConfig()
    let adapter = GitHubTrackerAdapter(transport: transport, config: config)

    // Valid JSON but no "data" key
    transport.enqueueResponse(#"{"errors": []}"#)

    await #expect(throws: GitHubTrackerError.self) {
      _ = try await adapter.fetchIssueStatesByIDs([IssueID("I_1")])
    }
  }

  @Test func fetchIssueStatesByIDsSkipsNonDictionaryNodes() async throws {
    let transport = StubGraphQLTransport()
    let config = makeConfig()
    let adapter = GitHubTrackerAdapter(transport: transport, config: config)

    transport.enqueueResponse(#"{"data": {"bad": 1, "good": {"id": "I_1", "state": "OPEN"}}}"#)

    let states = try await adapter.fetchIssueStatesByIDs([IssueID("I_1")])
    #expect(states == [IssueID("I_1"): "OPEN"])
  }

  @Test func resolveProjectIDUnparseableResponse() async throws {
    let transport = StubGraphQLTransport()
    let config = makeConfig()
    let adapter = GitHubTrackerAdapter(transport: transport, config: config)

    // Response where data is not a dict
    transport.enqueueResponse(#"{"data": "string"}"#)

    await #expect(throws: GitHubTrackerError.self) {
      _ = try await adapter.fetchCandidateIssues()
    }
  }

  @Test func normalizeItemsInvalidIdentifierSkipsItem() async throws {
    let transport = StubGraphQLTransport()
    let config = makeConfig(activeStates: ["Todo"])
    let adapter = GitHubTrackerAdapter(transport: transport, config: config)

    transport.enqueueResponse(projectIDResponse())
    // Item with empty repository (produces invalid identifier "/#1")
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
                  "title": "Bad repo",
                  "body": null,
                  "state": "OPEN",
                  "url": null,
                  "createdAt": null,
                  "updatedAt": null,
                  "labels": null,
                  "repository": {"nameWithOwner": "/"},
                  "trackedInIssues": null
                },
                "fieldValueByName": {"name": "Todo"}
              }],
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

  @Test func itemMissingRequiredFieldIsSkipped() async throws {
    let transport = StubGraphQLTransport()
    let config = makeConfig(activeStates: ["Todo"])
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
                  "title": null,
                  "body": null,
                  "state": "OPEN",
                  "url": null,
                  "createdAt": null,
                  "updatedAt": null,
                  "labels": null,
                  "repository": {"nameWithOwner": "test-owner/repo"},
                  "trackedInIssues": null
                },
                "fieldValueByName": {"name": "Todo"}
              }],
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

  @Test func nilIssueStateFallsBackToOpen() async throws {
    let transport = StubGraphQLTransport()
    let config = makeConfig(activeStates: ["Todo"])
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
                  "title": "Nil state",
                  "body": null,
                  "state": null,
                  "url": null,
                  "createdAt": null,
                  "updatedAt": null,
                  "labels": {"nodes": []},
                  "repository": {"nameWithOwner": "test-owner/repo"},
                  "trackedInIssues": null
                },
                "fieldValueByName": {"name": "Todo"}
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
    #expect(issues[0].issueState == "OPEN")
  }

  @Test func blockerWithInvalidIdentifierIsSkipped() async throws {
    let transport = StubGraphQLTransport()
    let config = makeConfig()
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
                  "title": "Has bad blocker",
                  "body": null,
                  "state": "OPEN",
                  "url": null,
                  "createdAt": "2026-01-01T00:00:00Z",
                  "updatedAt": null,
                  "labels": {"nodes": []},
                  "repository": {"nameWithOwner": "test-owner/repo"},
                  "trackedInIssues": {
                    "nodes": [{
                      "id": "I_BAD",
                      "number": 1,
                      "state": "OPEN",
                      "repository": {"nameWithOwner": "/"}
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
    #expect(issues[0].blockedBy.isEmpty)
  }

  @Test func decodeResponseNonGraphQLError() async throws {
    let transport = StubGraphQLTransport()
    let config = makeConfig()
    let adapter = GitHubTrackerAdapter(transport: transport, config: config)

    transport.enqueueResponse(projectIDResponse())
    // Valid JSON but not decodable as GitHubGraphQL.Response — an array instead of object
    transport.enqueueResponse(Data("[1,2,3]".utf8))

    await #expect(throws: GitHubTrackerError.self) {
      _ = try await adapter.fetchCandidateIssues()
    }
  }

  @Test func contentWithNullContentIsSkipped() async throws {
    let transport = StubGraphQLTransport()
    let config = makeConfig()
    let adapter = GitHubTrackerAdapter(transport: transport, config: config)

    transport.enqueueResponse(projectIDResponse())
    let response = """
      {
        "data": {
          "node": {
            "items": {
              "nodes": [{
                "id": "PVTI_1",
                "content": null,
                "fieldValueByName": null
              }],
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
}

// MARK: - URLSessionGraphQLTransport Tests

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var responseData: Data?
  nonisolated(unsafe) static var responseStatusCode: Int = 200
  nonisolated(unsafe) static var responseError: Error?

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    if let error = Self.responseError {
      client?.urlProtocol(self, didFailWithError: error)
      client?.urlProtocolDidFinishLoading(self)
      return
    }
    let response = HTTPURLResponse(
      url: request.url!, statusCode: Self.responseStatusCode,
      httpVersion: "HTTP/1.1", headerFields: nil)!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    if let data = Self.responseData {
      client?.urlProtocol(self, didLoad: data)
    }
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

@Suite("URLSessionGraphQLTransport")
struct URLSessionGraphQLTransportTests {
  @Test func initializesWithEndpointAndKey() {
    let url = URL(string: "https://api.github.com/graphql")!
    let transport = URLSessionGraphQLTransport(endpoint: url, apiKey: "test-key")
    _ = transport
  }

  @Test func executeCoversSuccessAndFailurePaths() async throws {
    StubURLProtocol.responseData = Data(#"{"ok":true}"#.utf8)
    StubURLProtocol.responseStatusCode = 200
    StubURLProtocol.responseError = nil

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    let session = URLSession(configuration: config)

    let url = URL(string: "https://api.github.com/graphql")!
    let transport = URLSessionGraphQLTransport(endpoint: url, apiKey: "key", session: session)

    let successData = try await transport.execute(query: "query", variables: ["x": 1])
    #expect(!successData.isEmpty)

    StubURLProtocol.responseData = Data([0xFF])
    StubURLProtocol.responseStatusCode = 401

    await #expect(throws: GitHubTrackerError.self) {
      _ = try await transport.execute(query: "{ test }", variables: nil)
    }
  }
}

// MARK: - GitHubTrackerError Tests

@Suite("GitHubTrackerError")
struct GitHubTrackerErrorTests {
  @Test func errorsAreEquatable() {
    #expect(
      GitHubTrackerError.invalidEndpoint("a") == GitHubTrackerError.invalidEndpoint("a"))
    #expect(GitHubTrackerError.missingAPIKey == GitHubTrackerError.missingAPIKey)
    #expect(
      GitHubTrackerError.requestFailed(statusCode: 401, body: "x")
        == GitHubTrackerError.requestFailed(statusCode: 401, body: "x"))
    #expect(
      GitHubTrackerError.decodingFailed("a") == GitHubTrackerError.decodingFailed("a"))
    #expect(
      GitHubTrackerError.unexpectedResponseStructure("a")
        == GitHubTrackerError.unexpectedResponseStructure("a"))
  }

  @Test func errorsAreNotEqual() {
    #expect(
      GitHubTrackerError.invalidEndpoint("a") != GitHubTrackerError.invalidEndpoint("b"))
    #expect(GitHubTrackerError.missingAPIKey != GitHubTrackerError.decodingFailed("x"))
  }
}
