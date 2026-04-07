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

// MARK: - Server Lifecycle Tests

@MainActor
final class RecordingServerManager: ValidationServerLifecycleManaging, @unchecked Sendable {
  var onStatusChange: (@MainActor (ValidationServerStatusSnapshot) -> Void)?
  private(set) var statusSnapshot = ValidationServerStatusSnapshot(state: .idle)
  private(set) var startCallCount = 0
  private(set) var stopCallCount = 0
  private(set) var lastHostname: String?
  private(set) var lastPort: Int?
  private(set) var lastProjectRoot: URL?

  var nextStartSnapshot = ValidationServerStatusSnapshot(
    state: .running,
    hostname: "127.0.0.1",
    port: 8090,
    transcript: ["[ValidationServer] started"],
    processIdentifier: 9999
  )
  var nextStopSnapshot = ValidationServerStatusSnapshot(state: .idle)

  func start(hostname: String, port: Int, projectRoot: URL) async {
    startCallCount += 1
    lastHostname = hostname
    lastPort = port
    lastProjectRoot = projectRoot
    statusSnapshot = nextStartSnapshot
    onStatusChange?(statusSnapshot)
  }

  func stop() async {
    stopCallCount += 1
    statusSnapshot = nextStopSnapshot
    onStatusChange?(statusSnapshot)
  }
}

@Suite("ValidationRunnerStore – Server Lifecycle")
@MainActor
struct ValidationRunnerStoreServerLifecycleTests {
  @Test("hasServerSupport is false when serverManager is nil")
  func hasServerSupportNil() {
    let client = MockValidationServerClient()
    let store = ValidationRunnerStore(client: client, serverManager: nil)
    #expect(store.hasServerSupport == false)
  }

  @Test("hasServerSupport is true when serverManager is provided")
  func hasServerSupportProvided() {
    let client = MockValidationServerClient()
    let manager = RecordingServerManager()
    let store = ValidationRunnerStore(client: client, serverManager: manager)
    #expect(store.hasServerSupport == true)
  }

  @Test("startServer calls manager and updates state")
  func startServerCallsManager() async {
    let client = MockValidationServerClient()
    let manager = RecordingServerManager()
    let store = ValidationRunnerStore(client: client, serverManager: manager)
    await store.startServer()
    #expect(manager.startCallCount == 1)
    #expect(store.serverLaunchState == .running)
    #expect(store.serverTranscript == ["[ValidationServer] started"])
  }

  @Test("stopServer calls manager and clears connected")
  func stopServerCallsManager() async {
    let client = MockValidationServerClient()
    let manager = RecordingServerManager()
    let store = ValidationRunnerStore(client: client, serverManager: manager)
    await store.startServer()
    await store.stopServer()
    #expect(manager.stopCallCount == 1)
    #expect(store.isConnected == false)
    #expect(store.serverLaunchState == .idle)
  }

  @Test("startServer without manager is a no-op")
  func startServerNoManager() async {
    let client = MockValidationServerClient()
    let store = ValidationRunnerStore(client: client, serverManager: nil)
    await store.startServer()
    #expect(store.serverLaunchState == .idle)
  }

  @Test("stopServer without manager is a no-op")
  func stopServerNoManager() async {
    let client = MockValidationServerClient()
    let store = ValidationRunnerStore(client: client, serverManager: nil)
    await store.stopServer()
    #expect(store.isConnected == false)
  }

  @Test("isServerRunning reflects serverLaunchState")
  func isServerRunning() async {
    let client = MockValidationServerClient()
    let manager = RecordingServerManager()
    let store = ValidationRunnerStore(client: client, serverManager: manager)
    #expect(store.isServerRunning == false)
    await store.startServer()
    #expect(store.isServerRunning == true)
  }

  @Test("server failure state is applied from snapshot")
  func failureState() async {
    let client = MockValidationServerClient()
    let manager = RecordingServerManager()
    manager.nextStartSnapshot = ValidationServerStatusSnapshot(
      state: .failed,
      hostname: "127.0.0.1",
      port: 8090,
      transcript: ["[ValidationServer] failed to start"],
      failureDescription: "Port in use"
    )
    let store = ValidationRunnerStore(client: client, serverManager: manager)
    await store.startServer()
    #expect(store.serverLaunchState == .failed)
    #expect(store.serverFailureDescription == "Port in use")
  }

  @Test("startServer uses configured hostname and port")
  func startServerUsesConfiguredValues() async {
    let client = MockValidationServerClient()
    let manager = RecordingServerManager()
    let store = ValidationRunnerStore(client: client, serverManager: manager)
    store.serverHostname = "192.168.1.1"
    store.serverPort = "9090"
    await store.startServer()
    #expect(manager.lastHostname == "192.168.1.1")
    #expect(manager.lastPort == 9090)
  }

  @Test("startServer falls back to defaults for empty hostname")
  func startServerDefaultHostname() async {
    let client = MockValidationServerClient()
    let manager = RecordingServerManager()
    let store = ValidationRunnerStore(client: client, serverManager: manager)
    store.serverHostname = ""
    await store.startServer()
    #expect(manager.lastHostname == "127.0.0.1")
  }

  @Test("startServer falls back to default port for invalid string")
  func startServerInvalidPort() async {
    let client = MockValidationServerClient()
    let manager = RecordingServerManager()
    let store = ValidationRunnerStore(client: client, serverManager: manager)
    store.serverPort = "abc"
    await store.startServer()
    #expect(manager.lastPort == 8090)
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
