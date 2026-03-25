import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdWebSocket
import SymphonyShared

@available(macOS 14, iOS 17, tvOS 17, *)
final class SymphonyHTTPServer: @unchecked Sendable {
  private let endpoint: BootstrapServerEndpoint
  private let store: SQLiteServerStateStore
  private let api: SymphonyHTTPAPI
  private let liveLogHub: LiveLogHub

  init(
    endpoint: BootstrapServerEndpoint,
    store: SQLiteServerStateStore,
    api: SymphonyHTTPAPI,
    liveLogHub: LiveLogHub
  ) {
    self.endpoint = endpoint
    self.store = store
    self.api = api
    self.liveLogHub = liveLogHub
  }

  func run(onReady: @escaping @Sendable () async -> Void) async throws {
    let httpRouter = Self.makeHTTPRouter(api: api)
    let webSocketRouter = Self.makeWebSocketRouter(store: store, liveLogHub: liveLogHub)
    let app = Application(
      router: httpRouter,
      server: .http1WebSocketUpgrade(webSocketRouter: webSocketRouter),
      configuration: .init(address: .hostname(endpoint.host, port: endpoint.port)),
      onServerRunning: { _ in
        await onReady()
      }
    )

    try await app.runService(gracefulShutdownSignals: [])
  }

  static func makeHTTPRouter(api: SymphonyHTTPAPI) -> Router<BasicRequestContext> {
    let router = Router(context: BasicRequestContext.self)

    for method in supportedMethods {
      router.on("/api/v1/**", method: method) { request, _ in
        try response(for: request, api: api)
      }
    }

    return router
  }

  static func makeWebSocketRouter(
    store: SQLiteServerStateStore,
    liveLogHub: LiveLogHub
  ) -> Router<BasicWebSocketRequestContext> {
    let router = Router(context: BasicWebSocketRequestContext.self)

    router.ws("/api/v1/logs/stream") { request, _ in
      guard let sessionID = sessionID(query: request.uri.query),
        try store.session(sessionID: sessionID) != nil
      else {
        return .dontUpgrade
      }
      return .upgrade()
    } onUpgrade: { _, outbound, context in
      let sessionID = sessionID(query: context.request.uri.query)!

      let encoder = makeEncoder()
      let initialCursor = cursor(query: context.request.uri.query)
      var lastDeliveredSequence = initialCursor?.lastDeliveredSequence ?? EventSequence(0)

      let subscription = await liveLogHub.subscribe(to: sessionID)

      while true {
        try Task.checkCancellation()

        let pollingCursor =
          lastDeliveredSequence.rawValue > 0
          ? EventCursor(sessionID: sessionID, lastDeliveredSequence: lastDeliveredSequence)
          : nil
        let page = try store.logs(sessionID: sessionID, cursor: pollingCursor, limit: 100)!

        guard !page.items.isEmpty else {
          break
        }

        for event in page.items {
          try await outbound.write(
            .text(String(decoding: try encoder.encode(event), as: UTF8.self)))
          lastDeliveredSequence = event.sequence
        }
      }

      let (mergedStream, mergedContinuation) = AsyncStream<AgentRawEvent>.makeStream()

      let subscriptionForwarder = Task {
        for await event in subscription {
          mergedContinuation.yield(event)
        }
      }

      let backlogEndSequence = lastDeliveredSequence
      let pollForwarder = Task {
        var lastPolledSequence = backlogEndSequence
        while !Task.isCancelled {
          do {
            try await Task.sleep(for: .seconds(1))
          } catch {
            break
          }
          let pollingCursor = EventCursor(
            sessionID: sessionID, lastDeliveredSequence: lastPolledSequence)
          if let page = try? store.logs(sessionID: sessionID, cursor: pollingCursor, limit: 100) {
            for event in page.items {
              mergedContinuation.yield(event)
              lastPolledSequence = event.sequence
            }
          }
        }
      }

      defer {
        subscriptionForwarder.cancel()
        pollForwarder.cancel()
        mergedContinuation.finish()
      }

      for await event in mergedStream {
        try Task.checkCancellation()
        guard event.sequence > lastDeliveredSequence else { continue }
        try await outbound.write(.text(String(decoding: try encoder.encode(event), as: UTF8.self)))
        lastDeliveredSequence = event.sequence
      }
    }

    return router
  }

  static func response(
    for request: Request,
    api: SymphonyHTTPAPI
  ) throws -> Response {
    let response = try api.respond(
      to: SymphonyAPIRequest(
        method: request.method.rawValue,
        path: request.uri.string
      )
    )

    return Response(
      status: status(for: response.statusCode),
      headers: httpFields(from: response.headers),
      body: .init(byteBuffer: ByteBuffer(bytes: response.body))
    )
  }

  static func httpFields(from headers: [String: String]) -> HTTPFields {
    var httpFields = HTTPFields()
    for header in headers.sorted(by: { $0.key < $1.key }).compactMap({ name, value in
      HTTPField.Name(name).map { HTTPField(name: $0, value: value) }
    }) {
      httpFields.append(header)
    }
    return httpFields
  }

  static func status(for statusCode: Int) -> HTTPResponse.Status {
    HTTPResponse.Status(code: statusCode)
  }

  static func sessionID(query: String?) -> SessionID? {
    queryValue(named: "session_id", in: query).map(SessionID.init)
  }

  static func cursor(query: String?) -> EventCursor? {
    queryValue(named: "cursor", in: query).map(EventCursor.init(rawValue:))
  }

  static func queryValue(named name: String, in query: String?) -> String? {
    guard let query else {
      return nil
    }

    var components = URLComponents()
    components.percentEncodedQuery = query
    return components.queryItems?.first(where: { $0.name == name })?.value
  }

  static func makeEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return encoder
  }

  private static let supportedMethods: [HTTPRequest.Method] = [
    .get,
    .post,
    .put,
    .patch,
    .delete,
    .head,
  ]
}
