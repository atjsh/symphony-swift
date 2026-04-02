import Foundation
import Testing

@testable import SymphonyHarness

@Test func testXcodeBootsSimulatorBeforeRunningTests() throws {
  try withTemporaryRepositoryFixture { repoRoot in
    let workspace = WorkspaceContext(
      projectRoot: repoRoot,
      buildStateRoot: repoRoot.appendingPathComponent(".build/harness", isDirectory: true),
      xcodeWorkspacePath: repoRoot.appendingPathComponent("Symphony.xcworkspace"),
      xcodeProjectPath: nil
    )
    let devices = [
      SimulatorDevice(
        name: "iPhone 17",
        udid: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
        state: "Shutdown",
        runtime: "iOS 26"
      )
    ]
    let bootSignals = SignalBox()
    let testSignals = SignalBox()

    let runner = RoutedProcessRunner { command, arguments, _, _, _ in
      if command == "xcrun",
        arguments.count >= 3,
        arguments[0] == "simctl",
        arguments[1] == "bootstatus"
      {
        bootSignals.append(arguments[2])
        return StubProcessRunner.success()
      }
      if command == "xcodebuild",
        arguments.contains("test")
      {
        testSignals.append("xcodebuild-test")
        return StubProcessRunner.success()
      }
      if command == "xcrun",
        arguments.prefix(2) == ["simctl", "boot"]
      {
        return StubProcessRunner.success()
      }
      return StubProcessRunner.success()
    }

    let tool = SymphonyHarnessTool(
      workspaceDiscovery: StubWorkspaceDiscovery(workspace: workspace),
      executionContextBuilder: ExecutionContextBuilder(),
      simulatorResolver: SimulatorResolver(
        catalog: StubSimulatorCatalog(devices: devices),
        processRunner: runner
      ),
      processRunner: runner,
      artifactManager: ArtifactManager(processRunner: runner),
      endpointOverrideStore: EndpointOverrideStore(),
      doctorService: StubDoctorService(
        report: DiagnosticsReport(issues: [], checkedPaths: [], checkedExecutables: []),
        rendered: "ok"),
      toolchainCapabilitiesResolver: StubToolchainCapabilitiesResolver(
        capabilities: .fullyAvailableForTests),
      productLocator: ProductLocator(processRunner: runner),
      commitHarness: CommitHarness(processRunner: runner),
      gitHookInstaller: GitHookInstaller(processRunner: runner),
      statusSink: { _ in }
    )

    _ = try tool.test(
      ExecutionRequest(
        command: .test,
        subjects: ["SymphonySwiftUIApp"],
        explicitTestSubjects: [],
        outputMode: .filtered
      )
    )

    #expect(bootSignals.values.contains("AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"))
    #expect(!testSignals.values.isEmpty)
  }
}

@Test func testXcodeSkipsBootForMacOSDestination() throws {
  try withTemporaryRepositoryFixture { repoRoot in
    let workspace = WorkspaceContext(
      projectRoot: repoRoot,
      buildStateRoot: repoRoot.appendingPathComponent(".build/harness", isDirectory: true),
      xcodeWorkspacePath: repoRoot.appendingPathComponent("Symphony.xcworkspace"),
      xcodeProjectPath: nil
    )
    let bootSignals = SignalBox()

    let runner = RoutedProcessRunner { command, arguments, _, _, _ in
      if command == "xcrun",
        arguments.count >= 3,
        arguments[0] == "simctl",
        arguments[1] == "bootstatus"
      {
        bootSignals.append(arguments[2])
        return StubProcessRunner.success()
      }
      if command == "swift" {
        if arguments == ["test", "--show-code-coverage-path"] {
          return StubProcessRunner.success(
            repoRoot.appendingPathComponent("missing-coverage.json").path + "\n")
        }
        return StubProcessRunner.success()
      }
      return StubProcessRunner.success()
    }

    let tool = SymphonyHarnessTool(
      workspaceDiscovery: StubWorkspaceDiscovery(workspace: workspace),
      executionContextBuilder: ExecutionContextBuilder(),
      simulatorResolver: SimulatorResolver(
        catalog: StubSimulatorCatalog(devices: []),
        processRunner: runner
      ),
      processRunner: runner,
      artifactManager: ArtifactManager(processRunner: runner),
      endpointOverrideStore: EndpointOverrideStore(),
      doctorService: StubDoctorService(
        report: DiagnosticsReport(issues: [], checkedPaths: [], checkedExecutables: []),
        rendered: "ok"),
      toolchainCapabilitiesResolver: StubToolchainCapabilitiesResolver(
        capabilities: .noXcodeForTests),
      productLocator: ProductLocator(processRunner: runner),
      commitHarness: CommitHarness(processRunner: runner),
      gitHookInstaller: GitHookInstaller(processRunner: runner),
      statusSink: { _ in }
    )

    _ = try tool.test(
      ExecutionRequest(
        command: .test,
        subjects: ["SymphonyServer"],
        explicitTestSubjects: [],
        outputMode: .filtered
      )
    )

    #expect(bootSignals.values.isEmpty)
  }
}

@Test func defaultAppValidationBootsAllDestinationsBeforeRunningPlans() throws {
  try withTemporaryRepositoryFixture { repoRoot in
    let testPlanRoot = repoRoot.appendingPathComponent(
      "SymphonyApps.xcodeproj/xcshareddata/xctestplans",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: testPlanRoot, withIntermediateDirectories: true)
    for name in [
      "SymphonySwiftUIApp.xctestplan",
      "SymphonySwiftUIAppUITests.xctestplan",
    ] {
      try #"""
      {
        "testTargets": [
          { "target": { "name": "SymphonySwiftUIAppUITests" } }
        ]
      }
      """#.write(
        to: testPlanRoot.appendingPathComponent(name),
        atomically: true,
        encoding: .utf8
      )
    }
    try #"""
    PRODUCT_BUNDLE_IDENTIFIER = dev.atjsh.symphony;
    PRODUCT_BUNDLE_IDENTIFIER = dev.atjsh.symphony.uitests;
    """#.write(
      to: repoRoot.appendingPathComponent("SymphonyApps.xcodeproj/project.pbxproj"),
      atomically: true,
      encoding: .utf8
    )

    let workspace = WorkspaceContext(
      projectRoot: repoRoot,
      buildStateRoot: repoRoot.appendingPathComponent(".build/harness", isDirectory: true),
      xcodeWorkspacePath: repoRoot.appendingPathComponent("Symphony.xcworkspace"),
      xcodeProjectPath: nil
    )
    let destinations = [
      SimulatorDevice(
        name: "iPhone 17",
        udid: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
        state: "Shutdown",
        runtime: "iOS 26"
      ),
      SimulatorDevice(
        name: "iPad Pro (M4)",
        udid: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB",
        state: "Shutdown",
        runtime: "iOS 26"
      ),
    ]
    let bootSignals = SignalBox()
    let testSignals = SignalBox()

    let runner = RoutedProcessRunner { command, arguments, _, _, _ in
      if command == "xcrun",
        arguments.count >= 3,
        arguments[0] == "simctl",
        arguments[1] == "bootstatus"
      {
        bootSignals.append(arguments[2])
        return StubProcessRunner.success()
      }
      if command == "xcodebuild", arguments.contains("test") {
        testSignals.append("xcodebuild-test")
        if let bundleIndex = arguments.firstIndex(of: "-resultBundlePath") {
          let bundlePath = URL(fileURLWithPath: arguments[bundleIndex + 1])
          try FileManager.default.createDirectory(at: bundlePath, withIntermediateDirectories: true)
        }
        return StubProcessRunner.success("validated")
      }
      return StubProcessRunner.success()
    }

    let coveragePath = repoRoot.appendingPathComponent(
      ".build/arm64-apple-macosx/debug/codecov/symphony-swift.json")
    try FileManager.default.createDirectory(
      at: coveragePath.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try #"""
    {
      "data": [
        {
          "files": [
            {
              "filename": "__REPO__/Sources/Covered.swift",
              "summary": { "lines": { "count": 4, "covered": 4 } }
            }
          ]
        }
      ]
    }
    """#
    .replacingOccurrences(of: "__REPO__", with: repoRoot.path)
    .write(to: coveragePath, atomically: true, encoding: .utf8)
    let perfectCoverage = CoverageReport(
      coveredLines: 4,
      executableLines: 4,
      lineCoverage: 1,
      includeTestTargets: false,
      excludedTargets: [],
      targets: []
    )
    let harnessRunner = StubProcessRunner(results: [
      "swift test --enable-code-coverage": StubProcessRunner.success(),
      "swift test --show-code-coverage-path": StubProcessRunner.success(coveragePath.path + "\n"),
    ])
    let tool = SymphonyHarnessTool(
      workspaceDiscovery: StubWorkspaceDiscovery(workspace: workspace),
      executionContextBuilder: ExecutionContextBuilder(),
      simulatorResolver: SimulatorResolver(
        catalog: StubSimulatorCatalog(devices: destinations),
        processRunner: runner
      ),
      processRunner: runner,
      artifactManager: ArtifactManager(processRunner: runner),
      endpointOverrideStore: EndpointOverrideStore(),
      doctorService: StubDoctorService(
        report: DiagnosticsReport(issues: [], checkedPaths: [], checkedExecutables: []),
        rendered: "ok"),
      toolchainCapabilitiesResolver: StubToolchainCapabilitiesResolver(
        capabilities: .fullyAvailableForTests),
      productLocator: ProductLocator(processRunner: runner),
      commitHarness: CommitHarness(
        processRunner: harnessRunner,
        statusSink: { _ in },
        clientCoverageLoader: { _ in perfectCoverage },
        serverCoverageLoader: { _ in perfectCoverage },
        toolchainCapabilitiesResolver: StubToolchainCapabilitiesResolver(
          capabilities: .fullyAvailableForTests)
      ),
      gitHookInstaller: GitHookInstaller(processRunner: runner),
      statusSink: { _ in }
    )

    let summaryPath = try tool.validate(
      ExecutionRequest(
        command: .validate,
        subjects: [],
        explicitTestSubjects: [],
        outputMode: .filtered
      )
    )

    #expect(FileManager.default.fileExists(atPath: summaryPath))
    let bootedUDIDs = Set(bootSignals.values)
    #expect(bootedUDIDs.contains("AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"))
    #expect(bootedUDIDs.contains("BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"))
    #expect(!testSignals.values.isEmpty)
  }
}
