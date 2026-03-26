import Foundation
import SymphonyShared

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

// MARK: - GitHub GraphQL Response Types

enum GitHubGraphQL {
  struct Response: Decodable {
    let data: ResponseData?
    let errors: [GraphQLError]?
  }

  struct GraphQLError: Decodable {
    let message: String
  }

  struct ResponseData: Decodable {
    let node: ProjectNode?
  }

  struct ProjectNode: Decodable {
    let items: ItemConnection
  }

  struct ItemConnection: Decodable {
    let nodes: [ProjectItem]
    let pageInfo: PageInfo
  }

  struct PageInfo: Decodable {
    let hasNextPage: Bool
    let endCursor: String?
  }

  struct ProjectItem: Decodable {
    let id: String
    let content: ItemContent?
    let fieldValueByName: FieldValue?
  }

  struct ItemContent: Decodable {
    let typename: String
    let id: String?
    let number: Int?
    let title: String?
    let body: String?
    let state: String?
    let url: String?
    let createdAt: String?
    let updatedAt: String?
    let labels: LabelConnection?
    let repository: RepositoryRef?
    let trackedInIssues: TrackedIssuesConnection?

    private enum CodingKeys: String, CodingKey {
      case typename = "__typename"
      case id, number, title, body, state, url, createdAt, updatedAt, labels
      case repository, trackedInIssues
    }
  }

  struct LabelConnection: Decodable {
    let nodes: [LabelNode]
  }

  struct LabelNode: Decodable {
    let name: String
  }

  struct RepositoryRef: Decodable {
    let nameWithOwner: String
  }

  struct TrackedIssuesConnection: Decodable {
    let nodes: [TrackedIssue]
  }

  struct TrackedIssue: Decodable {
    let id: String
    let number: Int
    let state: String
    let repository: RepositoryRef
  }

  struct FieldValue: Decodable {
    let name: String?
  }

  // MARK: - Query Construction

  static func projectItemsQuery(
    projectID: String,
    statusFieldName: String,
    cursor: String?
  ) -> (query: String, variables: [String: Any]) {
    let afterClause = cursor.map { ", after: \"\($0)\"" } ?? ""
    let query = """
      query($projectId: ID!) {
        node(id: $projectId) {
          ... on ProjectV2 {
            items(first: 100\(afterClause)) {
              nodes {
                id
                content {
                  __typename
                  ... on Issue {
                    id
                    number
                    title
                    body
                    state
                    url
                    createdAt
                    updatedAt
                    labels(first: 20) { nodes { name } }
                    repository { nameWithOwner }
                    trackedInIssues(first: 10) {
                      nodes {
                        id
                        number
                        state
                        repository { nameWithOwner }
                      }
                    }
                  }
                  ... on PullRequest { id }
                  ... on DraftIssue { id }
                }
                fieldValueByName(name: "\(statusFieldName)") {
                  ... on ProjectV2ItemFieldSingleSelectValue { name }
                }
              }
              pageInfo { hasNextPage endCursor }
            }
          }
        }
      }
      """
    return (query: query, variables: ["projectId": projectID])
  }

  static func issueStatesByIDsQuery(issueIDs: [String]) -> (query: String, variables: [String: Any])
  {
    var fragments: [String] = []
    var index = 0
    for id in issueIDs {
      fragments.append(
        """
          issue\(index): node(id: "\(id)") {
            ... on Issue { id state }
            ... on ProjectV2Item {
              content { ... on Issue { id state } }
            }
          }
        """)
      index += 1
    }
    let query = "query { \(fragments.joined(separator: "\n")) }"
    return (query: query, variables: [:])
  }
}

// MARK: - GitHub Tracker Adapter

public final class GitHubTrackerAdapter: TrackerAdapting, @unchecked Sendable {
  private let transport: any GraphQLTransporting
  private let config: TrackerConfig
  private let lock = NSLock()
  private var _projectID: String?

  public init(transport: any GraphQLTransporting, config: TrackerConfig) {
    self.transport = transport
    self.config = config
  }

  // MARK: - TrackerAdapting

  public func fetchAllIssues() async throws -> [Issue] {
    try await normalizeProjectItems(allowedStates: nil)
  }

  public func fetchCandidateIssues() async throws -> [Issue] {
    try await normalizeProjectItems(allowedStates: Set(config.activeStates))
  }

  public func fetchIssuesByStates(_ stateNames: [String]) async throws -> [Issue] {
    try await normalizeProjectItems(allowedStates: Set(stateNames))
  }

  private func normalizeProjectItems(
    allowedStates: Set<String>?
  ) async throws -> [Issue] {
    let projectID = try await resolveProjectID()
    var allItems: [GitHubGraphQL.ProjectItem] = []
    var cursor: String?

    repeat {
      let (query, variables) = GitHubGraphQL.projectItemsQuery(
        projectID: projectID,
        statusFieldName: config.statusFieldName,
        cursor: cursor
      )
      let data = try await transport.execute(query: query, variables: variables)
      let response = try decodeResponse(data)

      guard let project = response.data?.node else {
        throw GitHubTrackerError.unexpectedResponseStructure("Missing project node")
      }

      allItems.append(contentsOf: project.items.nodes)

      if project.items.pageInfo.hasNextPage {
        cursor = project.items.pageInfo.endCursor
      } else {
        cursor = nil
      }
    } while cursor != nil

    return normalizeItems(allItems, allowedStates: allowedStates)
  }

  public func fetchIssueStatesByIDs(_ issueIDs: [IssueID]) async throws -> [IssueID: String] {
    guard !issueIDs.isEmpty else { return [:] }

    let rawIDs = issueIDs.map(\.rawValue)
    let (query, variables) = GitHubGraphQL.issueStatesByIDsQuery(issueIDs: rawIDs)
    let data = try await transport.execute(query: query, variables: variables)

    let json: [String: Any]
    let dataObj: [String: Any]
    do {
      guard
        let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any],
        let parsedData = parsed["data"] as? [String: Any]
      else {
        throw GitHubTrackerError.unexpectedResponseStructure("Cannot parse state response")
      }
      json = parsed
      dataObj = parsedData
    } catch let error as GitHubTrackerError {
      throw error
    } catch {
      throw GitHubTrackerError.decodingFailed(error.localizedDescription)
    }
    _ = json

    var result: [IssueID: String] = [:]
    for (_, value) in dataObj {
      guard let node = value as? [String: Any] else { continue }

      if let id = node["id"] as? String, let state = node["state"] as? String {
        result[IssueID(id)] = state
      } else if let content = node["content"] as? [String: Any],
        let id = content["id"] as? String,
        let state = content["state"] as? String
      {
        result[IssueID(id)] = state
      }
    }

    return result
  }

  // MARK: - Project ID Resolution

  private func resolveProjectID() async throws -> String {
    if let cached = lock.withLock({ _projectID }) {
      return cached
    }

    guard let projectOwner = config.projectOwner,
      let projectOwnerType = config.projectOwnerType,
      let projectNumber = config.projectNumber
    else {
      throw GitHubTrackerError.unexpectedResponseStructure(
        "Missing project owner/type/number in tracker config")
    }

    let ownerFragment: String
    if projectOwnerType == "organization" {
      ownerFragment = "organization(login: \"\(projectOwner)\")"
    } else {
      ownerFragment = "user(login: \"\(projectOwner)\")"
    }

    let query = """
      query {
        \(ownerFragment) {
          projectV2(number: \(projectNumber)) {
            id
          }
        }
      }
      """

    let data = try await transport.execute(query: query, variables: nil)
    guard
      let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let dataObj = json["data"] as? [String: Any]
    else {
      throw GitHubTrackerError.unexpectedResponseStructure("Cannot parse project ID response")
    }

    let ownerKey = projectOwnerType == "organization" ? "organization" : "user"
    guard
      let ownerObj = dataObj[ownerKey] as? [String: Any],
      let projectObj = ownerObj["projectV2"] as? [String: Any],
      let projectID = projectObj["id"] as? String
    else {
      throw GitHubTrackerError.unexpectedResponseStructure(
        "Cannot find projectV2.id in response")
    }

    lock.withLock { _projectID = projectID }
    return projectID
  }

  // MARK: - Normalization

  private func normalizeItems(
    _ items: [GitHubGraphQL.ProjectItem],
    allowedStates: Set<String>?
  ) -> [Issue] {
    return items.compactMap { item -> Issue? in
      guard let content = item.content else { return nil }

      // Exclude pull requests and draft issues
      guard content.typename == "Issue" else { return nil }

      guard let issueID = content.id,
        let number = content.number,
        let title = content.title,
        let repository = content.repository?.nameWithOwner
      else { return nil }

      // Repository allowlist check
      let allowlist = config.repositoryAllowlist
      if !allowlist.isEmpty {
        guard allowlist.contains(repository) else { return nil }
      }

      let projectStatus = item.fieldValueByName?.name ?? ""

      // Filter by allowed states
      if let allowedStates, !allowedStates.contains(projectStatus) {
        return nil
      }

      let identifier: IssueIdentifier
      do {
        identifier = try IssueIdentifier(validating: "\(repository)#\(number)")
      } catch {
        return nil
      }

      let labels = content.labels?.nodes.map(\.name) ?? []
      let blockers = buildBlockerReferences(from: content.trackedInIssues)

      return Issue(
        id: IssueID(issueID),
        identifier: identifier,
        repository: repository,
        number: number,
        title: title,
        description: content.body,
        priority: nil,
        state: projectStatus,
        issueState: content.state ?? "OPEN",
        projectItemID: item.id,
        url: content.url,
        labels: labels,
        blockedBy: blockers,
        createdAt: content.createdAt,
        updatedAt: content.updatedAt
      )
    }
  }

  private func buildBlockerReferences(
    from connection: GitHubGraphQL.TrackedIssuesConnection?
  ) -> [BlockerReference] {
    guard let nodes = connection?.nodes else { return [] }
    return nodes.compactMap { tracked -> BlockerReference? in
      let repo = tracked.repository.nameWithOwner
      let identifier: IssueIdentifier
      do {
        identifier = try IssueIdentifier(validating: "\(repo)#\(tracked.number)")
      } catch {
        return nil
      }

      return BlockerReference(
        issueID: IssueID(tracked.id),
        identifier: identifier,
        state: "",
        issueState: tracked.state,
        url: nil
      )
    }
  }

  // MARK: - Decoding

  private func decodeResponse(_ data: Data) throws -> GitHubGraphQL.Response {
    let decoder = JSONDecoder()
    do {
      let response = try decoder.decode(GitHubGraphQL.Response.self, from: data)
      if let errors = response.errors, !errors.isEmpty {
        throw GitHubTrackerError.decodingFailed(
          errors.map(\.message).joined(separator: "; "))
      }
      return response
    } catch let error as GitHubTrackerError {
      throw error
    } catch {
      throw GitHubTrackerError.decodingFailed(error.localizedDescription)
    }
  }
}

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
