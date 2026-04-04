// swiftlint:disable force_try
import Foundation
import SymphonyShared
import Testing

@testable import SymphonySwiftUIApp

// SAFETY: @unchecked Sendable — all mutable state protected by `lock`.
final class TestHTTPSession: HTTPSessioning, @unchecked Sendable {
  private let lock = NSLock()
  private var _dataResponses = [(Data, URLResponse)]()
  private var _recordedRequests = [URLRequest]()
  private var _recordedWebSocketURLs = [URL]()
  let webSocketTask = TestWebSocketTask()

  var dataResponses: [(Data, URLResponse)] {
    get { lock.withLock { _dataResponses } }
    set { lock.withLock { _dataResponses = newValue } }
  }
  var recordedRequests: [URLRequest] { lock.withLock { _recordedRequests } }
  var recordedWebSocketURLs: [URL] { lock.withLock { _recordedWebSocketURLs } }

  func data(for request: URLRequest) async throws -> (Data, URLResponse) {
    lock.withLock { _recordedRequests.append(request) }
    return try lock.withLock {
      guard !_dataResponses.isEmpty else {
        Issue.record("Expected a queued HTTP response for the recorded request.")
        throw SymphonyClientError.invalidResponse
      }
      return _dataResponses.removeFirst()
    }
  }

  func webSocketTask(with url: URL) -> any WebSocketTasking {
    lock.withLock { _recordedWebSocketURLs.append(url) }
    return webSocketTask
  }
}

// SAFETY: @unchecked Sendable — all mutable state protected by `lock`.
final class TestWebSocketTask: WebSocketTasking, @unchecked Sendable {
  private let lock = NSLock()
  private var _messages = [Result<URLSessionWebSocketTask.Message, Error>]()
  private var _shouldSuspendReceives = false
  private var _didResume = false
  private var _didCancel = false

  var messages: [Result<URLSessionWebSocketTask.Message, Error>] {
    get { lock.withLock { _messages } }
    set { lock.withLock { _messages = newValue } }
  }
  var shouldSuspendReceives: Bool {
    get { lock.withLock { _shouldSuspendReceives } }
    set { lock.withLock { _shouldSuspendReceives = newValue } }
  }
  var didResume: Bool { lock.withLock { _didResume } }
  var didCancel: Bool { lock.withLock { _didCancel } }

  func resume() {
    lock.withLock { _didResume = true }
  }

  func receive(
    completionHandler: @escaping (Result<URLSessionWebSocketTask.Message, Error>) -> Void
  ) {
    let suspended = lock.withLock { _shouldSuspendReceives }
    if suspended {
      return
    }
    let message = lock.withLock { _messages.removeFirst() }
    completionHandler(message)
  }

  func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
    lock.withLock { _didCancel = true }
  }
}

enum TestClientFailure: Error, Equatable {
  case done
}

enum TestTimedOut: Error {
  case waitingForFirstEvent
}

func httpResponse<T: Encodable>(_ value: T, path: String) -> (Data, URLResponse) {
  let url = URL(string: "https://example.com:9443\(path)")!
  return (
    try! JSONEncoder().encode(value),
    HTTPURLResponse(
      url: url,
      statusCode: 200,
      httpVersion: nil,
      headerFields: ["Content-Type": "application/json"]
    )!
  )
}

func errorResponse<T: Encodable>(_ value: T, path: String, statusCode: Int)
  -> (Data, URLResponse)
{
  let url = URL(string: "https://example.com:9443\(path)")!
  return (
    try! JSONEncoder().encode(value),
    HTTPURLResponse(
      url: url,
      statusCode: statusCode,
      httpVersion: nil,
      headerFields: ["Content-Type": "application/json"]
    )!
  )
}

func encoded(_ event: AgentRawEvent) -> String {
  String(decoding: try! JSONEncoder().encode(event), as: UTF8.self)
}

func expectAsyncThrows<T, E: Error & Equatable>(
  expected: E,
  _ expression: @autoclosure () async throws -> T
) async {
  do {
    _ = try await expression()
    Issue.record("Expected the async expression to throw \(expected).")
  } catch {
    #expect(error as? E == expected)
  }
}

func firstEvent(
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

// SAFETY: @unchecked Sendable — URLProtocol subclass pattern requires static mutable
// state. Tests set requestHandler before making requests; no concurrent writes occur.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var requestHandler:
    (@Sendable (URLRequest) throws -> (Data, URLResponse))?

  override static func canInit(with request: URLRequest) -> Bool {
    true
  }

  override static func canonicalRequest(for request: URLRequest) -> URLRequest {
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

// swiftlint:enable force_try
