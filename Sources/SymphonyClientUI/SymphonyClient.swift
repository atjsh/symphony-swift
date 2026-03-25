import Foundation
import SymphonyShared

protocol HTTPSessioning: Sendable {
  func data(for request: URLRequest) async throws -> (Data, URLResponse)
  func webSocketTask(with url: URL) -> any WebSocketTasking
}

protocol WebSocketTasking: AnyObject, Sendable {
  func resume()
  func receive(
    completionHandler: @escaping @Sendable (Result<URLSessionWebSocketTask.Message, Error>) -> Void)
  func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?)
}

extension URLSession: HTTPSessioning {
  func webSocketTask(with url: URL) -> any WebSocketTasking {
    URLSessionWebSocketTaskAdapter(task: webSocketTask(with: url))
  }
}

private final class URLSessionWebSocketTaskAdapter: WebSocketTasking, @unchecked Sendable {
  private let task: URLSessionWebSocketTask

  init(task: URLSessionWebSocketTask) { self.task = task }

  func resume() { task.resume() }

  func receive(
    completionHandler: @escaping @Sendable (Result<URLSessionWebSocketTask.Message, Error>) -> Void
  ) { task.receive(completionHandler: completionHandler) }

  func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
    task.cancel(with: closeCode, reason: reason)
  }
}

public protocol SymphonyAPIClientProtocol: Sendable {
  func health(endpoint: ServerEndpoint) async throws -> HealthResponse
  func issues(endpoint: ServerEndpoint) async throws -> IssuesResponse
  func issueDetail(endpoint: ServerEndpoint, issueID: IssueID) async throws -> IssueDetail
  func runDetail(endpoint: ServerEndpoint, runID: RunID) async throws -> RunDetail
  func logs(endpoint: ServerEndpoint, sessionID: SessionID, cursor: EventCursor?, limit: Int)
    async throws -> LogEntriesResponse
  func refresh(endpoint: ServerEndpoint) async throws -> RefreshResponse
  func logStream(endpoint: ServerEndpoint, sessionID: SessionID, cursor: EventCursor?) throws
    -> AsyncThrowingStream<AgentRawEvent, Error>
}

public enum SymphonyClientError: LocalizedError, Equatable {
  case invalidEndpoint
  case invalidResponse
  case server(statusCode: Int)

  public var errorDescription: String? {
    switch self {
    case .invalidEndpoint:
      return "The configured server endpoint is invalid."
    case .invalidResponse:
      return "The server returned an invalid response."
    case .server(let statusCode):
      return "The server returned HTTP \(statusCode)."
    }
  }
}

public final class URLSessionSymphonyAPIClient: SymphonyAPIClientProtocol, @unchecked Sendable {
  private let session: any HTTPSessioning
  private let decoder: JSONDecoder

  public init(session: URLSession = .shared, decoder: JSONDecoder = JSONDecoder()) {
    self.session = session
    self.decoder = decoder
  }

  init(session: any HTTPSessioning, decoder: JSONDecoder = JSONDecoder()) {
    self.session = session
    self.decoder = decoder
  }

  public func health(endpoint: ServerEndpoint) async throws -> HealthResponse {
    try await request(endpoint: endpoint, method: "GET", path: "/api/v1/health")
  }

  public func issues(endpoint: ServerEndpoint) async throws -> IssuesResponse {
    try await request(endpoint: endpoint, method: "GET", path: "/api/v1/issues")
  }

  public func issueDetail(endpoint: ServerEndpoint, issueID: IssueID) async throws -> IssueDetail {
    try await request(endpoint: endpoint, method: "GET", path: "/api/v1/issues/\(issueID.rawValue)")
  }

  public func runDetail(endpoint: ServerEndpoint, runID: RunID) async throws -> RunDetail {
    try await request(endpoint: endpoint, method: "GET", path: "/api/v1/runs/\(runID.rawValue)")
  }

  public func logs(endpoint: ServerEndpoint, sessionID: SessionID, cursor: EventCursor?, limit: Int)
    async throws -> LogEntriesResponse
  {
    var queryItems = [URLQueryItem(name: "limit", value: String(limit))]
    if let cursor {
      queryItems.append(URLQueryItem(name: "cursor", value: cursor.rawValue))
    }
    return try await request(
      endpoint: endpoint, method: "GET", path: "/api/v1/logs/\(sessionID.rawValue)",
      queryItems: queryItems)
  }

  public func refresh(endpoint: ServerEndpoint) async throws -> RefreshResponse {
    try await request(endpoint: endpoint, method: "POST", path: "/api/v1/refresh")
  }

  public func logStream(endpoint: ServerEndpoint, sessionID: SessionID, cursor: EventCursor?) throws
    -> AsyncThrowingStream<AgentRawEvent, Error>
  {
    let url = try makeWebSocketURL(endpoint: endpoint, sessionID: sessionID, cursor: cursor)
    let task = session.webSocketTask(with: url)

    return AsyncThrowingStream(AgentRawEvent.self) { continuation in
      @Sendable func receiveNext() {
        task.receive { [decoder] result in
          switch result {
          case .success(let message):
            do {
              let data = message.payloadData
              let event = try decoder.decode(AgentRawEvent.self, from: data)
              continuation.yield(event)
              receiveNext()
            } catch {
              continuation.finish(throwing: error)
            }
          case .failure(let error):
            continuation.finish(throwing: error)
          }
        }
      }

      task.resume()
      receiveNext()
      continuation.onTermination = { _ in
        task.cancel(with: .goingAway, reason: nil)
      }
    }
  }

  private func request<T: Decodable>(
    endpoint: ServerEndpoint,
    method: String,
    path: String,
    queryItems: [URLQueryItem] = []
  ) async throws -> T {
    guard let url = makeURL(endpoint: endpoint, path: path, queryItems: queryItems) else {
      throw SymphonyClientError.invalidEndpoint
    }

    var request = URLRequest(url: url)
    request.httpMethod = method
    request.setValue("application/json", forHTTPHeaderField: "Accept")

    let (data, response) = try await session.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw SymphonyClientError.invalidResponse
    }
    guard (200...299).contains(httpResponse.statusCode) else {
      throw SymphonyClientError.server(statusCode: httpResponse.statusCode)
    }
    return try decoder.decode(T.self, from: data)
  }

  private func makeURL(endpoint: ServerEndpoint, path: String, queryItems: [URLQueryItem]) -> URL? {
    var components = URLComponents()
    components.scheme = endpoint.scheme
    components.host = endpoint.host
    components.port = endpoint.port
    components.path = path
    if !queryItems.isEmpty {
      components.queryItems = queryItems
    }
    return components.url
  }

  private func makeWebSocketURL(
    endpoint: ServerEndpoint, sessionID: SessionID, cursor: EventCursor?
  ) throws -> URL {
    let scheme: String
    switch endpoint.scheme {
    case "https":
      scheme = "wss"
    default:
      scheme = "ws"
    }

    var components = URLComponents()
    components.scheme = scheme
    components.host = endpoint.host
    components.port = endpoint.port
    components.path = "/api/v1/logs/stream"

    var queryItems = [URLQueryItem(name: "session_id", value: sessionID.rawValue)]
    if let cursor {
      queryItems.append(URLQueryItem(name: "cursor", value: cursor.rawValue))
    }
    components.queryItems = queryItems

    guard let url = components.url else {
      throw SymphonyClientError.invalidEndpoint
    }
    return url
  }
}

extension URLSessionWebSocketTask.Message {
  fileprivate var payloadData: Data {
    let value = Mirror(reflecting: self).children.first?.value
    let defaultData = Data()
    let reflectedData = (value as? Data) ?? defaultData
    if let text = value as? String {
      return Data(text.utf8)
    }
    return reflectedData
  }
}
