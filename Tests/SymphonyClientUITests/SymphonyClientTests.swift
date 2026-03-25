import Foundation
import XCTest
@testable import SymphonyClientUI
import SymphonyShared

final class SymphonyClientTests: XCTestCase {
    func testErrorDescriptionsCoverAllCases() {
        XCTAssertEqual(SymphonyClientError.invalidEndpoint.errorDescription, "The configured server endpoint is invalid.")
        XCTAssertEqual(SymphonyClientError.invalidResponse.errorDescription, "The server returned an invalid response.")
        XCTAssertEqual(SymphonyClientError.server(statusCode: 503).errorDescription, "The server returned HTTP 503.")
    }

    func testRequestMethodsUseExpectedPathsMethodsAndQueryItems() async throws {
        let session = TestHTTPSession()
        session.dataResponses = [
            httpResponse(HealthResponse(status: "ok", serverTime: "2026-03-24T00:00:00Z", version: "1.0.0", trackerKind: "github"), path: "/api/v1/health"),
            httpResponse(IssuesResponse(items: []), path: "/api/v1/issues"),
            httpResponse(makeIssueDetail(), path: "/api/v1/issues/issue-42"),
            httpResponse(makeRunDetail(), path: "/api/v1/runs/run-42"),
            httpResponse(
                LogEntriesResponse(
                    sessionID: SessionID("session-42"),
                    provider: "claude_code",
                    items: [],
                    nextCursor: EventCursor(sessionID: SessionID("session-42"), lastDeliveredSequence: EventSequence(3)),
                    hasMore: false
                ),
                path: "/api/v1/logs/session-42?limit=50&cursor=session-42:3"
            ),
            httpResponse(RefreshResponse(queued: true, requestedAt: "2026-03-24T00:00:01Z"), path: "/api/v1/refresh"),
        ]

        let client = URLSessionSymphonyAPIClient(session: session)
        let endpoint = try ServerEndpoint(scheme: "https", host: "example.com", port: 9443)
        let cursor = EventCursor(sessionID: SessionID("session-42"), lastDeliveredSequence: EventSequence(3))

        _ = try await client.health(endpoint: endpoint)
        _ = try await client.issues(endpoint: endpoint)
        _ = try await client.issueDetail(endpoint: endpoint, issueID: IssueID("issue-42"))
        _ = try await client.runDetail(endpoint: endpoint, runID: RunID("run-42"))
        _ = try await client.logs(
            endpoint: endpoint,
            sessionID: SessionID("session-42"),
            cursor: cursor,
            limit: 50
        )
        _ = try await client.refresh(endpoint: endpoint)

        XCTAssertEqual(session.recordedRequests.count, 6)
        XCTAssertEqual(session.recordedRequests[0].httpMethod, "GET")
        XCTAssertEqual(session.recordedRequests[0].url?.absoluteString, "https://example.com:9443/api/v1/health")
        XCTAssertEqual(session.recordedRequests[1].url?.absoluteString, "https://example.com:9443/api/v1/issues")
        XCTAssertEqual(session.recordedRequests[2].url?.absoluteString, "https://example.com:9443/api/v1/issues/issue-42")
        XCTAssertEqual(session.recordedRequests[3].url?.absoluteString, "https://example.com:9443/api/v1/runs/run-42")
        XCTAssertEqual(session.recordedRequests[4].url?.absoluteString, "https://example.com:9443/api/v1/logs/session-42?limit=50&cursor=\(cursor.rawValue)")
        XCTAssertEqual(session.recordedRequests[5].httpMethod, "POST")
        XCTAssertEqual(session.recordedRequests[5].url?.absoluteString, "https://example.com:9443/api/v1/refresh")
        XCTAssertTrue(session.recordedRequests.allSatisfy { $0.value(forHTTPHeaderField: "Accept") == "application/json" })
    }

    func testRequestFailuresSurfaceInvalidEndpointInvalidResponseAndServerStatus() async throws {
        let invalidEndpointClient = URLSessionSymphonyAPIClient(session: TestHTTPSession())
        let invalidEndpoint = try ServerEndpoint(scheme: "http", host: "bad host", port: 8080)
        await XCTAssertThrowsErrorAsync(try await invalidEndpointClient.health(endpoint: invalidEndpoint)) { error in
            XCTAssertEqual(error as? SymphonyClientError, .invalidEndpoint)
        }

        let invalidResponseSession = TestHTTPSession()
        invalidResponseSession.dataResponses = [
            (Data("{}".utf8), URLResponse(url: URL(string: "https://example.com")!, mimeType: "application/json", expectedContentLength: 2, textEncodingName: nil))
        ]
        let invalidResponseClient = URLSessionSymphonyAPIClient(session: invalidResponseSession)
        await XCTAssertThrowsErrorAsync(try await invalidResponseClient.health(endpoint: try ServerEndpoint(scheme: "https", host: "example.com", port: 9443))) { error in
            XCTAssertEqual(error as? SymphonyClientError, .invalidResponse)
        }

        let serverErrorSession = TestHTTPSession()
        let serverErrorURL = URL(string: "https://example.com:9443/api/v1/issues")!
        serverErrorSession.dataResponses = [
            (
                Data("{}".utf8),
                HTTPURLResponse(url: serverErrorURL, statusCode: 503, httpVersion: nil, headerFields: nil)!
            )
        ]
        let serverErrorClient = URLSessionSymphonyAPIClient(session: serverErrorSession)
        await XCTAssertThrowsErrorAsync(try await serverErrorClient.issues(endpoint: try ServerEndpoint(scheme: "https", host: "example.com", port: 9443))) { error in
            XCTAssertEqual(error as? SymphonyClientError, .server(statusCode: 503))
        }
    }

    func testLogStreamUsesWebSocketURLAndYieldsTextAndBinaryMessages() async throws {
        let session = TestHTTPSession()
        session.webSocketTask.messages = [
            .success(.string(encoded(makeEvent(sequence: 1, kind: "message")))),
            .success(.data(try JSONEncoder().encode(makeEvent(sequence: 2, kind: "tool_result")))),
            .failure(TestClientFailure.done),
        ]

        let client = URLSessionSymphonyAPIClient(session: session)
        let cursor = EventCursor(sessionID: SessionID("session-42"), lastDeliveredSequence: EventSequence(9))
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
            XCTFail("Expected the fake socket failure to end the stream.")
        } catch {
            XCTAssertEqual(error as? TestClientFailure, .done)
        }

        XCTAssertEqual(first, makeEvent(sequence: 1, kind: "message"))
        XCTAssertEqual(second, makeEvent(sequence: 2, kind: "tool_result"))
        XCTAssertEqual(session.recordedWebSocketURLs.map(\.absoluteString), ["wss://example.com:9443/api/v1/logs/stream?session_id=session-42&cursor=\(cursor.rawValue)"])
        XCTAssertTrue(session.webSocketTask.didResume)
    }

    func testLogStreamRejectsInvalidWebSocketEndpoint() async throws {
        let client = URLSessionSymphonyAPIClient(session: TestHTTPSession())
        let invalidEndpoint = try ServerEndpoint(scheme: "http", host: "bad host", port: 8080)

        XCTAssertThrowsError(
            try client.logStream(
                endpoint: invalidEndpoint,
                sessionID: SessionID("session-42"),
                cursor: nil
            )
        ) { error in
            XCTAssertEqual(error as? SymphonyClientError, .invalidEndpoint)
        }
    }

    func testLogStreamSurfacesDecodeFailuresAndCancelsTaskOnTermination() async throws {
        let session = TestHTTPSession()
        session.webSocketTask.messages = [.success(.string("{\"not\":\"an event\"}"))]
        let client = URLSessionSymphonyAPIClient(session: session)

        let decodeStream = try client.logStream(
            endpoint: try ServerEndpoint(host: "localhost", port: 8080),
            sessionID: SessionID("session-42"),
            cursor: nil
        )
        var decodeIterator = decodeStream.makeAsyncIterator()
        await XCTAssertThrowsErrorAsync(try await decodeIterator.next()) { error in
            XCTAssertTrue(error is DecodingError)
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

        XCTAssertTrue(hangingSession.webSocketTask.didCancel)
    }

    func testPublicURLSessionInitializerUsesURLProtocolBackedHTTPRequests() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]

        StubURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.absoluteString, "https://example.com:9443/api/v1/health")
            return httpResponse(
                HealthResponse(status: "ok", serverTime: "2026-03-24T00:00:00Z", version: "1.0.0", trackerKind: "github"),
                path: "/api/v1/health"
            )
        }

        let session = URLSession(configuration: configuration)
        defer {
            StubURLProtocol.requestHandler = nil
            session.invalidateAndCancel()
        }

        let client = URLSessionSymphonyAPIClient(session: session)
        let response = try await client.health(endpoint: try ServerEndpoint(scheme: "https", host: "example.com", port: 9443))

        XCTAssertEqual(response.status, "ok")
        XCTAssertEqual(response.trackerKind, "github")
    }

    func testPublicURLSessionInitializerUsesConcreteWebSocketTaskOnConnectionFailure() async throws {
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

        await XCTAssertThrowsErrorAsync(try await firstEvent(from: stream, timeout: .seconds(2))) { error in
            XCTAssertFalse(error is TestTimedOut)
        }
    }

    func testPublicInitializerDefaultArgumentsRemainUsable() {
        let client = URLSessionSymphonyAPIClient()
        XCTAssertNotNil(client)
    }

    func testConcreteURLSessionWebSocketAdapterLifecycleMethodsRemainCallable() {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }

        let task = (session as any HTTPSessioning).webSocketTask(with: URL(string: "ws://127.0.0.1:1")!)
        task.receive { _ in }
        task.resume()
        task.cancel(with: URLSessionWebSocketTask.CloseCode.goingAway, reason: nil)
    }
}

private final class TestHTTPSession: HTTPSessioning, @unchecked Sendable {
    var dataResponses = [(Data, URLResponse)]()
    var recordedRequests = [URLRequest]()
    var recordedWebSocketURLs = [URL]()
    let webSocketTask = TestWebSocketTask()

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        recordedRequests.append(request)
        return try XCTUnwrap(dataResponses.isEmpty ? nil : dataResponses.removeFirst())
    }

    func webSocketTask(with url: URL) -> any WebSocketTasking {
        recordedWebSocketURLs.append(url)
        return webSocketTask
    }
}

private final class TestWebSocketTask: WebSocketTasking, @unchecked Sendable {
    var messages = [Result<URLSessionWebSocketTask.Message, Error>]()
    var shouldSuspendReceives = false
    private(set) var didResume = false
    private(set) var didCancel = false

    func resume() {
        didResume = true
    }

    func receive(completionHandler: @escaping (Result<URLSessionWebSocketTask.Message, Error>) -> Void) {
        if shouldSuspendReceives {
            return
        }
        completionHandler(messages.removeFirst())
    }

    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        didCancel = true
    }
}

private enum TestClientFailure: Error, Equatable {
    case done
}

private enum TestTimedOut: Error {
    case waitingForFirstEvent
}

private func httpResponse<T: Encodable>(_ value: T, path: String) -> (Data, URLResponse) {
    let url = URL(string: "https://example.com:9443\(path)")!
    return (
        try! JSONEncoder().encode(value),
        HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
    )
}

private func encoded(_ event: AgentRawEvent) -> String {
    String(decoding: try! JSONEncoder().encode(event), as: UTF8.self)
}

private func makeIssueDetail() -> IssueDetail {
    let issue = SymphonyShared.Issue(
        id: IssueID("issue-42"),
        identifier: try! IssueIdentifier(validating: "atjsh/example#42"),
        repository: "atjsh/example",
        number: 42,
        title: "Provider-neutral operator",
        description: "Ship the real client.",
        priority: 1,
        state: "in_progress",
        issueState: "OPEN",
        projectItemID: nil,
        url: nil,
        labels: [],
        blockedBy: [],
        createdAt: nil,
        updatedAt: nil
    )
    return IssueDetail(issue: issue, latestRun: makeRunSummary(), workspacePath: "/tmp/example", recentSessions: [])
}

private func makeRunSummary() -> RunSummary {
    RunSummary(
        runID: RunID("run-42"),
        issueID: IssueID("issue-42"),
        issueIdentifier: try! IssueIdentifier(validating: "atjsh/example#42"),
        attempt: 1,
        status: "running",
        provider: "claude_code",
        providerSessionID: "provider-session-42",
        providerRunID: "provider-run-42",
        startedAt: "2026-03-24T00:00:00Z",
        endedAt: nil,
        workspacePath: "/tmp/example",
        sessionID: SessionID("session-42"),
        lastError: nil
    )
}

private func makeRunDetail() -> RunDetail {
    RunDetail(
        runID: RunID("run-42"),
        issueID: IssueID("issue-42"),
        issueIdentifier: try! IssueIdentifier(validating: "atjsh/example#42"),
        attempt: 1,
        status: "running",
        provider: "claude_code",
        providerSessionID: "provider-session-42",
        providerRunID: "provider-run-42",
        startedAt: "2026-03-24T00:00:00Z",
        endedAt: nil,
        workspacePath: "/tmp/example",
        sessionID: SessionID("session-42"),
        lastError: nil,
        issue: makeIssueDetail().issue,
        turnCount: 2,
        lastAgentEventType: "message",
        lastAgentMessage: "hello",
        tokens: try! TokenUsage(inputTokens: 7, outputTokens: 5),
        logs: RunLogStats(eventCount: 1, latestSequence: EventSequence(1))
    )
}

private func makeEvent(sequence: Int, kind: String) -> AgentRawEvent {
    AgentRawEvent(
        sessionID: SessionID("session-42"),
        provider: "claude_code",
        sequence: EventSequence(sequence),
        timestamp: "2026-03-24T00:00:0\(sequence)Z",
        rawJSON: #"{"message":"hello"}"#,
        providerEventType: "event",
        normalizedEventKind: kind
    )
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ verification: (Error) -> Void
) async {
    do {
        _ = try await expression()
        XCTFail("Expected expression to throw.")
    } catch {
        verification(error)
    }
}

private func firstEvent(
    from stream: AsyncThrowingStream<AgentRawEvent, Error>,
    timeout: Duration
) async throws -> AgentRawEvent? {
    try await withThrowingTaskGroup(of: AgentRawEvent?.self) { group in
        group.addTask {
            var iterator = stream.makeAsyncIterator()
            return try await iterator.next()
        }
        group.addTask {
            try await Task.sleep(for: timeout)
            throw TestTimedOut.waitingForFirstEvent
        }

        let result = try await group.next()
        group.cancelAll()
        return result ?? nil
    }
}

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: (@Sendable (URLRequest) throws -> (Data, URLResponse))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: SymphonyClientError.invalidResponse)
            return
        }

        do {
            let (data, response) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
