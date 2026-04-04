import Foundation
import Testing

@testable import SymphonyHarness

@Test func doctorReportsHealthyRepositoryLayoutWhenCanonicalFilesExist() throws {
  try withTemporaryDirectory { directory in
    let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
    let testPlanRoot = repoRoot.appendingPathComponent(
      "SymphonyApps.xcodeproj/xcshareddata/xctestplans", isDirectory: true)
    try FileManager.default.createDirectory(at: testPlanRoot, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent(".build/harness"), withIntermediateDirectories: true)
    try "# root package".write(
      to: repoRoot.appendingPathComponent("Package.swift"),
      atomically: true,
      encoding: .utf8
    )
    try "{}".write(
      to: testPlanRoot.appendingPathComponent("SymphonySwiftUIApp.xctestplan"),
      atomically: true,
      encoding: .utf8
    )

    let service = DoctorService(
      workspaceDiscovery: StubWorkspaceDiscovery(
        workspace: WorkspaceContext(
          projectRoot: repoRoot,
          buildStateRoot: repoRoot.appendingPathComponent(".build/harness", isDirectory: true),
          xcodeWorkspacePath: URL(fileURLWithPath: "/tmp/Symphony.xcworkspace"),
          xcodeProjectPath: repoRoot.appendingPathComponent("SymphonyApps.xcodeproj")
        )),
      processRunner: StubProcessRunner(results: [
        "which swift": StubProcessRunner.success()
      ]),
      toolchainCapabilitiesResolver: StubToolchainCapabilitiesResolver(capabilities: .noXcodeForTests)
    )

    let report = try service.makeReport(
      from: DoctorCommandRequest(strict: false, json: false, quiet: false, currentDirectory: repoRoot)
    )
    #expect(!report.issues.contains(where: { $0.code == "legacy_project_manifest" }))
    #expect(!report.issues.contains(where: { $0.code == "missing_xctestplan" }))
  }
}

@Test func doctorRequiresCanonicalAppOwnedTestPlanLocation() throws {
  try withTemporaryDirectory { directory in
    let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
    let strayTestPlanRoot = repoRoot.appendingPathComponent("TestPlans", isDirectory: true)
    try FileManager.default.createDirectory(at: strayTestPlanRoot, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent(".build/harness"), withIntermediateDirectories: true)
    try "# root package".write(
      to: repoRoot.appendingPathComponent("Package.swift"),
      atomically: true,
      encoding: .utf8
    )
    try "{}".write(
      to: strayTestPlanRoot.appendingPathComponent("SymphonySwiftUIApp.xctestplan"),
      atomically: true,
      encoding: .utf8
    )

    let service = DoctorService(
      workspaceDiscovery: StubWorkspaceDiscovery(
        workspace: WorkspaceContext(
          projectRoot: repoRoot,
          buildStateRoot: repoRoot.appendingPathComponent(".build/harness", isDirectory: true),
          xcodeWorkspacePath: URL(fileURLWithPath: "/tmp/Symphony.xcworkspace"),
          xcodeProjectPath: repoRoot.appendingPathComponent("SymphonyApps.xcodeproj")
        )),
      processRunner: StubProcessRunner(results: [
        "which swift": StubProcessRunner.success()
      ]),
      toolchainCapabilitiesResolver: StubToolchainCapabilitiesResolver(capabilities: .noXcodeForTests)
    )

    let report = try service.makeReport(
      from: DoctorCommandRequest(strict: false, json: false, quiet: false, currentDirectory: repoRoot)
    )
    #expect(report.issues.contains(where: { $0.code == "missing_xctestplan" }))
  }
}

@Test func endpointStoreWorkspaceDiscoveryAndDoctorServiceCoverErrorPaths() throws {
  try withTemporaryDirectory { directory in
    let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
    try FileManager.default.createDirectory(at: repoRoot, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent(".git"), withIntermediateDirectories: true)
    try "# root package".write(
      to: repoRoot.appendingPathComponent("Package.swift"),
      atomically: true,
      encoding: .utf8
    )
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent("One.xcodeproj"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent("Two.xcodeproj"), withIntermediateDirectories: true)
    let nested = repoRoot.appendingPathComponent("Sources/Nested", isDirectory: true)
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

    do {
      _ = try WorkspaceDiscovery(processRunner: StubProcessRunner()).discover(from: repoRoot)
      Issue.record("Expected ambiguous projects to fail.")
    } catch let error as SymphonyHarnessError {
      #expect(error.code == "ambiguous_project")
    }

    try FileManager.default.removeItem(at: repoRoot.appendingPathComponent("Two.xcodeproj"))
    try FileManager.default.removeItem(at: repoRoot.appendingPathComponent("One.xcodeproj"))

    do {
      _ = try WorkspaceDiscovery(processRunner: StubProcessRunner()).discover(from: repoRoot)
      Issue.record("Expected missing build definitions to fail.")
    } catch let error as SymphonyHarnessError {
      #expect(error.code == "missing_build_definition")
    }

    do {
      _ = try WorkspaceDiscovery(processRunner: StubProcessRunner()).discover(
        from: URL(fileURLWithPath: "/", isDirectory: true))
      Issue.record("Expected missing repository roots to fail.")
    } catch let error as SymphonyHarnessError {
      #expect(error.code == "missing_repository_root")
    }

    try FileManager.default.createDirectory(
      at: repoRoot.appendingPathComponent("Symphony.xcworkspace"), withIntermediateDirectories: true
    )
    let nestedWorkspace = try WorkspaceDiscovery(processRunner: StubProcessRunner()).discover(
      from: nested)
    #expect(nestedWorkspace.projectRoot.path == repoRoot.path)

    do {
      try WorkspaceDiscovery.validateBuildStateRoot(
        URL(fileURLWithPath: "/tmp/outside", isDirectory: true), within: repoRoot)
      Issue.record("Expected out-of-bounds build state roots to fail.")
    } catch let error as SymphonyHarnessError {
      #expect(error.code == "artifact_root_out_of_bounds")
    }

    let endpointWorkspace = WorkspaceContext(
      projectRoot: repoRoot,
      buildStateRoot: repoRoot.appendingPathComponent(".build/harness", isDirectory: true),
      xcodeWorkspacePath: nil,
      xcodeProjectPath: nil
    )
    let store = EndpointOverrideStore()
    #expect(
      store.storeURL(in: endpointWorkspace).path.hasSuffix(
        ".build/harness/runtime/server-endpoint.json"))
    #expect(
      store.clientEnvironment(
        for: try RuntimeEndpoint(scheme: "https", host: "example.com", port: 9443)) == [
          "SYMPHONY_SERVER_SCHEME": "https",
          "SYMPHONY_SERVER_HOST": "example.com",
          "SYMPHONY_SERVER_PORT": "9443",
        ])

    do {
      _ = try store.resolve(
        workspace: endpointWorkspace, serverURL: "not-a-url", scheme: nil, host: nil, port: nil)
      Issue.record("Expected invalid server URLs to fail.")
    } catch let error as SymphonyHarnessError {
      #expect(error.code == "invalid_server_url")
    }

    let buildStateFile = repoRoot.appendingPathComponent(
      ".build/harness", isDirectory: false)
    try FileManager.default.createDirectory(
      at: buildStateFile.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data().write(to: buildStateFile)

    let doctor = DoctorService(
      workspaceDiscovery: StubWorkspaceDiscovery(
        workspace: WorkspaceContext(
          projectRoot: repoRoot,
          buildStateRoot: buildStateFile,
          xcodeWorkspacePath: nil,
          xcodeProjectPath: nil
        )),
      processRunner: StubProcessRunner(results: [
        "which swift": StubProcessRunner.failure(""),
        "which xcodebuild": StubProcessRunner.success(),
        "which xcrun": StubProcessRunner.success(),
        "xcrun simctl help": StubProcessRunner.failure(""),
        "xcrun xcresulttool help": StubProcessRunner.success(),
      ]),
      toolchainCapabilitiesResolver: StubToolchainCapabilitiesResolver(
        capabilities: ToolchainCapabilities(
          swiftAvailable: false,
          xcodebuildAvailable: true,
          xcrunAvailable: true,
          simctlAvailable: false,
          xcresulttoolAvailable: true,
          llvmCovCommand: .xcrun
        ))
    )
    let report = try doctor.makeReport(
      from: DoctorCommandRequest(
        strict: false, json: false, quiet: false, currentDirectory: repoRoot))
    #expect(report.issues.contains(where: { $0.code == "missing_swift" }))
    #expect(report.issues.contains(where: { $0.code == "missing_simctl" }))
    #expect(report.issues.contains(where: { $0.code == "unwritable_build_state_root" }))
    #expect(report.issues.contains(where: { $0.code == "missing_scheme_symphonyswiftuiapp" }))

    let quiet = try doctor.render(
      report: DiagnosticsReport(
        issues: [], checkedPaths: [repoRoot.path], checkedExecutables: ["swift"]), json: false,
      quiet: true)
    #expect(quiet == "OK: environment is ready")

    let failingDoctor = DoctorService(
      workspaceDiscovery: StubWorkspaceDiscovery(
        workspace: WorkspaceContext(
          projectRoot: repoRoot,
          buildStateRoot: repoRoot.appendingPathComponent(
            ".build/harness", isDirectory: true),
          xcodeWorkspacePath: URL(fileURLWithPath: "/tmp/Symphony.xcworkspace"),
          xcodeProjectPath: nil
        )),
      processRunner: StubProcessRunner(results: [
        "which swift": StubProcessRunner.success(),
        "which xcodebuild": StubProcessRunner.success(),
        "which xcrun": StubProcessRunner.success(),
        "xcrun simctl help": StubProcessRunner.success(),
        "xcrun xcresulttool help": StubProcessRunner.success(),
        "xcodebuild -list -json -workspace /tmp/Symphony.xcworkspace": StubProcessRunner.failure(
          "list broke"),
      ]),
      toolchainCapabilitiesResolver: StubToolchainCapabilitiesResolver(
        capabilities: .fullyAvailableForTests)
    )
    let failingReport = try failingDoctor.makeReport(
      from: DoctorCommandRequest(
        strict: false, json: false, quiet: false, currentDirectory: repoRoot))
    #expect(failingReport.issues.contains(where: { $0.code == "xcodebuild_list_failed" }))
  }
}

@Test func doctorServiceRendersIssuesWithoutFixAndUsesFallbackListFailureMessage() throws {
  let repoRoot = URL(fileURLWithPath: "/tmp/repo", isDirectory: true)
  let service = DoctorService(
    workspaceDiscovery: StubWorkspaceDiscovery(
      workspace: WorkspaceContext(
        projectRoot: repoRoot,
        buildStateRoot: repoRoot.appendingPathComponent(".build/harness", isDirectory: true),
        xcodeWorkspacePath: URL(fileURLWithPath: "/tmp/Symphony.xcworkspace"),
        xcodeProjectPath: nil
      )),
    processRunner: StubProcessRunner(results: [
      "which swift": StubProcessRunner.success(),
      "which xcodebuild": StubProcessRunner.success(),
      "which xcrun": StubProcessRunner.success(),
      "xcrun simctl help": StubProcessRunner.success(),
      "xcrun xcresulttool help": StubProcessRunner.success(),
      "xcodebuild -list -json -workspace /tmp/Symphony.xcworkspace": CommandResult(
        exitStatus: 1, stdout: "", stderr: ""),
    ]),
    toolchainCapabilitiesResolver: StubToolchainCapabilitiesResolver(
      capabilities: .fullyAvailableForTests)
  )

  let report = try service.makeReport(
    from: DoctorCommandRequest(strict: false, json: false, quiet: false, currentDirectory: repoRoot)
  )
  #expect(
    report.issues.contains(where: {
      $0.code == "xcodebuild_list_failed" && $0.message == "Failed to list schemes."
    }))

  let rendered = try service.render(
    report: DiagnosticsReport(
      issues: [
        DiagnosticIssue(
          severity: .error, code: "plain_issue", message: "plain issue", suggestedFix: nil)
      ],
      checkedPaths: [repoRoot.path],
      checkedExecutables: ["swift"]
    ),
    json: false,
    quiet: false
  )
  #expect(rendered.contains("ERROR [plain_issue] plain issue"))
  #expect(!rendered.contains("fix="))
}

@Test func doctorServiceSkipsXcodeChecksWhenUnavailableAndRendersNotes() throws {
  let repoRoot = URL(fileURLWithPath: "/tmp/repo", isDirectory: true)
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
  #expect(report.issues.isEmpty)
  #expect(
    report.notes == [
      "Xcode-backed diagnostics were skipped because the current environment has no Xcode available."
    ])

  let human = try service.render(report: report, json: false, quiet: false)
  #expect(
    human.contains(
      "NOTE Xcode-backed diagnostics were skipped because the current environment has no Xcode available."
    ))
  #expect(human.contains("OK: environment is ready"))

  let json = try service.render(report: report, json: true, quiet: false)
  #expect(json.contains("\"notes\""))
}

@Test func simulatorResolverCoversDefaultSelectionAndEmptyFallbackMessages() throws {
  let devices = [
    SimulatorDevice(
      name: "iPhone 17", udid: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", state: "Shutdown",
      runtime: "iOS 18")
  ]
  let resolver = SimulatorResolver(
    catalog: StubSimulatorCatalog(devices: devices), processRunner: StubProcessRunner())
  let resolved = try resolver.resolve(DestinationSelector(platform: .iosSimulator))
  #expect(resolved.simulatorName == "iPhone 17")
  #expect(resolved.simulatorUDID == "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")

  let bootDestination = ResolvedDestination(
    platform: .iosSimulator,
    displayName: "iPhone 17 (AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA)",
    simulatorName: "iPhone 17",
    simulatorUDID: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
    xcodeDestination: "platform=iOS Simulator,id=AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
  )

  do {
    try SimulatorResolver(
      catalog: StubSimulatorCatalog(devices: devices),
      processRunner: StubProcessRunner(results: [
        "xcrun simctl bootstatus AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA -b":
          StubProcessRunner.failure("not booted"),
        "xcrun simctl boot AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA": CommandResult(
          exitStatus: 1, stdout: "", stderr: ""),
      ])
    ).boot(resolved: bootDestination)
    Issue.record("Expected empty-output boot failures to use the fallback message.")
  } catch let error as SymphonyHarnessError {
    #expect(error.code == "simulator_boot_failed")
    #expect(error.message == "Failed to boot simulator AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA.")
  }

  do {
    try SimulatorResolver(
      catalog: StubSimulatorCatalog(devices: devices),
      processRunner: BootSequenceProcessRunner(
        responses: [
          StubProcessRunner.failure("not booted"),
          StubProcessRunner.success(""),
          CommandResult(exitStatus: 1, stdout: "", stderr: ""),
        ]
      )
    ).boot(resolved: bootDestination)
    Issue.record("Expected empty-output boot confirmation failures to use the fallback message.")
  } catch let error as SymphonyHarnessError {
    #expect(error.code == "simulator_boot_failed")
    #expect(error.message == "Failed to confirm simulator boot.")
  }
}

@Test func simulatorResolverDefaultSelectionUsesDeterministicPhoneWhenNamesAreDuplicated() throws {
  let devices = [
    SimulatorDevice(
      name: "iPhone 17", udid: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB", state: "Shutdown",
      runtime: "iOS 18"),
    SimulatorDevice(
      name: "iPhone 17", udid: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", state: "Shutdown",
      runtime: "iOS 18"),
    SimulatorDevice(
      name: "iPad Pro (M4)", udid: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC", state: "Shutdown",
      runtime: "iOS 18"),
  ]

  let resolver = SimulatorResolver(
    catalog: StubSimulatorCatalog(devices: devices),
    processRunner: StubProcessRunner()
  )

  let resolved = try resolver.resolve(DestinationSelector(platform: .iosSimulator))
  #expect(resolved.simulatorName == "iPhone 17")
  #expect(resolved.simulatorUDID == "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")
  #expect(
    resolved.xcodeDestination
      == "platform=iOS Simulator,id=AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")
}
