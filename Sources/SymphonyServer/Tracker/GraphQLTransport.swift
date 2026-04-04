import Foundation

// MARK: - GraphQL Transport Protocol

/// Abstraction over HTTP transport for testability.
public protocol GraphQLTransporting: Sendable {
  func execute(query: String, variables: [String: Any]?) async throws -> Data
}

// MARK: - GitHub Tracker Error

public enum GitHubTrackerError: Error, Equatable, Sendable {
  case invalidEndpoint(String)
  case missingAPIKey
  case requestFailed(statusCode: Int, body: String)
  case decodingFailed(String)
  case unexpectedResponseStructure(String)
}

// MARK: - URLSession GraphQL Transport

// SAFETY: @unchecked Sendable — all stored fields are immutable (`let`).
public final class URLSessionGraphQLTransport: GraphQLTransporting, @unchecked Sendable {
  private let endpoint: URL
  private let apiKey: String
  private let session: URLSession

  public init(endpoint: URL, apiKey: String, session: URLSession = .shared) {
    self.endpoint = endpoint
    self.apiKey = apiKey
    self.session = session
  }

  public func execute(query: String, variables: [String: Any]?) async throws -> Data {
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("bearer \(apiKey)", forHTTPHeaderField: "Authorization")

    var body: [String: Any] = ["query": query]
    if let variables { body["variables"] = variables }

    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (data, response) = try await session.data(for: request)

    if let httpResponse = response as? HTTPURLResponse,
      !(200..<300).contains(httpResponse.statusCode)
    {
      let bodyText = String(data: data, encoding: .utf8) ?? "<non-utf8>"
      throw GitHubTrackerError.requestFailed(
        statusCode: httpResponse.statusCode, body: bodyText)
    }

    return data
  }
}
