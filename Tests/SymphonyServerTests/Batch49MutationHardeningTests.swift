// Batch 49 — RemoveSideEffects mutation hardening.
//
// Targets the following surviving mutations:
//
// GraphQLTransport.swift — URLSessionGraphQLTransport.execute():
//   L37: RemoveSideEffects on request.setValue("application/json", forHTTPHeaderField: "Content-Type")
//   L38: RemoveSideEffects on request.setValue("bearer \(apiKey)", forHTTPHeaderField: "Authorization")
//   Also verifies httpMethod = "POST" and httpBody encoding.
//
// CodexAdapter.swift — startSession error path:
//   RemoveSideEffects on activeSessions.remove(sessionID:) in the catch block.
//   Killed by verifying cancelSession throws sessionNotFound after failed startSession.

import Foundation
import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore
@testable import SymphonyShared

// MARK: - URLSessionGraphQLTransport Request Side Effects

// SAFETY: @unchecked Sendable — URLProtocol subclass requires static mutable state
// via nonisolated(unsafe). Tests configure static properties before each request.
private struct CapturedHTTPRequest: Sendable {
  let urlRequest: URLRequest
  let bodyData: Data?
}

private final class RequestCapturingURLProtocol: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var capturedRequest: CapturedHTTPRequest?

  override static func canInit(with request: URLRequest) -> Bool { true }
  override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    // Read body from httpBodyStream because URLSession converts httpBody to a stream
    var bodyData: Data?
    if let stream = request.httpBodyStream {
      stream.open()
      var buffer = [UInt8](repeating: 0, count: 4096)
      var data = Data()
      while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count > 0 { data.append(buffer, count: count) }
        else { break }
      }
      stream.close()
      bodyData = data
    } else {
      bodyData = request.httpBody
    }
    Self.capturedRequest = CapturedHTTPRequest(urlRequest: request, bodyData: bodyData)

    let response = HTTPURLResponse(
      url: request.url!,
      statusCode: 200,
      httpVersion: "HTTP/1.1",
      headerFields: nil
    )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(#"{"ok":true}"#.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

@Suite("URLSessionGraphQLTransport Request Side Effects", .serialized)
struct URLSessionGraphQLTransportRequestSideEffectTests {

  private func makeTransport(apiKey: String = "test-api-key") -> (
    URLSessionGraphQLTransport, () -> CapturedHTTPRequest?
  ) {
    RequestCapturingURLProtocol.capturedRequest = nil
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [RequestCapturingURLProtocol.self]
    let session = URLSession(configuration: config)
    let url = URL(string: "https://api.github.com/graphql")!
    let transport = URLSessionGraphQLTransport(endpoint: url, apiKey: apiKey, session: session)
    return (transport, { RequestCapturingURLProtocol.capturedRequest })
  }

  // Kills RemoveSideEffects on L37: request.setValue("application/json", ...)
  @Test func executeRequestSetsContentTypeHeader() async throws {
    let (transport, captured) = makeTransport()
    _ = try await transport.execute(query: "{ viewer { login } }", variables: nil)

    let cap = try #require(captured())
    #expect(cap.urlRequest.value(forHTTPHeaderField: "Content-Type") == "application/json")
  }

  // Kills RemoveSideEffects on L38: request.setValue("bearer \(apiKey)", ...)
  @Test func executeRequestSetsAuthorizationHeader() async throws {
    let (transport, captured) = makeTransport(apiKey: "gh_secret_token")
    _ = try await transport.execute(query: "{ test }", variables: nil)

    let cap = try #require(captured())
    #expect(cap.urlRequest.value(forHTTPHeaderField: "Authorization") == "bearer gh_secret_token")
  }

  // Kills RelationalOperatorReplacement if httpMethod were mutated
  @Test func executeRequestUsesPostMethod() async throws {
    let (transport, captured) = makeTransport()
    _ = try await transport.execute(query: "{ test }", variables: nil)

    let cap = try #require(captured())
    #expect(cap.urlRequest.httpMethod == "POST")
  }

  // Kills RemoveSideEffects on httpBody assignment
  @Test func executeRequestEncodesQueryAndVariablesInBody() async throws {
    let (transport, captured) = makeTransport()
    _ = try await transport.execute(query: "mutation { close }", variables: ["id": "abc"])

    let cap = try #require(captured())
    let bodyData = try #require(cap.bodyData)
    let body = try #require(
      JSONSerialization.jsonObject(with: bodyData) as? [String: Any])

    #expect(body["query"] as? String == "mutation { close }")
    let vars = try #require(body["variables"] as? [String: String])
    #expect(vars["id"] == "abc")
  }

  // Verifies variables are omitted from body when nil
  @Test func executeRequestOmitsVariablesWhenNil() async throws {
    let (transport, captured) = makeTransport()
    _ = try await transport.execute(query: "{ viewer }", variables: nil)

    let cap = try #require(captured())
    let bodyData = try #require(cap.bodyData)
    let body = try #require(
      JSONSerialization.jsonObject(with: bodyData) as? [String: Any])

    #expect(body["query"] as? String == "{ viewer }")
    #expect(body["variables"] == nil)
  }
}

// MARK: - CodexAdapter startSession Error Path Cleanup

@Suite("CodexAdapter startSession Error Path Cleanup")
struct CodexAdapterStartSessionErrorCleanupTests {

  // Kills RemoveSideEffects on activeSessions.remove(sessionID:) in the error handler.
  // If the remove call is deleted, cancelSession finds the stale session instead of
  // throwing sessionNotFound.
  @Test func failedStartSessionCleansUpSessionStoreSoCancelThrows() async throws {
    let stubLauncher = StubProcessLauncher()
    let stubProcess = StubLaunchedProcess()
    stubProcess.setInputError(ProviderAdapterError.processLaunchFailed("stdin broken"))
    stubLauncher.setStubProcess(stubProcess)

    let adapter = CodexAdapter(config: .defaults, processLauncher: stubLauncher)
    let sid = SessionID("s-cleanup-verify")

    // startSession should throw because submitJSONMessages fails
    await #expect(throws: ProviderAdapterError.self) {
      _ = try await adapter.startSession(
        sessionID: sid,
        workspacePath: "/tmp/ws",
        prompt: "Fix bug",
        environment: [:]
      )
    }

    // After error cleanup, the session store must be empty.
    // cancelSession checks activeSessions only — if remove was skipped,
    // cancelSession would find the session and NOT throw.
    await #expect(throws: ProviderAdapterError.self) {
      try await adapter.cancelSession(sessionID: sid)
    }
  }

  // Verifies the continueSession path also rejects the cleaned-up session
  @Test func failedStartSessionCleansUpSoContinueSessionThrows() async throws {
    let stubLauncher = StubProcessLauncher()
    let stubProcess = StubLaunchedProcess()
    stubProcess.setInputError(ProviderAdapterError.processLaunchFailed("stdin broken"))
    stubLauncher.setStubProcess(stubProcess)

    let adapter = CodexAdapter(config: .defaults, processLauncher: stubLauncher)
    let sid = SessionID("s-cleanup-continue")

    await #expect(throws: ProviderAdapterError.self) {
      _ = try await adapter.startSession(
        sessionID: sid,
        workspacePath: "/tmp/ws",
        prompt: "Fix bug",
        environment: [:]
      )
    }

    // continueSession checks both activeSessions AND sessionRegistry.threadID.
    // Either cleanup being missing would be caught here.
    await #expect(throws: ProviderAdapterError.self) {
      _ = try await adapter.continueSession(sessionID: sid, guidance: "retry")
    }
  }
}
