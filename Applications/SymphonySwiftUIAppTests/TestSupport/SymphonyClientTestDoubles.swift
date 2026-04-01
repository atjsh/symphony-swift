import Foundation
import SymphonyShared
import Testing

@testable import SymphonySwiftUIApp

final class TestHTTPSession: HTTPSessioning, @unchecked Sendable {
  var dataResponses = [(Data, URLResponse)]()
  var recordedRequests = [URLRequest]()
  var recordedWebSocketURLs = [URL]()
  let webSocketTask = TestWebSocketTask()

  func data(for request: URLRequest) async throws -> (Data, URLResponse) {
    recordedRequests.append(request)
    guard !dataResponses.isEmpty else {
      Issue.record("Expected a queued HTTP response for the recorded request.")
      throw SymphonyClientError.invalidResponse
    }
    return dataResponses.removeFirst()
  }

  func webSocketTask(with url: URL) -> any WebSocketTasking {
    recordedWebSocketURLs.append(url)
    return webSocketTask
  }
}

final class TestWebSocketTask: WebSocketTasking, @unchecked Sendable {
  var messages = [Result<URLSessionWebSocketTask.Message, Error>]()
  var shouldSuspendReceives = false
  private(set) var didResume = false
  private(set) var didCancel = false

  func resume() {
    didResume = true
  }

  func receive(
    completionHandler: @escaping (Result<URLSessionWebSocketTask.Message, Error>) -> Void
  ) {
    if shouldSuspendReceives {
      return
    }
    completionHandler(messages.removeFirst())
  }

  func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
    didCancel = true
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

final class StubURLProtocol: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var requestHandler:
    (@Sendable (URLRequest) throws -> (Data, URLResponse))?

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
