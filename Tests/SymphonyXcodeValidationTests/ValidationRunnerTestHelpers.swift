import Foundation
import Testing

@testable import SymphonyXcodeValidation
@testable import SymphonyXcodeValidationCLI

struct ValidationRunnerTestEnvironment {
  let projectRoot: URL
  let outputRoot: URL
  let now: @Sendable () -> Date

  static func make(fileManager: FileManager = .default) throws -> ValidationRunnerTestEnvironment {
    let root = fileManager.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    let projectRoot = root.appendingPathComponent("project", isDirectory: true)
    let outputRoot = root.appendingPathComponent("output", isDirectory: true)
    try fileManager.createDirectory(at: projectRoot, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: outputRoot, withIntermediateDirectories: true)
    return ValidationRunnerTestEnvironment(
      projectRoot: projectRoot,
      outputRoot: outputRoot,
      now: { Date(timeIntervalSince1970: 1_777_777_777) }
    )
  }
}

struct ValidationScenarioDescriptor: Hashable {
  let platform: String
  let plan: String
  let phase: String
  let runName: String
}

struct ValidationBuildDescriptor: Hashable {
  let platform: String
  let plan: String
  let buildProfile: String
}

enum XCResultCommandStubMode {
  case success
  case invalidJSON
  case failure(String)
}

struct ValidationScenarioOutcomeStub {
  let exitStatus: Int32
  let summary: ValidationTestSummary

  static let passed = ValidationScenarioOutcomeStub(
    exitStatus: 0,
    summary: ValidationTestSummary(
      result: "Passed",
      passedTests: 1,
      failedTests: 0,
      testFailures: []
    )
  )

  static func failed(testIdentifier: String, failureText: String) -> ValidationScenarioOutcomeStub {
    ValidationScenarioOutcomeStub(
      exitStatus: 65,
      summary: ValidationTestSummary(
        result: "Failed",
        passedTests: 0,
        failedTests: 1,
        testFailures: [
          ValidationTestFailure(
            testIdentifier: testIdentifier,
            failureText: failureText
          )
        ]
      )
    )
  }
}

enum ValidationProcessEvent: Equatable {
  case buildStarted(ValidationBuildDescriptor)
  case buildFinished(ValidationBuildDescriptor)
  case testStarted(ValidationScenarioDescriptor)
  case testFinished(ValidationScenarioDescriptor)
  case exportStarted(ValidationScenarioDescriptor)
  case exportFinished(ValidationScenarioDescriptor)
}

final class ValidationExecutionProbe: @unchecked Sendable {
  private let lock = NSLock()
  private var storage = [ValidationProcessEvent]()
  private var activeBuilds = 0
  private var activeTests = 0
  private var maxBuilds = 0
  private var maxTests = 0

  func started(_ event: ValidationProcessEvent) {
    lock.lock()
    storage.append(event)
    switch event {
    case .buildStarted:
      activeBuilds += 1
      maxBuilds = max(maxBuilds, activeBuilds)
    case .testStarted:
      activeTests += 1
      maxTests = max(maxTests, activeTests)
    default:
      break
    }
    lock.unlock()
  }

  func finished(_ event: ValidationProcessEvent) {
    lock.lock()
    storage.append(event)
    switch event {
    case .buildFinished:
      activeBuilds -= 1
    case .testFinished:
      activeTests -= 1
    default:
      break
    }
    lock.unlock()
  }

  var events: [ValidationProcessEvent] {
    lock.lock()
    defer { lock.unlock() }
    return storage
  }

  var maxConcurrentBuilds: Int {
    lock.lock()
    defer { lock.unlock() }
    return maxBuilds
  }

  var maxConcurrentTests: Int {
    lock.lock()
    defer { lock.unlock() }
    return maxTests
  }
}

final class ValidationProcessExecutorStub: ValidationProcessExecuting {
  private let lock = NSLock()
  private let fileManager: FileManager
  private let buildDelay: TimeInterval
  private let testDelay: TimeInterval
  private let exportDelay: TimeInterval
  private let probe: ValidationExecutionProbe?
  private var scenarioOutcomes: [ValidationScenarioDescriptor: [ValidationScenarioOutcomeStub]]
  private let buildFailures: [ValidationBuildDescriptor: ValidationCommandResult]
  private let summaryMode: XCResultCommandStubMode
  private let testsMode: XCResultCommandStubMode
  private var resultBundleSummaries = [String: ValidationTestSummary]()

  private(set) var runCommands = [ValidationCommand]()
  private(set) var startCommands = [ValidationCommand]()

  init(
    fileManager: FileManager = .default,
    buildDelay: TimeInterval = 0,
    testDelay: TimeInterval = 0,
    exportDelay: TimeInterval = 0,
    probe: ValidationExecutionProbe? = nil,
    scenarioOutcomes: [ValidationScenarioDescriptor: [ValidationScenarioOutcomeStub]] = [:],
    buildFailures: [ValidationBuildDescriptor: ValidationCommandResult] = [:],
    summaryMode: XCResultCommandStubMode = .success,
    testsMode: XCResultCommandStubMode = .success
  ) {
    self.fileManager = fileManager
    self.buildDelay = buildDelay
    self.testDelay = testDelay
    self.exportDelay = exportDelay
    self.probe = probe
    self.scenarioOutcomes = scenarioOutcomes
    self.buildFailures = buildFailures
    self.summaryMode = summaryMode
    self.testsMode = testsMode
  }

  var buildForTestingCommands: [ValidationCommand] {
    withLock {
      runCommands.filter { $0.arguments.contains("build-for-testing") }
    }
  }

  var testWithoutBuildingCommands: [ValidationCommand] {
    withLock {
      runCommands.filter { $0.arguments.contains("test-without-building") }
    }
  }

  func bootstatusCommandCount(for simulatorUDID: String) -> Int {
    withLock {
      runCommands.filter {
        $0.executable == "xcrun"
          && $0.arguments == ["simctl", "bootstatus", simulatorUDID, "-b"]
      }.count
    }
  }

  func run(_ command: ValidationCommand) throws -> ValidationCommandResult {
    withLock {
      runCommands.append(command)
    }

    switch command.executable {
    case "xcodebuild":
      return try handleXcodebuild(command)
    case "xcrun":
      return try handleXcrun(command)
    default:
      return ValidationCommandResult(exitStatus: 0, stdout: "", stderr: "")
    }
  }

  func start(_ command: ValidationCommand) throws -> RunningValidationCommand {
    withLock {
      startCommands.append(command)
    }
    if let outputPath = command.arguments.last, outputPath.hasSuffix(".mov") {
      let outputURL = URL(fileURLWithPath: outputPath)
      try fileManager.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try Data("video".utf8).write(to: outputURL)
    }
    return ValidationRunningCommandStub()
  }

  private func handleXcodebuild(_ command: ValidationCommand) throws -> ValidationCommandResult {
    if command.arguments.contains("build-for-testing") {
      let descriptor = try #require(ValidationBuildDescriptor.command(command))
      probe?.started(.buildStarted(descriptor))
      defer { probe?.finished(.buildFinished(descriptor)) }
      if buildDelay > 0 {
        Thread.sleep(forTimeInterval: buildDelay)
      }
      if let failure = buildFailures[descriptor] {
        return failure
      }
      let derivedDataPath = try #require(argument(after: "-derivedDataPath", in: command.arguments))
      let productsURL = URL(fileURLWithPath: derivedDataPath, isDirectory: true)
        .appendingPathComponent("Build/Products", isDirectory: true)
      try fileManager.createDirectory(at: productsURL, withIntermediateDirectories: true)
      try Data("stub".utf8).write(to: productsURL.appendingPathComponent("stub.xctestrun"))
      return ValidationCommandResult(exitStatus: 0, stdout: "", stderr: "")
    }

    if command.arguments.contains("test-without-building") {
      let resultBundlePath = try #require(argument(after: "-resultBundlePath", in: command.arguments))
      let descriptor = try #require(
        ValidationScenarioDescriptor.resultBundlePath(resultBundlePath)
      )
      probe?.started(.testStarted(descriptor))
      defer { probe?.finished(.testFinished(descriptor)) }
      if testDelay > 0 {
        Thread.sleep(forTimeInterval: testDelay)
      }
      let resultBundleURL = URL(fileURLWithPath: resultBundlePath, isDirectory: true)
      try fileManager.createDirectory(at: resultBundleURL, withIntermediateDirectories: true)

      let outcome = nextOutcome(for: descriptor)
      withLock {
        resultBundleSummaries[resultBundlePath] = outcome.summary
      }

      return ValidationCommandResult(exitStatus: outcome.exitStatus, stdout: "", stderr: "")
    }

    return ValidationCommandResult(exitStatus: 0, stdout: "", stderr: "")
  }

  private func handleXcrun(_ command: ValidationCommand) throws -> ValidationCommandResult {
    if command.arguments.starts(with: ["xcresulttool", "get", "test-results", "summary"]) {
      let resultBundlePath = try #require(argument(after: "--path", in: command.arguments))
      let summary = withLock {
        resultBundleSummaries[resultBundlePath, default: ValidationScenarioOutcomeStub.passed.summary]
      }
      return xcresultCommandResult(mode: summaryMode, defaultOutput: summaryPayload(for: summary))
    }

    if command.arguments.starts(with: ["xcresulttool", "get", "test-results", "tests"]) {
      return xcresultCommandResult(
        mode: testsMode,
        defaultOutput: """
        {"testNodes":[]}
        """
      )
    }

    if command.arguments.starts(with: ["xcresulttool", "export", "attachments"]) {
      let outputPath = try #require(argument(after: "--output-path", in: command.arguments))
      let descriptor = try #require(ValidationScenarioDescriptor.exportRootPath(outputPath))
      probe?.started(.exportStarted(descriptor))
      defer { probe?.finished(.exportFinished(descriptor)) }
      if exportDelay > 0 {
        Thread.sleep(forTimeInterval: exportDelay)
      }
      let exportRoot = URL(fileURLWithPath: outputPath, isDirectory: true)
      try fileManager.createDirectory(at: exportRoot, withIntermediateDirectories: true)
      try Data("png".utf8).write(to: exportRoot.appendingPathComponent("root.png"))
      try Data("audit body".utf8).write(to: exportRoot.appendingPathComponent("logs.txt"))
      try exportManifest.write(
        to: exportRoot.appendingPathComponent("manifest.json"),
        atomically: true,
        encoding: .utf8
      )
      return ValidationCommandResult(exitStatus: 0, stdout: "", stderr: "")
    }

    if command.arguments.count >= 6
      && command.arguments[0] == "simctl"
      && command.arguments[1] == "io"
      && command.arguments[3] == "screenshot"
    {
      let outputURL = URL(fileURLWithPath: command.arguments.last!)
      try fileManager.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try Data("png".utf8).write(to: outputURL)
      return ValidationCommandResult(exitStatus: 0, stdout: "", stderr: "")
    }

    return ValidationCommandResult(exitStatus: 0, stdout: "", stderr: "")
  }

  private func nextOutcome(for descriptor: ValidationScenarioDescriptor) -> ValidationScenarioOutcomeStub {
    withLock {
      guard var queued = scenarioOutcomes[descriptor], queued.isEmpty == false else {
        return .passed
      }

      let outcome = queued.removeFirst()
      scenarioOutcomes[descriptor] = queued
      return outcome
    }
  }

  private func argument(after flag: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
      return nil
    }
    return arguments[index + 1]
  }

  private func summaryPayload(for summary: ValidationTestSummary) -> String {
    let failures = summary.testFailures.map {
      """
      {"failureText":"\($0.failureText)","testIdentifierString":"\($0.testIdentifier)"}
      """
    }.joined(separator: ",")

    return """
    {"result":"\(summary.result)","passedTests":\(summary.passedTests),"failedTests":\(summary.failedTests),"testFailures":[\(failures)]}
    """
  }

  private let exportManifest = """
    [
      {
        "attachments": [
          {
            "configurationName": "Default",
            "deviceId": "stub-device",
            "deviceName": "Stub Device",
            "exportedFileName": "root.png",
            "isAssociatedWithFailure": false,
            "suggestedHumanReadableName": "surface=root__orientation=portrait__variant=base__artifact=screenshot_0_ABC.png",
            "timestamp": 1774771926.179
          },
          {
            "configurationName": "Default",
            "deviceId": "stub-device",
            "deviceName": "Stub Device",
            "exportedFileName": "logs.txt",
            "isAssociatedWithFailure": false,
            "suggestedHumanReadableName": "audit__checkpoint=logs__surface=logs.txt",
            "timestamp": 1774771926.179
          }
        ],
        "testIdentifier": "SymphonySwiftUIAppUITests/SymphonySwiftUIAppUITests/testAccessibilityAuditCoversRequiredCheckpoints()",
        "testIdentifierURL": "test://example"
      }
    ]
    """
}

extension ValidationProcessExecutorStub {
  func withLock<T>(_ body: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body()
  }
}
