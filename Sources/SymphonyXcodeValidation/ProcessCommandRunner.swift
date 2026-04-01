import Foundation

#if os(macOS)

public protocol ValidationProcessExecuting {
  func run(_ command: ValidationCommand) throws -> ValidationCommandResult
  func start(_ command: ValidationCommand) throws -> RunningValidationCommand
}

public protocol RunningValidationCommand: AnyObject {
  func stop()
}

public final class SystemValidationProcessExecutor: ValidationProcessExecuting {
  public init() {}

  public func run(_ command: ValidationCommand) throws -> ValidationCommandResult {
    let process = Process()
    let stdout = Pipe()
    let stderr = Pipe()
    let stdoutBuffer = LockedDataBuffer()
    let stderrBuffer = LockedDataBuffer()
    let drainGroup = DispatchGroup()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [command.executable] + command.arguments
    process.environment = ProcessInfo.processInfo.environment.merging(command.environment) { _, new in
      new
    }
    process.currentDirectoryURL = command.currentDirectory
    process.standardOutput = stdout
    process.standardError = stderr
    startDraining(stdout.fileHandleForReading, into: stdoutBuffer, group: drainGroup)
    startDraining(stderr.fileHandleForReading, into: stderrBuffer, group: drainGroup)

    try process.run()
    process.waitUntilExit()
    drainGroup.wait()

    return ValidationCommandResult(
      exitStatus: process.terminationStatus,
      stdout: stdoutBuffer.stringValue,
      stderr: stderrBuffer.stringValue
    )
  }

  public func start(_ command: ValidationCommand) throws -> RunningValidationCommand {
    try SystemRunningValidationCommand(command: command)
  }

  func startDraining(
    _ fileHandle: FileHandle,
    into buffer: LockedDataBuffer,
    group: DispatchGroup
  ) {
    group.enter()
    fileHandle.readabilityHandler = { handle in
      let data = handle.availableData
      guard data.isEmpty == false else {
        handle.readabilityHandler = nil
        group.leave()
        return
      }
      buffer.append(data)
    }
  }
}

final class SystemRunningValidationCommand: RunningValidationCommand {
  let process: Process

  init(command: ValidationCommand) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [command.executable] + command.arguments
    process.environment = ProcessInfo.processInfo.environment.merging(command.environment) { _, new in
      new
    }
    process.currentDirectoryURL = command.currentDirectory
    process.standardOutput = Pipe()
    process.standardError = Pipe()
    try process.run()
    self.process = process
  }

  func stop() {
    guard process.isRunning else {
      return
    }

    process.interrupt()
    let deadline = Date().addingTimeInterval(10)
    while process.isRunning && Date() < deadline {
      RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
    }

    if process.isRunning {
      process.terminate()
      process.waitUntilExit()
    }
  }
}

final class LockedDataBuffer: @unchecked Sendable {
  let lock = NSLock()
  var data = Data()

  func append(_ newData: Data) {
    lock.lock()
    data.append(newData)
    lock.unlock()
  }

  var stringValue: String {
    lock.lock()
    defer { lock.unlock() }
    return String(decoding: data, as: UTF8.self)
  }
}

#endif
