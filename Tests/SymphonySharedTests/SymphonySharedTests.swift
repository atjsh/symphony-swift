import Foundation
import SymphonyShared
import Testing

@Test func issueIdentifierValidationAndWorkspaceKeyDerivation() throws {
  let identifier = try IssueIdentifier(validating: "atjsh/example#42")

  #expect(identifier.owner == "atjsh")
  #expect(identifier.repository == "example")
  #expect(identifier.number == 42)
  #expect(identifier.rawValue == "atjsh/example#42")
  #expect(identifier.workspaceKey.rawValue == "atjsh_example_42")

  var didThrow = false
  do {
    _ = try IssueIdentifier(validating: "not-an-identifier")
  } catch {
    didThrow = true
  }

  #expect(didThrow)
}

@Test func serverEndpointDefaultsAndURL() throws {
  let endpoint = try ServerEndpoint()

  #expect(endpoint.scheme == "http")
  #expect(endpoint.host == "localhost")
  #expect(endpoint.port == 8080)
  #expect(endpoint.url?.absoluteString == "http://localhost:8080")
}

@Test func issueLabelsNormalizeToLowercaseOnDecode() throws {
  let json = """
    {
      "id": "issue-1",
      "identifier": "atjsh/example#42",
      "repository": "atjsh/example",
      "number": 42,
      "title": "Implement feature",
      "description": null,
      "priority": null,
      "state": "In Progress",
      "issue_state": "OPEN",
      "project_item_id": null,
      "url": null,
      "labels": ["Bug", "FIXME", "MiXeD-Case"],
      "blocked_by": [],
      "created_at": null,
      "updated_at": null
    }
    """

  let issue = try JSONDecoder().decode(Issue.self, from: Data(json.utf8))

  #expect(issue.labels == ["bug", "fixme", "mixed-case"])
}

@Test func tokenUsageSupportsDerivedAndPartialTotals() throws {
  let derived = try TokenUsage(inputTokens: 7, outputTokens: 5)
  #expect(derived.inputTokens == 7)
  #expect(derived.outputTokens == 5)
  #expect(derived.totalTokens == 12)

  let partial = try TokenUsage(totalTokens: 13)
  #expect(partial.inputTokens == nil)
  #expect(partial.outputTokens == nil)
  #expect(partial.totalTokens == 13)

  var didThrow = false
  do {
    _ = try TokenUsage(inputTokens: 7, outputTokens: 5, totalTokens: 13)
  } catch {
    didThrow = true
  }

  #expect(didThrow)
}

@Test func agentRawEventPreservesRawJSONThroughCodableRoundTrip() throws {
  let rawJSON =
    #"{"timestamp":"2026-03-24T12:00:01Z","type":"session_meta","payload":{"message":"hello","count":1}}"#
  let event = AgentRawEvent(
    sessionID: SessionID("session-7"),
    provider: "codex",
    sequence: EventSequence(1),
    timestamp: "2026-03-24T12:00:01Z",
    rawJSON: rawJSON,
    providerEventType: "session_meta",
    normalizedEventKind: "status"
  )

  let data = try JSONEncoder().encode(event)
  let decoded = try JSONDecoder().decode(AgentRawEvent.self, from: data)

  #expect(decoded.rawJSON == rawJSON)
  #expect(decoded.sessionID.rawValue == "session-7")
  #expect(decoded.sequence.rawValue == 1)
}
