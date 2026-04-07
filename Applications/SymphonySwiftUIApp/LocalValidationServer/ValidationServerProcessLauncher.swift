#if os(macOS)
  import Foundation

  /// Protocol for launching the validation server as a subprocess.
  protocol ValidationServerProcessLaunching {
    func launch(
      request: ValidationServerLaunchRequest,
      onOutput: @escaping @Sendable (String) -> Void,
      onExit: @escaping @Sendable (Int32) -> Void
    ) throws -> any ValidationServerProcessControlling
  }

  /// Protocol for controlling a launched validation server process.
  protocol ValidationServerProcessControlling: AnyObject {
    var processIdentifier: Int32 { get }
    func terminate()
  }

  final class DefaultValidationServerProcessController: ValidationServerProcessControlling,
    @unchecked Sendable
  {
    private let process: Process
    private let pipe: Pipe
    private let outputBuffer: ValidationServerOutputBuffer

    var processIdentifier: Int32 {
      process.processIdentifier
    }

    fileprivate init(process: Process, pipe: Pipe, outputBuffer: ValidationServerOutputBuffer) {
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

  struct DefaultValidationServerProcessLauncher: ValidationServerProcessLaunching {
    func launch(
      request: ValidationServerLaunchRequest,
      onOutput: @escaping @Sendable (String) -> Void,
      onExit: @escaping @Sendable (Int32) -> Void
    ) throws -> any ValidationServerProcessControlling {
      let process = Process()
      let pipe = Pipe()
      let outputBuffer = ValidationServerOutputBuffer()
      process.executableURL = request.helperURL
      process.arguments = [
        "--hostname", request.hostname,
        "--port", String(request.port),
        "--project-root", request.projectRoot.path,
      ]
      process.currentDirectoryURL = request.projectRoot
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
      return DefaultValidationServerProcessController(
        process: process,
        pipe: pipe,
        outputBuffer: outputBuffer
      )
    }
  }

  /// Line-buffering helper for process output.
  final class ValidationServerOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()

    func append(_ data: Data) -> [String] {
      guard !data.isEmpty else { return [] }
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
      guard !buffer.isEmpty else { return [] }
      let line = String(decoding: buffer, as: UTF8.self)
      return line.isEmpty ? [] : [line]
    }

    private func consumeLines() -> [String] {
      guard !buffer.isEmpty else { return [] }
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
