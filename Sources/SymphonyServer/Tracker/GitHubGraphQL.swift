import Foundation

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
