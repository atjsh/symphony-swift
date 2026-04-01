import Foundation
import Testing

@testable import SymphonyHarness

struct BootSequenceProcessRunner: ProcessRunning {
  private let responses: [CommandResult]
  private let counter = LockedCounter()

  init(responses: [CommandResult]) {
    self.responses = responses
  }

  func run(
    command: String, arguments: [String], environment: [String: String], currentDirectory: URL?,
    observation: ProcessObservation?
  ) throws -> CommandResult {
    responses[counter.next()]
  }

  func startDetached(
    executablePath: String, arguments: [String], environment: [String: String],
    currentDirectory: URL?, output: URL
  ) throws -> Int32 {
    0
  }
}

struct RoutedBuildServicesProcessRunner: ProcessRunning {
  let handler:
    @Sendable (String, [String], [String: String], URL?, ProcessObservation?) throws ->
      CommandResult

  func run(
    command: String, arguments: [String], environment: [String: String], currentDirectory: URL?,
    observation: ProcessObservation?
  ) throws -> CommandResult {
    try handler(command, arguments, environment, currentDirectory, observation)
  }

  func startDetached(
    executablePath: String, arguments: [String], environment: [String: String],
    currentDirectory: URL?, output: URL
  ) throws -> Int32 {
    0
  }
}

final class LockedCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var value = 0

  func next() -> Int {
    lock.lock()
    defer {
      value += 1
      lock.unlock()
    }
    return value
  }
}
