import Foundation
import Testing
@testable import SymphonyValidationGallery
import SymphonyXcodeValidationServerCore
import SymphonyXcodeValidation

// MARK: - Mock Server Client

@MainActor
final class MockValidationServerClient: ValidationServerConnecting, @unchecked Sendable {
  // SAFETY: Accessed only from @MainActor or test setup.
  var startRunResult: Result<RunID, Error> = .success(RunID("mock-run-1"))
  var pollStatusResult: Result<RunStatusResponse, Error> = .success(
    RunStatusResponse(runID: RunID("mock-run-1"), status: .running, logLines: [])
  )
  var fetchSummaryResult: Result<RunSummaryResponse, Error>?
  var cancelRunCalled = false
  var healthCheckResult = true
  var startRunCallCount = 0
  var pollStatusCallCount = 0

  nonisolated func startRun(_ request: StartRunRequest) async throws -> RunID {
    await MainActor.run { startRunCallCount += 1 }
    return try await MainActor.run { try startRunResult.get() }
  }

  nonisolated func pollStatus(_ runID: RunID, afterLine: Int?) async throws -> RunStatusResponse {
    await MainActor.run { pollStatusCallCount += 1 }
    return try await MainActor.run { try pollStatusResult.get() }
  }

  nonisolated func fetchSummary(_ runID: RunID) async throws -> RunSummaryResponse {
    return try await MainActor.run {
      guard let result = fetchSummaryResult else {
        throw ValidationServerClientError.unexpectedStatus(404)
      }
      return try result.get()
    }
  }

  nonisolated func cancelRun(_ runID: RunID) async throws {
    await MainActor.run { cancelRunCalled = true }
  }

  nonisolated func healthCheck() async throws -> Bool {
    await MainActor.run { healthCheckResult }
  }
}

// MARK: - ValidationRunnerStore Tests

@Suite("ValidationRunnerStore")
@MainActor
struct ValidationRunnerStoreTests {
  @Test("initial state is idle")
  func initialState() {
    let client = MockValidationServerClient()
    let store = ValidationRunnerStore(client: client)
    #expect(store.runStatus == .idle)
    #expect(store.logLines.isEmpty)
    #expect(store.activeRunID == nil)
  }

  @Test("checkConnection updates isConnected")
  func checkConnection() async {
    let client = MockValidationServerClient()
    client.healthCheckResult = true
    let store = ValidationRunnerStore(client: client)
    await store.checkConnection()
    #expect(store.isConnected == true)

    client.healthCheckResult = false
    await store.checkConnection()
    #expect(store.isConnected == false)
  }

  @Test("startRun transitions to running on success")
  func startRunSuccess() async {
    let client = MockValidationServerClient()
    let store = ValidationRunnerStore(client: client, pollingInterval: .seconds(60))
    await store.startRun()
    #expect(store.runStatus == .running)
    #expect(store.activeRunID?.rawValue == "mock-run-1")
    #expect(client.startRunCallCount == 1)
    store.reset()
  }

  @Test("startRun transitions to failed on error")
  func startRunFailure() async {
    let client = MockValidationServerClient()
    client.startRunResult = .failure(ValidationServerClientError.runAlreadyActive)
    let store = ValidationRunnerStore(client: client)
    await store.startRun()
    #expect(store.runStatus == .failed)
    #expect(store.errorMessage != nil)
  }

  @Test("cancelRun calls client and sets failed state")
  func cancelRun() async {
    let client = MockValidationServerClient()
    let store = ValidationRunnerStore(client: client, pollingInterval: .seconds(60))
    await store.startRun()
    await store.cancelRun()
    #expect(client.cancelRunCalled == true)
    #expect(store.runStatus == .failed)
    #expect(store.errorMessage == "Cancelled by user.")
  }

  @Test("reset clears all run state")
  func resetClearsState() async {
    let client = MockValidationServerClient()
    let store = ValidationRunnerStore(client: client, pollingInterval: .seconds(60))
    await store.startRun()
    store.reset()
    #expect(store.runStatus == .idle)
    #expect(store.logLines.isEmpty)
    #expect(store.activeRunID == nil)
    #expect(store.errorMessage == nil)
  }
}

// MARK: - ValidationServerClient Error Tests

@Suite("ValidationServerClientError")
struct ValidationServerClientErrorTests {
  @Test("error cases are distinct")
  func errorCases() {
    let active = ValidationServerClientError.runAlreadyActive
    let status = ValidationServerClientError.unexpectedStatus(500)
    let url = ValidationServerClientError.invalidURL
    // Just verify they can be constructed and are errors
    #expect(active is Error)
    #expect(status is Error)
    #expect(url is Error)
  }
}
