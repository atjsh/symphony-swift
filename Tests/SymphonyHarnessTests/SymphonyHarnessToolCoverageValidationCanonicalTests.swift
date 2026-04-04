import Foundation
import Testing

@testable import SymphonyHarness

@Test func subjectExecutionBridgeDefaultsCanonicalTestSetWithoutXcode() throws {
  try withTemporaryRepositoryFixture { repoRoot in
    let workspace = WorkspaceContext(
      projectRoot: repoRoot,
      buildStateRoot: repoRoot.appendingPathComponent(".build/harness", isDirectory: true),
      xcodeWorkspacePath: repoRoot.appendingPathComponent("Symphony.xcworkspace"),
      xcodeProjectPath: nil
    )
    let observedFilters = SignalBox()
    let runner = RoutedProcessRunner { command, arguments, _, _, _ in
      if command == "swift",
        arguments.count == 6,
        arguments[0] == "test",
        arguments[3] == "--enable-code-coverage",
        arguments[4] == "--filter"
      {
        observedFilters.append(arguments[5])
        return StubProcessRunner.success("ok")
      }
      if command == "swift", arguments == ["test", "--scratch-path", ".build/swiftpm-cache", "--show-code-coverage-path"] {
        return StubProcessRunner.success(
          repoRoot.appendingPathComponent("missing-coverage.json").path + "\n")
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
        capabilities: .noXcodeForTests),
      productLocator: ProductLocator(processRunner: runner),
      commitHarness: CommitHarness(processRunner: runner),
      gitHookInstaller: GitHookInstaller(processRunner: runner),
      statusSink: { _ in }
    )

    let summaryPath = try tool.test(
      ExecutionRequest(command: .test, subjects: [], explicitTestSubjects: [], outputMode: .filtered)
    )

    #expect(Set(observedFilters.values) == Set([
      "SymphonySharedTests",
      "SymphonyServerCoreTests",
      "SymphonyServerTests",
      "SymphonyServerCLITests",
      "SymphonyHarnessTests",
      "SymphonyHarnessCLITests",
      "SymphonyXcodeValidationTests",
      "SymphonyXcodeValidationServerCoreTests",
      "SymphonyXcodeValidationServerTests",
    ]))
    let summaryText = try String(contentsOf: URL(fileURLWithPath: summaryPath), encoding: .utf8)
    #expect(summaryText.contains("defaulted_subjects:"))
    #expect(!summaryText.contains("SymphonySwiftUIApp"))
  }
}

@Test func validateExecutionBridgeAcceptsMixedSubjectsAndWritesSharedSummary() throws {
  try withTemporaryRepositoryFixture { repoRoot in
    let workspace = WorkspaceContext(
      projectRoot: repoRoot,
      buildStateRoot: repoRoot.appendingPathComponent(".build/harness", isDirectory: true),
      xcodeWorkspacePath: repoRoot.appendingPathComponent("Symphony.xcworkspace"),
      xcodeProjectPath: nil
    )
    let runner = RoutedProcessRunner { command, arguments, _, _, _ in
      if command == "swift",
        arguments == ["test", "--scratch-path", ".build/swiftpm-cache", "--enable-code-coverage", "--filter", "SymphonySharedTests"]
      {
        return StubProcessRunner.success("shared tests")
      }
      if command == "swift",
        arguments == ["test", "--scratch-path", ".build/swiftpm-cache", "--enable-code-coverage", "--filter", "SymphonyHarnessCLITests"]
      {
        return StubProcessRunner.success("harness cli tests")
      }
      if command == "swift", arguments == ["test", "--scratch-path", ".build/swiftpm-cache", "--show-code-coverage-path"] {
        return StubProcessRunner.success(
          repoRoot.appendingPathComponent("missing-coverage.json").path + "\n")
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
        capabilities: .noXcodeForTests),
      productLocator: ProductLocator(processRunner: runner),
      commitHarness: CommitHarness(processRunner: runner),
      gitHookInstaller: GitHookInstaller(processRunner: runner),
      statusSink: { _ in }
    )

    let summaryPath = try tool.validate(
      ExecutionRequest(
        command: .validate,
        subjects: ["SymphonyShared"],
        explicitTestSubjects: ["SymphonyHarnessCLITests"],
        outputMode: .filtered
      )
    )

    let summaryText = try String(contentsOf: URL(fileURLWithPath: summaryPath), encoding: .utf8)
    #expect(summaryText.contains("command: validate"))
    #expect(summaryText.contains("validation_policies:"))
    #expect(summaryText.contains("subject_artifact_root SymphonyShared"))
    #expect(summaryText.contains("subject_artifact_root SymphonyHarnessCLITests"))
  }
}

@Test func subjectExecutionBridgeRunsCanonicalRunnableSubjectIntoSharedRunRoot() throws {
  try withTemporaryRepositoryFixture { repoRoot in
    let workspace = WorkspaceContext(
      projectRoot: repoRoot,
      buildStateRoot: repoRoot.appendingPathComponent(".build/harness", isDirectory: true),
      xcodeWorkspacePath: repoRoot.appendingPathComponent("Symphony.xcworkspace"),
      xcodeProjectPath: nil
    )
    let runner = RoutedProcessRunner { command, arguments, _, _, _ in
      if command == "swift", arguments == ["build", "--scratch-path", ".build/swiftpm-cache", "--product", "symphony-server"] {
        return StubProcessRunner.success("server built")
      }
      if command == "swift", arguments == ["build", "--scratch-path", ".build/swiftpm-cache", "--show-bin-path"] {
        return StubProcessRunner.success(repoRoot.appendingPathComponent(".build/debug").path + "\n")
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

    let summaryPath = try tool.run(
      ExecutionRequest(command: .run, subjects: ["SymphonyServerCLI"], outputMode: .filtered)
    )

    #expect(summaryPath.contains("/.build/harness/runs/"))
    let summaryText = try String(contentsOf: URL(fileURLWithPath: summaryPath), encoding: .utf8)
    #expect(summaryText.contains("command: run"))
    #expect(summaryText.contains("subject_artifact_root SymphonyServerCLI"))
  }
}

@Test func subjectExecutionBridgePreservesCanonicalEndpointOverridesAndExplicitPortPrecedence() throws {
  try withTemporaryRepositoryFixture { repoRoot in
    let workspace = WorkspaceContext(
      projectRoot: repoRoot,
      buildStateRoot: repoRoot.appendingPathComponent(".build/harness", isDirectory: true),
      xcodeWorkspacePath: repoRoot.appendingPathComponent("Symphony.xcworkspace"),
      xcodeProjectPath: nil
    )
    let overrideStore = EndpointOverrideStore()
    _ = try overrideStore.save(
      RuntimeEndpoint(scheme: "http", host: "persisted.example.com", port: 8080),
      in: workspace
    )

    let runner = RoutedProcessRunner { command, arguments, environment, _, _ in
      let invocation = ([command] + arguments).joined(separator: " ")
      if command == "xcodebuild", arguments.last == "build" {
        return StubProcessRunner.success("built")
      }
      if invocation.contains("-showBuildSettings") {
        return StubProcessRunner.success(
          #"[{"buildSettings":{"TARGET_BUILD_DIR":"/tmp/Build","FULL_PRODUCT_NAME":"Symphony.app","EXECUTABLE_PATH":"Symphony.app/Contents/MacOS/Symphony","PRODUCT_BUNDLE_IDENTIFIER":"com.example.client"}}]"#
        )
      }
      if command == "xcrun",
        arguments == ["simctl", "bootstatus", "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", "-b"]
      {
        return StubProcessRunner.success()
      }
      if command == "xcrun", arguments.prefix(2) == ["simctl", "install"] {
        return StubProcessRunner.success("installed")
      }
      if command == "xcrun", arguments.prefix(2) == ["simctl", "launch"] {
        #expect(environment["SIMCTL_CHILD_CUSTOM"] == "1")
        #expect(environment["SIMCTL_CHILD_SYMPHONY_SERVER_SCHEME"] == "https")
        #expect(environment["SIMCTL_CHILD_SYMPHONY_SERVER_HOST"] == "persisted.example.com")
        #expect(environment["SIMCTL_CHILD_SYMPHONY_SERVER_PORT"] == "9443")
        #expect(environment["SIMCTL_CHILD_SYMPHONY_SERVER_URL"] == nil)
        return StubProcessRunner.success("launched")
      }
      return StubProcessRunner.success()
    }
    let tool = SymphonyHarnessTool(
      workspaceDiscovery: StubWorkspaceDiscovery(workspace: workspace),
      executionContextBuilder: ExecutionContextBuilder(),
      simulatorResolver: SimulatorResolver(
        catalog: StubSimulatorCatalog(devices: [
          SimulatorDevice(
            name: "iPhone 17",
            udid: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
            state: "Shutdown",
            runtime: "iOS 18"
          )
        ]),
        processRunner: runner
      ),
      processRunner: runner,
      artifactManager: ArtifactManager(processRunner: runner),
      endpointOverrideStore: overrideStore,
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

    let summaryPath = try tool.run(
      ExecutionRequest(
        command: .run,
        subjects: ["SymphonySwiftUIApp"],
        environment: [
          "CUSTOM": "1",
          "SYMPHONY_SERVER_SCHEME": "https",
          "SYMPHONY_SERVER_PORT": "9443",
        ],
        outputMode: .filtered
      )
    )

    #expect(summaryPath.contains("/.build/harness/runs/"))
    let summaryText = try String(contentsOf: URL(fileURLWithPath: summaryPath), encoding: .utf8)
    #expect(summaryText.contains("command: run"))
    #expect(summaryText.contains("subject_artifact_root SymphonySwiftUIApp"))
  }
}

@Test func validateExecutionBridgeDefaultsCanonicalSubjectSetWithoutXcode() throws {
  try withTemporaryRepositoryFixture { repoRoot in
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

    let workspace = WorkspaceContext(
      projectRoot: repoRoot,
      buildStateRoot: repoRoot.appendingPathComponent(".build/harness", isDirectory: true),
      xcodeWorkspacePath: repoRoot.appendingPathComponent("Symphony.xcworkspace"),
      xcodeProjectPath: nil
    )
    let observedFilters = SignalBox()
    let perfectCoverage = CoverageReport(
      coveredLines: 4,
      executableLines: 4,
      lineCoverage: 1,
      includeTestTargets: false,
      excludedTargets: [],
      targets: []
    )
    let runner = RoutedProcessRunner { command, arguments, _, _, _ in
      if command == "swift",
        arguments.count == 6,
        arguments[0] == "test",
        arguments[3] == "--enable-code-coverage",
        arguments[4] == "--filter"
      {
        observedFilters.append(arguments[5])
        return StubProcessRunner.success("ok")
      }
      if command == "swift", arguments == ["test", "--scratch-path", ".build/swiftpm-cache", "--show-code-coverage-path"] {
        return StubProcessRunner.success(
          repoRoot.appendingPathComponent("missing-coverage.json").path + "\n")
      }
      return StubProcessRunner.success()
    }
    let noXcodeCapabilities = StubToolchainCapabilitiesResolver(capabilities: .noXcodeForTests)
    let harnessRunner = StubProcessRunner(results: [
      "swift test --scratch-path .build/swiftpm-cache --enable-code-coverage": StubProcessRunner.success(),
      "swift test --scratch-path .build/swiftpm-cache --show-code-coverage-path": StubProcessRunner.success(coveragePath.path + "\n"),
    ])
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
      toolchainCapabilitiesResolver: noXcodeCapabilities,
      productLocator: ProductLocator(processRunner: runner),
      commitHarness: CommitHarness(
        processRunner: harnessRunner,
        statusSink: { _ in },
        serverCoverageLoader: { _ in perfectCoverage },
        toolchainCapabilitiesResolver: noXcodeCapabilities
      ),
      gitHookInstaller: GitHookInstaller(processRunner: runner),
      statusSink: { _ in }
    )

    let summaryPath = try tool.validate(
      ExecutionRequest(command: .validate, subjects: [], explicitTestSubjects: [], outputMode: .filtered)
    )

    #expect(Set(observedFilters.values) == Set([
      "SymphonySharedTests",
      "SymphonyServerCoreTests",
      "SymphonyServerTests",
      "SymphonyServerCLITests",
      "SymphonyHarnessTests",
      "SymphonyHarnessCLITests",
      "SymphonyXcodeValidationTests",
      "SymphonyXcodeValidationServerCoreTests",
      "SymphonyXcodeValidationServerTests",
    ]))
    let summaryText = try String(contentsOf: URL(fileURLWithPath: summaryPath), encoding: .utf8)
    #expect(summaryText.contains("defaulted_subjects:"))
    #expect(
      summaryText.contains(
        "validation_policies: coverage, artifacts, environment, xcodeTestPlans, accessibility"))
    #expect(!summaryText.contains("SymphonySwiftUIApp"))
  }
}

@Test func validateExecutionBridgeEnforcesRepositoryCoveragePolicyForDefaultValidate() throws {
  try withTemporaryRepositoryFixture { repoRoot in
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent("Sources/Foo", isDirectory: true),
      withIntermediateDirectories: true
    )
    try "func bar() {}".write(
      to: repoRoot.appendingPathComponent("Sources/Foo/Bar.swift"),
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
              "filename": "__REPO__/Sources/Foo/Bar.swift",
              "summary": { "lines": { "count": 4, "covered": 2 } }
            }
          ]
        }
      ]
    }
    """#
    .replacingOccurrences(of: "__REPO__", with: repoRoot.path)
    .write(to: coveragePath, atomically: true, encoding: .utf8)

    let subjectRunner = RoutedProcessRunner { _, _, _, _, _ in
      StubProcessRunner.success("subject ok")
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

    do {
      _ = try tool.validate(
        ExecutionRequest(command: .validate, subjects: [], explicitTestSubjects: [], outputMode: .filtered)
      )
      Issue.record("Expected default validate to fail when repository coverage is below 100%.")
    } catch let error as SymphonyHarnessCommandFailure {
      let summaryPath = try #require(error.summaryPath)
      let summaryText = try String(contentsOf: summaryPath, encoding: .utf8)
      #expect(summaryText.contains("aggregate_outcome: failure"))
      #expect(summaryText.contains("coverage_policy_failed"))
    }
  }
}
