import Foundation
import Testing
@testable import SymphonyBuildCLI
import SymphonyBuildCore

@Test func buildCommandUsesSpecDefaults() throws {
    let command = try SymphonyBuildCommand.Build.parseAsRoot([]) as! SymphonyBuildCommand.Build

    #expect(command.product == .client)
    #expect(command.worker == 0)
    #expect(command.xcodeOutputMode == .filtered)
}

@Test func testCommandUsesSpecDefaults() throws {
    let command = try SymphonyBuildCommand.Test.parseAsRoot([]) as! SymphonyBuildCommand.Test

    #expect(command.product == .client)
    #expect(command.worker == 0)
    #expect(command.onlyTesting.isEmpty)
    #expect(command.skipTesting.isEmpty)
}

@Test func harnessCommandUsesSpecDefaults() throws {
    let command = try SymphonyBuildCommand.Harness.parseAsRoot([]) as! SymphonyBuildCommand.Harness

    #expect(command.minimumCoverage == 100)
    #expect(command.json == false)
    #expect(command.outputMode == .filtered)
}

@Test func harnessCommandParsesOutputMode() throws {
    let command = try SymphonyBuildCommand.Harness.parseAsRoot(["--output-mode", "quiet"]) as! SymphonyBuildCommand.Harness

    #expect(command.outputMode == .quiet)
}

@Test func commandsParseExplicitXcodeOutputModes() throws {
    let build = try SymphonyBuildCommand.Build.parseAsRoot(["--xcode-output-mode", "full"]) as! SymphonyBuildCommand.Build
    let test = try SymphonyBuildCommand.Test.parseAsRoot(["--xcode-output-mode", "quiet"]) as! SymphonyBuildCommand.Test
    let run = try SymphonyBuildCommand.Run.parseAsRoot(["--xcode-output-mode", "full"]) as! SymphonyBuildCommand.Run

    #expect(build.xcodeOutputMode == .full)
    #expect(test.xcodeOutputMode == .quiet)
    #expect(run.xcodeOutputMode == .full)
}

@Test func hooksInstallCommandParses() throws {
    let command = try SymphonyBuildCommand.Hooks.Install.parseAsRoot([]) as! SymphonyBuildCommand.Hooks.Install

    #expect(type(of: command) == SymphonyBuildCommand.Hooks.Install.self)
}

@Test func runCommandDefaultsToServerAndCapturesEnvOverrides() throws {
    let command = try SymphonyBuildCommand.Run.parseAsRoot(["--env", "FOO=bar", "--env", "BAR=baz"]) as! SymphonyBuildCommand.Run

    #expect(command.product == .server)
    #expect(command.worker == 0)
    #expect(command.env == ["FOO=bar", "BAR=baz"])
}

@Test func simCommandsParseBootSetServerAndClearServerOptions() throws {
    let list = try SymphonyBuildCommand.Sim.List.parseAsRoot([]) as! SymphonyBuildCommand.Sim.List
    let boot = try SymphonyBuildCommand.Sim.Boot.parseAsRoot(["--simulator", "iPhone 17 Pro"]) as! SymphonyBuildCommand.Sim.Boot
    let setServer = try SymphonyBuildCommand.Sim.SetServer.parseAsRoot([
        "--scheme", "https",
        "--host", "api.example.com",
        "--port", "9443",
    ]) as! SymphonyBuildCommand.Sim.SetServer
    let clearServer = try SymphonyBuildCommand.Sim.ClearServer.parseAsRoot([]) as! SymphonyBuildCommand.Sim.ClearServer

    #expect(type(of: list) == SymphonyBuildCommand.Sim.List.self)
    #expect(boot.simulator == "iPhone 17 Pro")
    #expect(setServer.scheme == "https")
    #expect(setServer.host == "api.example.com")
    #expect(setServer.port == 9443)
    #expect(type(of: clearServer) == SymphonyBuildCommand.Sim.ClearServer.self)
}

@Test func artifactsCommandDefaultsToBuildFamily() throws {
    let command = try SymphonyBuildCommand.Artifacts.parseAsRoot([]) as! SymphonyBuildCommand.Artifacts

    #expect(command.command == .build)
    #expect(command.runID == nil)
}

@Test func artifactsCommandAllowsExplicitRunSelection() throws {
    let command = try SymphonyBuildCommand.Artifacts.parseAsRoot(["test", "--run", "20260324-120000-symphony"]) as! SymphonyBuildCommand.Artifacts

    #expect(command.command == .test)
    #expect(command.runID == "20260324-120000-symphony")
    #expect(command.latest == false)
}

@Test func artifactsCommandSupportsHarnessFamily() throws {
    let command = try SymphonyBuildCommand.Artifacts.parseAsRoot(["harness"]) as! SymphonyBuildCommand.Artifacts

    #expect(command.command == .harness)
    #expect(command.latest == false)
    #expect(command.runID == nil)
}

@Test func doctorCommandDefaultsToHumanNonStrictMode() throws {
    let command = try SymphonyBuildCommand.Doctor.parseAsRoot([]) as! SymphonyBuildCommand.Doctor

    #expect(command.strict == false)
    #expect(command.json == false)
    #expect(command.quiet == false)
}

@Test func cliContextDefaultsMatchCurrentProcessEnvironment() {
    try! CLIContext.withOverrides(
        toolFactory: { RecordingCLITool() },
        printer: { _ in },
        currentDirectoryProvider: { URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true) }
    ) {
        let command = SymphonyBuildCommand()

        #expect(type(of: command) == SymphonyBuildCommand.self)
        #expect(CLIContext.currentDirectory().path == FileManager.default.currentDirectoryPath)
    }
}

@Test func cliContextDefaultFactoriesAndEmittersRemainUsable() {
    try! CLIContext.withOverrides(
        toolFactory: nil,
        printer: nil,
        currentDirectoryProvider: nil
    ) {
        #expect(CLIContext.makeTool() is SymphonyBuildTool)
        #expect(CLIContext.currentDirectory().path == FileManager.default.currentDirectoryPath)
        CLIContext.emit("")
    }
}

@Test func commandRunsDispatchRequestsThroughCLIContext() throws {
    let tool = RecordingCLITool()
    let output = OutputBox()
    let currentDirectory = URL(fileURLWithPath: "/tmp/cli-context", isDirectory: true)

    try CLIContext.withOverrides(
        toolFactory: { tool },
        printer: { output.append($0) },
        currentDirectoryProvider: { currentDirectory }
    ) {
        var build = try SymphonyBuildCommand.Build.parseAsRoot(["--product", "server", "--dry-run", "--worker", "7"]) as! SymphonyBuildCommand.Build
        try build.run()

        var test = try SymphonyBuildCommand.Test.parseAsRoot(["--product", "server", "--only-testing", "Suite/testThing"]) as! SymphonyBuildCommand.Test
        try test.run()

        var run = try SymphonyBuildCommand.Run.parseAsRoot(["--env", "FOO=bar", "--host", "example.com", "--port", "9443"]) as! SymphonyBuildCommand.Run
        try run.run()

        var harness = try SymphonyBuildCommand.Harness.parseAsRoot(["--minimum-coverage", "88", "--json"]) as! SymphonyBuildCommand.Harness
        try harness.run()

        var list = try SymphonyBuildCommand.Sim.List.parseAsRoot([]) as! SymphonyBuildCommand.Sim.List
        try list.run()

        var boot = try SymphonyBuildCommand.Sim.Boot.parseAsRoot(["--simulator", "AAAA-BBBB"]) as! SymphonyBuildCommand.Sim.Boot
        try boot.run()

        var setServer = try SymphonyBuildCommand.Sim.SetServer.parseAsRoot(["--server-url", "http://localhost:9000"]) as! SymphonyBuildCommand.Sim.SetServer
        try setServer.run()

        var clearServer = try SymphonyBuildCommand.Sim.ClearServer.parseAsRoot([]) as! SymphonyBuildCommand.Sim.ClearServer
        try clearServer.run()

        var install = try SymphonyBuildCommand.Hooks.Install.parseAsRoot([]) as! SymphonyBuildCommand.Hooks.Install
        try install.run()

        var artifacts = try SymphonyBuildCommand.Artifacts.parseAsRoot(["harness", "--run", "run-1"]) as! SymphonyBuildCommand.Artifacts
        try artifacts.run()

        var doctor = try SymphonyBuildCommand.Doctor.parseAsRoot(["--strict", "--json", "--quiet"]) as! SymphonyBuildCommand.Doctor
        try doctor.run()
    }

    #expect(tool.buildRequests.count == 1)
    #expect(tool.buildRequests[0].product == .server)
    #expect(tool.buildRequests[0].workerID == 7)
    #expect(tool.buildRequests[0].currentDirectory == currentDirectory)

    #expect(tool.testRequests.count == 1)
    #expect(tool.testRequests[0].onlyTesting == ["Suite/testThing"])
    #expect(tool.testRequests[0].currentDirectory == currentDirectory)

    #expect(tool.runRequests.count == 1)
    #expect(tool.runRequests[0].environment == ["FOO": "bar"])
    #expect(tool.runRequests[0].host == "example.com")
    #expect(tool.runRequests[0].port == 9443)

    #expect(tool.harnessRequests.count == 1)
    #expect(tool.harnessRequests[0].minimumCoveragePercent == 88)
    #expect(tool.harnessRequests[0].json == true)
    #expect(tool.harnessRequests[0].outputMode == .filtered)

    #expect(tool.simListDirectories == [currentDirectory])
    #expect(tool.simBootRequests.map(\.simulator) == ["AAAA-BBBB"])
    #expect(tool.simSetServerRequests.map(\.serverURL) == ["http://localhost:9000"])
    #expect(tool.simClearServerDirectories == [currentDirectory])
    #expect(tool.hooksInstallRequests.map(\.currentDirectory) == [currentDirectory])
    #expect(tool.artifactsRequests.map(\.command) == [.harness])
    #expect(tool.artifactsRequests.map(\.runID) == ["run-1"])
    #expect(tool.doctorRequests.count == 1)
    #expect(tool.doctorRequests[0].strict == true)
    #expect(tool.doctorRequests[0].json == true)
    #expect(tool.doctorRequests[0].quiet == true)

    #expect(output.values == [
        "build-output",
        "test-output",
        "run-output",
        "harness-output",
        "sim-list-output",
        "sim-boot-output",
        "sim-set-server-output",
        "sim-clear-server-output",
        "hooks-install-output",
        "artifacts-output",
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
            var run = try SymphonyBuildCommand.Run.parseAsRoot(["--env", "BROKEN"]) as! SymphonyBuildCommand.Run
            try run.run()
        }
        Issue.record("Expected invalid KEY=VALUE environment input to fail.")
    } catch {
        #expect(String(describing: error).contains("KEY=VALUE"))
        #expect(tool.runRequests.isEmpty)
    }
}

private final class RecordingCLITool: SymphonyBuildTooling {
    var buildRequests = [BuildCommandRequest]()
    var testRequests = [TestCommandRequest]()
    var runRequests = [RunCommandRequest]()
    var harnessRequests = [HarnessCommandRequest]()
    var hooksInstallRequests = [HooksInstallRequest]()
    var simListDirectories = [URL]()
    var simBootRequests = [SimBootRequest]()
    var simSetServerRequests = [SimSetServerRequest]()
    var simClearServerDirectories = [URL]()
    var artifactsRequests = [ArtifactsCommandRequest]()
    var doctorRequests = [DoctorCommandRequest]()

    func build(_ request: BuildCommandRequest) throws -> String {
        buildRequests.append(request)
        return "build-output"
    }

    func test(_ request: TestCommandRequest) throws -> String {
        testRequests.append(request)
        return "test-output"
    }

    func run(_ request: RunCommandRequest) throws -> String {
        runRequests.append(request)
        return "run-output"
    }

    func harness(_ request: HarnessCommandRequest) throws -> String {
        harnessRequests.append(request)
        return "harness-output"
    }

    func hooksInstall(_ request: HooksInstallRequest) throws -> String {
        hooksInstallRequests.append(request)
        return "hooks-install-output"
    }

    func simList(currentDirectory: URL) throws -> String {
        simListDirectories.append(currentDirectory)
        return "sim-list-output"
    }

    func simBoot(_ request: SimBootRequest) throws -> String {
        simBootRequests.append(request)
        return "sim-boot-output"
    }

    func simSetServer(_ request: SimSetServerRequest) throws -> String {
        simSetServerRequests.append(request)
        return "sim-set-server-output"
    }

    func simClearServer(currentDirectory: URL) throws -> String {
        simClearServerDirectories.append(currentDirectory)
        return "sim-clear-server-output"
    }

    func artifacts(_ request: ArtifactsCommandRequest) throws -> String {
        artifactsRequests.append(request)
        return "artifacts-output"
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
