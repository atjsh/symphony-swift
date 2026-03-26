import Darwin
import Foundation
import SymphonyShared
import Testing

@testable import SymphonyRuntime

@Test func inProcessServerServesHTTPRoutesAndWebSocketBacklog() async throws {
  let fixture = try makeWebSocketFixture(persistSecondEvent: true, observeWrites: true)
  let refreshCounter = Counter()
  let serverTask = try await launchInProcessServer(
    fixture: fixture,
    refresh: { refreshCounter.increment() }
  )
  defer { serverTask.cancel() }

  let health = try await requestHealth(endpoint: fixture.endpoint)
  #expect(health.status == "ok")
  #expect(health.trackerKind == "github")

  let refreshResponse = try await request(
    endpoint: fixture.endpoint,
    path: "/api/v1/refresh",
    method: "POST"
  )
  #expect(refreshResponse.statusCode == 202)
  #expect(try decodeBody(RefreshResponse.self, from: refreshResponse.data).queued)
  #expect(refreshCounter.value == 1)

  let missingIssueResponse = try await request(
    endpoint: fixture.endpoint,
    path: "/api/v1/issues/missing",
    method: "GET"
  )
  #expect(missingIssueResponse.statusCode == 404)
  #expect(
    try decodeBody(ErrorEnvelope.self, from: missingIssueResponse.data).error.code
      == "issue_not_found")

  let unsupportedResponse = try await request(
    endpoint: fixture.endpoint,
    path: "/api/v1/issues",
    method: "DELETE"
  )
  #expect(unsupportedResponse.statusCode == 405)
  #expect(
    try decodeBody(ErrorEnvelope.self, from: unsupportedResponse.data).error.code
      == "method_not_allowed")

  let backlogCursor = EventCursor(
    sessionID: fixture.session.sessionID,
    lastDeliveredSequence: EventSequence(1)
  )
  let websocket = try WebSocketProbe(
    endpoint: fixture.endpoint,
    sessionID: fixture.session.sessionID,
    cursor: backlogCursor
  )
  defer { websocket.cancel() }

  let events = try await websocket.collectEvents(count: 1)
  #expect(events == [fixture.secondEvent])
}

@Test func inProcessServerLiveTailPublishesNewEvents() async throws {
  let fixture = try makeWebSocketFixture(persistSecondEvent: false, observeWrites: true)
  let serverTask = try await launchInProcessServer(fixture: fixture)
  defer { serverTask.cancel() }

  let websocket = try WebSocketProbe(
    endpoint: fixture.endpoint,
    sessionID: fixture.session.sessionID,
    cursor: nil
  )
  defer { websocket.cancel() }

  let firstEvent = try await websocket.nextEvent()
  #expect(firstEvent == fixture.firstEvent)

  let appendedEvent = try fixture.store.appendEvent(
    sessionID: fixture.session.sessionID,
    provider: fixture.session.provider,
    timestamp: fixture.secondEvent.timestamp,
    rawJSON: fixture.secondEvent.rawJSON,
    providerEventType: fixture.secondEvent.providerEventType,
    normalizedEventKind: fixture.secondEvent.normalizedEventKind
  )
  let secondEvent = try await websocket.nextEvent()
  #expect(appendedEvent == fixture.secondEvent)
  #expect(secondEvent == fixture.secondEvent)
}

@Test func inProcessServerRejectsWebSocketUpgradeForMissingSessions() async throws {
  let fixture = try makeWebSocketFixture(persistSecondEvent: false, observeWrites: true)
  let serverTask = try await launchInProcessServer(fixture: fixture)
  defer { serverTask.cancel() }

  let task = URLSession(configuration: .ephemeral).webSocketTask(
    with: try #require(
      URL(
        string:
          "ws://\(fixture.endpoint.host):\(fixture.endpoint.port)/api/v1/logs/stream?session_id=missing-session"
      ))
  )
  task.resume()
  defer { task.cancel(with: .goingAway, reason: nil) }

  do {
    _ = try await receiveWebSocketMessage(from: task)
    Issue.record("Expected websocket upgrade to fail for missing sessions.")
  } catch {}
}

@Test func inProcessServerWebSocketLoopExitsWhenServerIsCancelled() async throws {
  let fixture = try makeWebSocketFixture(persistSecondEvent: false, observeWrites: true)
  let serverTask = try await launchInProcessServer(fixture: fixture)

  let websocket = try WebSocketProbe(
    endpoint: fixture.endpoint,
    sessionID: fixture.session.sessionID,
    cursor: nil
  )
  defer { websocket.cancel() }

  _ = try await websocket.nextEvent()
  serverTask.cancel()
  do {
    try await serverTask.value
  } catch {
    Issue.record(
      "Expected server cancellation to stop the websocket loop without surfacing an error.")
  }
}

@Test func inProcessSymphonyHTTPServerRunServesHealthEndpoint() async throws {
  let fixture = try makeWebSocketFixture(persistSecondEvent: false, observeWrites: true)
  let api = SymphonyHTTPAPI(store: fixture.store, version: "1.0.0", trackerKind: "github")
  let server = SymphonyHTTPServer(
    endpoint: fixture.endpoint,
    store: fixture.store,
    api: api,
    liveLogHub: fixture.liveLogHub
  )
  let startup = ServerStartupSignal()
  let serverTask = Task {
    try await server.run {
      startup.ready()
    }
  }
  defer { serverTask.cancel() }

  try await startup.waitUntilReady()
  try await waitForServerHealth(endpoint: fixture.endpoint)
  serverTask.cancel()
  _ = try? await serverTask.value
}

@Test func transportHelpersMapStatusAndParseQueries() throws {
  #expect(SymphonyHTTPServer.status(for: 200) == .ok)
  #expect(SymphonyHTTPServer.status(for: 202) == .accepted)
  #expect(SymphonyHTTPServer.status(for: 400) == .badRequest)
  #expect(SymphonyHTTPServer.status(for: 404) == .notFound)
  #expect(SymphonyHTTPServer.status(for: 405) == .methodNotAllowed)
  #expect(SymphonyHTTPServer.status(for: 503) == .init(code: 503))

  let cursor = EventCursor(
    sessionID: SessionID("session-42"), lastDeliveredSequence: EventSequence(7))
  let encodedQuery = "session_id=session-42&cursor=\(cursor.rawValue)&message=hello%20world"
  #expect(SymphonyHTTPServer.queryValue(named: "session_id", in: encodedQuery) == "session-42")
  #expect(SymphonyHTTPServer.queryValue(named: "message", in: encodedQuery) == "hello world")
  #expect(SymphonyHTTPServer.queryValue(named: "missing", in: encodedQuery) == nil)
  #expect(SymphonyHTTPServer.queryValue(named: "session_id", in: nil) == nil)
  #expect(SymphonyHTTPServer.sessionID(query: nil) == nil)
  #expect(SymphonyHTTPServer.sessionID(query: encodedQuery) == SessionID("session-42"))
  #expect(SymphonyHTTPServer.cursor(query: nil) == nil)
  #expect(SymphonyHTTPServer.cursor(query: encodedQuery) == cursor)

  let encoder = SymphonyHTTPServer.makeEncoder()
  let encoded = try encoder.encode(EncodingProbe(b: 2, a: 1))
  #expect(String(decoding: encoded, as: UTF8.self) == #"{"a":1,"b":2}"#)

  let sortedHeaders = SymphonyHTTPServer.httpFields(
    from: [
      "X-Zeta": "zeta",
      "Bad Header\n": "ignored",
      "Content-Type": "application/json; charset=utf-8",
      "X-Alpha": "alpha",
    ]
  )
  #expect(
    sortedHeaders.map { "\($0.name.rawName)=\($0.value)" } == [
      "Content-Type=application/json; charset=utf-8",
      "X-Alpha=alpha",
      "X-Zeta=zeta",
    ])
}

@Test func inProcessServerRoutesAdditionalSupportedHTTPMethods() async throws {
  let fixture = try makeWebSocketFixture(persistSecondEvent: false, observeWrites: true)
  let serverTask = try await launchInProcessServer(fixture: fixture)
  defer { serverTask.cancel() }

  let headResponse = try await request(
    endpoint: fixture.endpoint,
    path: "/api/v1/health",
    method: "HEAD"
  )
  #expect(headResponse.statusCode == 405)

  let patchResponse = try await request(
    endpoint: fixture.endpoint,
    path: "/api/v1/refresh",
    method: "PATCH"
  )
  #expect(patchResponse.statusCode == 405)

  let putResponse = try await request(
    endpoint: fixture.endpoint,
    path: "/api/v1/issues",
    method: "PUT"
  )
  #expect(putResponse.statusCode == 405)
}

@Test func inProcessWebSocketSubscribesToLiveLogHub() async throws {
  let fixture = try makeWebSocketFixture(persistSecondEvent: false, observeWrites: true)
  let serverTask = try await launchInProcessServer(fixture: fixture)
  defer { serverTask.cancel() }

  let websocket = try WebSocketProbe(
    endpoint: fixture.endpoint,
    sessionID: fixture.session.sessionID,
    cursor: nil
  )
  defer { websocket.cancel() }

  _ = try await websocket.nextEvent()

  try await waitUntil("LiveLogHub has a subscriber for the active WebSocket session") {
    await fixture.liveLogHub.subscriberCount(for: fixture.session.sessionID) > 0
  }
}

@Test func pollForwarderDeliversCrossProcessWriteAndDeduplicatesOverlap() async throws {
  let fixture = try makeWebSocketFixture(persistSecondEvent: false, observeWrites: true)
  let serverTask = try await launchInProcessServer(fixture: fixture)
  defer { serverTask.cancel() }

  let websocket = try WebSocketProbe(
    endpoint: fixture.endpoint,
    sessionID: fixture.session.sessionID,
    cursor: nil
  )
  defer { websocket.cancel() }

  let firstEvent = try await websocket.nextEvent()
  #expect(firstEvent == fixture.firstEvent)

  _ = try fixture.store.appendEvent(
    sessionID: fixture.session.sessionID,
    provider: fixture.session.provider,
    timestamp: fixture.secondEvent.timestamp,
    rawJSON: fixture.secondEvent.rawJSON,
    providerEventType: fixture.secondEvent.providerEventType,
    normalizedEventKind: fixture.secondEvent.normalizedEventKind
  )
  let secondEvent = try await websocket.nextEvent()
  #expect(secondEvent == fixture.secondEvent)

  let separateStore = try SQLiteServerStateStore(databaseURL: fixture.databaseURL)
  _ = try separateStore.appendEvent(
    sessionID: fixture.session.sessionID,
    provider: fixture.session.provider,
    timestamp: "2026-03-24T03:00:03Z",
    rawJSON: #"{"type":"tool_call","payload":{"name":"ls"}}"#,
    providerEventType: "tool_call",
    normalizedEventKind: "tool_call"
  )

  let thirdEvent = try await websocket.nextEvent(timeout: .seconds(3))
  #expect(thirdEvent.sequence == EventSequence(3))
  #expect(thirdEvent.providerEventType == "tool_call")
}

@Test func polledEventForwarderYieldsStoredEventsAndPreservesSequenceForMissingSessions() throws {
  let fixture = try makeWebSocketFixture(persistSecondEvent: true, observeWrites: false)
  var yielded = [AgentRawEvent]()

  let unchangedSequence = SymphonyHTTPServer.forwardPolledEvents(
    store: fixture.store,
    sessionID: SessionID("missing-session"),
    lastPolledSequence: EventSequence(7)
  ) { event in
    yielded.append(event)
  }
  #expect(unchangedSequence == EventSequence(7))
  #expect(yielded.isEmpty)

  let advancedSequence = SymphonyHTTPServer.forwardPolledEvents(
    store: fixture.store,
    sessionID: fixture.session.sessionID,
    lastPolledSequence: EventSequence(0)
  ) { event in
    yielded.append(event)
  }

  #expect(yielded == [fixture.firstEvent, fixture.secondEvent])
  #expect(advancedSequence == fixture.secondEvent.sequence)
}

@Test func liveLogHubPublishesToSubscribersAndRemovesTerminatedStreams() async throws {
  let hub = LiveLogHub()
  let sessionID = SessionID("session-42")
  let otherSessionID = SessionID("session-43")
  let event = AgentRawEvent(
    sessionID: sessionID,
    provider: "claude_code",
    sequence: EventSequence(1),
    timestamp: "2026-03-24T03:00:01Z",
    rawJSON: #"{"type":"message","payload":{"text":"hello"}}"#,
    providerEventType: "message",
    normalizedEventKind: "message"
  )

  await hub.publish(event)

  let subscriberStream = await hub.subscribe(to: sessionID)
  let otherStream = await hub.subscribe(to: otherSessionID)
  #expect(await hub.subscriberCount(for: sessionID) == 1)
  #expect(await hub.subscriberCount(for: otherSessionID) == 1)

  let subscriberTask = Task {
    var iterator = subscriberStream.makeAsyncIterator()
    return await iterator.next()
  }
  let otherTask = Task {
    var iterator = otherStream.makeAsyncIterator()
    return await iterator.next()
  }

  await hub.publish(event)
  let receivedEvent = try #require(await subscriberTask.value)
  #expect(receivedEvent == event)

  otherTask.cancel()
  _ = await otherTask.result
  try await waitUntil("other live-log subscriber is removed") {
    await hub.subscriberCount(for: otherSessionID) == 0
  }
}

@Test func websocketBacklogFromCursorDeliversEventsAfterTheCursor() async throws {
  let fixture = try makeWebSocketFixture(persistSecondEvent: true)
  let server = try launchServer(fixture: fixture)
  defer { server.process.terminateAndWait() }

  try await waitForServerHealth(endpoint: server.endpoint)

  let websocket = try WebSocketProbe(
    endpoint: server.endpoint,
    sessionID: fixture.session.sessionID,
    cursor: EventCursor(
      sessionID: fixture.session.sessionID, lastDeliveredSequence: EventSequence(1))
  )
  defer { websocket.cancel() }

  let events = try await websocket.collectEvents(count: 1)
  #expect(events == [fixture.secondEvent])
}

@Test func websocketLiveTailDeliversAppendedEventAfterBacklog() async throws {
  let fixture = try makeWebSocketFixture(persistSecondEvent: false)
  let server = try launchServer(fixture: fixture)
  defer { server.process.terminateAndWait() }

  try await waitForServerHealth(endpoint: server.endpoint)

  let websocket = try WebSocketProbe(
    endpoint: server.endpoint,
    sessionID: fixture.session.sessionID,
    cursor: nil
  )
  defer { websocket.cancel() }

  let firstEvent = try await websocket.nextEvent()
  #expect(firstEvent == fixture.firstEvent)

  let appendTask = Task<AgentRawEvent, Error> {
    try await Task.sleep(for: .milliseconds(200))
    let store = try SQLiteServerStateStore(databaseURL: fixture.databaseURL)
    return try store.appendEvent(
      sessionID: fixture.session.sessionID,
      provider: fixture.session.provider,
      timestamp: fixture.secondEvent.timestamp,
      rawJSON: fixture.secondEvent.rawJSON,
      providerEventType: fixture.secondEvent.providerEventType,
      normalizedEventKind: fixture.secondEvent.normalizedEventKind
    )
  }
  defer { appendTask.cancel() }

  let secondEvent = try await websocket.nextEvent(timeout: .seconds(5))
  let appendedEvent = try await appendTask.value
  #expect(secondEvent == fixture.secondEvent)
  #expect(appendedEvent == fixture.secondEvent)
}

@Test func terminateAndWaitKillsProcessesThatIgnoreTerminate() throws {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/bin/sh")
  process.arguments = ["-c", "trap '' TERM; while :; do sleep 1; done"]
  let output = Pipe()
  process.standardOutput = output
  process.standardError = output
  try process.run()

  process.terminateAndWait(timeout: 0.2)

  #expect(!process.isRunning)
}

private struct WebSocketFixture {
  let store: SQLiteServerStateStore
  let liveLogHub: LiveLogHub
  let databaseURL: URL
  let endpoint: BootstrapServerEndpoint
  let session: AgentSession
  let firstEvent: AgentRawEvent
  let secondEvent: AgentRawEvent
}

private struct LaunchedServer {
  let process: Process
  let endpoint: BootstrapServerEndpoint
}

private func makeWebSocketFixture(persistSecondEvent: Bool, observeWrites: Bool = false) throws
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

private func launchServer(fixture: WebSocketFixture) throws -> LaunchedServer {
  let executable = builtProductsDirectory().appendingPathComponent("SymphonyServer")
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

private func waitForServerHealth(endpoint: BootstrapServerEndpoint) async throws {
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

private final class WebSocketProbe: @unchecked Sendable {
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
      throw SymphonyRuntimeError.encoding("Unsupported websocket message payload.")
    }
  }
}

private func makeWebSocketURL(
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

private func decodeBody<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
  return try JSONDecoder().decode(T.self, from: data)
}

private func makeTemporaryDirectory() throws -> URL {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    UUID().uuidString, isDirectory: true)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  return root
}

private func launchInProcessServer(
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

private func requestHealth(endpoint: BootstrapServerEndpoint) async throws -> HealthResponse {
  let response = try await request(endpoint: endpoint, path: "/api/v1/health", method: "GET")
  #expect(response.statusCode == 200)
  return try decodeBody(HealthResponse.self, from: response.data)
}

private func request(
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

private func receiveWebSocketMessage(from task: URLSessionWebSocketTask) async throws
  -> URLSessionWebSocketTask.Message
{
  try await withCheckedThrowingContinuation { continuation in
    task.receive { result in
      continuation.resume(with: result)
    }
  }
}

private struct EncodingProbe: Codable, Equatable {
  let b: Int
  let a: Int
}

private final class Counter: @unchecked Sendable {
  private let lock = NSLock()
  private(set) var value = 0

  func increment() {
    lock.lock()
    value += 1
    lock.unlock()
  }
}

private func waitUntil(
  _ description: String,
  timeout: Duration = .seconds(1),
  interval: Duration = .milliseconds(20),
  condition: @escaping @Sendable () async -> Bool
) async throws {
  let deadline = ContinuousClock.now + timeout
  while ContinuousClock.now < deadline {
    if await condition() {
      return
    }
    try await Task.sleep(for: interval)
  }

  Issue.record("Timed out waiting for \(description).")
  throw POSIXError(.ETIMEDOUT)
}

private func builtProductsDirectory() -> URL {
  Bundle(for: BundleLocator.self).bundleURL.deletingLastPathComponent()
}

private final class BundleLocator {}

extension Process {
  fileprivate func terminateAndWait(timeout: TimeInterval = 1) {
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

private func availableLoopbackPort() throws -> Int {
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
