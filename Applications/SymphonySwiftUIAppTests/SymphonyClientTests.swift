import Foundation
import SymphonyShared
import Testing

@testable import SymphonySwiftUIApp

@Suite("SymphonyClient", .tags(.client))
struct SymphonyClientTests {
  @Test func errorDescriptionsCoverAllCases() {
    #expect(
      SymphonyClientError.invalidEndpoint.errorDescription
        == "The configured server endpoint is invalid.")
    #expect(
      SymphonyClientError.invalidResponse.errorDescription
        == "The server returned an invalid response.")
    #expect(
      SymphonyClientError.server(statusCode: 503).errorDescription
        == "The server returned HTTP 503.")
    #expect(
      SymphonyClientError.serverEnvelope(
        statusCode: 404,
        code: "issue_not_found",
        message: "Issue issue-42 was not found."
      ).errorDescription == "Issue issue-42 was not found.")
  }

  @Test func requestMethodsUseExpectedPathsMethodsAndQueryItems() async throws {
    let session = TestHTTPSession()
    session.dataResponses = [
      httpResponse(
        HealthResponse(
          status: "ok", serverTime: "2026-03-24T00:00:00Z", version: "1.0.0", trackerKind: "github"
        ),
        path: "/api/v1/health"
      ),
      httpResponse(IssuesResponse(items: []), path: "/api/v1/issues"),
      httpResponse(makeIssueDetail(), path: "/api/v1/issues/issue-42"),
      httpResponse(
        makeIssueProgressReport(), path: "/api/v1/issues/issue-42/progress-report"),
      httpResponse(makeRunDetail(), path: "/api/v1/runs/run-42"),
      httpResponse(
        LogEntriesResponse(
          sessionID: SessionID("session-42"),
          provider: "claude_code",
          items: [],
          nextCursor: EventCursor(
            sessionID: SessionID("session-42"), lastDeliveredSequence: EventSequence(3)
          ),
          hasMore: false
        ),
        path: "/api/v1/logs/session-42?limit=50&cursor=session-42:3"
      ),
      httpResponse(
        RefreshResponse(queued: true, requestedAt: "2026-03-24T00:00:01Z"), path: "/api/v1/refresh"
      ),
    ]

    let client = URLSessionSymphonyAPIClient(session: session)
    let endpoint = try ServerEndpoint(scheme: "https", host: "example.com", port: 9443)
    let cursor = EventCursor(
      sessionID: SessionID("session-42"), lastDeliveredSequence: EventSequence(3)
    )

    _ = try await client.health(endpoint: endpoint)
    _ = try await client.issues(endpoint: endpoint)
    _ = try await client.issueDetail(endpoint: endpoint, issueID: IssueID("issue-42"))
    _ = try await client.issueProgressReport(endpoint: endpoint, issueID: IssueID("issue-42"))
    _ = try await client.runDetail(endpoint: endpoint, runID: RunID("run-42"))
    _ = try await client.logs(
      endpoint: endpoint,
      sessionID: SessionID("session-42"),
      cursor: cursor,
      limit: 50
    )
    _ = try await client.refresh(endpoint: endpoint)

    #expect(session.recordedRequests.count == 7)
    #expect(session.recordedRequests[0].httpMethod == "GET")
    #expect(
      session.recordedRequests[0].url?.absoluteString == "https://example.com:9443/api/v1/health")
    #expect(
      session.recordedRequests[1].url?.absoluteString == "https://example.com:9443/api/v1/issues")
    #expect(
      session.recordedRequests[2].url?.absoluteString
        == "https://example.com:9443/api/v1/issues/issue-42")
    #expect(
      session.recordedRequests[3].url?.absoluteString
        == "https://example.com:9443/api/v1/issues/issue-42/progress-report")
    #expect(
      session.recordedRequests[4].url?.absoluteString
        == "https://example.com:9443/api/v1/runs/run-42")
    #expect(
      session.recordedRequests[5].url?.absoluteString
        == "https://example.com:9443/api/v1/logs/session-42?limit=50&cursor=\(cursor.rawValue)")
    #expect(session.recordedRequests[6].httpMethod == "POST")
    #expect(
      session.recordedRequests[6].url?.absoluteString
        == "https://example.com:9443/api/v1/refresh")
    #expect(
      session.recordedRequests.allSatisfy {
        $0.value(forHTTPHeaderField: "Accept") == "application/json"
      })
  }

  @Test func requestFailuresSurfaceInvalidEndpointInvalidResponseAndServerStatus() async throws {
    let invalidEndpointClient = URLSessionSymphonyAPIClient(session: TestHTTPSession())
    let invalidEndpoint = try ServerEndpoint(scheme: "http", host: "bad host", port: 8080)
    await expectAsyncThrows(
      expected: SymphonyClientError.invalidEndpoint,
      try await invalidEndpointClient.health(endpoint: invalidEndpoint)
    )

    let invalidResponseSession = TestHTTPSession()
    invalidResponseSession.dataResponses = [
      (
        Data("{}".utf8),
        URLResponse(
          url: URL(string: "https://example.com")!,
          mimeType: "application/json",
          expectedContentLength: 2,
          textEncodingName: nil
        )
      )
    ]
    let invalidResponseClient = URLSessionSymphonyAPIClient(session: invalidResponseSession)
    await expectAsyncThrows(
      expected: SymphonyClientError.invalidResponse,
      try await invalidResponseClient.health(
        endpoint: try ServerEndpoint(scheme: "https", host: "example.com", port: 9443))
    )

    let serverErrorSession = TestHTTPSession()
    let serverErrorURL = URL(string: "https://example.com:9443/api/v1/issues")!
    serverErrorSession.dataResponses = [
      (
        Data("{}".utf8),
        HTTPURLResponse(url: serverErrorURL, statusCode: 503, httpVersion: nil, headerFields: nil)!
      )
    ]
    let serverErrorClient = URLSessionSymphonyAPIClient(session: serverErrorSession)
    await expectAsyncThrows(
      expected: SymphonyClientError.server(statusCode: 503),
      try await serverErrorClient.issues(
        endpoint: try ServerEndpoint(scheme: "https", host: "example.com", port: 9443))
    )

    let serverEnvelopeSession = TestHTTPSession()
    serverEnvelopeSession.dataResponses = [
      errorResponse(
        ErrorEnvelope(
          error: ErrorPayload(
            code: "issue_not_found",
            message: "Issue issue-42 was not found."
          )
        ),
        path: "/api/v1/issues/issue-42",
        statusCode: 404
      )
    ]
    let serverEnvelopeClient = URLSessionSymphonyAPIClient(session: serverEnvelopeSession)
    do {
      _ = try await serverEnvelopeClient.issueDetail(
        endpoint: try ServerEndpoint(scheme: "https", host: "example.com", port: 9443),
        issueID: IssueID("issue-42")
      )
      Issue.record("Expected issue detail lookup to surface the server envelope.")
    } catch {
      #expect(
        error as? SymphonyClientError
          == .serverEnvelope(
            statusCode: 404,
            code: "issue_not_found",
            message: "Issue issue-42 was not found."
          )
      )
      #expect(error.localizedDescription == "Issue issue-42 was not found.")
    }
  }

  @Test func logStreamUsesWebSocketURLAndYieldsTextAndBinaryMessages() async throws {
    let session = TestHTTPSession()
    session.webSocketTask.messages = [
      .success(.string(encoded(makeEvent(sequence: 1, kind: "message")))),
      .success(.data(try JSONEncoder().encode(makeEvent(sequence: 2, kind: "tool_result")))),
      .failure(TestClientFailure.done),
    ]

    let client = URLSessionSymphonyAPIClient(session: session)
    let cursor = EventCursor(
      sessionID: SessionID("session-42"), lastDeliveredSequence: EventSequence(9)
    )
    let stream = try client.logStream(
      endpoint: try ServerEndpoint(scheme: "https", host: "example.com", port: 9443),
      sessionID: SessionID("session-42"),
      cursor: cursor
    )

    var iterator = stream.makeAsyncIterator()
    let first = try await iterator.next()
    let second = try await iterator.next()
    do {
      _ = try await iterator.next()
      Issue.record("Expected the fake socket failure to end the stream.")
    } catch {
      #expect(error as? TestClientFailure == .done)
    }

    #expect(first == makeEvent(sequence: 1, kind: "message"))
    #expect(second == makeEvent(sequence: 2, kind: "tool_result"))
    #expect(
      session.recordedWebSocketURLs.map(\.absoluteString)
        == [
          "wss://example.com:9443/api/v1/logs/stream?session_id=session-42&cursor=\(cursor.rawValue)"
        ])
    #expect(session.webSocketTask.didResume)
  }

  @Test func logStreamRejectsInvalidWebSocketEndpoint() throws {
    let client = URLSessionSymphonyAPIClient(session: TestHTTPSession())
    let invalidEndpoint = try ServerEndpoint(scheme: "http", host: "bad host", port: 8080)

    #expect(throws: SymphonyClientError.invalidEndpoint) {
      try client.logStream(
        endpoint: invalidEndpoint,
        sessionID: SessionID("session-42"),
        cursor: nil
      )
    }
  }

  @Test func logStreamSurfacesDecodeFailuresAndCancelsTaskOnTermination() async throws {
    let session = TestHTTPSession()
    session.webSocketTask.messages = [.success(.string("{\"not\":\"an event\"}"))]
    let client = URLSessionSymphonyAPIClient(session: session)

    let decodeStream = try client.logStream(
      endpoint: try ServerEndpoint(host: "localhost", port: 8080),
      sessionID: SessionID("session-42"),
      cursor: nil
    )
    var decodeIterator = decodeStream.makeAsyncIterator()
    do {
      _ = try await decodeIterator.next()
      Issue.record("Expected malformed websocket payloads to fail decoding.")
    } catch {
      #expect(error is DecodingError)
    }

    let hangingSession = TestHTTPSession()
    hangingSession.webSocketTask.shouldSuspendReceives = true
    let hangingClient = URLSessionSymphonyAPIClient(session: hangingSession)
    let hangingStream = try hangingClient.logStream(
      endpoint: try ServerEndpoint(host: "localhost", port: 8080),
      sessionID: SessionID("session-42"),
      cursor: nil
    )

    let consumer = Task {
      var iterator = hangingStream.makeAsyncIterator()
      _ = try await iterator.next()
    }
    consumer.cancel()
    _ = await consumer.result

    #expect(hangingSession.webSocketTask.didCancel)
  }

  @Test func publicURLSessionInitializerUsesURLProtocolBackedHTTPRequests() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]

    StubURLProtocol.requestHandler = { request in
      #expect(request.httpMethod == "GET")
      #expect(request.url?.absoluteString == "https://example.com:9443/api/v1/health")
      return httpResponse(
        HealthResponse(
          status: "ok", serverTime: "2026-03-24T00:00:00Z", version: "1.0.0", trackerKind: "github"
        ),
        path: "/api/v1/health"
      )
    }

    let session = URLSession(configuration: configuration)
    defer {
      StubURLProtocol.requestHandler = nil
      session.invalidateAndCancel()
    }

    let client = URLSessionSymphonyAPIClient(session: session)
    let response = try await client.health(
      endpoint: try ServerEndpoint(scheme: "https", host: "example.com", port: 9443))

    #expect(response.status == "ok")
    #expect(response.trackerKind == "github")
  }

  @Test func publicURLSessionInitializerUsesConcreteWebSocketTaskOnConnectionFailure() async throws
  {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 1
    configuration.timeoutIntervalForResource = 1
    configuration.waitsForConnectivity = false
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }

    let client = URLSessionSymphonyAPIClient(session: session)
    let stream = try client.logStream(
      endpoint: try ServerEndpoint(host: "127.0.0.1", port: 1),
      sessionID: SessionID("session-42"),
      cursor: nil
    )

    do {
      _ = try await firstEvent(from: stream, timeout: .seconds(2))
      Issue.record("Expected the websocket connection attempt to fail.")
    } catch {
      #expect(!(error is TestTimedOut))
    }
  }

  @Test func publicInitializerDefaultArgumentsRemainUsable() {
    _ = URLSessionSymphonyAPIClient()
  }

  @Test func concreteURLSessionWebSocketAdapterLifecycleMethodsRemainCallable() {
    let session = URLSession(configuration: .ephemeral)
    defer { session.invalidateAndCancel() }

    let task = (session as any HTTPSessioning).webSocketTask(with: URL(string: "ws://127.0.0.1:1")!)
    task.receive { _ in }
    task.resume()
    task.cancel(with: URLSessionWebSocketTask.CloseCode.goingAway, reason: nil)
  }
}
