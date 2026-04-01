import Foundation
import Testing

@testable import SymphonyXcodeValidation
@testable import SymphonyXcodeValidationCLI

extension ValidationProcessExecutorStub {
  func xcresultCommandResult(
    mode: XCResultCommandStubMode,
    defaultOutput: String
  ) -> ValidationCommandResult {
    switch mode {
    case .success:
      return ValidationCommandResult(exitStatus: 0, stdout: defaultOutput, stderr: "")
    case .invalidJSON:
      return ValidationCommandResult(exitStatus: 0, stdout: "{", stderr: "")
    case .failure(let stderr):
      return ValidationCommandResult(exitStatus: 1, stdout: "", stderr: stderr)
    }
  }
}

final class ValidationRunningCommandStub: RunningValidationCommand {
  func stop() {}
}

extension ValidationScenarioDescriptor {
  static func resultBundlePath(_ path: String) -> ValidationScenarioDescriptor? {
    let components = URL(fileURLWithPath: path).pathComponents
    guard let resultIndex = components.lastIndex(of: "result.xcresult"), resultIndex >= 4 else {
      return nil
    }

    return ValidationScenarioDescriptor(
      platform: components[resultIndex - 4],
      plan: components[resultIndex - 3],
      phase: components[resultIndex - 2],
      runName: components[resultIndex - 1]
    )
  }

  static func exportRootPath(_ path: String) -> ValidationScenarioDescriptor? {
    let components = URL(fileURLWithPath: path).pathComponents
    guard let runIndex = components.indices.last else {
      return nil
    }
    guard runIndex >= 3 else {
      return nil
    }

    return ValidationScenarioDescriptor(
      platform: components[runIndex - 3],
      plan: components[runIndex - 2],
      phase: components[runIndex - 1],
      runName: components[runIndex]
    )
  }
}

extension ValidationBuildDescriptor {
  static func command(_ command: ValidationCommand) -> ValidationBuildDescriptor? {
    guard let destination = command.arguments.value(after: "-destination"),
      let testPlan = command.arguments.value(after: "-testPlan")
    else {
      return nil
    }

    let platform: String
    if destination.contains("platform=macOS") {
      platform = "macos"
    } else if destination.contains("FB1A9F71-0620-4314-BF84-1BD1C46ABF5D") {
      platform = "ipados"
    } else if destination.contains("platform=iOS Simulator") {
      platform = "ios"
    } else {
      return nil
    }

    let plan: String
    switch testPlan {
    case "SymphonySwiftUIApp":
      plan = "app"
    case "XcodeValidationGalleryApp":
      plan = "app"
    case "SymphonySwiftUIAppTests":
      plan = "app-tests"
    case "XcodeValidationGalleryAppTests":
      plan = "app-tests"
    case "SymphonySwiftUIAppUITests":
      plan = "ui-tests"
    case "XcodeValidationGalleryAppUITests":
      plan = "ui-tests"
    default:
      return nil
    }

    let buildProfile = command.arguments.contains("COMPILER_INDEX_STORE_ENABLE=NO") ? "fast" : "standard"
    return ValidationBuildDescriptor(platform: platform, plan: plan, buildProfile: buildProfile)
  }
}

extension Array where Element == String {
  func value(after flag: String) -> String? {
    guard let index = firstIndex(of: flag), indices.contains(index + 1) else {
      return nil
    }
    return self[index + 1]
  }
}

final class LockedStringBox: @unchecked Sendable {
  private let lock = NSLock()
  private var storage = [String]()

  func append(_ value: String) {
    lock.lock()
    storage.append(value)
    lock.unlock()
  }

  var values: [String] {
    lock.lock()
    defer { lock.unlock() }
    return storage
  }
}
