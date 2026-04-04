import Foundation
import Testing

@testable import SymphonyHarness

@Test func validateExecutionBridgeRemovesStaleResultBundlesBeforeRunningCheckedInPlans() throws {
  try withTemporaryRepositoryFixture { repoRoot in
    let testPlanRoot = repoRoot.appendingPathComponent(
      "SymphonyApps.xcodeproj/xcshareddata/xctestplans",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: testPlanRoot, withIntermediateDirectories: true)
    for name in [
      "SymphonySwiftUIApp.xctestplan",
      "SymphonySwiftUIAppTests.xctestplan",
      "SymphonySwiftUIAppUITests.xctestplan",
    ] {
      try "{}\n".write(
        to: testPlanRoot.appendingPathComponent(name),
        atomically: true,
        encoding: .utf8
      )
    }
    try #"""
    PRODUCT_BUNDLE_IDENTIFIER = dev.atjsh.symphony;
    PRODUCT_BUNDLE_IDENTIFIER = dev.atjsh.symphony.tests;
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
        runtime: "iOS 18"
      ),
      SimulatorDevice(
        name: "iPad Pro (M4)",
        udid: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB",
        state: "Shutdown",
        runtime: "iOS 18"
      ),
    ]
    for testPlan in ["SymphonySwiftUIApp", "SymphonySwiftUIAppTests", "SymphonySwiftUIAppUITests"] {
      for destination in destinations {
        let slug = ShellQuoting.slugify("\(testPlan)-\(destination.name)")
        let staleBundle = workspace.buildStateRoot.appendingPathComponent(
          "results/SymphonySwiftUIApp/\(slug).xcresult",
          isDirectory: true
        )
        try FileManager.default.createDirectory(
          at: staleBundle,
          withIntermediateDirectories: true
        )
      }
    }

    let runner = RoutedProcessRunner { command, arguments, _, _, _ in
      if command == "xcodebuild", arguments.last == "test" {
        guard let bundleIndex = arguments.firstIndex(of: "-resultBundlePath") else {
          return StubProcessRunner.failure("missing result bundle path")
        }

        let bundlePath = URL(fileURLWithPath: arguments[bundleIndex + 1])
        if FileManager.default.fileExists(atPath: bundlePath.path) {
          return StubProcessRunner.failure("stale result bundle was not cleared")
        }

        try FileManager.default.createDirectory(at: bundlePath, withIntermediateDirectories: true)
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
      "swift test --scratch-path .build/swiftpm-cache --enable-code-coverage": StubProcessRunner.success(),
      "swift test --scratch-path .build/swiftpm-cache --show-code-coverage-path": StubProcessRunner.success(coveragePath.path + "\n"),
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
      ExecutionRequest(command: .validate, subjects: [], explicitTestSubjects: [], outputMode: .filtered)
    )

    #expect(FileManager.default.fileExists(atPath: summaryPath))
  }
}

@Test func validateExecutionBridgeTerminatesAndUninstallsExistingSimulatorAppBeforeEachPlan() throws {
  try withTemporaryRepositoryFixture { repoRoot in
    let testPlanRoot = repoRoot.appendingPathComponent(
      "SymphonyApps.xcodeproj/xcshareddata/xctestplans",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: testPlanRoot, withIntermediateDirectories: true)
    for name in [
      "SymphonySwiftUIApp.xctestplan",
      "SymphonySwiftUIAppTests.xctestplan",
      "SymphonySwiftUIAppUITests.xctestplan",
    ] {
      try "{}\n".write(
        to: testPlanRoot.appendingPathComponent(name),
        atomically: true,
        encoding: .utf8
      )
    }
    try #"""
    PRODUCT_BUNDLE_IDENTIFIER = dev.atjsh.symphony;
    PRODUCT_BUNDLE_IDENTIFIER = dev.atjsh.symphony.tests;
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
        runtime: "iOS 18"
      ),
      SimulatorDevice(
        name: "iPad Pro (M4)",
        udid: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB",
        state: "Shutdown",
        runtime: "iOS 18"
      ),
    ]
    let terminateSignals = SignalBox()
    let uninstallSignals = SignalBox()
    let testInvocationCount = InvocationCounterBox()
    let expectedBundleIdentifiers = Set([
      "dev.atjsh.symphony",
      "dev.atjsh.symphony.tests",
      "dev.atjsh.symphony.tests.xctrunner",
      "dev.atjsh.symphony.uitests",
      "dev.atjsh.symphony.uitests.xctrunner",
    ])
    let expectedCleanupCountPerPlan = expectedBundleIdentifiers.count

    let runner = RoutedProcessRunner { command, arguments, _, _, _ in
      if command == "xcodebuild",
        arguments.starts(with: ["-showBuildSettings", "-json"])
      {
        let payload = """
          [
            {
              "buildSettings": {
                "TARGET_BUILD_DIR": "\(repoRoot.path)/DerivedData/Products",
                "FULL_PRODUCT_NAME": "Symphony.app",
                "PRODUCT_BUNDLE_IDENTIFIER": "dev.atjsh.symphony"
              }
            }
          ]
          """
        return StubProcessRunner.success(payload)
      }

      if command == "xcrun", arguments.prefix(2) == ["simctl", "terminate"] {
        terminateSignals.append(arguments.suffix(2).joined(separator: "|"))
        return StubProcessRunner.success()
      }
      if command == "xcrun", arguments.prefix(2) == ["simctl", "uninstall"] {
        uninstallSignals.append(arguments.suffix(2).joined(separator: "|"))
        return StubProcessRunner.success()
      }

      if command == "xcodebuild", arguments.last == "test" {
        let currentInvocation = testInvocationCount.increment()
        #expect(terminateSignals.values.count == currentInvocation * expectedCleanupCountPerPlan)
        #expect(uninstallSignals.values.count == currentInvocation * expectedCleanupCountPerPlan)
        #expect(Set(terminateSignals.values.suffix(expectedCleanupCountPerPlan)) == Set(
          expectedBundleIdentifiers.map { "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA|\($0)" }
        ) || Set(terminateSignals.values.suffix(expectedCleanupCountPerPlan)) == Set(
          expectedBundleIdentifiers.map { "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB|\($0)" }
        ))
        #expect(Set(uninstallSignals.values.suffix(expectedCleanupCountPerPlan)) == Set(
          expectedBundleIdentifiers.map { "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA|\($0)" }
        ) || Set(uninstallSignals.values.suffix(expectedCleanupCountPerPlan)) == Set(
          expectedBundleIdentifiers.map { "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB|\($0)" }
        ))

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
      "swift test --scratch-path .build/swiftpm-cache --enable-code-coverage": StubProcessRunner.success(),
      "swift test --scratch-path .build/swiftpm-cache --show-code-coverage-path": StubProcessRunner.success(coveragePath.path + "\n"),
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
      ExecutionRequest(command: .validate, subjects: [], explicitTestSubjects: [], outputMode: .filtered)
    )

    #expect(FileManager.default.fileExists(atPath: summaryPath))
    #expect(terminateSignals.values.count == 6 * expectedCleanupCountPerPlan)
    #expect(uninstallSignals.values.count == 6 * expectedCleanupCountPerPlan)
  }
}

@Test func validateExecutionBridgeSeparatesAccessibilityFromGeneralPlanFailures() throws {
  try withTemporaryRepositoryFixture { repoRoot in
    let testPlanRoot = repoRoot.appendingPathComponent(
      "SymphonyApps.xcodeproj/xcshareddata/xctestplans",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: testPlanRoot, withIntermediateDirectories: true)
    try #"""
    {
      "testTargets": [
        { "target": { "name": "SymphonySwiftUIAppTests" } },
        { "target": { "name": "SymphonySwiftUIAppUITests" } }
      ]
    }
    """#.write(
      to: testPlanRoot.appendingPathComponent("SymphonySwiftUIApp.xctestplan"),
      atomically: true,
      encoding: .utf8
    )
    try #"""
    {
      "testTargets": [
        { "target": { "name": "SymphonySwiftUIAppTests" } }
      ]
    }
    """#.write(
      to: testPlanRoot.appendingPathComponent("SymphonySwiftUIAppTests.xctestplan"),
      atomically: true,
      encoding: .utf8
    )
    try #"""
    {
      "testTargets": [
        { "target": { "name": "SymphonySwiftUIAppUITests" } }
      ]
    }
    """#.write(
      to: testPlanRoot.appendingPathComponent("SymphonySwiftUIAppUITests.xctestplan"),
      atomically: true,
      encoding: .utf8
    )

    let workspace = WorkspaceContext(
      projectRoot: repoRoot,
      buildStateRoot: repoRoot.appendingPathComponent(".build/harness", isDirectory: true),
      xcodeWorkspacePath: repoRoot.appendingPathComponent("Symphony.xcworkspace"),
      xcodeProjectPath: nil
    )
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

    let runner = RoutedProcessRunner { command, arguments, _, _, _ in
      if command == "xcodebuild", arguments.last == "test" {
        guard
          let testPlanFlagIndex = arguments.firstIndex(of: "-testPlan"),
          arguments.indices.contains(testPlanFlagIndex + 1)
        else {
          return StubProcessRunner.failure("missing test plan")
        }
        let testPlan = arguments[testPlanFlagIndex + 1]
        if let bundleIndex = arguments.firstIndex(of: "-resultBundlePath") {
          let bundlePath = URL(fileURLWithPath: arguments[bundleIndex + 1])
          try FileManager.default.createDirectory(at: bundlePath, withIntermediateDirectories: true)
        }
        if testPlan == "SymphonySwiftUIAppTests" {
          return StubProcessRunner.failure("unit test plan failed")
        }
        return StubProcessRunner.success("validated \(testPlan)")
      }
      return StubProcessRunner.success()
    }
    let perfectCoverage = CoverageReport(
      coveredLines: 4,
      executableLines: 4,
      lineCoverage: 1,
      includeTestTargets: false,
      excludedTargets: [],
      targets: []
    )
    let harnessRunner = StubProcessRunner(results: [
      "swift test --scratch-path .build/swiftpm-cache --enable-code-coverage": StubProcessRunner.success(),
      "swift test --scratch-path .build/swiftpm-cache --show-code-coverage-path": StubProcessRunner.success(coveragePath.path + "\n"),
    ])
    let tool = SymphonyHarnessTool(
      workspaceDiscovery: StubWorkspaceDiscovery(workspace: workspace),
      executionContextBuilder: ExecutionContextBuilder(),
      simulatorResolver: SimulatorResolver(
        catalog: StubSimulatorCatalog(
          devices: [
            SimulatorDevice(
              name: "iPhone 17",
              udid: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
              state: "Shutdown",
              runtime: "iOS 18"
            ),
            SimulatorDevice(
              name: "iPad Pro (M4)",
              udid: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB",
              state: "Shutdown",
              runtime: "iOS 18"
            ),
          ]
        ),
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

    do {
      _ = try tool.validate(
        ExecutionRequest(command: .validate, subjects: [], explicitTestSubjects: [], outputMode: .filtered)
      )
      Issue.record("Expected default validate to fail when a required non-accessibility plan fails.")
    } catch let error as SymphonyHarnessCommandFailure {
      let summaryPath = try #require(error.summaryPath)
      let summaryText = try String(contentsOf: summaryPath, encoding: .utf8)
      #expect(summaryText.contains("validation_policy_result xcodeTestPlans: failure"))
      #expect(summaryText.contains("validation_policy_result accessibility: success"))
      #expect(!summaryText.contains("accessibility_validation_failed"))
    }
  }
}

