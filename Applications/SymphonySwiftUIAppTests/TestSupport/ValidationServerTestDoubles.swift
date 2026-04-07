#if os(macOS)
  import Foundation
  @testable import SymphonySwiftUIApp
  import SymphonyValidationGallery

  /// Recording mock for `ValidationServerProcessLaunching`.
  final class RecordingValidationServerProcessLauncher: ValidationServerProcessLaunching,
    @unchecked Sendable
  {
    private(set) var launchedRequests: [ValidationServerLaunchRequest] = []
    var nextProcess: RecordingValidationServerProcess = .init()
    var shouldThrow: Error?

    func launch(
      request: ValidationServerLaunchRequest,
      onOutput: @escaping @Sendable (String) -> Void,
      onExit: @escaping @Sendable (Int32) -> Void
    ) throws -> any ValidationServerProcessControlling {
      if let error = shouldThrow {
        throw error
      }
      launchedRequests.append(request)
      let proc = nextProcess
      proc.onOutput = onOutput
      proc.onExit = onExit
      return proc
    }
  }

  /// Recording mock for `ValidationServerProcessControlling`.
  final class RecordingValidationServerProcess: ValidationServerProcessControlling,
    @unchecked Sendable
  {
    let processIdentifier: Int32
    private(set) var terminateCallCount = 0
    var onOutput: (@Sendable (String) -> Void)?
    var onExit: (@Sendable (Int32) -> Void)?

    init(processIdentifier: Int32 = 1234) {
      self.processIdentifier = processIdentifier
    }

    func terminate() {
      terminateCallCount += 1
    }

    func simulateOutput(_ line: String) {
      onOutput?(line)
    }

    func simulateExit(status: Int32 = 0) {
      onExit?(status)
    }
  }

  /// Recording mock for `ValidationServerHelperLocating`.
  struct RecordingValidationServerHelperLocator: ValidationServerHelperLocating {
    var url: URL
    var shouldThrow: Error?

    init(url: URL = URL(fileURLWithPath: "/tmp/SymphonyValidationServerHelper")) {
      self.url = url
    }

    func helperURL() throws -> URL {
      if let error = shouldThrow {
        throw error
      }
      return url
    }
  }

  /// Recording mock for the full `ValidationServerLifecycleManaging` protocol.
  @MainActor
  final class RecordingValidationServerManager: ValidationServerLifecycleManaging,
    @unchecked Sendable
  {
    var onStatusChange: (@MainActor (ValidationServerStatusSnapshot) -> Void)?
    private(set) var statusSnapshot = ValidationServerStatusSnapshot(state: .idle)
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var lastStartHostname: String?
    private(set) var lastStartPort: Int?
    private(set) var lastStartProjectRoot: URL?

    var nextStartSnapshot = ValidationServerStatusSnapshot(
      state: .running,
      hostname: "127.0.0.1",
      port: 8090,
      transcript: ["[ValidationServer] started"],
      processIdentifier: 9999
    )
    var nextStopSnapshot = ValidationServerStatusSnapshot(
      state: .idle,
      hostname: "127.0.0.1",
      port: 8090,
      transcript: ["[ValidationServer] stopped"]
    )

    func start(hostname: String, port: Int, projectRoot: URL) async {
      startCallCount += 1
      lastStartHostname = hostname
      lastStartPort = port
      lastStartProjectRoot = projectRoot
      statusSnapshot = nextStartSnapshot
      onStatusChange?(statusSnapshot)
    }

    func stop() async {
      stopCallCount += 1
      statusSnapshot = nextStopSnapshot
      onStatusChange?(statusSnapshot)
    }
  }
#endif
