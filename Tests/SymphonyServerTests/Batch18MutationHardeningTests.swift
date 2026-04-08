// Batch 18 – Mutation hardening for ProviderJSONMessage, GitHubGraphQL,
// CodexTimeoutMonitor, BootstrapServerEndpoint URL/displayString.

import Foundation
import Synchronization
import Testing
@testable import SymphonyServer
@testable import SymphonyServerCore
import SymphonyShared

// MARK: - ProviderJSONMessage Single-Key Access

@Suite("ProviderJSONMessage Single-Key Access")
struct ProviderJSONMessageSingleKeyTests {

  @Test func paramsStringSingleKeyReturnsLeafValue() {
    let msg = ProviderJSONMessage.parse(#"{"params":{"status":"active"}}"#)!
    #expect(msg.paramsString("status") == "active")
  }

  @Test func paramsStringMissingKeyReturnsNil() {
    let msg = ProviderJSONMessage.parse(#"{"params":{"status":"active"}}"#)!
    #expect(msg.paramsString("missing") == nil)
  }

  @Test func resultStringSingleKeyReturnsLeafValue() {
    let msg = ProviderJSONMessage.parse(#"{"result":{"outcome":"success"}}"#)!
    #expect(msg.resultString("outcome") == "success")
  }

  @Test func resultStringMissingKeyReturnsNil() {
    let msg = ProviderJSONMessage.parse(#"{"result":{"outcome":"success"}}"#)!
    #expect(msg.resultString("missing") == nil)
  }

  @Test func paramsStringNilParamsReturnsNil() {
    let msg = ProviderJSONMessage.parse(#"{"method":"test"}"#)!
    #expect(msg.paramsString("anything") == nil)
  }
}

// MARK: - ProviderJSONMessage Nested Access Edge Cases

@Suite("ProviderJSONMessage Nested Access")
struct ProviderJSONMessageNestedAccessTests {

  @Test func twoKeyPathReturnsNestedValue() {
    let msg = ProviderJSONMessage.parse(
      #"{"params":{"turn":{"id":"turn-42"}}}"#)!
    #expect(msg.paramsString("turn", "id") == "turn-42")
  }

  @Test func intermediateNonObjectReturnsNil() {
    // "turn" is a string, not an object → objectValue guard fails → nil
    let msg = ProviderJSONMessage.parse(
      #"{"params":{"turn":"not-an-object"}}"#)!
    #expect(msg.paramsString("turn", "id") == nil)
  }

  @Test func intermediateNullValueReturnsNil() {
    let msg = ProviderJSONMessage.parse(
      #"{"params":{"turn":null}}"#)!
    #expect(msg.paramsString("turn", "id") == nil)
  }

  @Test func paramsObjectReturnsNestedDict() {
    let msg = ProviderJSONMessage.parse(
      #"{"params":{"meta":{"key":"val"}}}"#)!
    let obj = msg.paramsObject("meta")
    #expect(obj?["key"]?.stringValue == "val")
  }

  @Test func paramsObjectMissingKeyReturnsNil() {
    let msg = ProviderJSONMessage.parse(#"{"params":{"meta":"string"}}"#)!
    #expect(msg.paramsObject("meta") == nil, "String is not an object")
  }

  @Test func resultObjectReturnsNestedDict() {
    let msg = ProviderJSONMessage.parse(
      #"{"result":{"data":{"count":5}}}"#)!
    let obj = msg.resultObject("data")
    #expect(obj?["count"]?.intValue == 5)
  }

  @Test func resultObjectNilResultReturnsNil() {
    let msg = ProviderJSONMessage.parse(#"{"method":"test"}"#)!
    #expect(msg.resultObject("anything") == nil)
  }
}

// MARK: - ProviderJSONMessage Serialization

@Suite("ProviderJSONMessage Serialization")
struct ProviderJSONMessageSerializationTests {

  @Test func toDataRoundTrips() throws {
    let msg = ProviderJSONMessage.parse(
      #"{"method":"notify","params":{"status":"done"}}"#)!
    let data = try msg.toData()
    let decoded = ProviderJSONMessage.parse(data: data)
    #expect(decoded?.method == "notify")
    #expect(decoded?.paramsString("status") == "done")
  }

  @Test func parseFromDataReturnsNilForNonObject() {
    let data = "[1,2,3]".data(using: .utf8)!
    #expect(ProviderJSONMessage.parse(data: data) == nil)
  }

  @Test func parseFromInvalidStringReturnsNil() {
    #expect(ProviderJSONMessage.parse("not json") == nil)
  }
}

// MARK: - GitHubGraphQL Empty IDs

@Suite("GitHubGraphQL Edge Cases")
struct GitHubGraphQLEdgeCaseTests {

  @Test func issueStatesByIDsQueryWithEmptyArrayProducesValidQuery() {
    let (query, variables) = GitHubGraphQL.issueStatesByIDsQuery(issueIDs: [])
    #expect(query.contains("query"))
    #expect((variables as [String: Any]).isEmpty)
    // Should not contain any issue fragments
    #expect(!query.contains("issue0"))
  }

  @Test func issueStatesByIDsQuerySingleIDProducesOneFragment() {
    let (query, _) = GitHubGraphQL.issueStatesByIDsQuery(issueIDs: ["I_abc"])
    #expect(query.contains("issue0"))
    #expect(query.contains("I_abc"))
    #expect(!query.contains("issue1"))
  }

  @Test func projectItemsQueryIncludesAllRequiredFields() {
    let (query, _) = GitHubGraphQL.projectItemsQuery(
      projectID: "PVT_1", statusFieldName: "MyStatus", cursor: nil)
    #expect(query.contains("title"))
    #expect(query.contains("body"))
    #expect(query.contains("state"))
    #expect(query.contains("labels"))
    #expect(query.contains("trackedInIssues"))
    #expect(query.contains("pageInfo"))
    #expect(query.contains("hasNextPage"))
    #expect(query.contains("endCursor"))
    #expect(query.contains(#"fieldValueByName(name: "MyStatus")"#))
  }
}

// MARK: - CodexTimeoutMonitor Zero/Negative Guard

@Suite("CodexTimeoutMonitor Threshold Guard")
struct CodexTimeoutMonitorThresholdTests {

  @Test func zeroReadTimeoutDoesNotSchedule() async throws {
    let monitor = CodexTimeoutMonitor()
    let errorFired = Mutex(false)
    let process = StubLaunchedProcess()

    monitor.startReadTimeout(
      sessionID: SessionID("s-zero"),
      readTimeoutMS: 0,
      process: process,
      finish: { _ in errorFired.withLock { $0 = true } }
    )

    // Give time for potential Task to fire
    try await Task.sleep(nanoseconds: 50_000_000)
    #expect(!errorFired.withLock { $0 }, "Zero timeout must not fire")
  }

  @Test func negativeReadTimeoutDoesNotSchedule() async throws {
    let monitor = CodexTimeoutMonitor()
    let errorFired = Mutex(false)
    let process = StubLaunchedProcess()

    monitor.startReadTimeout(
      sessionID: SessionID("s-neg"),
      readTimeoutMS: -100,
      process: process,
      finish: { _ in errorFired.withLock { $0 = true } }
    )

    try await Task.sleep(nanoseconds: 50_000_000)
    #expect(!errorFired.withLock { $0 }, "Negative timeout must not fire")
  }

  @Test func cancelReadTimeoutPreventsCallback() async throws {
    let monitor = CodexTimeoutMonitor()
    let errorFired = Mutex(false)
    let process = StubLaunchedProcess()

    monitor.startReadTimeout(
      sessionID: SessionID("s-cancel"),
      readTimeoutMS: 100,
      process: process,
      finish: { _ in errorFired.withLock { $0 = true } }
    )
    monitor.cancelReadTimeout()

    try await Task.sleep(nanoseconds: 200_000_000)
    #expect(!errorFired.withLock { $0 }, "Cancelled timeout must not fire")
  }
}

// MARK: - BootstrapServerEndpoint URL and DisplayString

@Suite("BootstrapServerEndpoint URL")
struct BootstrapServerEndpointURLTests {

  @Test func urlProducesValidComponents() {
    let endpoint = BootstrapServerEndpoint(scheme: "http", host: "127.0.0.1", port: 8080)
    let url = endpoint.url
    #expect(url != nil)
    #expect(url?.scheme == "http")
    #expect(url?.host == "127.0.0.1")
    #expect(url?.port == 8080)
  }

  @Test func displayStringMatchesURL() {
    let endpoint = BootstrapServerEndpoint(scheme: "http", host: "localhost", port: 3000)
    #expect(endpoint.displayString == "http://localhost:3000")
  }

  @Test func descriptionMatchesDisplayString() {
    let endpoint = BootstrapServerEndpoint(scheme: "https", host: "example.com", port: 443)
    #expect(endpoint.description == endpoint.displayString)
  }

  @Test func defaultEndpointIsHTTPLocalhost8080() {
    let d = BootstrapServerEndpoint.defaultEndpoint
    #expect(d.scheme == "http")
    #expect(d.host == "127.0.0.1")
    #expect(d.port == 8080)
  }

  @Test func serverEndpointConversion() {
    let endpoint = BootstrapServerEndpoint(scheme: "https", host: "example.com", port: 9090)
    let se = endpoint.serverEndpoint
    #expect(se.scheme == "https")
    #expect(se.host == "example.com")
    #expect(se.port == 9090)
  }

  @Test func equalityCheckWorks() {
    let a = BootstrapServerEndpoint(scheme: "http", host: "localhost", port: 8080)
    let b = BootstrapServerEndpoint(scheme: "http", host: "localhost", port: 8080)
    let c = BootstrapServerEndpoint(scheme: "https", host: "localhost", port: 8080)
    #expect(a == b)
    #expect(a != c)
  }
}

// MARK: - CodexSessionState Sequence Counter

@Suite("CodexSessionState Sequence Counter")
struct CodexSessionStateSequenceTests {

  @Test func sequenceIncrementsFromZero() {
    let state = CodexSessionState()
    let s1 = state.nextSequence()
    let s2 = state.nextSequence()
    #expect(s1.rawValue == 0)
    #expect(s2.rawValue == 1)
  }
}

// MARK: - ProviderJSONMessage Fields

@Suite("ProviderJSONMessage Field Access")
struct ProviderJSONMessageFieldTests {

  @Test func allFieldsDecodedCorrectly() {
    let json = """
      {
        "id": 42,
        "method": "update",
        "type": "message",
        "event": "output",
        "error": {"code": -1, "message": "fail"},
        "params": {"key": "val"},
        "result": {"data": "ok"}
      }
      """
    let msg = ProviderJSONMessage.parse(json)!
    #expect(msg.id?.intValue == 42)
    #expect(msg.method == "update")
    #expect(msg.type == "message")
    #expect(msg.event == "output")
    #expect(msg.error != nil)
    #expect(msg.paramsString("key") == "val")
    #expect(msg.resultString("data") == "ok")
  }

  @Test func minimalMessageDecodesSuccessfully() {
    let msg = ProviderJSONMessage.parse("{}")!
    #expect(msg.id == nil)
    #expect(msg.method == nil)
    #expect(msg.type == nil)
    #expect(msg.event == nil)
    #expect(msg.error == nil)
  }
}
