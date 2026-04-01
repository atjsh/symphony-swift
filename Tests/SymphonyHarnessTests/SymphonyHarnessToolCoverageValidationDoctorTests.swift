import Foundation
import Testing

@testable import SymphonyHarness

@Test func validateExecutionBridgeEnforcesDoctorPoliciesForDefaultValidate() throws {
  try withTemporaryRepositoryFixture { repoRoot in
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

    let perfectCoverage = CoverageReport(
      coveredLines: 4,
      executableLines: 4,
      lineCoverage: 1,
      includeTestTargets: false,
      excludedTargets: [],
      targets: []
    )
    let noXcodeCapabilities = StubToolchainCapabilitiesResolver(capabilities: .noXcodeForTests)
    let harnessRunner = StubProcessRunner(results: [
      "swift test --enable-code-coverage": StubProcessRunner.success(),
      "swift test --show-code-coverage-path": StubProcessRunner.success(coveragePath.path + "\n"),
    ])
    let subjectRunner = RoutedProcessRunner { _, _, _, _, _ in
      StubProcessRunner.success("subject ok")
    }
    let tool = SymphonyHarnessTool(
      workspaceDiscovery: StubWorkspaceDiscovery(workspace: workspace),
      executionContextBuilder: ExecutionContextBuilder(),
      simulatorResolver: SimulatorResolver(
        catalog: StubSimulatorCatalog(devices: []), processRunner: subjectRunner),
      processRunner: subjectRunner,
      artifactManager: ArtifactManager(processRunner: subjectRunner),
      endpointOverrideStore: EndpointOverrideStore(),
      doctorService: StubDoctorService(
        report: DiagnosticsReport(
          issues: [
            DiagnosticIssue(
              severity: .error,
              code: "legacy_project_manifest",
              message: "Legacy XcodeGen input `project.yml` is still present."
            )
          ],
          checkedPaths: [repoRoot.path],
          checkedExecutables: ["swift"]
        ),
        rendered: "ERROR [legacy_project_manifest] Legacy XcodeGen input `project.yml` is still present."
      ),
      toolchainCapabilitiesResolver: noXcodeCapabilities,
      productLocator: ProductLocator(processRunner: subjectRunner),
      commitHarness: CommitHarness(
        processRunner: harnessRunner,
        statusSink: { _ in },
        serverCoverageLoader: { _ in perfectCoverage },
        toolchainCapabilitiesResolver: noXcodeCapabilities
      ),
      gitHookInstaller: GitHookInstaller(processRunner: subjectRunner),
      statusSink: { _ in }
    )

    do {
      _ = try tool.validate(
        ExecutionRequest(command: .validate, subjects: [], explicitTestSubjects: [], outputMode: .filtered)
      )
      Issue.record("Expected default validate to fail when doctor reports environment policy errors.")
    } catch let error as SymphonyHarnessCommandFailure {
      let summaryPath = try #require(error.summaryPath)
      let summaryText = try String(contentsOf: summaryPath, encoding: .utf8)
      #expect(summaryText.contains("aggregate_outcome: failure"))
      #expect(summaryText.contains("environment_policy_failed"))
      #expect(summaryText.contains("legacy_project_manifest"))
    }
  }
}

@Test func validateExecutionBridgeRunsCheckedInTestPlansAcrossPhoneAndPadDestinations() throws {
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
    let observedPlans = SignalBox()
    let observedDerivedDataPaths = SignalBox()
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
          arguments.indices.contains(testPlanFlagIndex + 1),
          let destinationFlagIndex = arguments.firstIndex(of: "-destination"),
          arguments.indices.contains(destinationFlagIndex + 1),
          let derivedDataFlagIndex = arguments.firstIndex(of: "-derivedDataPath"),
          arguments.indices.contains(derivedDataFlagIndex + 1)
        else {
          return StubProcessRunner.failure("missing test plan, destination, or derived data path")
        }

        let testPlan = arguments[testPlanFlagIndex + 1]
        let destination = arguments[destinationFlagIndex + 1]
        let derivedDataPath = arguments[derivedDataFlagIndex + 1]
        observedPlans.append("\(testPlan)|\(destination)")
        observedDerivedDataPaths.append("\(testPlan)|\(derivedDataPath)")

        if let bundleIndex = arguments.firstIndex(of: "-resultBundlePath") {
          let bundlePath = URL(fileURLWithPath: arguments[bundleIndex + 1])
          try FileManager.default.createDirectory(at: bundlePath, withIntermediateDirectories: true)
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
      "swift test --enable-code-coverage": StubProcessRunner.success(),
      "swift test --show-code-coverage-path": StubProcessRunner.success(coveragePath.path + "\n"),
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

    let summaryPath = try tool.validate(
      ExecutionRequest(command: .validate, subjects: [], explicitTestSubjects: [], outputMode: .filtered)
    )

    #expect(Set(observedPlans.values) == Set([
      "SymphonySwiftUIApp|platform=iOS Simulator,id=AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
      "SymphonySwiftUIApp|platform=iOS Simulator,id=BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB",
      "SymphonySwiftUIAppTests|platform=iOS Simulator,id=AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
      "SymphonySwiftUIAppTests|platform=iOS Simulator,id=BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB",
      "SymphonySwiftUIAppUITests|platform=iOS Simulator,id=AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
      "SymphonySwiftUIAppUITests|platform=iOS Simulator,id=BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB",
    ]))
    #expect(
      Set(observedDerivedDataPaths.values) == Set([
        "SymphonySwiftUIApp|\(repoRoot.appendingPathComponent(".build/harness/derived-data/SymphonySwiftUIApp/symphonyswiftuiapp").path)",
        "SymphonySwiftUIAppTests|\(repoRoot.appendingPathComponent(".build/harness/derived-data/SymphonySwiftUIApp/symphonyswiftuiapptests").path)",
        "SymphonySwiftUIAppUITests|\(repoRoot.appendingPathComponent(".build/harness/derived-data/SymphonySwiftUIApp/symphonyswiftuiappuitests").path)",
      ]))
    let summaryText = try String(contentsOf: URL(fileURLWithPath: summaryPath), encoding: .utf8)
    #expect(
      summaryText.contains(
        "validation_policies: coverage, artifacts, environment, xcodeTestPlans, accessibility"))
  }
}

@Test func validateExecutionBridgeRetriesBusyPreflightValidationPlanOnce() throws {
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
    let attemptCounts = StringIntBox()
    let busyPlanKey =
      "SymphonySwiftUIApp|platform=iOS Simulator,id=AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"

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
          arguments.indices.contains(testPlanFlagIndex + 1),
          let destinationFlagIndex = arguments.firstIndex(of: "-destination"),
          arguments.indices.contains(destinationFlagIndex + 1)
        else {
          return StubProcessRunner.failure("missing test plan or destination")
        }

        let testPlan = arguments[testPlanFlagIndex + 1]
        let destination = arguments[destinationFlagIndex + 1]
        let key = "\(testPlan)|\(destination)"
        let attempt = attemptCounts.increment(for: key)

        if let bundleIndex = arguments.firstIndex(of: "-resultBundlePath") {
          let bundlePath = URL(fileURLWithPath: arguments[bundleIndex + 1])
          try FileManager.default.createDirectory(at: bundlePath, withIntermediateDirectories: true)
        }

        if key == busyPlanKey, attempt == 1 {
          return StubProcessRunner.failure(
            "Application failed preflight checks (Underlying Error: Busy)")
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
      "swift test --enable-code-coverage": StubProcessRunner.success(),
      "swift test --show-code-coverage-path": StubProcessRunner.success(coveragePath.path + "\n"),
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

    let summaryPath = try tool.validate(
      ExecutionRequest(command: .validate, subjects: [], explicitTestSubjects: [], outputMode: .filtered)
    )

    let summaryText = try String(contentsOf: URL(fileURLWithPath: summaryPath), encoding: .utf8)
    #expect(summaryText.contains("validation_policy_result xcodeTestPlans: success"))
    #expect(attemptCounts.value(for: busyPlanKey) == 2)
  }
}

