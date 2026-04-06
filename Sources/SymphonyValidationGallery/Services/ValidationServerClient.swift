import Foundation
import SymphonyXcodeValidationServerCore

/// Protocol for connecting to the Xcode validation server.
public protocol ValidationServerConnecting: Sendable {
  func startRun(_ request: StartRunRequest) async throws -> RunID
  func pollStatus(_ runID: RunID, afterLine: Int?) async throws -> RunStatusResponse
  func fetchSummary(_ runID: RunID) async throws -> RunSummaryResponse
  func cancelRun(_ runID: RunID) async throws
  func healthCheck() async throws -> Bool
}

/// Default URLSession-based client for the validation server.
public struct URLSessionValidationServerClient: ValidationServerConnecting {
  private let baseURL: URL
  private let session: URLSession
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  public init(baseURL: URL, session: URLSession = .shared) {
    self.baseURL = baseURL
    self.session = session
    self.encoder = JSONEncoder()
    self.decoder = JSONDecoder()
    self.decoder.dateDecodingStrategy = .iso8601
    self.encoder.dateEncodingStrategy = .iso8601
  }

  public func startRun(_ request: StartRunRequest) async throws -> RunID {
    let url = baseURL.appendingPathComponent("api/v1/runs")
    var urlRequest = URLRequest(url: url)
    urlRequest.httpMethod = "POST"
    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    urlRequest.httpBody = try encoder.encode(request)

    let (data, response) = try await session.data(for: urlRequest)
    let httpResponse = response as? HTTPURLResponse
    if httpResponse?.statusCode == 409 {
      throw ValidationServerClientError.runAlreadyActive
    }
    guard httpResponse?.statusCode == 200 else {
      throw ValidationServerClientError.unexpectedStatus(httpResponse?.statusCode ?? 0)
    }

    let startResponse = try decoder.decode(StartRunResponse.self, from: data)
    return startResponse.runID
  }

  public func pollStatus(_ runID: RunID, afterLine: Int?) async throws -> RunStatusResponse {
    var components = URLComponents(
      url: baseURL.appendingPathComponent("api/v1/runs/\(runID.rawValue)"),
      resolvingAgainstBaseURL: false
    )
    if let afterLine {
      components?.queryItems = [URLQueryItem(name: "after_line", value: String(afterLine))]
    }
    guard let url = components?.url else {
      throw ValidationServerClientError.invalidURL
    }

    let (data, response) = try await session.data(from: url)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
      throw ValidationServerClientError.unexpectedStatus(
        (response as? HTTPURLResponse)?.statusCode ?? 0
      )
    }

    return try decoder.decode(RunStatusResponse.self, from: data)
  }

  public func fetchSummary(_ runID: RunID) async throws -> RunSummaryResponse {
    let url = baseURL.appendingPathComponent("api/v1/runs/\(runID.rawValue)/summary")
    let (data, response) = try await session.data(from: url)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
      throw ValidationServerClientError.unexpectedStatus(
        (response as? HTTPURLResponse)?.statusCode ?? 0
      )
    }
    return try decoder.decode(RunSummaryResponse.self, from: data)
  }

  public func cancelRun(_ runID: RunID) async throws {
    let url = baseURL.appendingPathComponent("api/v1/runs/\(runID.rawValue)")
    var urlRequest = URLRequest(url: url)
    urlRequest.httpMethod = "DELETE"
    let (_, response) = try await session.data(for: urlRequest)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
      throw ValidationServerClientError.unexpectedStatus(
        (response as? HTTPURLResponse)?.statusCode ?? 0
      )
    }
  }

  public func healthCheck() async throws -> Bool {
    let url = baseURL.appendingPathComponent("api/v1/health")
    let (data, response) = try await session.data(from: url)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
      return false
    }
    let health = try decoder.decode(ValidationServerHealthResponse.self, from: data)
    return health.status == "ok"
  }
}

/// Errors from the validation server client.
public enum ValidationServerClientError: Error, Sendable {
  case runAlreadyActive
  case unexpectedStatus(Int)
  case invalidURL
}
