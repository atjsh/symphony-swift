import Foundation
import SymphonyHarness
import Testing

@testable import SymphonyHarnessCLI

@Test func symphonyHarnessCommandUsesHarnessCommandName() {
  #expect(SymphonyHarnessCommand.configuration.commandName == "harness")
}

@Test func rootCommandExposesOnlyCanonicalPublicCommands() {
  #expect(SymphonyHarnessCommand.configuration.defaultSubcommand == nil)
  #expect(SymphonyHarnessCommand.configuration.subcommands.count == 5)
  #expect(SymphonyHarnessCommand.configuration.subcommands[0] == SymphonyHarnessCommand.Build.self)
  #expect(SymphonyHarnessCommand.configuration.subcommands[1] == SymphonyHarnessCommand.Test.self)
  #expect(SymphonyHarnessCommand.configuration.subcommands[2] == SymphonyHarnessCommand.Run.self)
  #expect(SymphonyHarnessCommand.configuration.subcommands[3] == SymphonyHarnessCommand.Validate.self)
  #expect(SymphonyHarnessCommand.configuration.subcommands[4] == SymphonyHarnessCommand.Doctor.self)
}

@Test func buildCommandParsesCanonicalSubjectsAndOutputMode() throws {
  let command =
    try SymphonyHarnessCommand.Build.parseAsRoot([
      "SymphonyShared",
      "SymphonyServerCLI",
      "--xcode-output-mode", "quiet",
    ]) as! SymphonyHarnessCommand.Build

  #expect(command.subjects == ["SymphonyShared", "SymphonyServerCLI"])
  #expect(command.xcodeOutputMode == .quiet)
}

@Test func testCommandDefaultsToDeferredSubjectExpansion() throws {
  let command = try SymphonyHarnessCommand.Test.parseAsRoot([]) as! SymphonyHarnessCommand.Test

  #expect(command.subjects.isEmpty)
  #expect(command.xcodeOutputMode == .filtered)
}

@Test func validateCommandDefaultsToDeferredSubjectExpansion() throws {
  let command =
    try SymphonyHarnessCommand.Validate.parseAsRoot([]) as! SymphonyHarnessCommand.Validate

  #expect(command.subjects.isEmpty)
  #expect(command.xcodeOutputMode == .filtered)
}

@Test func runCommandCapturesSingleSubjectAndEnvironmentOverrides() throws {
  let command =
    try SymphonyHarnessCommand.Run.parseAsRoot([
      "SymphonyServerCLI",
      "--env", "FOO=bar",
      "--env", "BAR=baz",
      "--xcode-output-mode", "full",
    ]) as! SymphonyHarnessCommand.Run

  #expect(command.subject == "SymphonyServerCLI")
  #expect(command.env == ["FOO=bar", "BAR=baz"])
  #expect(command.xcodeOutputMode == .full)
}

@Test func doctorCommandDefaultsToHumanNonStrictMode() throws {
  let command = try SymphonyHarnessCommand.Doctor.parseAsRoot([]) as! SymphonyHarnessCommand.Doctor

  #expect(command.strict == false)
  #expect(command.json == false)
  #expect(command.quiet == false)
}

@Test func buildCommandRejectsLegacyProductFlag() throws {
  do {
    _ = try SymphonyHarnessCommand.Build.parseAsRoot(["--product", "server"])
    Issue.record("Expected legacy --product parsing to fail.")
  } catch {
    #expect(String(describing: error).contains("--product"))
  }
}

@Test func cliContextDefaultsMatchCurrentProcessEnvironment() {
  try! CLIContext.withOverrides(
    toolFactory: { RecordingCLITool() },
    printer: { _ in },
    currentDirectoryProvider: {
      URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    }
  ) {
    let command = SymphonyHarnessCommand()

    #expect(type(of: command) == SymphonyHarnessCommand.self)
    #expect(CLIContext.currentDirectory().path == FileManager.default.currentDirectoryPath)
  }
}

@Test func cliContextDefaultFactoriesAndEmittersRemainUsable() {
  try! CLIContext.withOverrides(
    toolFactory: nil,
    printer: nil,
    currentDirectoryProvider: nil
  ) {
    #expect(CLIContext.makeTool() is SymphonyHarnessTool)
    #expect(CLIContext.currentDirectory().path == FileManager.default.currentDirectoryPath)
    CLIContext.emit("")
  }
}

@Test func commandRunsDispatchExecutionRequestsThroughCLIContext() throws {
  let tool = RecordingCLITool()
  let output = OutputBox()
  let currentDirectory = URL(fileURLWithPath: "/tmp/cli-context", isDirectory: true)

  try CLIContext.withOverrides(
    toolFactory: { tool },
    printer: { output.append($0) },
    currentDirectoryProvider: { currentDirectory }
  ) {
    var build =
      try SymphonyHarnessCommand.Build.parseAsRoot([
        "SymphonyShared",
        "SymphonyServerCLI",
        "--xcode-output-mode", "quiet",
      ]) as! SymphonyHarnessCommand.Build
    try build.run()

    var test =
      try SymphonyHarnessCommand.Test.parseAsRoot([
        "SymphonyServerCLI",
        "SymphonyServerCLITests",
      ]) as! SymphonyHarnessCommand.Test
    try test.run()

    var run =
      try SymphonyHarnessCommand.Run.parseAsRoot([
        "SymphonyServerCLI",
        "--server-url", "https://example.com:9443",
        "--env", "FOO=bar",
      ]) as! SymphonyHarnessCommand.Run
    try run.run()

    var validate =
      try SymphonyHarnessCommand.Validate.parseAsRoot([
        "SymphonyShared",
        "SymphonySwiftUIApp",
      ]) as! SymphonyHarnessCommand.Validate
    try validate.run()

    var doctor =
      try SymphonyHarnessCommand.Doctor.parseAsRoot(["--strict", "--json", "--quiet"])
      as! SymphonyHarnessCommand.Doctor
    try doctor.run()
  }

  #expect(tool.executionRequests.count == 4)
  #expect(tool.executionRequests[0].command == .build)
  #expect(tool.executionRequests[0].subjects == ["SymphonyShared", "SymphonyServerCLI"])
  #expect(tool.executionRequests[0].explicitTestSubjects.isEmpty)
  #expect(tool.executionRequests[0].outputMode == .quiet)

  #expect(tool.executionRequests[1].command == .test)
  #expect(tool.executionRequests[1].subjects == ["SymphonyServerCLI"])
  #expect(tool.executionRequests[1].explicitTestSubjects == ["SymphonyServerCLITests"])

  #expect(tool.executionRequests[2].command == .run)
  #expect(tool.executionRequests[2].subjects == ["SymphonyServerCLI"])
  #expect(
    tool.executionRequests[2].environment == [
      "FOO": "bar",
      "SYMPHONY_SERVER_SCHEME": "https",
      "SYMPHONY_SERVER_HOST": "example.com",
      "SYMPHONY_SERVER_PORT": "9443",
    ])

  #expect(tool.executionRequests[3].command == .validate)
  #expect(tool.executionRequests[3].subjects == ["SymphonyShared", "SymphonySwiftUIApp"])
  #expect(tool.executionRequests[3].outputMode == .filtered)

  #expect(tool.doctorRequests.count == 1)
  #expect(tool.doctorRequests[0].strict == true)
  #expect(tool.doctorRequests[0].json == true)
  #expect(tool.doctorRequests[0].quiet == true)
  #expect(tool.doctorRequests[0].currentDirectory == currentDirectory)

  #expect(
    output.values == [
      "build-output",
      "test-output",
      "run-output",
      "validate-output",
      "doctor-output",
    ])
}

@Test func runCommandRejectsInvalidEnvironmentOverrideFormat() throws {
  let tool = RecordingCLITool()

  do {
    try CLIContext.withOverrides(
      toolFactory: { tool },
      printer: { _ in },
      currentDirectoryProvider: { URL(fileURLWithPath: "/tmp/cli-context", isDirectory: true) }
    ) {
      var run =
        try SymphonyHarnessCommand.Run.parseAsRoot([
          "SymphonyServerCLI",
          "--env", "BROKEN",
        ]) as! SymphonyHarnessCommand.Run
      try run.run()
    }
    Issue.record("Expected invalid KEY=VALUE environment input to fail.")
  } catch {
    #expect(String(describing: error).contains("KEY=VALUE"))
    #expect(tool.executionRequests.isEmpty)
  }
}

@Test func runCommandRejectsInvalidServerURLOverride() throws {
  let tool = RecordingCLITool()

  do {
    try CLIContext.withOverrides(
      toolFactory: { tool },
      printer: { _ in },
      currentDirectoryProvider: { URL(fileURLWithPath: "/tmp/cli-context", isDirectory: true) }
    ) {
      var run =
        try SymphonyHarnessCommand.Run.parseAsRoot([
          "SymphonySwiftUIApp",
          "--server-url", "https://example.com",
        ]) as! SymphonyHarnessCommand.Run
      try run.run()
    }
    Issue.record("Expected invalid server URL input to fail.")
  } catch {
    #expect(String(describing: error).contains("scheme, host, and port"))
    #expect(tool.executionRequests.isEmpty)
  }
}

private final class RecordingCLITool: SymphonyHarnessTooling {
  var executionRequests = [ExecutionRequest]()
  var doctorRequests = [DoctorCommandRequest]()

  func build(_ request: ExecutionRequest) throws -> String {
    executionRequests.append(request)
    return "build-output"
  }

  func test(_ request: ExecutionRequest) throws -> String {
    executionRequests.append(request)
    return "test-output"
  }

  func run(_ request: ExecutionRequest) throws -> String {
    executionRequests.append(request)
    return "run-output"
  }

  func validate(_ request: ExecutionRequest) throws -> String {
    executionRequests.append(request)
    return "validate-output"
  }

  func doctor(_ request: DoctorCommandRequest) throws -> String {
    doctorRequests.append(request)
    return "doctor-output"
  }
}

private final class OutputBox {
  private(set) var values = [String]()

  func append(_ value: String) {
    values.append(value)
  }
}
