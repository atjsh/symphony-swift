import Darwin
import Foundation
import SymphonyShared
import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore

struct WebSocketFixture {
  let store: SQLiteServerStateStore
  let liveLogHub: LiveLogHub
  let databaseURL: URL
  let endpoint: BootstrapServerEndpoint
  let session: AgentSession
  let firstEvent: AgentRawEvent
  let secondEvent: AgentRawEvent
}

struct LaunchedServer {
  let process: Process
  let endpoint: BootstrapServerEndpoint
}

func makeWebSocketFixture(persistSecondEvent: Bool, observeWrites: Bool = false) throws
  -> WebSocketFixture
{
  let root = try makeTemporaryDirectory()
  let databaseURL = root.appendingPathComponent("symphony.sqlite3")
  let liveLogHub = LiveLogHub()
  let store = try SQLiteServerStateStore(
    databaseURL: databaseURL,
    eventObserver: observeWrites
      ? BootstrapServerRunner.makeEventObserver(liveLogHub: liveLogHub) : nil
  )
  let port = try availableLoopbackPort()
  let identifierSuffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()

  let identifier = try IssueIdentifier(validating: "atjsh/example#42")
  let issue = SymphonyShared.Issue(
    id: IssueID("issue-\(identifierSuffix)"),
    identifier: identifier,
    repository: "atjsh/example",
    number: 42,
    title: "Implement provider-neutral server",
    description: "The bootstrap runtime must become a real API.",
    priority: 1,
    state: "in_progress",
    issueState: "OPEN",
    projectItemID: "item-42",
    url: "https://example.com/issues/42",
    labels: ["Server", "Spec"],
    blockedBy: [],
    createdAt: "2026-03-24T01:00:00Z",
    updatedAt: "2026-03-24T02:00:00Z"
  )

  let runDetail = RunDetail(
    runID: RunID("run-\(identifierSuffix)"),
    issueID: issue.id,
    issueIdentifier: identifier,
    attempt: 1,
    status: "running",
    provider: "claude_code",
    providerSessionID: "provider-session-\(identifierSuffix)",
    providerRunID: "provider-run-\(identifierSuffix)",
    startedAt: "2026-03-24T03:00:00Z",
    endedAt: nil,
    workspacePath: "/tmp/symphony/atjsh_example_42",
    sessionID: SessionID("session-\(identifierSuffix)"),
    lastError: nil,
    issue: issue,
    turnCount: 1,
    lastAgentEventType: "status",
    lastAgentMessage: "starting",
    tokens: try TokenUsage(inputTokens: 4, outputTokens: 3),
    logs: RunLogStats(eventCount: 0, latestSequence: nil)
  )

  let session = AgentSession(
    sessionID: runDetail.sessionID!,
    provider: runDetail.provider,
    providerSessionID: runDetail.providerSessionID,
    providerThreadID: "thread-\(identifierSuffix)",
    providerTurnID: "turn-\(identifierSuffix)",
    providerRunID: runDetail.providerRunID,
    runID: runDetail.runID,
    providerProcessPID: "999",
    status: "active",
    lastEventType: "status",
    lastEventAt: "2026-03-24T03:00:01Z",
    turnCount: 1,
    tokenUsage: try TokenUsage(inputTokens: 4, outputTokens: 3),
    latestRateLimitPayload: #"{"remaining":100}"#
  )

  let firstEvent = AgentRawEvent(
    sessionID: session.sessionID,
    provider: session.provider,
    sequence: EventSequence(1),
    timestamp: "2026-03-24T03:00:01Z",
    rawJSON: #"{"type":"status","payload":{"message":"starting"}}"#,
    providerEventType: "status",
    normalizedEventKind: "status"
  )

  let secondEvent = AgentRawEvent(
    sessionID: session.sessionID,
    provider: session.provider,
    sequence: EventSequence(2),
    timestamp: "2026-03-24T03:00:02Z",
    rawJSON: #"{"type":"message","payload":{"text":"working"}}"#,
    providerEventType: "message",
    normalizedEventKind: "message"
  )

  try store.upsertIssue(issue)
  try store.upsertRun(runDetail)
  try store.upsertSession(session)
  _ = try store.appendEvent(
    sessionID: session.sessionID,
    provider: session.provider,
    timestamp: firstEvent.timestamp,
    rawJSON: firstEvent.rawJSON,
    providerEventType: firstEvent.providerEventType,
    normalizedEventKind: firstEvent.normalizedEventKind
  )

  if persistSecondEvent {
    _ = try store.appendEvent(
      sessionID: session.sessionID,
      provider: session.provider,
      timestamp: secondEvent.timestamp,
      rawJSON: secondEvent.rawJSON,
      providerEventType: secondEvent.providerEventType,
      normalizedEventKind: secondEvent.normalizedEventKind
    )
  }

  return WebSocketFixture(
    store: store,
    liveLogHub: liveLogHub,
    databaseURL: databaseURL,
    endpoint: BootstrapServerEndpoint(scheme: "http", host: "127.0.0.1", port: port),
    session: session,
    firstEvent: firstEvent,
    secondEvent: secondEvent
  )
}

func launchServer(fixture: WebSocketFixture) throws -> LaunchedServer {
  let executable = builtProductsDirectory().appendingPathComponent("symphony-server")
  #expect(FileManager.default.isExecutableFile(atPath: executable.path))

  let endpoint = BootstrapServerEndpoint(
    scheme: fixture.endpoint.scheme,
    host: fixture.endpoint.host,
    port: try availableLoopbackPort()
  )
  let process = Process()
  let output = Pipe()
  process.executableURL = executable
  var environment = ProcessInfo.processInfo.environment
  environment[BootstrapEnvironment.serverHostKey] = endpoint.host
  environment[BootstrapEnvironment.serverPortKey] = String(endpoint.port)
  environment[BootstrapEnvironment.serverSQLitePathKey] = fixture.databaseURL.path
  process.environment = environment
  process.standardOutput = output
  process.standardError = output
  try process.run()
  return LaunchedServer(process: process, endpoint: endpoint)
}

func waitForServerHealth(endpoint: BootstrapServerEndpoint) async throws {
  let url = try #require(URL(string: "http://\(endpoint.host):\(endpoint.port)/api/v1/health"))
  let session = URLSession(configuration: .ephemeral)

  for _ in 0..<30 {
    do {
      let (data, response) = try await session.data(from: url)
      let httpResponse = try #require(response as? HTTPURLResponse)
      if httpResponse.statusCode == 200 {
        let health = try JSONDecoder().decode(HealthResponse.self, from: data)
        #expect(health.status == "ok")
        return
      }
    } catch {
      try await Task.sleep(for: .milliseconds(100))
    }
  }

  Issue.record("Expected the server to become healthy before websocket assertions.")
  throw POSIXError(.ETIMEDOUT)
}

final class WebSocketProbe: @unchecked Sendable {
  private let session: URLSession
  private let task: URLSessionWebSocketTask
  private let decoder = JSONDecoder()

  init(endpoint: BootstrapServerEndpoint, sessionID: SessionID, cursor: EventCursor?) throws {
    let session = URLSession(configuration: .ephemeral)
    self.session = session
    self.task = session.webSocketTask(
      with: try makeWebSocketURL(endpoint: endpoint, sessionID: sessionID, cursor: cursor))
    self.task.resume()
  }

  func cancel() {
    task.cancel(with: .goingAway, reason: nil)
  }

  func nextEvent(timeout: Duration = .seconds(3)) async throws -> AgentRawEvent {
    let payload = try await nextPayload(timeout: timeout)
    return try decoder.decode(AgentRawEvent.self, from: payload)
  }

  func collectEvents(count: Int, timeout: Duration = .seconds(3)) async throws -> [AgentRawEvent] {
    var events = [AgentRawEvent]()
    events.reserveCapacity(count)
    for _ in 0..<count {
      events.append(try await nextEvent(timeout: timeout))
    }
    return events
  }

  private func nextPayload(timeout: Duration) async throws -> Data {
    try await withThrowingTaskGroup(of: Data.self) { group in
      group.addTask {
        try await withCheckedThrowingContinuation { continuation in
          self.task.receive { result in
            switch result {
            case .success(let message):
              do {
                continuation.resume(returning: try Self.payloadData(from: message))
              } catch {
                continuation.resume(throwing: error)
              }
            case .failure(let error):
              continuation.resume(throwing: error)
            }
          }
        }
      }

      group.addTask {
        try await Task.sleep(for: timeout)
        throw POSIXError(.ETIMEDOUT)
      }

      defer { group.cancelAll() }
      return try await group.next()!
    }
  }

  private static func payloadData(from message: URLSessionWebSocketTask.Message) throws -> Data {
    switch message {
    case .data(let data):
      return data
    case .string(let string):
      return Data(string.utf8)
    @unknown default:
      throw SymphonyServerError.encoding("Unsupported websocket message payload.")
    }
  }
}

func makeWebSocketURL(
  endpoint: BootstrapServerEndpoint,
  sessionID: SessionID,
  cursor: EventCursor?
) throws -> URL {
  var components = URLComponents()
  components.scheme = "ws"
  components.host = endpoint.host
  components.port = endpoint.port
  components.path = "/api/v1/logs/stream"
  var queryItems = [URLQueryItem(name: "session_id", value: sessionID.rawValue)]
  if let cursor {
    queryItems.append(URLQueryItem(name: "cursor", value: cursor.rawValue))
  }
  components.queryItems = queryItems
  return try #require(components.url)
}

func decodeBody<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
  return try JSONDecoder().decode(T.self, from: data)
}

func makeTemporaryDirectory() throws -> URL {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    UUID().uuidString, isDirectory: true)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  return root
}

func launchInProcessServer(
  fixture: WebSocketFixture,
  refresh: @escaping @Sendable () -> Void = {}
) async throws -> Task<Void, Error> {
  let api = SymphonyHTTPAPI(
    store: fixture.store,
    version: "1.0.0",
    trackerKind: "github",
    refresh: refresh
  )
  let server = SymphonyHTTPServer(
    endpoint: fixture.endpoint,
    store: fixture.store,
    api: api,
    liveLogHub: fixture.liveLogHub
  )
  let startup = ServerStartupSignal()
  let serverTask = Task.detached {
    try await server.run {
      startup.ready()
    }
  }
  do {
    try await startup.waitUntilReady()
    return serverTask
  } catch {
    serverTask.cancel()
    throw error
  }
}

func requestHealth(endpoint: BootstrapServerEndpoint) async throws -> HealthResponse {
  let response = try await request(endpoint: endpoint, path: "/api/v1/health", method: "GET")
  #expect(response.statusCode == 200)
  return try decodeBody(HealthResponse.self, from: response.data)
}

func request(
  endpoint: BootstrapServerEndpoint,
  path: String,
  method: String
) async throws -> (data: Data, statusCode: Int) {
  let url = try #require(URL(string: "http://\(endpoint.host):\(endpoint.port)\(path)"))
  var request = URLRequest(url: url)
  request.httpMethod = method
  let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
  let httpResponse = try #require(response as? HTTPURLResponse)
  return (data, httpResponse.statusCode)
}

func receiveWebSocketMessage(from task: URLSessionWebSocketTask) async throws
  -> URLSessionWebSocketTask.Message
{
  try await withCheckedThrowingContinuation { continuation in
    task.receive { result in
      continuation.resume(with: result)
    }
  }
}

struct EncodingProbe: Codable, Equatable {
  let b: Int
  let a: Int
}

final class Counter: @unchecked Sendable {
  private let lock = NSLock()
  private(set) var value = 0

  func increment() {
    lock.lock()
    value += 1
    lock.unlock()
  }
}

func builtProductsDirectory() -> URL {
  Bundle(for: BundleLocator.self).bundleURL.deletingLastPathComponent()
}

final class BundleLocator {}

extension Process {
  func terminateAndWait(timeout: TimeInterval = 1) {
    guard isRunning else {
      return
    }

    let semaphore = DispatchSemaphore(value: 0)
    let waitQueue = DispatchQueue(label: "symphony.tests.process.wait.\(processIdentifier)")
    waitQueue.async {
      self.waitUntilExit()
      semaphore.signal()
    }

    terminate()
    if semaphore.wait(timeout: .now() + timeout) == .success {
      return
    }

    Darwin.kill(processIdentifier, SIGKILL)
    _ = semaphore.wait(timeout: .now() + timeout)
  }
}

func availableLoopbackPort() throws -> Int {
  let descriptor = socket(AF_INET, SOCK_STREAM, 0)
  guard descriptor >= 0 else {
    throw POSIXError(.EIO)
  }
  defer { close(descriptor) }

  var address = sockaddr_in()
  address.sin_len = UInt8(MemoryLayout<sockaddr_in>.stride)
  address.sin_family = sa_family_t(AF_INET)
  address.sin_port = in_port_t(0).bigEndian
  address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

  let bindResult = withUnsafePointer(to: &address) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
      Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.stride))
    }
  }
  guard bindResult == 0 else {
    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
  }

  var length = socklen_t(MemoryLayout<sockaddr_in>.stride)
  let nameResult = withUnsafeMutablePointer(to: &address) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
      getsockname(descriptor, $0, &length)
    }
  }
  guard nameResult == 0 else {
    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
  }

  return Int(UInt16(bigEndian: address.sin_port))
}
