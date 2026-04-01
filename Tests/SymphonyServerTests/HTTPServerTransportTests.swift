import Darwin
import Foundation
import SymphonyShared
import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore

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

@Test func inProcessServerLogsRejectedWebSocketUpgradeWithoutSessionIdentifier() async throws {
  let fixture = try makeWebSocketFixture(persistSecondEvent: false, observeWrites: true)

  let (_, logs) = try await withCapturedRuntimeLogs {
    let serverTask = try await launchInProcessServer(fixture: fixture)
    defer { serverTask.cancel() }

    let task = URLSession(configuration: .ephemeral).webSocketTask(
      with: try #require(
        URL(string: "ws://\(fixture.endpoint.host):\(fixture.endpoint.port)/api/v1/logs/stream"))
    )
    task.resume()
    defer { task.cancel(with: .goingAway, reason: nil) }

    do {
      _ = try await receiveWebSocketMessage(from: task)
      Issue.record("Expected websocket upgrade without a session_id to fail.")
    } catch {}
  }

  let rejectionLog = try #require(
    logs.first {
      $0.json["event"] as? String == "websocket_upgrade_rejected"
        && $0.json["error"] as? String == "Missing session identifier."
    })
  #expect(rejectionLog.json["path"] as? String == "/api/v1/logs/stream")
}

@Test func inProcessServerLogsRejectedWebSocketUpgradeForMissingSessions() async throws {
  let fixture = try makeWebSocketFixture(persistSecondEvent: false, observeWrites: true)

  let (_, logs) = try await withCapturedRuntimeLogs {
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

  let rejectionLog = try #require(
    logs.first {
      $0.json["event"] as? String == "websocket_upgrade_rejected"
        && $0.json["session_id"] as? String == "missing-session"
    })
  #expect(rejectionLog.json["session_id"] as? String == "missing-session")
}

@Test func inProcessServerLogsRejectedWebSocketUpgradeWhenStoreLookupThrows() async throws {
  let fixture = try makeWebSocketFixture(persistSecondEvent: false, observeWrites: true)
  fixture.store.diagnostics.closeDatabase()

  let (_, logs) = try await withCapturedRuntimeLogs {
    let serverTask = try await launchInProcessServer(fixture: fixture)
    defer { serverTask.cancel() }

    let task = URLSession(configuration: .ephemeral).webSocketTask(
      with: try #require(
        URL(
          string:
            "ws://\(fixture.endpoint.host):\(fixture.endpoint.port)/api/v1/logs/stream?session_id=\(fixture.session.sessionID.rawValue)"
        ))
    )
    task.resume()
    defer { task.cancel(with: .goingAway, reason: nil) }

    do {
      _ = try await receiveWebSocketMessage(from: task)
      Issue.record("Expected websocket upgrade to fail when the session lookup throws.")
    } catch {}
  }

  let rejectionLog = try #require(
    logs.first {
      $0.json["event"] as? String == "websocket_upgrade_rejected"
        && $0.json["session_id"] as? String == fixture.session.sessionID.rawValue
        && (($0.json["error"] as? String)?.contains("SQLite database is closed") == true)
    })
  #expect(rejectionLog.json["path"] as? String == "/api/v1/logs/stream")
}

@Test func streamLogEventsLogsAndRethrowsWriterFailures() async throws {
  let fixture = try makeWebSocketFixture(persistSecondEvent: true, observeWrites: true)

  let (_, logs) = try await withCapturedRuntimeLogs {
    do {
      try await SymphonyHTTPServer.streamLogEvents(
        store: fixture.store,
        liveLogHub: fixture.liveLogHub,
        sessionID: fixture.session.sessionID,
        path: "/api/v1/logs/stream",
        initialCursor: nil
      ) { _ in
        throw SymphonyServerError.encoding("writer failed")
      }
      Issue.record("Expected streamLogEvents to rethrow writer failures.")
    } catch let error as SymphonyServerError {
      #expect(error == .encoding("writer failed"))
    }
  }

  let streamFailureLog = try #require(
    logs.first {
      $0.json["event"] as? String == "websocket_stream_failed"
        && $0.json["session_id"] as? String == fixture.session.sessionID.rawValue
    })
  #expect(streamFailureLog.json["path"] as? String == "/api/v1/logs/stream")
  #expect((streamFailureLog.json["error"] as? String)?.contains("writer failed") == true)
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

