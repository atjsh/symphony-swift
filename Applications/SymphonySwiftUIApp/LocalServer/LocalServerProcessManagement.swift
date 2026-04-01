#if os(macOS)
  import Foundation
  import SymphonyServerCore
  import SymphonyShared

  final class DefaultLocalServerProcessController: LocalServerProcessControlling, @unchecked Sendable
  {
    private let process: Process
    private let pipe: Pipe
    private let outputBuffer: OutputBuffer

    var processIdentifier: Int32 {
      process.processIdentifier
    }

    fileprivate init(process: Process, pipe: Pipe, outputBuffer: OutputBuffer) {
      self.process = process
      self.pipe = pipe
      self.outputBuffer = outputBuffer
    }

    func terminate() {
      pipe.fileHandleForReading.readabilityHandler = nil
      process.terminate()
      _ = outputBuffer.finish()
    }
  }

  struct DefaultLocalServerProcessLauncher: LocalServerProcessLaunching {
    func launch(
      request: LocalServerLaunchRequest,
      onOutput: @escaping @Sendable (String) -> Void,
      onExit: @escaping @Sendable (Int32) -> Void
    ) throws -> any LocalServerProcessControlling {
      let process = Process()
      let pipe = Pipe()
      let outputBuffer = OutputBuffer(onLine: onOutput)
      process.executableURL = request.helperURL
      process.arguments = []
      process.environment = request.environment
      process.currentDirectoryURL = request.currentDirectoryURL
      process.standardOutput = pipe
      process.standardError = pipe
      pipe.fileHandleForReading.readabilityHandler = { handle in
        let data = handle.availableData
        if data.isEmpty {
          for line in outputBuffer.finish() {
            onOutput(line)
          }
          return
        }

        for line in outputBuffer.append(data) {
          onOutput(line)
        }
      }

      process.terminationHandler = { process in
        pipe.fileHandleForReading.readabilityHandler = nil
        for line in outputBuffer.finish() {
          onOutput(line)
        }
        onExit(process.terminationStatus)
      }

      try process.run()
      return DefaultLocalServerProcessController(
        process: process,
        pipe: pipe,
        outputBuffer: outputBuffer
      )
    }
  }

  @MainActor
  final class DefaultLocalServerManager: LocalServerManaging, @unchecked Sendable {
    var onStatusChange: ((LocalServerStatusSnapshot) -> Void)?
    private(set) var statusSnapshot = LocalServerStatusSnapshot(
      state: .idle,
      endpoint: .defaultEndpoint
    )

    private let processLauncher: any LocalServerProcessLaunching
    private let healthCheck: @Sendable (BootstrapServerEndpoint) async throws -> Void
    private let clock: ContinuousClock
    private var process: (any LocalServerProcessControlling)?
    private var generation: Int = 0
    private var requestedStopGenerations = Set<Int>()

    init(
      processLauncher: (any LocalServerProcessLaunching)? = nil,
      healthCheck: (@Sendable (BootstrapServerEndpoint) async throws -> Void)? = nil,
      clock: ContinuousClock = ContinuousClock()
    ) {
      self.processLauncher = processLauncher ?? DefaultLocalServerProcessLauncher()
      self.clock = clock
      if let healthCheck {
        self.healthCheck = healthCheck
      } else {
        let client = URLSessionSymphonyAPIClient()
        self.healthCheck = { endpoint in
          let resolved = try ServerEndpoint(
            scheme: endpoint.scheme,
            host: endpoint.host,
            port: endpoint.port
          )
          _ = try await client.health(endpoint: resolved)
        }
      }
    }

    func start(request: LocalServerLaunchRequest) async {
      await stop()
      generation += 1
      let currentGeneration = generation
      updateStatus(
        LocalServerStatusSnapshot(
          state: .starting,
          endpoint: request.endpoint,
          transcript: [],
          failureDescription: nil,
          processIdentifier: nil
        )
      )

      do {
        let process = try processLauncher.launch(
          request: request,
          onOutput: { [weak self] line in
            Task { @MainActor in
              self?.appendTranscript(line, generation: currentGeneration)
            }
          },
          onExit: { [weak self] status in
            Task { @MainActor in
              self?.handleProcessExit(status: status, generation: currentGeneration)
            }
          }
        )

        self.process = process
        updateStatus(
          LocalServerStatusSnapshot(
            state: .waitingForHealth,
            endpoint: request.endpoint,
            transcript: statusSnapshot.transcript,
            failureDescription: nil,
            processIdentifier: process.processIdentifier
          )
        )

        do {
          try await waitForHealth(endpoint: request.endpoint, generation: currentGeneration)
          guard currentGeneration == generation else {
            return
          }
          updateStatus(
            LocalServerStatusSnapshot(
              state: .running,
              endpoint: request.endpoint,
              transcript: statusSnapshot.transcript,
              failureDescription: nil,
              processIdentifier: process.processIdentifier
            )
          )
        } catch let error as LocalServerLaunchError {
          fail(with: error, generation: currentGeneration)
        } catch {
          fail(with: .startupFailed(error.localizedDescription), generation: currentGeneration)
        }
      } catch let error as LocalServerLaunchError {
        fail(with: error, generation: currentGeneration)
      } catch {
        fail(with: .startupFailed(error.localizedDescription), generation: currentGeneration)
      }
    }

    func stop() async {
      guard let process else {
        updateStatus(
          LocalServerStatusSnapshot(
            state: .idle,
            endpoint: statusSnapshot.endpoint,
            transcript: statusSnapshot.transcript,
            failureDescription: nil,
            processIdentifier: nil
          )
        )
        return
      }

      requestedStopGenerations.insert(generation)
      process.terminate()
      self.process = nil
      updateStatus(
        LocalServerStatusSnapshot(
          state: .idle,
          endpoint: statusSnapshot.endpoint,
          transcript: statusSnapshot.transcript,
          failureDescription: nil,
          processIdentifier: nil
        )
      )
    }

    func restart(request: LocalServerLaunchRequest) async {
      await stop()
      await start(request: request)
    }

    private func waitForHealth(endpoint: BootstrapServerEndpoint, generation: Int) async throws {
      let deadline = clock.now.advanced(by: .seconds(15))
      while clock.now < deadline {
        if generation != self.generation {
          throw LocalServerLaunchError.startupFailed("The local server launch was cancelled.")
        }

        do {
          try await healthCheck(endpoint)
          return
        } catch {
          if process == nil {
            throw mappedFailure(
              from: statusSnapshot.transcript,
              endpoint: endpoint,
              fallback: .helperExitedBeforeReady(-1)
            )
          }
        }

        try await Task.sleep(for: .milliseconds(150))
      }

      throw mappedFailure(
        from: statusSnapshot.transcript,
        endpoint: endpoint,
        fallback: .healthTimedOut(endpoint.displayString)
      )
    }

    private func handleProcessExit(status: Int32, generation: Int) {
      guard generation == self.generation else {
        return
      }

      process = nil
      if requestedStopGenerations.remove(generation) != nil || statusSnapshot.state == .idle {
        return
      }

      let failure = mappedFailure(
        from: statusSnapshot.transcript,
        endpoint: statusSnapshot.endpoint,
        fallback: .helperExitedBeforeReady(status)
      )
      fail(with: failure, generation: generation)
    }

    private func appendTranscript(_ line: String, generation: Int) {
      guard generation == self.generation else {
        return
      }

      var updated = statusSnapshot
      updated.transcript.append(line)
      updateStatus(updated)
    }

    private func fail(with error: LocalServerLaunchError, generation: Int) {
      guard generation == self.generation else {
        return
      }

      updateStatus(
        LocalServerStatusSnapshot(
          state: .failed,
          endpoint: statusSnapshot.endpoint,
          transcript: statusSnapshot.transcript,
          failureDescription: error.localizedDescription,
          processIdentifier: statusSnapshot.processIdentifier
        )
      )
    }

    private func updateStatus(_ status: LocalServerStatusSnapshot) {
      statusSnapshot = status
      onStatusChange?(status)
    }

    private func mappedFailure(
      from transcript: [String],
      endpoint: BootstrapServerEndpoint,
      fallback: LocalServerLaunchError
    ) -> LocalServerLaunchError {
      if transcript.contains(where: { $0.localizedCaseInsensitiveContains("address already in use") })
      {
        return .occupiedPort(endpoint.port)
      }

      if let lastFailure = transcript.last(where: { $0.contains("failed to start:") }) {
        return .startupFailed(lastFailure)
      }

      return fallback
    }
  }

  @MainActor
  final class UITestingLocalServerManager: LocalServerManaging, @unchecked Sendable {
    var onStatusChange: ((LocalServerStatusSnapshot) -> Void)?
    private(set) var statusSnapshot = LocalServerStatusSnapshot(
      state: .needsSetup,
      endpoint: .defaultEndpoint
    )

    func start(request: LocalServerLaunchRequest) async {
      statusSnapshot = LocalServerStatusSnapshot(
        state: .running,
        endpoint: request.endpoint,
        transcript: [
          "[SymphonyServer] starting",
          "[SymphonyServer] endpoint=\(request.endpoint.displayString)",
        ],
        failureDescription: nil,
        processIdentifier: 4242
      )
      onStatusChange?(statusSnapshot)
    }

    func stop() async {
      statusSnapshot = LocalServerStatusSnapshot(
        state: .idle,
        endpoint: statusSnapshot.endpoint,
        transcript: statusSnapshot.transcript,
        failureDescription: nil,
        processIdentifier: nil
      )
      onStatusChange?(statusSnapshot)
    }

    func restart(request: LocalServerLaunchRequest) async {
      await start(request: request)
    }
  }

  private final class OutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()

    init(onLine _: @escaping @Sendable (String) -> Void) {}

    func append(_ data: Data) -> [String] {
      guard !data.isEmpty else {
        return []
      }

      lock.lock()
      buffer.append(data)
      let lines = consumeLines()
      lock.unlock()
      return lines
    }

    func finish() -> [String] {
      lock.lock()
      defer {
        buffer.removeAll(keepingCapacity: false)
        lock.unlock()
      }

      guard !buffer.isEmpty else {
        return []
      }

      let line = String(decoding: buffer, as: UTF8.self)
      return line.isEmpty ? [] : [line]
    }

    private func consumeLines() -> [String] {
      guard !buffer.isEmpty else {
        return []
      }

      var lines = [String]()
      while let newlineIndex = buffer.firstIndex(of: 0x0A) {
        let lineData = buffer.prefix(upTo: newlineIndex)
        buffer.removeSubrange(...newlineIndex)
        let line = String(decoding: lineData, as: UTF8.self)
          .trimmingCharacters(in: .newlines)
        if !line.isEmpty {
          lines.append(line)
        }
      }
      return lines
    }
  }
#endif
