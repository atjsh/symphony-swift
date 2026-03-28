import Foundation
import Testing

@testable import SymphonyHarness

@Test func diagnosticsReportCapturesToolAvailability() {
  let report = DiagnosticsReport(
    issues: [],
    notes: [],
    checkedPaths: ["/tmp/repo"],
    checkedExecutables: ["swift", "just"],
    xcodeAvailability: true,
    justAvailability: false
  )

  #expect(report.xcodeAvailability)
  #expect(report.justAvailability == false)
}

@Test func doctorServiceReportsMigrationPolicyGaps() throws {
  try withTemporaryDirectory { directory in
    let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
    try FileManager.default.createDirectory(at: repoRoot, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent("Symphony.xcworkspace"), withIntermediateDirectories: true
    )
    try "# root package".write(
      to: repoRoot.appendingPathComponent("Package.swift"),
      atomically: true,
      encoding: .utf8
    )
    try "legacy".write(
      to: repoRoot.appendingPathComponent("project.yml"),
      atomically: true,
      encoding: .utf8
    )
    let nestedPackageRoot = repoRoot.appendingPathComponent("Fixtures/SamplePackage", isDirectory: true)
    try FileManager.default.createDirectory(at: nestedPackageRoot, withIntermediateDirectories: true)
    try "# nested package".write(
      to: nestedPackageRoot.appendingPathComponent("Package.swift"),
      atomically: true,
      encoding: .utf8
    )
    let schemeRoot = repoRoot.appendingPathComponent(
      "SymphonyApps.xcodeproj/xcshareddata/xcschemes",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: schemeRoot, withIntermediateDirectories: true)
    try """
      <Scheme>
        <TestAction>
          <TestPlans>
            <TestPlanReference reference = "container:SymphonySwiftUIApp.xctestplan"></TestPlanReference>
          </TestPlans>
        </TestAction>
      </Scheme>
      """.write(
      to: schemeRoot.appendingPathComponent("SymphonySwiftUIApp.xcscheme"),
      atomically: true,
      encoding: .utf8
    )

    let discovery = StubWorkspaceDiscovery(
      workspace: WorkspaceContext(
        projectRoot: repoRoot,
        buildStateRoot: repoRoot.appendingPathComponent(".build/harness", isDirectory: true),
        xcodeWorkspacePath: repoRoot.appendingPathComponent("Symphony.xcworkspace"),
        xcodeProjectPath: nil
      )
    )
    let runner = StubProcessRunner(results: [
      "which just": StubProcessRunner.failure("not found"),
      "xcodebuild -list -json -workspace \(repoRoot.appendingPathComponent("Symphony.xcworkspace").path)":
        StubProcessRunner.success(#"{"workspace":{"schemes":["SymphonySwiftUIApp"]}}"#),
    ])
    let service = DoctorService(
      workspaceDiscovery: discovery,
      processRunner: runner,
      toolchainCapabilitiesResolver: StubToolchainCapabilitiesResolver(
        capabilities: .fullyAvailableForTests)
    )

    let report = try service.makeReport(
      from: DoctorCommandRequest(
        strict: false,
        json: false,
        quiet: false,
        currentDirectory: repoRoot
      )
    )

    #expect(report.xcodeAvailability)
    #expect(report.justAvailability == false)
    #expect(report.checkedExecutables.contains("just"))
    #expect(report.issues.contains { $0.code == "missing_just" })
    #expect(report.issues.contains { $0.code == "extra_package_manifest" })
    #expect(report.issues.contains { $0.code == "legacy_project_manifest" })
    #expect(report.issues.contains { $0.code == "missing_xctestplan" })
    #expect(report.issues.contains { $0.code == "missing_xcscheme_symphonyswiftuiappuitests" })
    #expect(report.issues.contains { $0.code == "missing_testplan_reference_symphonyswiftuiapp" })
    #expect(!report.issues.contains { $0.code == "missing_scheme_symphonyswiftuiapp" })
  }
}

@Test func doctorServiceRecognizesMultipleCheckedInTestPlans() throws {
  try withTemporaryDirectory { directory in
    let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
    try FileManager.default.createDirectory(at: repoRoot, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent("Symphony.xcworkspace"),
      withIntermediateDirectories: true
    )
    try "# root package".write(
      to: repoRoot.appendingPathComponent("Package.swift"),
      atomically: true,
      encoding: .utf8
    )

    let testPlanRoot = repoRoot.appendingPathComponent(
      "SymphonyApps.xcodeproj/xcshareddata/xctestplans",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: testPlanRoot, withIntermediateDirectories: true)
    try "{}".write(
      to: testPlanRoot.appendingPathComponent("SymphonySwiftUIAppUITests.xctestplan"),
      atomically: true,
      encoding: .utf8
    )
    try "{}".write(
      to: testPlanRoot.appendingPathComponent("SymphonySwiftUIApp.xctestplan"),
      atomically: true,
      encoding: .utf8
    )

    let discovery = StubWorkspaceDiscovery(
      workspace: WorkspaceContext(
        projectRoot: repoRoot,
        buildStateRoot: repoRoot.appendingPathComponent(".build/harness", isDirectory: true),
        xcodeWorkspacePath: repoRoot.appendingPathComponent("Symphony.xcworkspace"),
        xcodeProjectPath: nil
      )
    )
    let service = DoctorService(
      workspaceDiscovery: discovery,
      processRunner: StubProcessRunner(),
      toolchainCapabilitiesResolver: StubToolchainCapabilitiesResolver(
        capabilities: .noXcodeForTests
      )
    )

    let report = try service.makeReport(
      from: DoctorCommandRequest(
        strict: false,
        json: false,
        quiet: false,
        currentDirectory: repoRoot
      )
    )

    #expect(!report.issues.contains { $0.code == "missing_xctestplan" })
  }
}
