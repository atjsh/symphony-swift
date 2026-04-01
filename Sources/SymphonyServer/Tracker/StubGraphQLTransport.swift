import Foundation

// MARK: - Stub Transport (for testing)

public final class StubGraphQLTransport: GraphQLTransporting, @unchecked Sendable {
  private let lock = NSLock()
  private var _responses: [Data] = []
  private var _errors: [Error] = []
  private var _executedQueries: [(query: String, variables: [String: Any]?)] = []

  public init() {}

  public var executedQueries: [(query: String, variables: [String: Any]?)] {
    lock.withLock { _executedQueries }
  }

  public var executedQueryCount: Int {
    lock.withLock { _executedQueries.count }
  }

  public func enqueueResponse(_ data: Data) {
    lock.withLock { _responses.append(data) }
  }

  public func enqueueResponse(_ json: String) {
    let data = Data(json.utf8)
    lock.withLock { _responses.append(data) }
  }

  public func enqueueError(_ error: Error) {
    lock.withLock { _errors.append(error) }
  }

  public func execute(query: String, variables: [String: Any]?) async throws -> Data {
    let result: Result<Data, Error> = lock.withLock {
      _executedQueries.append((query: query, variables: variables))

      if !_errors.isEmpty {
        return .failure(_errors.removeFirst())
      }

      guard !_responses.isEmpty else {
        return .failure(
          GitHubTrackerError.unexpectedResponseStructure("No enqueued response"))
      }

      return .success(_responses.removeFirst())
    }

    return try result.get()
  }
}
