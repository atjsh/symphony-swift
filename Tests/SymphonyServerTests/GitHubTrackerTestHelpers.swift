import Foundation
import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore
@testable import SymphonyShared

func makeTrackerConfig(
  projectOwner: String = "test-owner",
  projectOwnerType: String = "organization",
  projectNumber: Int = 1,
  activeStates: [String] = ["Todo", "In Progress"],
  terminalStates: [String] = ["Done"],
  repositoryAllowlist: [String] = []
) -> TrackerConfig {
  TrackerConfig(
    kind: "github",
    projectOwner: projectOwner,
    projectOwnerType: projectOwnerType,
    projectNumber: projectNumber,
    repositoryAllowlist: repositoryAllowlist,
    activeStates: activeStates,
    terminalStates: terminalStates
  )
}

func projectIDResponse(id: String = "PVT_TEST") -> String {
  """
  {"data":{"organization":{"projectV2":{"id":"\(id)"}}}}
  """
}

func userProjectIDResponse(id: String = "PVT_USER") -> String {
  """
  {"data":{"user":{"projectV2":{"id":"\(id)"}}}}
  """
}

func candidateItemsResponse(
  items: [(id: String, number: Int, title: String, repo: String, status: String)],
  hasNextPage: Bool = false,
  endCursor: String? = nil
) -> String {
  let nodes = items.map { item in
    """
    {
      "id": "PVTI_\(item.id)",
      "content": {
        "__typename": "Issue",
        "id": "\(item.id)",
        "number": \(item.number),
        "title": "\(item.title)",
        "body": "Description for \(item.title)",
        "state": "OPEN",
        "url": "https://github.com/\(item.repo)/issues/\(item.number)",
        "createdAt": "2026-01-01T00:00:00Z",
        "updatedAt": "2026-01-02T00:00:00Z",
        "labels": {"nodes": [{"name": "bug"}]},
        "repository": {"nameWithOwner": "\(item.repo)"},
        "trackedInIssues": {"nodes": []}
      },
      "fieldValueByName": {"name": "\(item.status)"}
    }
    """
  }
  let cursor = endCursor.map { #""endCursor": "\#($0)""# } ?? #""endCursor": null"#
  return """
    {
      "data": {
        "node": {
          "items": {
            "nodes": [\(nodes.joined(separator: ","))],
            "pageInfo": {"hasNextPage": \(hasNextPage), \(cursor)}
          }
        }
      }
    }
    """
}
