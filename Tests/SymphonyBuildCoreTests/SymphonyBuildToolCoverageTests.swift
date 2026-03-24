import Foundation
import Testing
@testable import SymphonyBuildCore

@Test func buildToolCoversBuildTestAndCoverageSuccessAndFailurePaths() throws {
    try withTemporaryRepositoryFixture { repoRoot in
        let workspace = WorkspaceContext(
            projectRoot: repoRoot,
            buildStateRoot: repoRoot.appendingPathComponent(".build/symphony-build", isDirectory: true),
            xcodeWorkspacePath: repoRoot.appendingPathComponent("Symphony.xcworkspace"),
            xcodeProjectPath: nil
        )
        let signals = SignalBox()
        let runner = RoutedProcessRunner { command, arguments, _, _, observation in
            if command == "xcodebuild" {
                observation?.onLine?(.stdout, "Command line invocation:")
                return StubProcessRunner.success("xcodebuild ok")
            }
            if command == "xcrun", arguments.prefix(2) == ["xccov", "view"] {
                let json = #"""
                {"targets":[{"buildProductPath":"/tmp/SymphonyServer","coveredLines":4,"executableLines":4,"files":[{"coveredLines":4,"executableLines":4,"name":"Main.swift","path":"/tmp/Main.swift"}],"name":"SymphonyServer"}]}
                """#
                return StubProcessRunner.success(json)
            }
            return StubProcessRunner.success()
        }
        let tool = makeCoverageTool(workspace: workspace, runner: runner, statusSink: { signals.append($0) })

        let buildOutput = try tool.build(
            BuildCommandRequest(
                product: .server,
                scheme: nil,
                platform: nil,
                simulator: nil,
                workerID: 0,
                dryRun: false,
                buildForTesting: true,
                outputMode: .full,
                currentDirectory: repoRoot
            )
        )
        #expect(buildOutput.hasSuffix("summary.txt"))

        let testOutput = try tool.test(
            TestCommandRequest(
                product: .server,
                scheme: nil,
                platform: nil,
                simulator: nil,
                workerID: 0,
                dryRun: false,
                onlyTesting: ["Suite/test"],
                skipTesting: ["Suite/skip"],
                outputMode: .filtered,
                currentDirectory: repoRoot
            )
        )
        #expect(testOutput.hasSuffix("summary.txt"))

        let coverageOutput = try tool.coverage(
            CoverageCommandRequest(
                product: .server,
                scheme: nil,
                platform: nil,
                simulator: nil,
                workerID: 0,
                dryRun: false,
                onlyTesting: [],
                skipTesting: [],
                json: false,
                showFiles: true,
                includeTestTargets: false,
                outputMode: .quiet,
                currentDirectory: repoRoot
            )
        )
        #expect(coverageOutput.contains("overall 100.00% (4/4)"))
        #expect(signals.values.contains(where: { $0.contains("Command line invocation:") }))
        #expect(runner.startedDetachedExecutions.isEmpty)

        let failingRunner = RoutedProcessRunner { command, arguments, _, _, _ in
            if command == "xcodebuild", arguments.last == "build" {
                return StubProcessRunner.failure("build failed")
            }
            if command == "xcodebuild", arguments.last == "test" {
                return StubProcessRunner.failure("test failed")
            }
            if command == "xcrun", arguments.prefix(2) == ["xccov", "view"] {
                return StubProcessRunner.failure("xccov failed")
            }
            return StubProcessRunner.success()
        }
        let failingTool = makeCoverageTool(workspace: workspace, runner: failingRunner, statusSink: { _ in })

        do {
            _ = try failingTool.build(
                BuildCommandRequest(product: .server, scheme: nil, platform: nil, simulator: nil, workerID: 0, dryRun: false, buildForTesting: false, outputMode: .filtered, currentDirectory: repoRoot)
            )
            Issue.record("Expected failing builds to surface.")
        } catch let error as SymphonyBuildCommandFailure {
            #expect(error.message.contains("xcodebuild build failed"))
        }

        do {
            _ = try failingTool.test(
                TestCommandRequest(product: .server, scheme: nil, platform: nil, simulator: nil, workerID: 0, dryRun: false, onlyTesting: [], skipTesting: [], outputMode: .filtered, currentDirectory: repoRoot)
            )
            Issue.record("Expected failing tests to surface.")
        } catch let error as SymphonyBuildCommandFailure {
            #expect(error.message.contains("xcodebuild test failed"))
        }

        do {
            _ = try failingTool.coverage(
                CoverageCommandRequest(product: .server, scheme: nil, platform: nil, simulator: nil, workerID: 0, dryRun: false, onlyTesting: [], skipTesting: [], json: false, showFiles: false, includeTestTargets: false, outputMode: .filtered, currentDirectory: repoRoot)
            )
            Issue.record("Expected failing coverage builds to surface.")
        } catch let error as SymphonyBuildCommandFailure {
            #expect(error.message.contains("xcodebuild test with code coverage failed."))
        }

        let exportFailRunner = RoutedProcessRunner { command, arguments, _, _, _ in
            if command == "xcodebuild" {
                return StubProcessRunner.success("ok")
            }
            if command == "xcrun", arguments.prefix(2) == ["xccov", "view"] {
                return StubProcessRunner.failure("xccov failed")
            }
            return StubProcessRunner.success()
        }
        let exportFailTool = makeCoverageTool(workspace: workspace, runner: exportFailRunner, statusSink: { _ in })
        do {
            _ = try exportFailTool.coverage(
                CoverageCommandRequest(product: .server, scheme: nil, platform: nil, simulator: nil, workerID: 0, dryRun: false, onlyTesting: [], skipTesting: [], json: false, showFiles: false, includeTestTargets: false, outputMode: .filtered, currentDirectory: repoRoot)
            )
            Issue.record("Expected coverage export failures to surface.")
        } catch let error as SymphonyBuildCommandFailure {
            #expect(error.message == "Coverage export failed.")
        }
    }
}

@Test func buildToolCoversRunServerAndClientLaunchPaths() throws {
    try withTemporaryRepositoryFixture { repoRoot in
        let workspace = WorkspaceContext(
            projectRoot: repoRoot,
            buildStateRoot: repoRoot.appendingPathComponent(".build/symphony-build", isDirectory: true),
            xcodeWorkspacePath: repoRoot.appendingPathComponent("Symphony.xcworkspace"),
            xcodeProjectPath: nil
        )
        let destination = expectedHostMacOSDestination()
        let buildSettingsCommand = "xcodebuild -showBuildSettings -json -scheme SymphonyServer -destination \(destination) -derivedDataPath \(repoRoot.appendingPathComponent(".build/symphony-build/derived-data/worker-0").path) -workspace \(repoRoot.appendingPathComponent("Symphony.xcworkspace").path)"
        let runner = RoutedProcessRunner { command, arguments, environment, _, _ in
            if command == "xcodebuild", arguments.last == "build" {
                return StubProcessRunner.success("built")
            }
            if ([command] + arguments).joined(separator: " ") == buildSettingsCommand {
                return StubProcessRunner.success(#"[{"buildSettings":{"TARGET_BUILD_DIR":"/tmp/Build","FULL_PRODUCT_NAME":"SymphonyServer","EXECUTABLE_PATH":"SymphonyServer","PRODUCT_BUNDLE_IDENTIFIER":"com.example.server"}}]"#)
            }
            return StubProcessRunner.success()
        }
        let tool = SymphonyBuildTool(
            workspaceDiscovery: StubWorkspaceDiscovery(workspace: workspace),
            executionContextBuilder: ExecutionContextBuilder(),
            simulatorResolver: SimulatorResolver(catalog: StubSimulatorCatalog(devices: []), processRunner: runner),
            processRunner: runner,
            artifactManager: ArtifactManager(processRunner: runner),
            endpointOverrideStore: EndpointOverrideStore(),
            doctorService: StubDoctorService(report: DiagnosticsReport(issues: [], checkedPaths: [], checkedExecutables: []), rendered: "ok"),
            productLocator: ProductLocator(processRunner: runner),
            commitHarness: CommitHarness(processRunner: runner),
            gitHookInstaller: GitHookInstaller(processRunner: runner),
            statusSink: { _ in }
        )

        let serverOutput = try tool.run(
            RunCommandRequest(
                product: .server,
                scheme: nil,
                platform: nil,
                simulator: nil,
                workerID: 0,
                dryRun: false,
                serverURL: nil,
                host: nil,
                port: nil,
                environment: ["CUSTOM": "1"],
                outputMode: .filtered,
                currentDirectory: repoRoot
            )
        )
        #expect(serverOutput.hasSuffix("summary.txt"))
        #expect(runner.startedDetachedExecutions.count == 1)
        #expect(runner.startedDetachedExecutions[0].environment == ["CUSTOM": "1"])

        let clientRunner = RoutedProcessRunner { command, arguments, environment, _, _ in
            let invocation = ([command] + arguments).joined(separator: " ")
            if command == "xcodebuild", arguments.last == "build" {
                return StubProcessRunner.success("built")
            }
            if invocation.contains("-showBuildSettings") {
                return StubProcessRunner.success(#"[{"buildSettings":{"TARGET_BUILD_DIR":"/tmp/Build","FULL_PRODUCT_NAME":"Symphony.app","EXECUTABLE_PATH":"Symphony.app/Contents/MacOS/Symphony","PRODUCT_BUNDLE_IDENTIFIER":"com.example.client"}}]"#)
            }
            if command == "xcrun", arguments == ["simctl", "bootstatus", "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", "-b"] {
                return StubProcessRunner.success()
            }
            if command == "xcrun", arguments.prefix(2) == ["simctl", "install"] {
                return StubProcessRunner.success("installed")
            }
            if command == "xcrun", arguments.prefix(2) == ["simctl", "launch"] {
                #expect(environment["SIMCTL_CHILD_FOO"] == "bar")
                #expect(environment["SIMCTL_CHILD_SYMPHONY_SERVER_HOST"] == "localhost")
                return StubProcessRunner.success("launched")
            }
            return StubProcessRunner.success()
        }
        let clientTool = SymphonyBuildTool(
            workspaceDiscovery: StubWorkspaceDiscovery(workspace: workspace),
            executionContextBuilder: ExecutionContextBuilder(),
            simulatorResolver: SimulatorResolver(
                catalog: StubSimulatorCatalog(devices: [
                    SimulatorDevice(name: "iPhone 17", udid: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", state: "Shutdown", runtime: "iOS 18")
                ]),
                processRunner: clientRunner
            ),
            processRunner: clientRunner,
            artifactManager: ArtifactManager(processRunner: clientRunner),
            endpointOverrideStore: EndpointOverrideStore(),
            doctorService: StubDoctorService(report: DiagnosticsReport(issues: [], checkedPaths: [], checkedExecutables: []), rendered: "ok"),
            productLocator: ProductLocator(processRunner: clientRunner),
            commitHarness: CommitHarness(processRunner: clientRunner),
            gitHookInstaller: GitHookInstaller(processRunner: clientRunner),
            statusSink: { _ in }
        )
        let clientOutput = try clientTool.run(
            RunCommandRequest(
                product: .client,
                scheme: nil,
                platform: nil,
                simulator: "iPhone 17",
                workerID: 0,
                dryRun: false,
                serverURL: nil,
                host: nil,
                port: nil,
                environment: ["FOO": "bar"],
                outputMode: .filtered,
                currentDirectory: repoRoot
            )
        )
        #expect(clientOutput.hasSuffix("summary.txt"))

        let missingMetadataRunner = RoutedProcessRunner { command, arguments, _, _, _ in
            if command == "xcodebuild", arguments.last == "build" {
                return StubProcessRunner.success("built")
            }
            if ([command] + arguments).joined(separator: " ").contains("-showBuildSettings") {
                return StubProcessRunner.success(#"[{"buildSettings":{"TARGET_BUILD_DIR":"/tmp/Build","FULL_PRODUCT_NAME":"Symphony.app"}}]"#)
            }
            return StubProcessRunner.success()
        }
        let missingMetadataTool = SymphonyBuildTool(
            workspaceDiscovery: StubWorkspaceDiscovery(workspace: workspace),
            executionContextBuilder: ExecutionContextBuilder(),
            simulatorResolver: SimulatorResolver(
                catalog: StubSimulatorCatalog(devices: [
                    SimulatorDevice(name: "iPhone 17", udid: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", state: "Shutdown", runtime: "iOS 18")
                ]),
                processRunner: missingMetadataRunner
            ),
            processRunner: missingMetadataRunner,
            artifactManager: ArtifactManager(processRunner: missingMetadataRunner),
            endpointOverrideStore: EndpointOverrideStore(),
            doctorService: StubDoctorService(report: DiagnosticsReport(issues: [], checkedPaths: [], checkedExecutables: []), rendered: "ok"),
            productLocator: ProductLocator(processRunner: missingMetadataRunner),
            commitHarness: CommitHarness(processRunner: missingMetadataRunner),
            gitHookInstaller: GitHookInstaller(processRunner: missingMetadataRunner),
            statusSink: { _ in }
        )
        do {
            _ = try missingMetadataTool.run(
                RunCommandRequest(product: .client, scheme: nil, platform: nil, simulator: "iPhone 17", workerID: 0, dryRun: false, serverURL: nil, host: nil, port: nil, environment: [:], outputMode: .filtered, currentDirectory: repoRoot)
            )
            Issue.record("Expected missing launch metadata to fail.")
        } catch let error as SymphonyBuildError {
            #expect(error.code == "missing_launch_metadata")
        }
    }
}

@Test func buildToolCoversRunClientFailureAndSimulatorManagementPaths() throws {
    try withTemporaryRepositoryFixture { repoRoot in
        let workspace = WorkspaceContext(
            projectRoot: repoRoot,
            buildStateRoot: repoRoot.appendingPathComponent(".build/symphony-build", isDirectory: true),
            xcodeWorkspacePath: repoRoot.appendingPathComponent("Symphony.xcworkspace"),
            xcodeProjectPath: nil
        )
        let devices = [
            SimulatorDevice(name: "iPhone 17", udid: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", state: "Shutdown", runtime: "iOS 18")
        ]

        let installFailRunner = RoutedProcessRunner { command, arguments, _, _, _ in
            let invocation = ([command] + arguments).joined(separator: " ")
            if command == "xcodebuild", arguments.last == "build" {
                return StubProcessRunner.success("built")
            }
            if invocation.contains("-showBuildSettings") {
                return StubProcessRunner.success(#"[{"buildSettings":{"TARGET_BUILD_DIR":"/tmp/Build","FULL_PRODUCT_NAME":"Symphony.app","PRODUCT_BUNDLE_IDENTIFIER":"com.example.client"}}]"#)
            }
            if command == "xcrun", arguments == ["simctl", "bootstatus", "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", "-b"] {
                return StubProcessRunner.success()
            }
            if command == "xcrun", arguments.prefix(2) == ["simctl", "install"] {
                return StubProcessRunner.failure("install failed")
            }
            return StubProcessRunner.success()
        }
        let installFailTool = SymphonyBuildTool(
            workspaceDiscovery: StubWorkspaceDiscovery(workspace: workspace),
            executionContextBuilder: ExecutionContextBuilder(),
            simulatorResolver: SimulatorResolver(catalog: StubSimulatorCatalog(devices: devices), processRunner: installFailRunner),
            processRunner: installFailRunner,
            artifactManager: ArtifactManager(processRunner: installFailRunner),
            endpointOverrideStore: EndpointOverrideStore(),
            doctorService: StubDoctorService(report: DiagnosticsReport(issues: [], checkedPaths: [], checkedExecutables: []), rendered: "ok"),
            productLocator: ProductLocator(processRunner: installFailRunner),
            commitHarness: CommitHarness(processRunner: installFailRunner),
            gitHookInstaller: GitHookInstaller(processRunner: installFailRunner),
            statusSink: { _ in }
        )
        do {
            _ = try installFailTool.run(
                RunCommandRequest(product: .client, scheme: nil, platform: nil, simulator: "iPhone 17", workerID: 0, dryRun: false, serverURL: nil, host: nil, port: nil, environment: [:], outputMode: .filtered, currentDirectory: repoRoot)
            )
            Issue.record("Expected install failures to fail the launch step.")
        } catch let error as SymphonyBuildCommandFailure {
            #expect(error.message == "The launch step failed.")
        }

        let launchFailRunner = RoutedProcessRunner { command, arguments, _, _, _ in
            let invocation = ([command] + arguments).joined(separator: " ")
            if command == "xcodebuild", arguments.last == "build" {
                return StubProcessRunner.success("built")
            }
            if invocation.contains("-showBuildSettings") {
                return StubProcessRunner.success(#"[{"buildSettings":{"TARGET_BUILD_DIR":"/tmp/Build","FULL_PRODUCT_NAME":"Symphony.app","PRODUCT_BUNDLE_IDENTIFIER":"com.example.client"}}]"#)
            }
            if command == "xcrun", arguments == ["simctl", "bootstatus", "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", "-b"] {
                return StubProcessRunner.success()
            }
            if command == "xcrun", arguments.prefix(2) == ["simctl", "install"] {
                return StubProcessRunner.success("installed")
            }
            if command == "xcrun", arguments.prefix(2) == ["simctl", "launch"] {
                return StubProcessRunner.failure("launch failed")
            }
            return StubProcessRunner.success()
        }
        let launchFailTool = SymphonyBuildTool(
            workspaceDiscovery: StubWorkspaceDiscovery(workspace: workspace),
            executionContextBuilder: ExecutionContextBuilder(),
            simulatorResolver: SimulatorResolver(catalog: StubSimulatorCatalog(devices: devices), processRunner: launchFailRunner),
            processRunner: launchFailRunner,
            artifactManager: ArtifactManager(processRunner: launchFailRunner),
            endpointOverrideStore: EndpointOverrideStore(),
            doctorService: StubDoctorService(report: DiagnosticsReport(issues: [], checkedPaths: [], checkedExecutables: []), rendered: "ok"),
            productLocator: ProductLocator(processRunner: launchFailRunner),
            commitHarness: CommitHarness(processRunner: launchFailRunner),
            gitHookInstaller: GitHookInstaller(processRunner: launchFailRunner),
            statusSink: { _ in }
        )
        do {
            _ = try launchFailTool.run(
                RunCommandRequest(product: .client, scheme: nil, platform: nil, simulator: "iPhone 17", workerID: 0, dryRun: false, serverURL: nil, host: nil, port: nil, environment: [:], outputMode: .filtered, currentDirectory: repoRoot)
            )
            Issue.record("Expected launch failures to fail the launch step.")
        } catch let error as SymphonyBuildCommandFailure {
            #expect(error.message == "The launch step failed.")
        }

        let listBootRunner = RoutedProcessRunner { command, arguments, _, _, _ in
            if command == "xcrun", arguments == ["simctl", "list", "devices", "available", "-j"] {
                return StubProcessRunner.success(#"{"devices":{"iOS 18":[{"name":"iPhone 17","udid":"AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA","state":"Shutdown"}]}}"#)
            }
            if command == "xcrun", arguments == ["simctl", "bootstatus", "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", "-b"] {
                return StubProcessRunner.success()
            }
            return StubProcessRunner.success()
        }
        let managementTool = SymphonyBuildTool(
            workspaceDiscovery: StubWorkspaceDiscovery(workspace: workspace),
            executionContextBuilder: ExecutionContextBuilder(),
            simulatorResolver: SimulatorResolver(catalog: StubSimulatorCatalog(devices: devices), processRunner: listBootRunner),
            processRunner: listBootRunner,
            artifactManager: ArtifactManager(processRunner: listBootRunner),
            endpointOverrideStore: EndpointOverrideStore(),
            doctorService: StubDoctorService(report: DiagnosticsReport(issues: [], checkedPaths: [], checkedExecutables: []), rendered: "ok"),
            productLocator: ProductLocator(processRunner: listBootRunner),
            commitHarness: CommitHarness(processRunner: listBootRunner),
            gitHookInstaller: GitHookInstaller(processRunner: listBootRunner),
            statusSink: { _ in }
        )
        #expect(try managementTool.simList(currentDirectory: repoRoot).contains("iPhone 17 (AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA)"))
        #expect(try managementTool.simBoot(SimBootRequest(simulator: "iPhone 17", currentDirectory: repoRoot)) == "iPhone 17 (AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA)")
    }
}

@Test func buildToolCoversArtifactsDoctorRunFallbackAndDefaultStatusSink() throws {
    try withTemporaryRepositoryFixture { repoRoot in
        let workspace = WorkspaceContext(
            projectRoot: repoRoot,
            buildStateRoot: repoRoot.appendingPathComponent(".build/symphony-build", isDirectory: true),
            xcodeWorkspacePath: repoRoot.appendingPathComponent("Symphony.xcworkspace"),
            xcodeProjectPath: nil
        )

        let genericCoverageRunner = RoutedProcessRunner { command, arguments, _, _, observation in
            if command == "xcodebuild" {
                observation?.onLine?(.stdout, "build output")
                return StubProcessRunner.success("built")
            }
            if command == "xcrun", arguments.prefix(2) == ["xccov", "view"] {
                struct GenericFailure: Error {}
                throw GenericFailure()
            }
            return StubProcessRunner.success()
        }
        let defaultSinkTool = SymphonyBuildTool(
            workspaceDiscovery: StubWorkspaceDiscovery(workspace: workspace),
            executionContextBuilder: ExecutionContextBuilder(),
            simulatorResolver: SimulatorResolver(catalog: StubSimulatorCatalog(devices: []), processRunner: genericCoverageRunner),
            processRunner: genericCoverageRunner,
            artifactManager: ArtifactManager(processRunner: genericCoverageRunner),
            endpointOverrideStore: EndpointOverrideStore(),
            doctorService: StubDoctorService(report: DiagnosticsReport(issues: [], checkedPaths: [], checkedExecutables: []), rendered: "ok"),
            productLocator: ProductLocator(processRunner: genericCoverageRunner),
            commitHarness: CommitHarness(processRunner: genericCoverageRunner),
            gitHookInstaller: GitHookInstaller(processRunner: genericCoverageRunner)
        )
        do {
            _ = try defaultSinkTool.coverage(
                CoverageCommandRequest(product: .server, scheme: nil, platform: nil, simulator: nil, workerID: 0, dryRun: false, onlyTesting: [], skipTesting: [], json: false, showFiles: false, includeTestTargets: false, outputMode: .full, currentDirectory: repoRoot)
            )
            Issue.record("Expected generic coverage export failures to surface.")
        } catch let error as SymphonyBuildCommandFailure {
            #expect(error.message == "Coverage export failed.")
        }

        let runBuildFailRunner = RoutedProcessRunner { command, arguments, _, _, _ in
            if command == "xcodebuild", arguments.last == "build" {
                return StubProcessRunner.failure("run build failed")
            }
            return StubProcessRunner.success()
        }
        let runBuildFailTool = SymphonyBuildTool(
            workspaceDiscovery: StubWorkspaceDiscovery(workspace: workspace),
            executionContextBuilder: ExecutionContextBuilder(),
            simulatorResolver: SimulatorResolver(catalog: StubSimulatorCatalog(devices: []), processRunner: runBuildFailRunner),
            processRunner: runBuildFailRunner,
            artifactManager: ArtifactManager(processRunner: runBuildFailRunner),
            endpointOverrideStore: EndpointOverrideStore(),
            doctorService: StubDoctorService(report: DiagnosticsReport(issues: [], checkedPaths: [], checkedExecutables: []), rendered: "ok"),
            productLocator: ProductLocator(processRunner: runBuildFailRunner),
            commitHarness: CommitHarness(processRunner: runBuildFailRunner),
            gitHookInstaller: GitHookInstaller(processRunner: runBuildFailRunner),
            statusSink: { _ in }
        )
        do {
            _ = try runBuildFailTool.run(
                RunCommandRequest(product: .server, scheme: nil, platform: nil, simulator: nil, workerID: 0, dryRun: false, serverURL: nil, host: nil, port: nil, environment: [:], outputMode: .filtered, currentDirectory: repoRoot)
            )
            Issue.record("Expected run build failures to surface.")
        } catch let error as SymphonyBuildCommandFailure {
            #expect(error.message == "The run build step failed.")
        }

        let noExecutableRunner = RoutedProcessRunner { command, arguments, _, _, _ in
            let invocation = ([command] + arguments).joined(separator: " ")
            if command == "xcodebuild", arguments.last == "build" {
                return StubProcessRunner.success("built")
            }
            if invocation.contains("-showBuildSettings") {
                return StubProcessRunner.success(#"[{"buildSettings":{"TARGET_BUILD_DIR":"/tmp/Build","FULL_PRODUCT_NAME":"SymphonyServer"}}]"#)
            }
            return StubProcessRunner.success()
        }
        let noExecutableTool = SymphonyBuildTool(
            workspaceDiscovery: StubWorkspaceDiscovery(workspace: workspace),
            executionContextBuilder: ExecutionContextBuilder(),
            simulatorResolver: SimulatorResolver(
                catalog: StubSimulatorCatalog(devices: [
                    SimulatorDevice(name: "iPhone 17", udid: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", state: "Shutdown", runtime: "iOS 18")
                ]),
                processRunner: noExecutableRunner
            ),
            processRunner: noExecutableRunner,
            artifactManager: ArtifactManager(processRunner: noExecutableRunner),
            endpointOverrideStore: EndpointOverrideStore(),
            doctorService: StubDoctorService(report: DiagnosticsReport(issues: [], checkedPaths: [], checkedExecutables: []), rendered: "ok"),
            productLocator: ProductLocator(processRunner: noExecutableRunner),
            commitHarness: CommitHarness(processRunner: noExecutableRunner),
            gitHookInstaller: GitHookInstaller(processRunner: noExecutableRunner),
            statusSink: { _ in }
        )
        let serverFallbackOutput = try noExecutableTool.run(
            RunCommandRequest(product: .server, scheme: nil, platform: nil, simulator: nil, workerID: 0, dryRun: false, serverURL: nil, host: nil, port: nil, environment: [:], outputMode: .filtered, currentDirectory: repoRoot)
        )
        #expect(serverFallbackOutput.hasSuffix("summary.txt"))

        let dryRunUDIDOutput = try noExecutableTool.run(
            RunCommandRequest(product: .client, scheme: nil, platform: nil, simulator: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", workerID: 0, dryRun: true, serverURL: nil, host: nil, port: nil, environment: [:], outputMode: .filtered, currentDirectory: repoRoot)
        )
        #expect(dryRunUDIDOutput.contains("platform=iOS Simulator,id=AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"))

        let manager = ArtifactManager(processRunner: StubProcessRunner())
        let worker = try WorkerScope(id: 0)
        let executionContext = try ExecutionContextBuilder().make(
            workspace: workspace,
            worker: worker,
            command: .build,
            runID: "artifact",
            date: Date(timeIntervalSince1970: 1_700_000_500)
        )
        _ = try manager.recordXcodeExecution(
            workspace: workspace,
            executionContext: executionContext,
            command: .build,
            product: .server,
            scheme: "SymphonyServer",
            destination: ResolvedDestination(platform: .macos, displayName: "macOS", simulatorName: nil, simulatorUDID: nil, xcodeDestination: expectedHostMacOSDestination()),
            invocation: "xcodebuild build",
            exitStatus: 0,
            combinedOutput: "",
            startedAt: Date(timeIntervalSince1970: 1_700_000_500),
            endedAt: Date(timeIntervalSince1970: 1_700_000_530)
        )
        let artifactsTool = SymphonyBuildTool(
            workspaceDiscovery: StubWorkspaceDiscovery(workspace: workspace),
            executionContextBuilder: ExecutionContextBuilder(),
            simulatorResolver: SimulatorResolver(catalog: StubSimulatorCatalog(devices: []), processRunner: StubProcessRunner()),
            processRunner: StubProcessRunner(),
            artifactManager: manager,
            endpointOverrideStore: EndpointOverrideStore(),
            doctorService: StubDoctorService(report: DiagnosticsReport(issues: [], checkedPaths: [], checkedExecutables: []), rendered: "ok"),
            productLocator: ProductLocator(processRunner: StubProcessRunner()),
            commitHarness: CommitHarness(processRunner: StubProcessRunner()),
            gitHookInstaller: GitHookInstaller(processRunner: StubProcessRunner()),
            statusSink: { _ in }
        )
        let artifactsOutput = try artifactsTool.artifacts(
            ArtifactsCommandRequest(command: .build, latest: true, runID: nil, currentDirectory: repoRoot)
        )
        #expect(artifactsOutput.contains("summary.txt"))

        let unhealthyDoctorTool = SymphonyBuildTool(
            doctorService: StubDoctorService(
                report: DiagnosticsReport(issues: [DiagnosticIssue(severity: .error, code: "bad", message: "bad")], checkedPaths: [], checkedExecutables: []),
                rendered: "rendered-bad"
            )
        )
        do {
            _ = try unhealthyDoctorTool.doctor(
                DoctorCommandRequest(strict: false, json: false, quiet: false, currentDirectory: repoRoot)
            )
            Issue.record("Expected unhealthy non-strict doctor runs to fail.")
        } catch let error as SymphonyBuildCommandFailure {
            #expect(error.message == "rendered-bad")
        }
    }
}

private func makeCoverageTool(workspace: WorkspaceContext, runner: RoutedProcessRunner, statusSink: @escaping @Sendable (String) -> Void) -> SymphonyBuildTool {
    SymphonyBuildTool(
        workspaceDiscovery: StubWorkspaceDiscovery(workspace: workspace),
        executionContextBuilder: ExecutionContextBuilder(),
        simulatorResolver: SimulatorResolver(catalog: StubSimulatorCatalog(devices: []), processRunner: runner),
        processRunner: runner,
        artifactManager: ArtifactManager(processRunner: runner),
        endpointOverrideStore: EndpointOverrideStore(),
        doctorService: StubDoctorService(report: DiagnosticsReport(issues: [], checkedPaths: [], checkedExecutables: []), rendered: "ok"),
        productLocator: ProductLocator(processRunner: runner),
        commitHarness: CommitHarness(processRunner: runner, clientCoverageLoader: { _ in
            CoverageReport(coveredLines: 1, executableLines: 1, lineCoverage: 1, includeTestTargets: false, excludedTargets: [], targets: [])
        }, serverCoverageLoader: { _ in
            CoverageReport(coveredLines: 1, executableLines: 1, lineCoverage: 1, includeTestTargets: false, excludedTargets: [], targets: [])
        }),
        gitHookInstaller: GitHookInstaller(processRunner: runner),
        statusSink: statusSink
    )
}

private final class RoutedProcessRunner: ProcessRunning, @unchecked Sendable {
    private let handler: @Sendable (String, [String], [String: String], URL?, ProcessObservation?) throws -> CommandResult
    private let lock = NSLock()
    private(set) var startedDetachedExecutions = [(executablePath: String, environment: [String: String], output: URL)]()

    init(handler: @escaping @Sendable (String, [String], [String: String], URL?, ProcessObservation?) throws -> CommandResult) {
        self.handler = handler
    }

    func run(command: String, arguments: [String], environment: [String : String], currentDirectory: URL?, observation: ProcessObservation?) throws -> CommandResult {
        try handler(command, arguments, environment, currentDirectory, observation)
    }

    func startDetached(executablePath: String, arguments: [String], environment: [String : String], currentDirectory: URL?, output: URL) throws -> Int32 {
        lock.lock()
        startedDetachedExecutions.append((executablePath, environment, output))
        lock.unlock()
        return 4242
    }
}
