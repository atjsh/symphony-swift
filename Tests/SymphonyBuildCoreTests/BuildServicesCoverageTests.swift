import Foundation
import Testing
@testable import SymphonyBuildCore

@Test func buildErrorsAndCommandFailuresRenderDescriptions() {
    let error = SymphonyBuildError(code: "sample_error", message: "something broke")
    #expect(error.errorDescription == "[sample_error] something broke")
    #expect(error.description == "[sample_error] something broke")

    let failureWithSummary = SymphonyBuildCommandFailure(
        message: "build failed",
        summaryPath: URL(fileURLWithPath: "/tmp/summary.txt")
    )
    #expect(failureWithSummary.errorDescription == "build failed Summary: /tmp/summary.txt")

    let failureWithoutSummary = SymphonyBuildCommandFailure(message: "build failed")
    #expect(failureWithoutSummary.errorDescription == "build failed")
}

@Test func productLocatorCoversSuccessAndFailureModes() throws {
    let workspace = WorkspaceContext(
        projectRoot: URL(fileURLWithPath: "/tmp/repo", isDirectory: true),
        buildStateRoot: URL(fileURLWithPath: "/tmp/repo/.build/symphony-build", isDirectory: true),
        xcodeWorkspacePath: URL(fileURLWithPath: "/tmp/repo/Symphony.xcworkspace"),
        xcodeProjectPath: nil
    )
    let destination = ResolvedDestination(
        platform: .macos,
        displayName: "macOS",
        simulatorName: nil,
        simulatorUDID: nil,
        xcodeDestination: expectedHostMacOSDestination()
    )
    let derivedDataPath = URL(fileURLWithPath: "/tmp/repo/.build/DerivedData", isDirectory: true)
    let buildSettingsJSON = #"""
    [
      {
        "buildSettings": {
          "TARGET_BUILD_DIR": "/tmp/repo/Build/Products/Debug",
          "FULL_PRODUCT_NAME": "Symphony.app",
          "EXECUTABLE_PATH": "Symphony.app/Contents/MacOS/Symphony",
          "PRODUCT_BUNDLE_IDENTIFIER": "com.example.Symphony",
          "INT_VALUE": 1,
          "BOOL_VALUE": true,
          "ARRAY_VALUE": ["a", 2, false],
          "DICT_VALUE": {"nested": "value"},
          "NULL_VALUE": null
        }
      }
    ]
    """#
    let workspaceCommand = "xcodebuild -showBuildSettings -json -scheme Symphony -destination \(expectedHostMacOSDestination()) -derivedDataPath \(derivedDataPath.path) -workspace /tmp/repo/Symphony.xcworkspace"
    let locator = ProductLocator(processRunner: StubProcessRunner(results: [
        workspaceCommand: StubProcessRunner.success(buildSettingsJSON),
    ]))

    let details = try locator.locateProduct(
        workspace: workspace,
        scheme: "Symphony",
        destination: destination,
        derivedDataPath: derivedDataPath
    )
    #expect(details.fullProductName == "Symphony.app")
    #expect(details.productURL.path.hasSuffix("Symphony.app"))
    #expect(details.executablePath == "Symphony.app/Contents/MacOS/Symphony")
    #expect(details.bundleIdentifier == "com.example.Symphony")

    let projectWorkspace = WorkspaceContext(
        projectRoot: workspace.projectRoot,
        buildStateRoot: workspace.buildStateRoot,
        xcodeWorkspacePath: nil,
        xcodeProjectPath: URL(fileURLWithPath: "/tmp/repo/SymphonyApps.xcodeproj")
    )
    let projectCommand = "xcodebuild -showBuildSettings -json -scheme Symphony -destination \(expectedHostMacOSDestination()) -derivedDataPath \(derivedDataPath.path) -project /tmp/repo/SymphonyApps.xcodeproj"
    let projectLocator = ProductLocator(processRunner: StubProcessRunner(results: [
        projectCommand: StubProcessRunner.success(buildSettingsJSON.replacingOccurrences(of: "Symphony.app", with: "SymphonyServer")),
    ]))
    let projectDetails = try projectLocator.locateProduct(
        workspace: projectWorkspace,
        scheme: "Symphony",
        destination: destination,
        derivedDataPath: derivedDataPath
    )
    #expect(projectDetails.productURL.path.hasSuffix("SymphonyServer"))

    do {
        _ = try ProductLocator(processRunner: StubProcessRunner(results: [
            workspaceCommand: StubProcessRunner.failure("boom"),
        ])).locateProduct(workspace: workspace, scheme: "Symphony", destination: destination, derivedDataPath: derivedDataPath)
        Issue.record("Expected showBuildSettings failures to surface.")
    } catch let error as SymphonyBuildError {
        #expect(error.code == "show_build_settings_failed")
        #expect(error.message == "boom")
    }

    do {
        _ = try ProductLocator(processRunner: StubProcessRunner(results: [
            workspaceCommand: CommandResult(exitStatus: 1, stdout: "", stderr: ""),
        ])).locateProduct(workspace: workspace, scheme: "Symphony", destination: destination, derivedDataPath: derivedDataPath)
        Issue.record("Expected empty showBuildSettings failures to use the fallback message.")
    } catch let error as SymphonyBuildError {
        #expect(error.message == "Failed to query build settings.")
    }

    do {
        _ = try ProductLocator(processRunner: StubProcessRunner(results: [
            workspaceCommand: StubProcessRunner.success("[]"),
        ])).locateProduct(workspace: workspace, scheme: "Symphony", destination: destination, derivedDataPath: derivedDataPath)
        Issue.record("Expected missing build settings to fail.")
    } catch let error as SymphonyBuildError {
        #expect(error.code == "missing_build_settings")
    }

    let incompleteJSON = #"""
    [
      {
        "buildSettings": {
          "TARGET_BUILD_DIR": "/tmp/repo/Build/Products/Debug",
          "FULL_PRODUCT_NAME": 17
        }
      }
    ]
    """#
    do {
        _ = try ProductLocator(processRunner: StubProcessRunner(results: [
            workspaceCommand: StubProcessRunner.success(incompleteJSON),
        ])).locateProduct(workspace: workspace, scheme: "Symphony", destination: destination, derivedDataPath: derivedDataPath)
        Issue.record("Expected incomplete build settings to fail.")
    } catch let error as SymphonyBuildError {
        #expect(error.code == "incomplete_build_settings")
    }
}

@Test func simulatorCatalogAndResolverCoverResolutionAndBootBranches() throws {
    let listJSON = #"""
    {
      "devices": {
        "iOS 18.0": [
          {"name":"iPhone 17 Pro","udid":"BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB","state":"Shutdown"},
          {"name":"iPhone 17","udid":"AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA","state":"Shutdown"}
        ],
        "iOS 18.1": [
          {"name":"iPhone 17 Plus","udid":"CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC","state":"Booted"}
        ]
      }
    }
    """#
    let catalogRunner = StubProcessRunner(results: [
        "xcrun simctl list devices available -j": StubProcessRunner.success(listJSON),
    ])
    let catalog = SimctlSimulatorCatalog(processRunner: catalogRunner)
    let devices = try catalog.availableDevices()
    #expect(devices.map(\.name) == ["iPhone 17", "iPhone 17 Plus", "iPhone 17 Pro"])

    do {
        _ = try SimctlSimulatorCatalog(processRunner: StubProcessRunner(results: [
            "xcrun simctl list devices available -j": StubProcessRunner.failure("simctl broke"),
        ])).availableDevices()
        Issue.record("Expected simctl failures to surface.")
    } catch let error as SymphonyBuildError {
        #expect(error.code == "simctl_failed")
    }

    let catalogStub = StubSimulatorCatalog(devices: devices)
    let resolver = SimulatorResolver(catalog: catalogStub, processRunner: StubProcessRunner())
    #expect(try resolver.resolve(DestinationSelector(platform: .iosSimulator, simulatorName: "plus")).simulatorUDID == "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")

    do {
        _ = try resolver.resolve(DestinationSelector(platform: .iosSimulator, simulatorName: "iphone 17"))
        Issue.record("Expected fuzzy duplicate matches to fail.")
    } catch let error as SymphonyBuildError {
        #expect(error.code == "ambiguous_simulator_match")
    }

    do {
        _ = try resolver.resolve(DestinationSelector(platform: .iosSimulator, simulatorName: "does-not-exist"))
        Issue.record("Expected missing simulators to fail.")
    } catch let error as SymphonyBuildError {
        #expect(error.code == "missing_simulator")
    }

    try SimulatorResolver(catalog: catalogStub, processRunner: StubProcessRunner()).boot(
        resolved: ResolvedDestination(platform: .macos, displayName: "macOS", simulatorName: nil, simulatorUDID: nil, xcodeDestination: expectedHostMacOSDestination())
    )

    let bootDestination = ResolvedDestination(
        platform: .iosSimulator,
        displayName: "iPhone 17 (AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA)",
        simulatorName: "iPhone 17",
        simulatorUDID: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
        xcodeDestination: "platform=iOS Simulator,id=AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
    )
    let alreadyBootingRunner = BootSequenceProcessRunner(
        responses: [
            StubProcessRunner.failure("not booted"),
            CommandResult(exitStatus: 1, stdout: "", stderr: "Unable to boot device in current state"),
            StubProcessRunner.success(""),
        ]
    )
    try SimulatorResolver(catalog: catalogStub, processRunner: alreadyBootingRunner).boot(resolved: bootDestination)

    do {
        try SimulatorResolver(
            catalog: catalogStub,
            processRunner: StubProcessRunner(results: [
                "xcrun simctl bootstatus AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA -b": StubProcessRunner.failure("not booted"),
                "xcrun simctl boot AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA": StubProcessRunner.failure("boot failed"),
            ])
        ).boot(resolved: bootDestination)
        Issue.record("Expected boot failures to surface.")
    } catch let error as SymphonyBuildError {
        #expect(error.code == "simulator_boot_failed")
        #expect(error.message == "boot failed")
    }

    let readyFailRunner = BootSequenceProcessRunner(
        responses: [
            StubProcessRunner.failure("bootstatus 1"),
            StubProcessRunner.success(""),
            StubProcessRunner.failure("bootstatus 2"),
        ]
    )
    do {
        try SimulatorResolver(catalog: catalogStub, processRunner: readyFailRunner).boot(resolved: bootDestination)
        Issue.record("Expected boot confirmation failures to surface.")
    } catch let error as SymphonyBuildError {
        #expect(error.code == "simulator_boot_failed")
        #expect(error.message == "bootstatus 2")
    }
}

@Test func simulatorCatalogSortsMatchingNamesByUDID() throws {
    let listJSON = #"""
    {
      "devices": {
        "iOS 18.0": [
          {"name":"iPhone 17","udid":"BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB","state":"Shutdown"},
          {"name":"iPhone 17","udid":"AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA","state":"Shutdown"}
        ]
      }
    }
    """#
    let devices = try SimctlSimulatorCatalog(processRunner: StubProcessRunner(results: [
        "xcrun simctl list devices available -j": StubProcessRunner.success(listJSON),
    ])).availableDevices()

    #expect(devices.map(\.udid) == [
        "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
        "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB",
    ])
}

@Test func doctorServiceSupportsProjectOnlySchemeDiscovery() throws {
    let runner = StubProcessRunner(results: [
        "which swift": StubProcessRunner.success(),
        "which xcodebuild": StubProcessRunner.success(),
        "xcrun simctl help": StubProcessRunner.success(),
        "xcrun xcresulttool help": StubProcessRunner.success(),
        "which xcrun": StubProcessRunner.success(),
        "xcodebuild -list -json -project /tmp/repo/SymphonyApps.xcodeproj": StubProcessRunner.success(#"{"project":{"schemes":["Symphony"]}}"#),
    ])
    let discovery = StubWorkspaceDiscovery(
        workspace: WorkspaceContext(
            projectRoot: URL(fileURLWithPath: "/tmp/repo", isDirectory: true),
            buildStateRoot: URL(fileURLWithPath: "/tmp/repo/.build/symphony-build", isDirectory: true),
            xcodeWorkspacePath: nil,
            xcodeProjectPath: URL(fileURLWithPath: "/tmp/repo/SymphonyApps.xcodeproj")
        )
    )
    let service = DoctorService(workspaceDiscovery: discovery, processRunner: runner)

    let report = try service.makeReport(
        from: DoctorCommandRequest(strict: false, json: false, quiet: false, currentDirectory: URL(fileURLWithPath: "/tmp/repo"))
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
        "xcodebuild -list -json -workspace /tmp/repo/Symphony.xcworkspace": StubProcessRunner.success(#"{"workspace":{"schemes":["Symphony"]}}"#),
    ])
    let discovery = StubWorkspaceDiscovery(
        workspace: WorkspaceContext(
            projectRoot: URL(fileURLWithPath: "/tmp/repo", isDirectory: true),
            buildStateRoot: URL(fileURLWithPath: "/tmp/repo/.build/symphony-build", isDirectory: true),
            xcodeWorkspacePath: URL(fileURLWithPath: "/tmp/repo/Symphony.xcworkspace"),
            xcodeProjectPath: nil
        )
    )
    let service = DoctorService(workspaceDiscovery: discovery, processRunner: runner)

    let report = try service.makeReport(
        from: DoctorCommandRequest(strict: false, json: false, quiet: false, currentDirectory: URL(fileURLWithPath: "/tmp/repo"))
    )

    #expect(report.issues.isEmpty)
}

@Test func endpointStoreWorkspaceDiscoveryAndDoctorServiceCoverErrorPaths() throws {
    try withTemporaryDirectory { directory in
        let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repoRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: repoRoot.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: repoRoot.appendingPathComponent("One.xcodeproj"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: repoRoot.appendingPathComponent("Two.xcodeproj"), withIntermediateDirectories: true)
        let nested = repoRoot.appendingPathComponent("Sources/Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        do {
            _ = try WorkspaceDiscovery(processRunner: StubProcessRunner()).discover(from: repoRoot)
            Issue.record("Expected ambiguous projects to fail.")
        } catch let error as SymphonyBuildError {
            #expect(error.code == "ambiguous_project")
        }

        try FileManager.default.removeItem(at: repoRoot.appendingPathComponent("Two.xcodeproj"))
        try FileManager.default.removeItem(at: repoRoot.appendingPathComponent("One.xcodeproj"))

        do {
            _ = try WorkspaceDiscovery(processRunner: StubProcessRunner()).discover(from: repoRoot)
            Issue.record("Expected missing build definitions to fail.")
        } catch let error as SymphonyBuildError {
            #expect(error.code == "missing_build_definition")
        }

        do {
            _ = try WorkspaceDiscovery(processRunner: StubProcessRunner()).discover(from: URL(fileURLWithPath: "/", isDirectory: true))
            Issue.record("Expected missing repository roots to fail.")
        } catch let error as SymphonyBuildError {
            #expect(error.code == "missing_repository_root")
        }

        try FileManager.default.createDirectory(at: repoRoot.appendingPathComponent("Symphony.xcworkspace"), withIntermediateDirectories: true)
        let nestedWorkspace = try WorkspaceDiscovery(processRunner: StubProcessRunner()).discover(from: nested)
        #expect(nestedWorkspace.projectRoot.path == repoRoot.path)

        do {
            try WorkspaceDiscovery.validateBuildStateRoot(URL(fileURLWithPath: "/tmp/outside", isDirectory: true), within: repoRoot)
            Issue.record("Expected out-of-bounds build state roots to fail.")
        } catch let error as SymphonyBuildError {
            #expect(error.code == "artifact_root_out_of_bounds")
        }

        let endpointWorkspace = WorkspaceContext(
            projectRoot: repoRoot,
            buildStateRoot: repoRoot.appendingPathComponent(".build/symphony-build", isDirectory: true),
            xcodeWorkspacePath: nil,
            xcodeProjectPath: nil
        )
        let store = EndpointOverrideStore()
        #expect(store.storeURL(in: endpointWorkspace).path.hasSuffix(".build/symphony-build/runtime/server-endpoint.json"))
        #expect(store.clientEnvironment(for: try RuntimeEndpoint(scheme: "https", host: "example.com", port: 9443)) == [
            "SYMPHONY_SERVER_SCHEME": "https",
            "SYMPHONY_SERVER_HOST": "example.com",
            "SYMPHONY_SERVER_PORT": "9443",
        ])

        do {
            _ = try store.resolve(workspace: endpointWorkspace, serverURL: "not-a-url", scheme: nil, host: nil, port: nil)
            Issue.record("Expected invalid server URLs to fail.")
        } catch let error as SymphonyBuildError {
            #expect(error.code == "invalid_server_url")
        }

        let buildStateFile = repoRoot.appendingPathComponent(".build/symphony-build", isDirectory: false)
        try FileManager.default.createDirectory(at: buildStateFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: buildStateFile)

        let doctor = DoctorService(
            workspaceDiscovery: StubWorkspaceDiscovery(workspace: WorkspaceContext(
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
            ])
        )
        let report = try doctor.makeReport(from: DoctorCommandRequest(strict: false, json: false, quiet: false, currentDirectory: repoRoot))
        #expect(report.issues.contains(where: { $0.code == "missing_swift" }))
        #expect(report.issues.contains(where: { $0.code == "missing_simctl" }))
        #expect(report.issues.contains(where: { $0.code == "unwritable_build_state_root" }))
        #expect(report.issues.contains(where: { $0.code == "missing_scheme_symphony" }))

        let quiet = try doctor.render(report: DiagnosticsReport(issues: [], checkedPaths: [repoRoot.path], checkedExecutables: ["swift"]), json: false, quiet: true)
        #expect(quiet == "OK: environment is ready")

        let failingDoctor = DoctorService(
            workspaceDiscovery: StubWorkspaceDiscovery(workspace: WorkspaceContext(
                projectRoot: repoRoot,
                buildStateRoot: repoRoot.appendingPathComponent(".build/symphony-build", isDirectory: true),
                xcodeWorkspacePath: URL(fileURLWithPath: "/tmp/Symphony.xcworkspace"),
                xcodeProjectPath: nil
            )),
            processRunner: StubProcessRunner(results: [
                "which swift": StubProcessRunner.success(),
                "which xcodebuild": StubProcessRunner.success(),
                "which xcrun": StubProcessRunner.success(),
                "xcrun simctl help": StubProcessRunner.success(),
                "xcrun xcresulttool help": StubProcessRunner.success(),
                "xcodebuild -list -json -workspace /tmp/Symphony.xcworkspace": StubProcessRunner.failure("list broke"),
            ])
        )
        let failingReport = try failingDoctor.makeReport(from: DoctorCommandRequest(strict: false, json: false, quiet: false, currentDirectory: repoRoot))
        #expect(failingReport.issues.contains(where: { $0.code == "xcodebuild_list_failed" }))
    }
}

@Test func doctorServiceRendersIssuesWithoutFixAndUsesFallbackListFailureMessage() throws {
    let repoRoot = URL(fileURLWithPath: "/tmp/repo", isDirectory: true)
    let service = DoctorService(
        workspaceDiscovery: StubWorkspaceDiscovery(workspace: WorkspaceContext(
            projectRoot: repoRoot,
            buildStateRoot: repoRoot.appendingPathComponent(".build/symphony-build", isDirectory: true),
            xcodeWorkspacePath: URL(fileURLWithPath: "/tmp/Symphony.xcworkspace"),
            xcodeProjectPath: nil
        )),
        processRunner: StubProcessRunner(results: [
            "which swift": StubProcessRunner.success(),
            "which xcodebuild": StubProcessRunner.success(),
            "which xcrun": StubProcessRunner.success(),
            "xcrun simctl help": StubProcessRunner.success(),
            "xcrun xcresulttool help": StubProcessRunner.success(),
            "xcodebuild -list -json -workspace /tmp/Symphony.xcworkspace": CommandResult(exitStatus: 1, stdout: "", stderr: ""),
        ])
    )

    let report = try service.makeReport(
        from: DoctorCommandRequest(strict: false, json: false, quiet: false, currentDirectory: repoRoot)
    )
    #expect(report.issues.contains(where: { $0.code == "xcodebuild_list_failed" && $0.message == "Failed to list schemes." }))

    let rendered = try service.render(
        report: DiagnosticsReport(
            issues: [DiagnosticIssue(severity: .error, code: "plain_issue", message: "plain issue", suggestedFix: nil)],
            checkedPaths: [repoRoot.path],
            checkedExecutables: ["swift"]
        ),
        json: false,
        quiet: false
    )
    #expect(rendered.contains("ERROR [plain_issue] plain issue"))
    #expect(!rendered.contains("fix="))
}

@Test func simulatorResolverCoversDefaultSelectionAndEmptyFallbackMessages() throws {
    let devices = [
        SimulatorDevice(name: "iPhone 17", udid: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", state: "Shutdown", runtime: "iOS 18"),
    ]
    let resolver = SimulatorResolver(catalog: StubSimulatorCatalog(devices: devices), processRunner: StubProcessRunner())
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
                "xcrun simctl bootstatus AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA -b": StubProcessRunner.failure("not booted"),
                "xcrun simctl boot AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA": CommandResult(exitStatus: 1, stdout: "", stderr: ""),
            ])
        ).boot(resolved: bootDestination)
        Issue.record("Expected empty-output boot failures to use the fallback message.")
    } catch let error as SymphonyBuildError {
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
    } catch let error as SymphonyBuildError {
        #expect(error.code == "simulator_boot_failed")
        #expect(error.message == "Failed to confirm simulator boot.")
    }
}

@Test func endpointOverrideStoreFallsBackToPersistedHostAndPortWhenOnlySchemeOverrides() throws {
    try withTemporaryDirectory { directory in
        let workspace = WorkspaceContext(
            projectRoot: directory,
            buildStateRoot: directory.appendingPathComponent(".build/symphony-build", isDirectory: true),
            xcodeWorkspacePath: nil,
            xcodeProjectPath: nil
        )
        let store = EndpointOverrideStore()
        _ = try store.save(try RuntimeEndpoint(scheme: "http", host: "persisted.example.com", port: 9555), in: workspace)

        let resolved = try store.resolve(
            workspace: workspace,
            serverURL: nil,
            scheme: "https",
            host: nil,
            port: nil
        )

        #expect(resolved.scheme == "https")
        #expect(resolved.host == "persisted.example.com")
        #expect(resolved.port == 9555)
    }
}

private struct BootSequenceProcessRunner: ProcessRunning {
    private let responses: [CommandResult]
    private let counter = LockedCounter()

    init(responses: [CommandResult]) {
        self.responses = responses
    }

    func run(command: String, arguments: [String], environment: [String : String], currentDirectory: URL?, observation: ProcessObservation?) throws -> CommandResult {
        responses[counter.next()]
    }

    func startDetached(executablePath: String, arguments: [String], environment: [String : String], currentDirectory: URL?, output: URL) throws -> Int32 {
        0
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func next() -> Int {
        lock.lock()
        defer {
            value += 1
            lock.unlock()
        }
        return value
    }
}
