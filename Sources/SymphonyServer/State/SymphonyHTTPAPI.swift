import Foundation
import SymphonyShared
import SymphonyServerCore

public struct SymphonyAPIRequest: Sendable {
  public let method: String
  public let path: String
  public let headers: [String: String]
  public let body: Data

  public init(method: String, path: String, headers: [String: String] = [:], body: Data = Data()) {
    self.method = method
    self.path = path
    self.headers = headers
    self.body = body
  }
}

public struct SymphonyHTTPResponse: Sendable {
  public let statusCode: Int
  public let headers: [String: String]
  public let body: Data

  public init(statusCode: Int, headers: [String: String], body: Data) {
    self.statusCode = statusCode
    self.headers = headers
    self.body = body
  }
}

// SAFETY: @unchecked Sendable — all stored fields are immutable (`let`).
public final class SymphonyHTTPAPI: @unchecked Sendable {
  private let store: SQLiteServerStateStore
  private let version: String
  private let trackerKind: String
  private let progressReports: (any IssueProgressReportGenerating)?
  private let now: @Sendable () -> Date
  private let refresh: @Sendable () -> Void
  private let encoder: JSONEncoder

  public init(
    store: SQLiteServerStateStore,
    version: String,
    trackerKind: String,
    progressReports: (any IssueProgressReportGenerating)? = nil,
    now: (@Sendable () -> Date)? = nil,
    refresh: (@Sendable () -> Void)? = nil
  ) {
    self.store = store
    self.version = version
    self.trackerKind = trackerKind
    self.progressReports = progressReports
    self.now = now ?? Date.init
    self.refresh = refresh ?? {}
    self.encoder = JSONEncoder()
    self.encoder.outputFormatting = [.sortedKeys]
  }

  public func respond(to request: SymphonyAPIRequest) throws -> SymphonyHTTPResponse {
    let components = URLComponents(string: "http://localhost\(request.path)")!
    let path = components.path
    let method = request.method.uppercased()

    switch path {
    case "/api/v1/health":
      guard method == "GET" else {
        return try methodNotAllowed(
          message: "This endpoint only supports GET.",
          path: path,
          method: method
        )
      }
      return try ok(
        HealthResponse(
          status: "ok",
          serverTime: Self.iso8601(now()),
          version: version,
          trackerKind: trackerKind
        ))
    case "/api/v1/issues":
      guard method == "GET" else {
        return try methodNotAllowed(
          message: "This endpoint only supports GET.",
          path: path,
          method: method
        )
      }
      return try ok(IssuesResponse(items: store.issues()))
    case "/api/v1/refresh":
      guard method == "POST" else {
        return try methodNotAllowed(
          message: "This endpoint only supports POST.",
          path: path,
          method: method
        )
      }
      refresh()
      return try response(
        statusCode: 202, value: RefreshResponse(queued: true, requestedAt: Self.iso8601(now())))
    default:
      break
    }

    if path.hasPrefix("/api/v1/issues/"), path.hasSuffix("/progress-report") {
      guard method == "GET" else {
        return try methodNotAllowed(
          message: "This endpoint only supports GET.",
          path: path,
          method: method
        )
      }

      let issueID = String(
        path
          .dropFirst("/api/v1/issues/".count)
          .dropLast("/progress-report".count)
      )
      guard let detail = try store.issueDetail(id: IssueID(issueID)) else {
        return try error(
          statusCode: 404,
          code: "issue_not_found",
          message: "Issue \(issueID) was not found.",
          path: path,
          method: method
        )
      }
      guard let workspacePath = detail.workspacePath, !workspacePath.isEmpty else {
        return try error(
          statusCode: 409,
          code: "workspace_unavailable",
          message: "Issue \(issueID) does not have an available workspace.",
          path: path,
          method: method
        )
      }
      guard let progressReports else {
        return try error(
          statusCode: 503,
          code: "repository_history_unavailable",
          message: "Issue \(issueID) progress reports are unavailable on this server.",
          path: path,
          method: method
        )
      }

      do {
        let report = try progressReports.issueProgressReport(
          issueID: IssueID(issueID),
          workspacePath: workspacePath
        )
        return try ok(report)
      } catch let progressReportError as IssueProgressReportError {
        switch progressReportError {
        case .workspaceUnavailable:
          return try error(
            statusCode: 409,
            code: "workspace_unavailable",
            message: "Issue \(issueID) does not have an available workspace.",
            path: path,
            method: method
          )
        case .repositoryHistoryUnavailable(let message):
          return try error(
            statusCode: 503,
            code: "repository_history_unavailable",
            message: message,
            path: path,
            method: method
          )
        }
      }
    }

    if path.hasPrefix("/api/v1/issues/") {
      guard method == "GET" else {
        return try methodNotAllowed(
          message: "This endpoint only supports GET.",
          path: path,
          method: method
        )
      }
      let issueID = String(path.dropFirst("/api/v1/issues/".count))
      guard let detail = try store.issueDetail(id: IssueID(issueID)) else {
        return try error(
          statusCode: 404,
          code: "issue_not_found",
          message: "Issue \(issueID) was not found.",
          path: path,
          method: method
        )
      }
      return try ok(detail)
    }

    if path.hasPrefix("/api/v1/runs/") {
      guard method == "GET" else {
        return try methodNotAllowed(
          message: "This endpoint only supports GET.",
          path: path,
          method: method
        )
      }
      let runID = String(path.dropFirst("/api/v1/runs/".count))
      guard let detail = try store.runDetail(id: RunID(runID)) else {
        return try error(
          statusCode: 404,
          code: "run_not_found",
          message: "Run \(runID) was not found.",
          path: path,
          method: method
        )
      }
      return try ok(detail)
    }

    if path.hasPrefix("/api/v1/logs/") {
      guard method == "GET" else {
        return try methodNotAllowed(
          message: "This endpoint only supports GET.",
          path: path,
          method: method
        )
      }
      let sessionID = SessionID(String(path.dropFirst("/api/v1/logs/".count)))
      let queryItems = components.queryItems ?? []
      let cursorValue = queryItems.first(where: { $0.name == "cursor" })?.value
      let cursor = cursorValue.map(EventCursor.init(rawValue:))
      let limitValue = queryItems.first(where: { $0.name == "limit" })?.value
      let limit = limitValue.flatMap(Int.init) ?? 50
      guard let logs = try store.logs(sessionID: sessionID, cursor: cursor, limit: limit) else {
        return try error(
          statusCode: 404,
          code: "session_not_found",
          message: "Session \(sessionID.rawValue) was not found.",
          path: path,
          method: method
        )
      }
      return try ok(logs)
    }

    if path.hasPrefix("/api/v1/issues") || path.hasPrefix("/api/v1/runs")
      || path.hasPrefix("/api/v1/logs")
    {
      return try error(
        statusCode: 405,
        code: "method_not_allowed",
        message: "This endpoint does not support \(method).",
        path: path,
        method: method
      )
    }

    return try error(
      statusCode: 404,
      code: "not_found",
      message: "The requested endpoint does not exist.",
      path: path,
      method: method
    )
  }

  private func ok<T: Encodable>(_ value: T) throws -> SymphonyHTTPResponse {
    try response(statusCode: 200, value: value)
  }

  private func methodNotAllowed(message: String, path: String, method: String) throws
    -> SymphonyHTTPResponse
  {
    try error(
      statusCode: 405,
      code: "method_not_allowed",
      message: message,
      path: path,
      method: method
    )
  }

  private func error(
    statusCode: Int,
    code: String,
    message: String,
    path: String,
    method: String
  ) throws -> SymphonyHTTPResponse {
    RuntimeLogger.log(
      level: statusCode >= 500 ? .error : .warning,
      event: "http_api_error_response",
      context: RuntimeLogContext(
        metadata: [
          "status_code": String(statusCode),
          "code": code,
          "path": path,
          "method": method,
        ]
      ),
      error: message
    )
    return try response(
      statusCode: statusCode,
      value: ErrorEnvelope(error: ErrorPayload(code: code, message: message)))
  }

  private func response<T: Encodable>(statusCode: Int, value: T) throws -> SymphonyHTTPResponse {
    SymphonyHTTPResponse(
      statusCode: statusCode,
      headers: ["Content-Type": "application/json; charset=utf-8"],
      body: try encoder.encode(value)
    )
  }

  private static func iso8601(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.string(from: date)
  }
}
