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

@Test func coverageCommandUsesSpecDefaults() throws {
    let command = try SymphonyBuildCommand.Coverage.parseAsRoot([]) as! SymphonyBuildCommand.Coverage

    #expect(command.product == .client)
    #expect(command.worker == 0)
    #expect(command.onlyTesting.isEmpty)
    #expect(command.skipTesting.isEmpty)
    #expect(command.json == false)
    #expect(command.showFiles == false)
    #expect(command.includeTestTargets == false)
    #expect(command.xcodeOutputMode == .filtered)
}

@Test func harnessCommandUsesSpecDefaults() throws {
    let command = try SymphonyBuildCommand.Harness.parseAsRoot([]) as! SymphonyBuildCommand.Harness

    #expect(command.minimumCoverage == 50)
    #expect(command.json == false)
}

@Test func commandsParseExplicitXcodeOutputModes() throws {
    let build = try SymphonyBuildCommand.Build.parseAsRoot(["--xcode-output-mode", "full"]) as! SymphonyBuildCommand.Build
    let test = try SymphonyBuildCommand.Test.parseAsRoot(["--xcode-output-mode", "quiet"]) as! SymphonyBuildCommand.Test
    let coverage = try SymphonyBuildCommand.Coverage.parseAsRoot(["--xcode-output-mode", "full"]) as! SymphonyBuildCommand.Coverage
    let run = try SymphonyBuildCommand.Run.parseAsRoot(["--xcode-output-mode", "full"]) as! SymphonyBuildCommand.Run

    #expect(build.xcodeOutputMode == .full)
    #expect(test.xcodeOutputMode == .quiet)
    #expect(coverage.xcodeOutputMode == .full)
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
    let command = try SymphonyBuildCommand.Artifacts.parseAsRoot(["coverage", "--run", "20260324-120000-symphony"]) as! SymphonyBuildCommand.Artifacts

    #expect(command.command == .coverage)
    #expect(command.runID == "20260324-120000-symphony")
    #expect(command.latest == false)
}

@Test func doctorCommandDefaultsToHumanNonStrictMode() throws {
    let command = try SymphonyBuildCommand.Doctor.parseAsRoot([]) as! SymphonyBuildCommand.Doctor

    #expect(command.strict == false)
    #expect(command.json == false)
    #expect(command.quiet == false)
}
