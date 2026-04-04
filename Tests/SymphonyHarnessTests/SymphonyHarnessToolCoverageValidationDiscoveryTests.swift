import Foundation
import Testing

@testable import SymphonyHarness

@Test func validateExecutionBridgeWritesSyntheticFailureWhenDefaultAppValidationCannotResolveDestinations() throws {
  try withTemporaryRepositoryFixture { repoRoot in
    let testPlanRoot = repoRoot.appendingPathComponent(
      "SymphonyApps.xcodeproj/xcshareddata/xctestplans",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: testPlanRoot, withIntermediateDirectories: true)
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
    let coveragePath = repoRoot.appendingPathComponent(".build/destination-failure-coverage.json")
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
      Issue.record("Expected default validate to fail when approved validation destinations cannot be resolved.")
    } catch let error as SymphonyHarnessCommandFailure {
      let summaryPath = try #require(error.summaryPath)
      let sharedSummary = try JSONDecoder().decode(
        SharedRunSummary.self,
        from: Data(contentsOf: summaryPath.deletingLastPathComponent().appendingPathComponent("summary.json"))
      )
      let appResult = try #require(sharedSummary.subjectResults.first { $0.subject == "SymphonySwiftUIApp" })
      #expect(appResult.outcome == .failure)
      let appSummaryText = try String(contentsOf: appResult.artifactSet.summaryPath, encoding: .utf8)
      #expect(appSummaryText.contains("outcome: failure"))
      #expect(appSummaryText.contains("reason:"))
      let appIndex = try JSONDecoder().decode(
        DecodedSharedRunIndex.self,
        from: Data(contentsOf: appResult.artifactSet.indexPath)
      )
      #expect(appIndex.anomalies.map(\.code).contains("subject_execution_failed"))
    }
  }
}

@Test func subjectExecutionBridgePreservesRecordedArtifactsWhenCommandExecutionFails() throws {
  try withTemporaryRepositoryFixture { repoRoot in
    let workspace = WorkspaceContext(
      projectRoot: repoRoot,
      buildStateRoot: repoRoot.appendingPathComponent(".build/harness", isDirectory: true),
      xcodeWorkspacePath: repoRoot.appendingPathComponent("Symphony.xcworkspace"),
      xcodeProjectPath: nil
    )
    let runner = RoutedProcessRunner { command, arguments, _, _, _ in
      if command == "swift", arguments == ["build", "--scratch-path", ".build/swiftpm-cache", "--product", "SymphonyHarness"] {
        return StubProcessRunner.failure("build failed")
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
        rendered: "ok"
      ),
      toolchainCapabilitiesResolver: StubToolchainCapabilitiesResolver(
        capabilities: .fullyAvailableForTests
      ),
      productLocator: ProductLocator(processRunner: runner),
      commitHarness: CommitHarness(processRunner: runner),
      gitHookInstaller: GitHookInstaller(processRunner: runner),
      statusSink: { _ in }
    )

    do {
      _ = try tool.execute(
        ExecutionRequest(command: .build, subjects: ["SymphonyHarness"], outputMode: .filtered),
        currentDirectory: repoRoot
      )
      Issue.record("Expected the subject-scoped build to fail.")
    } catch let error as SymphonyHarnessCommandFailure {
      let summaryPath = try #require(error.summaryPath)
      let sharedSummary = try JSONDecoder().decode(
        SharedRunSummary.self,
        from: Data(contentsOf: summaryPath.deletingLastPathComponent().appendingPathComponent("summary.json"))
      )
      let result = try #require(sharedSummary.subjectResults.first)
      #expect(result.outcome == .failure)
      let subjectSummary = try String(contentsOf: result.artifactSet.summaryPath, encoding: .utf8)
      #expect(subjectSummary.contains("exit_code: 1"))
      #expect(subjectSummary.contains("stdout_stderr:"))
      let index = try JSONDecoder().decode(
        DecodedSharedRunIndex.self,
        from: Data(contentsOf: result.artifactSet.indexPath)
      )
      #expect(index.anomalies.map(\.code).contains("not_applicable_result_bundle"))
    }
  }
}

@Test func workspaceDiscoveryAndDoctorServiceCoverManifestSchemeAndExecutableFallbackBranches() throws {
  try withTemporaryDirectory { directory in
    let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
    try FileManager.default.createDirectory(at: repoRoot, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent(".git"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent("Symphony.xcworkspace"), withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent("SymphonyApps.xcodeproj/xcshareddata/xcschemes"),
      withIntermediateDirectories: true
    )

    do {
      _ = try WorkspaceDiscovery(processRunner: StubProcessRunner()).discover(from: repoRoot)
      Issue.record("Expected missing root manifests to fail discovery.")
    } catch let error as SymphonyHarnessError {
      #expect(error.code == "missing_root_package")
    }

    try "# root package".write(
      to: repoRoot.appendingPathComponent("Package.swift"),
      atomically: true,
      encoding: .utf8
    )
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent("SymphonyApps.xcodeproj/xcshareddata/xctestplans"),
      withIntermediateDirectories: true
    )
    try "{}".write(
      to: repoRoot.appendingPathComponent(
        "SymphonyApps.xcodeproj/xcshareddata/xctestplans/SymphonySwiftUIAppUITests.xctestplan"),
      atomically: true,
      encoding: .utf8
    )
    try """
    <Scheme>
      <TestAction>
        <TestPlans>
          <TestPlanReference reference = \"container:SymphonySwiftUIApp.xctestplan\"/>
          <TestPlanReference reference = \"container:SymphonySwiftUIAppTests.xctestplan\"/>
          <TestPlanReference reference = \"container:SymphonySwiftUIAppUITests.xctestplan\"/>
        </TestPlans>
      </TestAction>
    </Scheme>
    """.write(
      to: repoRoot.appendingPathComponent(
        "SymphonyApps.xcodeproj/xcshareddata/xcschemes/SymphonySwiftUIApp.xcscheme"),
      atomically: true,
      encoding: .utf8
    )
    try """
    <Scheme>
      <TestAction>
        <TestPlans>
        </TestPlans>
      </TestAction>
    </Scheme>
    """.write(
      to: repoRoot.appendingPathComponent(
        "SymphonyApps.xcodeproj/xcshareddata/xcschemes/SymphonySwiftUIAppUITests.xcscheme"),
      atomically: true,
      encoding: .utf8
    )

    let runner = RoutedProcessRunner { command, arguments, _, _, _ in
      if command == "which", arguments == ["just"] {
        throw SymphonyHarnessError(code: "which_failed", message: "which just failed")
      }
      return StubProcessRunner.success()
    }
    let service = DoctorService(
      workspaceDiscovery: StubWorkspaceDiscovery(
        workspace: WorkspaceContext(
          projectRoot: repoRoot,
          buildStateRoot: repoRoot.appendingPathComponent(".build/harness", isDirectory: true),
          xcodeWorkspacePath: repoRoot.appendingPathComponent("Symphony.xcworkspace"),
          xcodeProjectPath: repoRoot.appendingPathComponent("SymphonyApps.xcodeproj")
        )),
      processRunner: runner,
      toolchainCapabilitiesResolver: StubToolchainCapabilitiesResolver(capabilities: .noXcodeForTests)
    )

    let report = try service.makeReport(
      from: DoctorCommandRequest(strict: false, json: false, quiet: false, currentDirectory: repoRoot)
    )
    #expect(report.issues.contains(where: { $0.code == "missing_just" }))
    #expect(
      report.issues.contains(where: {
        $0.code == "missing_testplan_reference_symphonyswiftuiappuitests"
      }))
    #expect(
      !report.issues.contains(where: {
        $0.code == "missing_testplan_reference_symphonyswiftuiapp"
      }))
  }
}

@Test func subjectExecutionBridgeRunsNonExclusiveSubjectsInParallelByDefault() throws {
  try withTemporaryRepositoryFixture { repoRoot in
    let workspace = WorkspaceContext(
      projectRoot: repoRoot,
      buildStateRoot: repoRoot.appendingPathComponent(".build/harness", isDirectory: true),
      xcodeWorkspacePath: repoRoot.appendingPathComponent("Symphony.xcworkspace"),
      xcodeProjectPath: nil
    )
    let concurrency = InvocationConcurrencyBox()
    let runner = RoutedProcessRunner { command, arguments, _, _, _ in
      if command == "swift", arguments == ["build", "--scratch-path", ".build/swiftpm-cache", "--product", "SymphonyShared"]
        || arguments == ["build", "--scratch-path", ".build/swiftpm-cache", "--product", "harness"]
      {
        concurrency.enterSynchronizingUntilStarted(expectedCount: 2)
        defer { concurrency.leave() }
        Thread.sleep(forTimeInterval: 0.05)
        return StubProcessRunner.success("built")
      }
      return StubProcessRunner.success()
    }
    let tool = SymphonyHarnessTool(
      workspaceDiscovery: StubWorkspaceDiscovery(workspace: workspace),
      executionContextBuilder: ExecutionContextBuilder(),
      simulatorResolver: SimulatorResolver(
        catalog: StubSimulatorCatalog(devices: []), processRunner: runner),
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

    let summaryPath = try tool.build(
      ExecutionRequest(
        command: .build,
        subjects: ["SymphonyShared", "SymphonyHarnessCLI"],
        outputMode: .filtered
      )
    )

    #expect(FileManager.default.fileExists(atPath: summaryPath))
    #expect(concurrency.maxConcurrentInvocations > 1)
  }
}

@Test func subjectExecutionBridgeSerializesExclusiveXcodeSubjects() throws {
  try withTemporaryRepositoryFixture { repoRoot in
    let workspace = WorkspaceContext(
      projectRoot: repoRoot,
      buildStateRoot: repoRoot.appendingPathComponent(".build/harness", isDirectory: true),
      xcodeWorkspacePath: repoRoot.appendingPathComponent("Symphony.xcworkspace"),
      xcodeProjectPath: nil
    )
    let concurrency = InvocationConcurrencyBox()
    let runner = RoutedProcessRunner { command, arguments, _, _, _ in
      if command == "xcodebuild", arguments.last == "test" {
        concurrency.enter()
        defer { concurrency.leave() }
        if let bundleIndex = arguments.firstIndex(of: "-resultBundlePath") {
          let bundlePath = URL(fileURLWithPath: arguments[bundleIndex + 1])
          try FileManager.default.createDirectory(at: bundlePath, withIntermediateDirectories: true)
        }
        Thread.sleep(forTimeInterval: 0.05)
        return StubProcessRunner.success("xcode tests ok")
      }
      if command == "xcrun", arguments.prefix(2) == ["xccov", "view"] {
        return StubProcessRunner.failure("coverage unavailable")
      }
      return StubProcessRunner.success()
    }
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
            )
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
      commitHarness: CommitHarness(processRunner: runner),
      gitHookInstaller: GitHookInstaller(processRunner: runner),
      statusSink: { _ in }
    )

    let summaryPath = try tool.test(
      ExecutionRequest(
        command: .test,
        subjects: [],
        explicitTestSubjects: ["SymphonySwiftUIAppTests", "SymphonySwiftUIAppUITests"],
        outputMode: .filtered
      )
    )

    #expect(FileManager.default.fileExists(atPath: summaryPath))
    #expect(concurrency.maxConcurrentInvocations == 1)
  }
}

@Test func validateExecutionBridgeSerializesSubjectRunsToAvoidNestedValidateDeadlocks() throws {
  try withTemporaryRepositoryFixture { repoRoot in
    let workspace = WorkspaceContext(
      projectRoot: repoRoot,
      buildStateRoot: repoRoot.appendingPathComponent(".build/harness", isDirectory: true),
      xcodeWorkspacePath: repoRoot.appendingPathComponent("Symphony.xcworkspace"),
      xcodeProjectPath: nil
    )
    let concurrency = InvocationConcurrencyBox()
    let coveragePath = repoRoot.appendingPathComponent(
      ".build/arm64-apple-macosx/debug/codecov/symphony-swift.json")
    try FileManager.default.createDirectory(
      at: coveragePath.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let coverageJSON = #"""
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
    """#.replacingOccurrences(of: "__REPO__", with: repoRoot.path)
    try coverageJSON.write(to: coveragePath, atomically: true, encoding: .utf8)

    let subjectRunner = RoutedProcessRunner { command, arguments, _, _, _ in
      if command == "swift",
        arguments.count == 6,
        arguments[0] == "test",
        arguments[3] == "--enable-code-coverage",
        arguments[4] == "--filter"
      {
        concurrency.enterSynchronizingUntilStarted(expectedCount: 2)
        defer { concurrency.leave() }
        Thread.sleep(forTimeInterval: 0.05)
        return StubProcessRunner.success("ok")
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
    let noXcodeCapabilities = StubToolchainCapabilitiesResolver(capabilities: .noXcodeForTests)
    let tool = SymphonyHarnessTool(
      workspaceDiscovery: StubWorkspaceDiscovery(workspace: workspace),
      executionContextBuilder: ExecutionContextBuilder(),
      simulatorResolver: SimulatorResolver(
        catalog: StubSimulatorCatalog(devices: []), processRunner: subjectRunner),
      processRunner: subjectRunner,
      artifactManager: ArtifactManager(processRunner: subjectRunner),
      endpointOverrideStore: EndpointOverrideStore(),
      doctorService: StubDoctorService(
        report: DiagnosticsReport(issues: [], checkedPaths: [], checkedExecutables: []),
        rendered: "ok"),
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

    let summaryPath = try tool.validate(
      ExecutionRequest(
        command: .validate,
        subjects: ["SymphonyShared", "SymphonyHarnessCLI"],
        explicitTestSubjects: [],
        outputMode: .filtered
      )
    )

    #expect(FileManager.default.fileExists(atPath: summaryPath))
    #expect(concurrency.maxConcurrentInvocations == 1)
  }
}
