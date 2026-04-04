import Foundation
import Testing

@testable import SymphonyHarness

@Test func validateExecutionBridgeFailsWhenNoCheckedInAppPlansExist() throws {
  try withTemporaryRepositoryFixture { repoRoot in
    let workspace = WorkspaceContext(
      projectRoot: repoRoot,
      buildStateRoot: repoRoot.appendingPathComponent(".build/harness", isDirectory: true),
      xcodeWorkspacePath: repoRoot.appendingPathComponent("Symphony.xcworkspace"),
      xcodeProjectPath: nil
    )
    let coveragePath = repoRoot.appendingPathComponent(".build/no-plans-coverage.json")
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

    let runner = RoutedProcessRunner { _, _, _, _, _ in
      StubProcessRunner.success()
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
        rendered: "ok"
      ),
      toolchainCapabilitiesResolver: StubToolchainCapabilitiesResolver(
        capabilities: .fullyAvailableForTests
      ),
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
      Issue.record("Expected default validate to fail when no checked-in app plans exist.")
    } catch let error as SymphonyHarnessCommandFailure {
      let summaryPath = try #require(error.summaryPath)
      let summaryRoot = summaryPath.deletingLastPathComponent()
      let summaryText = try String(contentsOf: summaryPath, encoding: .utf8)
      #expect(summaryText.contains("xcode_test_plans_failed"))
      let sharedSummary = try JSONDecoder().decode(
        SharedRunSummary.self,
        from: Data(contentsOf: summaryRoot.appendingPathComponent("summary.json"))
      )
      let appResult = try #require(sharedSummary.subjectResults.first { $0.subject == "SymphonySwiftUIApp" })
      #expect(appResult.outcome == .failure)
      let appSummaryText = try String(contentsOf: appResult.artifactSet.summaryPath, encoding: .utf8)
      #expect(appSummaryText.contains("outcome: failure"))
      #expect(appSummaryText.contains("No checked-in .xctestplan files were found"))
    }
  }
}

@Test func validateExecutionBridgeFailsWhenAccessibilityCoveragePlanIsMissing() throws {
  try withTemporaryRepositoryFixture { repoRoot in
    let testPlanRoot = repoRoot.appendingPathComponent(
      "SymphonyApps.xcodeproj/xcshareddata/xctestplans",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: testPlanRoot, withIntermediateDirectories: true)
    try #"""
    {
      "testTargets": [
        { "target": { "name": "SymphonySwiftUIAppTests" } }
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

    let workspace = WorkspaceContext(
      projectRoot: repoRoot,
      buildStateRoot: repoRoot.appendingPathComponent(".build/harness", isDirectory: true),
      xcodeWorkspacePath: repoRoot.appendingPathComponent("Symphony.xcworkspace"),
      xcodeProjectPath: nil
    )
    let coveragePath = repoRoot.appendingPathComponent(".build/missing-accessibility-plan-coverage.json")
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
        if let bundleIndex = arguments.firstIndex(of: "-resultBundlePath") {
          let bundlePath = URL(fileURLWithPath: arguments[bundleIndex + 1])
          try FileManager.default.createDirectory(at: bundlePath, withIntermediateDirectories: true)
        }
        return StubProcessRunner.success("validated")
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
      Issue.record("Expected default validate to fail when no checked-in plan covers accessibility.")
    } catch let error as SymphonyHarnessCommandFailure {
      let summaryPath = try #require(error.summaryPath)
      let summaryText = try String(contentsOf: summaryPath, encoding: .utf8)
      #expect(summaryText.contains("validation_policy_result xcodeTestPlans: success"))
      #expect(summaryText.contains("validation_policy_result accessibility: failure"))
      #expect(summaryText.contains("missing_accessibility_validation_plan"))
    }
  }
}

@Test func validateExecutionBridgeFailsWhenAccessibilityValidationPlanExecutionFails() throws {
  try withTemporaryRepositoryFixture { repoRoot in
    let testPlanRoot = repoRoot.appendingPathComponent(
      "SymphonyApps.xcodeproj/xcshareddata/xctestplans",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: testPlanRoot, withIntermediateDirectories: true)
    try #"""
    {
      "testTargets": [
        { "target": { "name": "SymphonySwiftUIAppTests" } }
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
    let coveragePath = repoRoot.appendingPathComponent(".build/accessibility-plan-failure-coverage.json")
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
        if testPlan == "SymphonySwiftUIAppUITests" {
          return StubProcessRunner.failure("ui accessibility plan failed")
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
      Issue.record("Expected default validate to fail when an accessibility plan execution fails.")
    } catch let error as SymphonyHarnessCommandFailure {
      let summaryPath = try #require(error.summaryPath)
      let summaryText = try String(contentsOf: summaryPath, encoding: .utf8)
      #expect(summaryText.contains("validation_policy_result xcodeTestPlans: failure"))
      #expect(summaryText.contains("validation_policy_result accessibility: failure"))
      #expect(summaryText.contains("accessibility_validation_plan_failed"))
    }
  }
}

