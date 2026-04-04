import Darwin
import Foundation
import SymphonyShared
import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore

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

@Test func polledEventForwarderLogsStoreFailuresAndPreservesSequence() async throws {
  let fixture = try makeWebSocketFixture(persistSecondEvent: true, observeWrites: false)
  fixture.store.diagnostics.closeDatabase()

  let (sequence, logs) = try await withCapturedRuntimeLogs {
    SymphonyHTTPServer.forwardPolledEvents(
      store: fixture.store,
      sessionID: fixture.session.sessionID,
      lastPolledSequence: EventSequence(7)
    ) { _ in
      Issue.record("Expected no events to be yielded when polling throws.")
    }
  }

  #expect(sequence == EventSequence(7))
  let pollFailureLog = try #require(
    logs.first {
      $0.entry.event == "websocket_poll_failed"
        && $0.entry.sessionID == fixture.session.sessionID.rawValue
    })
  #expect(pollFailureLog.entry.error?.contains("SQLite database is closed") == true)
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
