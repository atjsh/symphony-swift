import Foundation
import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore
@testable import SymphonyShared

@Suite("GitHubTrackerAdapter Edge Cases")
struct GitHubTrackerAdapterEdgeCaseTests {
  @Test func contentWithNullFieldsReturnsNoStatus() async throws {
    let transport = StubGraphQLTransport()
    let config = makeTrackerConfig(activeStates: [""])
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
    let config = makeTrackerConfig()
    let adapter = GitHubTrackerAdapter(transport: transport, config: config)

    transport.enqueueResponse(projectIDResponse())
    transport.enqueueResponse(#"{"data": {"node": null}}"#)

    await #expect(throws: GitHubTrackerError.self) {
      _ = try await adapter.fetchIssuesByStates(["Todo"])
    }
  }

  @Test func fetchIssuesByStatesPagination() async throws {
    let transport = StubGraphQLTransport()
    let config = makeTrackerConfig(activeStates: ["Todo"])
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
    let config = makeTrackerConfig()
    let adapter = GitHubTrackerAdapter(transport: transport, config: config)

    // Valid JSON but data is not a dict
    transport.enqueueResponse(#"{"data": "not_a_dict"}"#)

    await #expect(throws: GitHubTrackerError.self) {
      _ = try await adapter.fetchIssueStatesByIDs([IssueID("I_1")])
    }
  }

  @Test func fetchIssueStatesByIDsMissingDataKey() async throws {
    let transport = StubGraphQLTransport()
    let config = makeTrackerConfig()
    let adapter = GitHubTrackerAdapter(transport: transport, config: config)

    // Valid JSON but no "data" key
    transport.enqueueResponse(#"{"errors": []}"#)

    await #expect(throws: GitHubTrackerError.self) {
      _ = try await adapter.fetchIssueStatesByIDs([IssueID("I_1")])
    }
  }

  @Test func fetchIssueStatesByIDsSkipsNonDictionaryNodes() async throws {
    let transport = StubGraphQLTransport()
    let config = makeTrackerConfig()
    let adapter = GitHubTrackerAdapter(transport: transport, config: config)

    transport.enqueueResponse(#"{"data": {"bad": 1, "good": {"id": "I_1", "state": "OPEN"}}}"#)

    let states = try await adapter.fetchIssueStatesByIDs([IssueID("I_1")])
    #expect(states == [IssueID("I_1"): "OPEN"])
  }

  @Test func resolveProjectIDUnparseableResponse() async throws {
    let transport = StubGraphQLTransport()
    let config = makeTrackerConfig()
    let adapter = GitHubTrackerAdapter(transport: transport, config: config)

    // Response where data is not a dict
    transport.enqueueResponse(#"{"data": "string"}"#)

    await #expect(throws: GitHubTrackerError.self) {
      _ = try await adapter.fetchCandidateIssues()
    }
  }

  @Test func normalizeItemsInvalidIdentifierSkipsItem() async throws {
    let transport = StubGraphQLTransport()
    let config = makeTrackerConfig(activeStates: ["Todo"])
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
    let config = makeTrackerConfig(activeStates: ["Todo"])
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
    let config = makeTrackerConfig(activeStates: ["Todo"])
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
    let config = makeTrackerConfig()
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
