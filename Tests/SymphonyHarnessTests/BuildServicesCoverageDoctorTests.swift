import Foundation
import Testing

@testable import SymphonyHarness

@Test func simulatorResolverValidationDestinationsRequireBothIPhoneAndIPad() throws {
  do {
    _ = try SimulatorResolver(
      catalog: StubSimulatorCatalog(
        devices: [
          SimulatorDevice(
            name: "iPad Pro (M4)",
            udid: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB",
            state: "Shutdown",
            runtime: "iOS 18"
          )
        ]
      ),
      processRunner: StubProcessRunner()
    ).approvedValidationDestinations()
    Issue.record("Expected missing iPhone validation destination to fail.")
  } catch let error as SymphonyHarnessError {
    #expect(error.code == "missing_iphone_validation_destination")
  }

  do {
    _ = try SimulatorResolver(
      catalog: StubSimulatorCatalog(
        devices: [
          SimulatorDevice(
            name: "iPhone 17",
            udid: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
            state: "Shutdown",
            runtime: "iOS 18"
          )
        ]
      ),
      processRunner: StubProcessRunner()
    ).approvedValidationDestinations()
    Issue.record("Expected missing iPad validation destination to fail.")
  } catch let error as SymphonyHarnessError {
    #expect(error.code == "missing_ipad_validation_destination")
  }

  do {
    _ = try SimulatorResolver(
      catalog: StubSimulatorCatalog(devices: []),
      processRunner: StubProcessRunner()
    ).resolve(DestinationSelector(platform: .iosSimulator))
    Issue.record("Expected empty simulator catalogs to fail default resolution.")
  } catch let error as SymphonyHarnessError {
    #expect(error.code == "missing_simulator")
  }
}

@Test func doctorServiceSupportsProjectOnlySchemeDiscovery() throws {
  let runner = StubProcessRunner(results: [
    "which swift": StubProcessRunner.success(),
    "which xcodebuild": StubProcessRunner.success(),
    "xcrun simctl help": StubProcessRunner.success(),
    "xcrun xcresulttool help": StubProcessRunner.success(),
    "which xcrun": StubProcessRunner.success(),
    "xcodebuild -list -json -project /tmp/repo/SymphonyApps.xcodeproj": StubProcessRunner.success(
      #"{"project":{"schemes":["SymphonySwiftUIApp"]}}"#),
  ])
  let discovery = StubWorkspaceDiscovery(
    workspace: WorkspaceContext(
      projectRoot: URL(fileURLWithPath: "/tmp/repo", isDirectory: true),
      buildStateRoot: URL(fileURLWithPath: "/tmp/repo/.build/harness", isDirectory: true),
      xcodeWorkspacePath: nil,
      xcodeProjectPath: URL(fileURLWithPath: "/tmp/repo/SymphonyApps.xcodeproj")
    )
  )
  let service = DoctorService(
    workspaceDiscovery: discovery,
    processRunner: runner,
    toolchainCapabilitiesResolver: StubToolchainCapabilitiesResolver(
      capabilities: .fullyAvailableForTests)
  )

  let report = try service.makeReport(
    from: DoctorCommandRequest(
      strict: false, json: false, quiet: false, currentDirectory: URL(fileURLWithPath: "/tmp/repo"))
  )

  #expect(report.issues.isEmpty)
}

@Test func doctorServiceSupportsWorkspaceOnlySchemeDiscovery() throws {
  let runner = StubProcessRunner(results: [
    "which swift": StubProcessRunner.success(),
    "which xcodebuild": StubProcessRunner.success(),
    "xcrun simctl help": StubProcessRunner.success(),
    "xcrun xcresulttool help": StubProcessRunner.success(),
    "which xcrun": StubProcessRunner.success(),
    "xcodebuild -list -json -workspace /tmp/repo/Symphony.xcworkspace": StubProcessRunner.success(
      #"{"workspace":{"schemes":["SymphonySwiftUIApp"]}}"#),
  ])
  let discovery = StubWorkspaceDiscovery(
    workspace: WorkspaceContext(
      projectRoot: URL(fileURLWithPath: "/tmp/repo", isDirectory: true),
      buildStateRoot: URL(fileURLWithPath: "/tmp/repo/.build/harness", isDirectory: true),
      xcodeWorkspacePath: URL(fileURLWithPath: "/tmp/repo/Symphony.xcworkspace"),
      xcodeProjectPath: nil
    )
  )
  let service = DoctorService(
    workspaceDiscovery: discovery,
    processRunner: runner,
    toolchainCapabilitiesResolver: StubToolchainCapabilitiesResolver(
      capabilities: .fullyAvailableForTests)
  )

  let report = try service.makeReport(
    from: DoctorCommandRequest(
      strict: false, json: false, quiet: false, currentDirectory: URL(fileURLWithPath: "/tmp/repo"))
  )

  #expect(report.issues.isEmpty)
}

@Test func doctorReportsMissingXcodeTestPlansAndLegacyProjectYML() throws {
  try withTemporaryDirectory { directory in
    let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
    try FileManager.default.createDirectory(at: repoRoot, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent(".build/harness"), withIntermediateDirectories: true)
    try "# root package".write(
      to: repoRoot.appendingPathComponent("Package.swift"),
      atomically: true,
      encoding: .utf8
    )
    try "name: Symphony".write(
      to: repoRoot.appendingPathComponent("project.yml"),
      atomically: true,
      encoding: .utf8
    )

    let service = DoctorService(
      workspaceDiscovery: StubWorkspaceDiscovery(
        workspace: WorkspaceContext(
          projectRoot: repoRoot,
          buildStateRoot: repoRoot.appendingPathComponent(".build/harness", isDirectory: true),
          xcodeWorkspacePath: URL(fileURLWithPath: "/tmp/Symphony.xcworkspace"),
          xcodeProjectPath: nil
        )),
      processRunner: StubProcessRunner(results: [
        "which swift": StubProcessRunner.success()
      ]),
      toolchainCapabilitiesResolver: StubToolchainCapabilitiesResolver(capabilities: .noXcodeForTests)
    )

    let report = try service.makeReport(
      from: DoctorCommandRequest(strict: false, json: false, quiet: false, currentDirectory: repoRoot)
    )
    #expect(report.issues.contains(where: { $0.code == "legacy_project_manifest" }))
    #expect(report.issues.contains(where: { $0.code == "missing_xctestplan" }))
  }
}

