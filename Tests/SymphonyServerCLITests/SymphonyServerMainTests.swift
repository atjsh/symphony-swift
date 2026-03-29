import Foundation
import Testing

@testable import SymphonyServerCLI
@testable import SymphonyServer

@Suite("SymphonyServerMain", .serialized)
struct SymphonyServerMainTests {
  @MainActor @Test func topLevelMainUsesRuntimeHooksAndStartsServerByDefault() {
    let originalHooks = SymphonyServerMain.runtimeHooks
    defer { SymphonyServerMain.runtimeHooks = originalHooks }

    var capturedEnvironment = [String: String]()
    var emittedOutput = [String]()
    var emittedErrors = [String]()
    var didInvokeKeepAlive = false
    var exitCode: Int32?

    SymphonyServerMain.runtimeHooks = .init(
      environment: {
        [
          "SYMPHONY_SERVER_HOST": "127.0.0.1",
          "SYMPHONY_SERVER_PORT": "8080",
        ]
      },
      output: { emittedOutput.append($0) },
      errorOutput: { emittedErrors.append($0) },
      exit: { code in exitCode = code },
      runner: { _, environment, output, keepAlive, startServer in
        capturedEnvironment = environment
        output("[SymphonyServer] started")
        keepAlive()
        didInvokeKeepAlive = true
        #expect(startServer)
      }
    )

    SymphonyServerMain.main()

    #expect(capturedEnvironment["SYMPHONY_SERVER_HOST"] == "127.0.0.1")
    #expect(emittedOutput == ["[SymphonyServer] started"])
    #expect(emittedErrors.isEmpty)
    #expect(didInvokeKeepAlive)
    #expect(exitCode == nil)
  }

  @MainActor @Test func topLevelMainRoutesFailuresThroughRuntimeHooks() {
    enum StartupFailure: Error, CustomStringConvertible {
      case failed

      var description: String { "boom" }
    }

    let originalHooks = SymphonyServerMain.runtimeHooks
    defer { SymphonyServerMain.runtimeHooks = originalHooks }

    var emittedErrors = [String]()
    var exitCode: Int32?

    SymphonyServerMain.runtimeHooks = .init(
      environment: { [:] },
      output: { _ in },
      errorOutput: { emittedErrors.append($0) },
      exit: { code in exitCode = code },
      runner: { _, _, _, _, _ in
        throw StartupFailure.failed
      }
    )

    SymphonyServerMain.main()

    #expect(emittedErrors == ["[SymphonyServer] failed to start: boom\n"])
    #expect(exitCode == 1)
  }

  @Test func defaultRuntimeHooksReadEnvironmentAndWriteStandardStreams() throws {
    let hooks = SymphonyServerMain.runtimeHooks

    #expect(
      hooks.environment()[BootstrapKeepAlivePolicy.exitAfterStartupKey]
        == ProcessInfo.processInfo.environment[BootstrapKeepAlivePolicy.exitAfterStartupKey]
    )

    let output = try captureStandardOutput {
      hooks.output("[SymphonyServer] stdout probe")
    }
    #expect(output.contains("[SymphonyServer] stdout probe"))

    let errorOutput = try captureStandardError {
      hooks.errorOutput("[SymphonyServer] stderr probe")
    }
    #expect(errorOutput.contains("[SymphonyServer] stderr probe"))
  }

  @Test func mainRunsBootstrapRunnerWithExitAfterStartupPolicy() {
    var capturedEnvironment = [String: String]()
    var didInvokeKeepAlive = false
    var emittedOutput = [String]()
    var exitCode: Int32?

    SymphonyServerMain.main(
      environment: [
        BootstrapKeepAlivePolicy.exitAfterStartupKey: "1",
        "SYMPHONY_SERVER_HOST": "127.0.0.1",
      ],
      output: { emittedOutput.append($0) },
      errorOutput: { _ in },
      exit: { code in
        exitCode = code
      },
      runner: { _, environment, output, keepAlive, startServer in
        capturedEnvironment = environment
        output("[SymphonyServer] started")
        keepAlive()
        didInvokeKeepAlive = true
        #expect(!startServer)
      }
    )

    #expect(capturedEnvironment[BootstrapKeepAlivePolicy.exitAfterStartupKey] == "1")
    #expect(emittedOutput == ["[SymphonyServer] started"])
    #expect(didInvokeKeepAlive)
    #expect(exitCode == nil)
  }

  @Test func mainPrintsFailuresAndRequestsExitCodeOne() {
    enum StartupFailure: Error, CustomStringConvertible {
      case failed

      var description: String { "boom" }
    }

    var emittedErrors = [String]()
    var exitCode: Int32?

    SymphonyServerMain.main(
      environment: [:],
      output: { _ in },
      errorOutput: { emittedErrors.append($0) },
      exit: { code in
        exitCode = code
      },
      runner: { _, _, _, _, _ in
        throw StartupFailure.failed
      }
    )

    #expect(emittedErrors == ["[SymphonyServer] failed to start: boom\n"])
    #expect(exitCode == 1)
  }

  @Test func builtExecutableStartsAndExitsWhenRequested() throws {
    let executable = builtProductsDirectory().appendingPathComponent("symphony-server")
    #expect(FileManager.default.isExecutableFile(atPath: executable.path))

    let process = Process()
    let output = Pipe()
    process.executableURL = executable
    var environment = ProcessInfo.processInfo.environment
    environment[BootstrapKeepAlivePolicy.exitAfterStartupKey] = "1"
    environment[BootstrapEnvironment.serverSchemeKey] = "https"
    environment[BootstrapEnvironment.serverHostKey] = "server.example.com"
    environment[BootstrapEnvironment.serverPortKey] = "9555"
    process.environment = environment
    process.standardOutput = output
    process.standardError = output
    try process.run()
    process.waitUntilExit()

    let transcript = String(
      decoding: output.fileHandleForReading.readDataToEndOfFile(),
      as: UTF8.self
    )
    #expect(process.terminationStatus == 0)
    #expect(transcript.contains("[SymphonyServer] starting"))
    #expect(transcript.contains("[SymphonyServer] endpoint=https://server.example.com:9555"))
  }

  @Test func builtExecutablePrintsFailureAndExitsForInvalidSQLitePath() throws {
    let executable = builtProductsDirectory().appendingPathComponent("symphony-server")
    #expect(FileManager.default.isExecutableFile(atPath: executable.path))

    let invalidDatabaseURL = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    try FileManager.default.createDirectory(
      at: invalidDatabaseURL,
      withIntermediateDirectories: true
    )

    let process = Process()
    let output = Pipe()
    process.executableURL = executable
    var environment = ProcessInfo.processInfo.environment
    environment[BootstrapEnvironment.serverSQLitePathKey] = invalidDatabaseURL.path
    process.environment = environment
    process.standardOutput = output
    process.standardError = output
    try process.run()
    process.waitUntilExit()

    let transcript = String(
      decoding: output.fileHandleForReading.readDataToEndOfFile(),
      as: UTF8.self
    )
    #expect(process.terminationStatus == 1)
    #expect(transcript.contains("[SymphonyServer] failed to start:"))
    #expect(transcript.contains(invalidDatabaseURL.path))
  }

  @Test func sharedExecutableSupportsCustomComponentName() {
    var capturedComponentName: String?
    var emittedOutput = [String]()
    var emittedErrors = [String]()
    var exitCode: Int32?

    SymphonyServerExecutable.main(
      componentName: "SymphonyLocalServerHelper",
      environment: [:],
      output: { emittedOutput.append($0) },
      errorOutput: { emittedErrors.append($0) },
      exit: { exitCode = $0 },
      runner: { componentName, _, output, keepAlive, startServer in
        capturedComponentName = componentName
        output("[\(componentName)] started")
        keepAlive()
        #expect(startServer)
      }
    )

    #expect(capturedComponentName == "SymphonyLocalServerHelper")
    #expect(emittedOutput == ["[SymphonyLocalServerHelper] started"])
    #expect(emittedErrors.isEmpty)
    #expect(exitCode == nil)
  }

  @Test func sharedExecutableUsesCustomComponentNameForFailures() {
    var emittedErrors = [String]()
    var exitCode: Int32?

    SymphonyServerExecutable.main(
      componentName: "SymphonyLocalServerHelper",
      environment: [:],
      output: { _ in },
      errorOutput: { emittedErrors.append($0) },
      exit: { exitCode = $0 },
      runner: { _, _, _, _, _ in
        throw POSIXError(.EIO)
      }
    )

    #expect(emittedErrors.count == 1)
    #expect(emittedErrors[0].contains("[SymphonyLocalServerHelper] failed to start:"))
    #expect(exitCode == 1)
  }
}

private func captureStandardOutput(_ operation: () -> Void) throws -> String {
  try captureFileDescriptor(STDOUT_FILENO, flush: { fflush(stdout) }, operation: operation)
}

private func captureStandardError(_ operation: () -> Void) throws -> String {
  try captureFileDescriptor(STDERR_FILENO, flush: { fflush(stderr) }, operation: operation)
}

private func captureFileDescriptor(
  _ fileDescriptor: Int32,
  flush: () -> Void,
  operation: () -> Void
) throws -> String {
  let pipe = Pipe()
  let original = dup(fileDescriptor)
  #expect(original >= 0)
  guard original >= 0 else { return "" }

  flush()
  dup2(pipe.fileHandleForWriting.fileDescriptor, fileDescriptor)

  operation()
  flush()
  dup2(original, fileDescriptor)
  close(original)
  pipe.fileHandleForWriting.closeFile()
  let data = pipe.fileHandleForReading.readDataToEndOfFile()
  return String(decoding: data, as: UTF8.self)
}

private func builtProductsDirectory() -> URL {
  Bundle(for: BundleLocator.self).bundleURL.deletingLastPathComponent()
}

private final class BundleLocator {}
