import Foundation
import SymphonyShared
import Testing

@testable import SymphonyServer

func makeIssue(
  id: String = "issue-1",
  owner: String = "org",
  repo: String = "repo",
  number: Int = 1,
  title: String = "Fix bug"
) throws -> SymphonyShared.Issue {
  SymphonyShared.Issue(
    id: IssueID(id),
    identifier: try IssueIdentifier(validating: "\(owner)/\(repo)#\(number)"),
    repository: "\(owner)/\(repo)",
    number: number,
    title: title,
    description: "Description",
    priority: nil,
    state: "In Progress",
    issueState: "OPEN",
    projectItemID: nil,
    url: "https://github.com/\(owner)/\(repo)/issues/\(number)",
    labels: [],
    blockedBy: [],
    createdAt: nil,
    updatedAt: nil
  )
}

final class ErrorCapture: @unchecked Sendable {
  private let lock = NSLock()
  private var _error: Error?

  func record(_ error: Error) {
    lock.withLock { _error = error }
  }

  var value: Error? {
    lock.withLock { _error }
  }
}

func waitForRecordedError(
  _ capture: ErrorCapture,
  attempts: Int = 100,
  intervalNanoseconds: UInt64 = 20_000_000
) async -> Error? {
  for _ in 0..<attempts {
    if let error = capture.value {
      return error
    }
    try? await Task.sleep(nanoseconds: intervalNanoseconds)
  }
  return capture.value
}

func parseJSONObject(_ rawJSON: String) throws -> [String: Any] {
  let data = try #require(rawJSON.data(using: .utf8))
  let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
  return object
}

func firstInputObject(from params: [String: Any]) throws -> [String: Any] {
  let input = try #require(params["input"] as? [Any])
  return try #require(input.first as? [String: Any])
}
