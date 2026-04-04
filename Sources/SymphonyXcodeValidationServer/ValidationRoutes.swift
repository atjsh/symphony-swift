#if os(macOS)

import Foundation
import Hummingbird
import SymphonyXcodeValidationServerCore

/// Hummingbird route handlers for the validation server API.
struct ValidationRoutes {
  let runManager: RunManager

  func register(on router: Router<BasicRequestContext>) {
    let routes = router.group("api/v1")

    routes.get("health") { _, _ in
      let data = try JSONEncoder().encode(HealthResponse())
      return Response(
        status: .ok,
        headers: [.contentType: "application/json"],
        body: .init(byteBuffer: .init(data: data))
      )
    }

    routes.post("runs") { request, _ in
      let body = try await request.body.collect(upTo: 1_048_576)
      let startRequest = try JSONDecoder().decode(StartRunRequest.self, from: body)
      do {
        let runID = try await runManager.start(startRequest)
        let responseData = try JSONEncoder().encode(StartRunResponse(runID: runID))
        return Response(
          status: .ok,
          headers: [.contentType: "application/json"],
          body: .init(byteBuffer: .init(data: responseData))
        )
      } catch is RunManagerError {
        let errorBody = try JSONEncoder().encode(["error": "A run is already active."])
        return Response(
          status: .conflict,
          headers: [.contentType: "application/json"],
          body: .init(byteBuffer: .init(data: errorBody))
        )
      }
    }

    routes.get("runs/{id}") { request, context in
      guard let idString = context.parameters.get("id") else {
        return Response(status: .badRequest)
      }
      let runID = RunID(idString)
      let afterLine = Self.queryInt(named: "after_line", in: request.uri.query)
      let status = await runManager.status(for: runID, afterLine: afterLine)
      let encoder = JSONEncoder()
      encoder.dateEncodingStrategy = .iso8601
      let data = try encoder.encode(status)
      return Response(
        status: .ok,
        headers: [.contentType: "application/json"],
        body: .init(byteBuffer: .init(data: data))
      )
    }

    routes.get("runs/{id}/summary") { _, context in
      guard let idString = context.parameters.get("id") else {
        return Response(status: .badRequest)
      }
      let runID = RunID(idString)
      guard let summary = await runManager.summary(for: runID) else {
        return Response(status: .notFound)
      }
      let data = try JSONEncoder().encode(RunSummaryResponse(runID: runID, summary: summary))
      return Response(
        status: .ok,
        headers: [.contentType: "application/json"],
        body: .init(byteBuffer: .init(data: data))
      )
    }

    routes.delete("runs/{id}") { _, context in
      guard let idString = context.parameters.get("id") else {
        return Response(status: .badRequest)
      }
      let runID = RunID(idString)
      let cancelled = await runManager.cancel(runID)
      return Response(status: cancelled ? .ok : .notFound)
    }
  }

  // MARK: - Helpers

  private static func queryInt(named name: String, in query: String?) -> Int? {
    guard let query else { return nil }
    var components = URLComponents()
    components.percentEncodedQuery = query
    return components.queryItems?
      .first(where: { $0.name == name })?
      .value
      .flatMap(Int.init)
  }
}

#endif
