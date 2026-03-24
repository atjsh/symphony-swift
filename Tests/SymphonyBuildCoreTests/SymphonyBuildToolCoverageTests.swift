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
        let coveragePath = repoRoot.appendingPathComponent(".build/server-coverage.json")
        try FileManager.default.createDirectory(at: coveragePath.deletingLastPathComponent(), withIntermediateDirectories: true)
        try #"""
        {
          "data": [
            {
              "files": [
                {
                  "filename": "__REPO__/Sources/SymphonyRuntime/BootstrapSupport.swift",
                  "summary": { "lines": { "count": 4, "covered": 4 } }
                },
                {
                  "filename": "__REPO__/Sources/SymphonyServer/main.swift",
                  "summary": { "lines": { "count": 2, "covered": 2 } }
                },
                {
                  "filename": "__REPO__/Tests/SymphonyServerTests/BootstrapServerRunnerTests.swift",
                  "summary": { "lines": { "count": 20, "covered": 20 } }
                }
              ]
            }
          ]
        }
        """#
        .replacingOccurrences(of: "__REPO__", with: repoRoot.path)
        .write(to: coveragePath, atomically: true, encoding: .utf8)

        let signals = SignalBox()
        let runner = RoutedProcessRunner { command, arguments, _, _, _ in
            if command == "swift", arguments == ["build", "--product", "SymphonyServer"] {
                return StubProcessRunner.success("swift build ok")
            }
            if command == "swift", arguments == ["test", "--filter", "SymphonyServerTests"] {
                return StubProcessRunner.success("swift test ok")
            }
            if command == "swift", arguments == ["test", "--enable-code-coverage", "--filter", "SymphonyServerTests"] {
                return StubProcessRunner.success("swift coverage ok")
            }
            if command == "swift", arguments == ["test", "--show-code-coverage-path"] {
                return StubProcessRunner.success(coveragePath.path + "\n")
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
        #expect(coverageOutput.contains("overall 100.00% (6/6)"))
        #expect(coverageOutput.contains("target SymphonyRuntime 100.00% (4/4)"))
        #expect(coverageOutput.contains("target SymphonyServer 100.00% (2/2)"))
        #expect(runner.startedDetachedExecutions.isEmpty)
        #expect(signals.values.isEmpty)

        let failingRunner = RoutedProcessRunner { command, arguments, _, _, _ in
            if command == "swift", arguments == ["build", "--product", "SymphonyServer"] {
                return StubProcessRunner.failure("build failed")
            }
            if command == "swift", arguments == ["test", "--filter", "SymphonyServerTests"] {
                return StubProcessRunner.failure("test failed")
            }
            if command == "swift", arguments == ["test", "--enable-code-coverage", "--filter", "SymphonyServerTests"] {
                return StubProcessRunner.failure("coverage failed")
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
            #expect(error.message.contains("swift build failed"))
        }

        do {
            _ = try failingTool.test(
                TestCommandRequest(product: .server, scheme: nil, platform: nil, simulator: nil, workerID: 0, dryRun: false, onlyTesting: [], skipTesting: [], outputMode: .filtered, currentDirectory: repoRoot)
            )
            Issue.record("Expected failing tests to surface.")
        } catch let error as SymphonyBuildCommandFailure {
            #expect(error.message.contains("swift test failed"))
        }

        do {
            _ = try failingTool.coverage(
                CoverageCommandRequest(product: .server, scheme: nil, platform: nil, simulator: nil, workerID: 0, dryRun: false, onlyTesting: [], skipTesting: [], json: false, showFiles: false, includeTestTargets: false, outputMode: .filtered, currentDirectory: repoRoot)
            )
            Issue.record("Expected failing coverage builds to surface.")
        } catch let error as SymphonyBuildCommandFailure {
            #expect(error.message.contains("swift test with code coverage failed."))
        }

        let exportFailRunner = RoutedProcessRunner { command, arguments, _, _, _ in
            if command == "swift", arguments == ["test", "--enable-code-coverage", "--filter", "SymphonyServerTests"] {
                return StubProcessRunner.success("ok")
            }
            if command == "swift", arguments == ["test", "--show-code-coverage-path"] {
                return StubProcessRunner.success(repoRoot.appendingPathComponent("missing-coverage.json").path + "\n")
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

@Test func buildToolCoversClientXcodeBuildTestAndCoveragePaths() throws {
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
        let coverageJSON = #"""
        {
          "targets": [
            {
              "buildProductPath": "/tmp/Symphony.app",
              "coveredLines": 3,
              "executableLines": 4,
              "files": [
                { "coveredLines": 2, "executableLines": 2, "name": "ContentView.swift", "path": "/tmp/ContentView.swift" },
                { "coveredLines": 1, "executableLines": 2, "name": "SymphonyApp.swift", "path": "/tmp/SymphonyApp.swift" }
              ],
              "name": "Symphony"
            }
          ]
        }
        """#

        let runner = RoutedProcessRunner { command, arguments, _, _, _ in
            if command == "xcodebuild", arguments.last == "build-for-testing" {
                return StubProcessRunner.success("build-for-testing ok")
            }
            if command == "xcodebuild", arguments.last == "test", !arguments.contains("-enableCodeCoverage"), !arguments.contains("YES") {
                return StubProcessRunner.success("test ok")
            }
            if command == "xcodebuild", arguments.last == "test", arguments.contains("-enableCodeCoverage"), arguments.contains("YES") {
                return StubProcessRunner.success("coverage ok")
            }
            if command == "xcrun", arguments.prefix(4) == ["xccov", "view", "--report", "--json"] {
                return StubProcessRunner.success(coverageJSON)
            }
            return StubProcessRunner.success()
        }

        let tool = SymphonyBuildTool(
            workspaceDiscovery: StubWorkspaceDiscovery(workspace: workspace),
            executionContextBuilder: ExecutionContextBuilder(),
            simulatorResolver: SimulatorResolver(catalog: StubSimulatorCatalog(devices: devices), processRunner: runner),
            processRunner: runner,
            artifactManager: ArtifactManager(processRunner: runner),
            endpointOverrideStore: EndpointOverrideStore(),
            doctorService: StubDoctorService(report: DiagnosticsReport(issues: [], checkedPaths: [], checkedExecutables: []), rendered: "ok"),
            productLocator: ProductLocator(processRunner: runner),
            commitHarness: CommitHarness(processRunner: runner),
            gitHookInstaller: GitHookInstaller(processRunner: runner),
            statusSink: { _ in }
        )

        let dryRunBuild = try tool.build(
            BuildCommandRequest(
                product: .client,
                scheme: nil,
                platform: nil,
                simulator: "iPhone 17",
                workerID: 0,
                dryRun: true,
                buildForTesting: false,
                outputMode: .filtered,
                currentDirectory: repoRoot
            )
        )
        #expect(dryRunBuild.contains("xcodebuild"))
        #expect(dryRunBuild.contains("-scheme Symphony"))
        #expect(dryRunBuild.contains("platform=iOS Simulator,id=AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"))

        let dryRunTest = try tool.test(
            TestCommandRequest(
                product: .client,
                scheme: nil,
                platform: nil,
                simulator: "iPhone 17",
                workerID: 0,
                dryRun: true,
                onlyTesting: ["SymphonyTests/BootstrapSupportTests"],
                skipTesting: ["SymphonyTests/OtherTests"],
                outputMode: .filtered,
                currentDirectory: repoRoot
            )
        )
        #expect(dryRunTest.contains("-only-testing:SymphonyTests/BootstrapSupportTests"))
        #expect(dryRunTest.contains("-skip-testing:SymphonyTests/OtherTests"))

        let dryRunCoverage = try tool.coverage(
            CoverageCommandRequest(
                product: .client,
                scheme: nil,
                platform: nil,
                simulator: "iPhone 17",
                workerID: 0,
                dryRun: true,
                onlyTesting: [],
                skipTesting: [],
                json: false,
                showFiles: false,
                includeTestTargets: false,
                outputMode: .filtered,
                currentDirectory: repoRoot
            )
        )
        #expect(dryRunCoverage.contains("xcodebuild"))
        #expect(dryRunCoverage.contains("xcrun xccov view --report --json"))

        let macOSDryRun = try tool.run(
            RunCommandRequest(
                product: .client,
                scheme: nil,
                platform: .macos,
                simulator: nil,
                workerID: 0,
                dryRun: true,
                serverURL: nil,
                host: nil,
                port: nil,
                environment: [:],
                outputMode: .filtered,
                currentDirectory: repoRoot
            )
        )
        #expect(macOSDryRun.split(separator: "\n").count == 1)
        #expect(macOSDryRun.contains("platform=macOS"))

        let buildOutput = try tool.build(
            BuildCommandRequest(
                product: .client,
                scheme: nil,
                platform: nil,
                simulator: "iPhone 17",
                workerID: 0,
                dryRun: false,
                buildForTesting: true,
                outputMode: .quiet,
                currentDirectory: repoRoot
            )
        )
        #expect(buildOutput.hasSuffix("summary.txt"))

        let testOutput = try tool.test(
            TestCommandRequest(
                product: .client,
                scheme: nil,
                platform: nil,
                simulator: "iPhone 17",
                workerID: 0,
                dryRun: false,
                onlyTesting: [],
                skipTesting: [],
                outputMode: .quiet,
                currentDirectory: repoRoot
            )
        )
        #expect(testOutput.hasSuffix("summary.txt"))

        let coverageOutput = try tool.coverage(
            CoverageCommandRequest(
                product: .client,
                scheme: nil,
                platform: nil,
                simulator: "iPhone 17",
                workerID: 0,
                dryRun: false,
                onlyTesting: [],
                skipTesting: [],
                json: true,
                showFiles: true,
                includeTestTargets: false,
                outputMode: .quiet,
                currentDirectory: repoRoot
            )
        )
        #expect(coverageOutput.contains("\"targets\""))
        #expect(coverageOutput.contains("\"Symphony\""))

        let failingRunner = RoutedProcessRunner { command, arguments, _, _, _ in
            if command == "xcodebuild", arguments.last == "build" {
                return StubProcessRunner.failure("client build failed")
            }
            if command == "xcodebuild", arguments.last == "test", !arguments.contains("-enableCodeCoverage"), !arguments.contains("YES") {
                return StubProcessRunner.failure("client test failed")
            }
            if command == "xcodebuild", arguments.last == "test", arguments.contains("-enableCodeCoverage"), arguments.contains("YES") {
                return StubProcessRunner.failure("client coverage failed")
            }
            return StubProcessRunner.success()
        }
        let failingTool = SymphonyBuildTool(
            workspaceDiscovery: StubWorkspaceDiscovery(workspace: workspace),
            executionContextBuilder: ExecutionContextBuilder(),
            simulatorResolver: SimulatorResolver(catalog: StubSimulatorCatalog(devices: devices), processRunner: failingRunner),
            processRunner: failingRunner,
            artifactManager: ArtifactManager(processRunner: failingRunner),
            endpointOverrideStore: EndpointOverrideStore(),
            doctorService: StubDoctorService(report: DiagnosticsReport(issues: [], checkedPaths: [], checkedExecutables: []), rendered: "ok"),
            productLocator: ProductLocator(processRunner: failingRunner),
            commitHarness: CommitHarness(processRunner: failingRunner),
            gitHookInstaller: GitHookInstaller(processRunner: failingRunner),
            statusSink: { _ in }
        )

        do {
            _ = try failingTool.build(
                BuildCommandRequest(product: .client, scheme: nil, platform: nil, simulator: "iPhone 17", workerID: 0, dryRun: false, buildForTesting: false, outputMode: .filtered, currentDirectory: repoRoot)
            )
            Issue.record("Expected client xcodebuild failures to surface.")
        } catch let error as SymphonyBuildCommandFailure {
            #expect(error.message == "xcodebuild build failed.")
        }

        do {
            _ = try failingTool.test(
                TestCommandRequest(product: .client, scheme: nil, platform: nil, simulator: "iPhone 17", workerID: 0, dryRun: false, onlyTesting: [], skipTesting: [], outputMode: .filtered, currentDirectory: repoRoot)
            )
            Issue.record("Expected client xcodebuild test failures to surface.")
        } catch let error as SymphonyBuildCommandFailure {
            #expect(error.message == "xcodebuild test failed.")
        }

        do {
            _ = try failingTool.coverage(
                CoverageCommandRequest(product: .client, scheme: nil, platform: nil, simulator: "iPhone 17", workerID: 0, dryRun: false, onlyTesting: [], skipTesting: [], json: false, showFiles: false, includeTestTargets: false, outputMode: .filtered, currentDirectory: repoRoot)
            )
            Issue.record("Expected client xcode coverage failures to surface.")
        } catch let error as SymphonyBuildCommandFailure {
            #expect(error.message == "xcodebuild test with code coverage failed.")
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
        let runner = RoutedProcessRunner { command, arguments, _, _, _ in
            if command == "swift", arguments == ["build", "--product", "SymphonyServer"] {
                return StubProcessRunner.success("built")
            }
            if command == "swift", arguments == ["build", "--show-bin-path"] {
                return StubProcessRunner.success("/tmp/Build\n")
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
        #expect(runner.startedDetachedExecutions[0].executablePath == "/tmp/Build/SymphonyServer")
        #expect(runner.startedDetachedExecutions[0].environment == ["CUSTOM": "1"])
        let serverSummary = try String(contentsOf: URL(fileURLWithPath: serverOutput), encoding: .utf8)
        #expect(serverSummary.contains("swift build --product SymphonyServer"))
        #expect(serverSummary.contains("swift build --show-bin-path"))

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
        let devices = [
            SimulatorDevice(name: "iPhone 17", udid: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", state: "Shutdown", runtime: "iOS 18")
        ]

        let defaultSinkCoverageRunner = RoutedProcessRunner { command, arguments, _, _, observation in
            if command == "xcodebuild", arguments.last == "test", arguments.contains("-enableCodeCoverage"), arguments.contains("YES") {
                observation?.onLine?(.stdout, "warning: default sink covered")
                return StubProcessRunner.success("coverage ok")
            }
            if command == "xcrun", arguments.prefix(4) == ["xccov", "view", "--report", "--json"] {
                return StubProcessRunner.success("not json")
            }
            return StubProcessRunner.success()
        }
        let defaultSinkTool = SymphonyBuildTool(
            workspaceDiscovery: StubWorkspaceDiscovery(workspace: workspace),
            executionContextBuilder: ExecutionContextBuilder(),
            simulatorResolver: SimulatorResolver(catalog: StubSimulatorCatalog(devices: devices), processRunner: defaultSinkCoverageRunner),
            processRunner: defaultSinkCoverageRunner,
            artifactManager: ArtifactManager(processRunner: defaultSinkCoverageRunner),
            endpointOverrideStore: EndpointOverrideStore(),
            doctorService: StubDoctorService(report: DiagnosticsReport(issues: [], checkedPaths: [], checkedExecutables: []), rendered: "ok"),
            productLocator: ProductLocator(processRunner: defaultSinkCoverageRunner),
            commitHarness: CommitHarness(processRunner: defaultSinkCoverageRunner),
            gitHookInstaller: GitHookInstaller(processRunner: defaultSinkCoverageRunner)
        )
        do {
            _ = try defaultSinkTool.coverage(
                CoverageCommandRequest(product: .client, scheme: nil, platform: nil, simulator: "iPhone 17", workerID: 0, dryRun: false, onlyTesting: [], skipTesting: [], json: false, showFiles: false, includeTestTargets: false, outputMode: .full, currentDirectory: repoRoot)
            )
            Issue.record("Expected xccov decode failures to surface with the default status sink.")
        } catch let error as SymphonyBuildCommandFailure {
            #expect(error.message == "Coverage export failed.")
        }

        let runBuildFailRunner = RoutedProcessRunner { command, arguments, _, _, _ in
            if command == "swift", arguments == ["build", "--product", "SymphonyServer"] {
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

        let clientRunBuildFailRunner = RoutedProcessRunner { command, arguments, _, _, _ in
            if command == "xcodebuild", arguments.last == "build" {
                return StubProcessRunner.failure("client run build failed")
            }
            return StubProcessRunner.success()
        }
        let clientRunBuildFailTool = SymphonyBuildTool(
            workspaceDiscovery: StubWorkspaceDiscovery(workspace: workspace),
            executionContextBuilder: ExecutionContextBuilder(),
            simulatorResolver: SimulatorResolver(catalog: StubSimulatorCatalog(devices: devices), processRunner: clientRunBuildFailRunner),
            processRunner: clientRunBuildFailRunner,
            artifactManager: ArtifactManager(processRunner: clientRunBuildFailRunner),
            endpointOverrideStore: EndpointOverrideStore(),
            doctorService: StubDoctorService(report: DiagnosticsReport(issues: [], checkedPaths: [], checkedExecutables: []), rendered: "ok"),
            productLocator: ProductLocator(processRunner: clientRunBuildFailRunner),
            commitHarness: CommitHarness(processRunner: clientRunBuildFailRunner),
            gitHookInstaller: GitHookInstaller(processRunner: clientRunBuildFailRunner),
            statusSink: { _ in }
        )
        do {
            _ = try clientRunBuildFailTool.run(
                RunCommandRequest(product: .client, scheme: nil, platform: nil, simulator: "iPhone 17", workerID: 0, dryRun: false, serverURL: nil, host: nil, port: nil, environment: [:], outputMode: .filtered, currentDirectory: repoRoot)
            )
            Issue.record("Expected client run build failures to surface.")
        } catch let error as SymphonyBuildCommandFailure {
            #expect(error.message == "The run build step failed.")
        }

        let noExecutableRunner = RoutedProcessRunner { command, arguments, _, _, _ in
            if command == "swift", arguments == ["build", "--product", "SymphonyServer"] {
                return StubProcessRunner.success("built")
            }
            if command == "swift", arguments == ["build", "--show-bin-path"] {
                return StubProcessRunner.success("/tmp/Build\n")
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

@Test func buildToolCoversSwiftPMCoverageAndRunFallbackFailures() throws {
    try withTemporaryRepositoryFixture { repoRoot in
        let workspace = WorkspaceContext(
            projectRoot: repoRoot,
            buildStateRoot: repoRoot.appendingPathComponent(".build/symphony-build", isDirectory: true),
            xcodeWorkspacePath: repoRoot.appendingPathComponent("Symphony.xcworkspace"),
            xcodeProjectPath: nil
        )

        let dryRunTool = SymphonyBuildTool(
            workspaceDiscovery: StubWorkspaceDiscovery(workspace: workspace),
            executionContextBuilder: ExecutionContextBuilder(),
            simulatorResolver: SimulatorResolver(catalog: StubSimulatorCatalog(devices: []), processRunner: StubProcessRunner()),
            processRunner: StubProcessRunner(),
            artifactManager: ArtifactManager(processRunner: StubProcessRunner()),
            endpointOverrideStore: EndpointOverrideStore(),
            doctorService: StubDoctorService(report: DiagnosticsReport(issues: [], checkedPaths: [], checkedExecutables: []), rendered: "ok"),
            productLocator: ProductLocator(processRunner: StubProcessRunner()),
            commitHarness: CommitHarness(processRunner: StubProcessRunner()),
            gitHookInstaller: GitHookInstaller(processRunner: StubProcessRunner()),
            statusSink: { _ in }
        )
        let runDryRun = try dryRunTool.run(
            RunCommandRequest(
                product: .server,
                scheme: nil,
                platform: nil,
                simulator: nil,
                workerID: 0,
                dryRun: true,
                serverURL: nil,
                host: nil,
                port: nil,
                environment: [:],
                outputMode: .filtered,
                currentDirectory: repoRoot
            )
        )
        #expect(runDryRun.contains("swift build --product SymphonyServer"))
        #expect(runDryRun.contains("swift build --show-bin-path"))
        #expect(runDryRun.contains("<built-product>/SymphonyServer"))

        let pathFailureRunner = RoutedProcessRunner { command, arguments, _, _, _ in
            if command == "swift", arguments == ["test", "--enable-code-coverage", "--filter", "SymphonyServerTests"] {
                return StubProcessRunner.success("coverage ok")
            }
            if command == "swift", arguments == ["test", "--show-code-coverage-path"] {
                return StubProcessRunner.failure("no swiftpm coverage path")
            }
            return StubProcessRunner.success()
        }
        let pathFailureTool = makeCoverageTool(workspace: workspace, runner: pathFailureRunner, statusSink: { _ in })
        do {
            _ = try pathFailureTool.coverage(
                CoverageCommandRequest(product: .server, scheme: nil, platform: nil, simulator: nil, workerID: 0, dryRun: false, onlyTesting: [], skipTesting: [], json: false, showFiles: false, includeTestTargets: false, outputMode: .filtered, currentDirectory: repoRoot)
            )
            Issue.record("Expected failing SwiftPM coverage-path lookups to surface.")
        } catch let error as SymphonyBuildCommandFailure {
            #expect(error.message == "Coverage export failed.")
        }

        let emptyPathRunner = RoutedProcessRunner { command, arguments, _, _, _ in
            if command == "swift", arguments == ["test", "--enable-code-coverage", "--filter", "SymphonyServerTests"] {
                return StubProcessRunner.success("coverage ok")
            }
            if command == "swift", arguments == ["test", "--show-code-coverage-path"] {
                return StubProcessRunner.success("\n")
            }
            return StubProcessRunner.success()
        }
        let emptyPathTool = makeCoverageTool(workspace: workspace, runner: emptyPathRunner, statusSink: { _ in })
        do {
            _ = try emptyPathTool.coverage(
                CoverageCommandRequest(product: .server, scheme: nil, platform: nil, simulator: nil, workerID: 0, dryRun: false, onlyTesting: [], skipTesting: [], json: false, showFiles: false, includeTestTargets: false, outputMode: .filtered, currentDirectory: repoRoot)
            )
            Issue.record("Expected empty SwiftPM coverage paths to surface.")
        } catch let error as SymphonyBuildCommandFailure {
            #expect(error.message == "Coverage export failed.")
        }

        let throwingCoverageRunner = RoutedProcessRunner { command, arguments, _, _, _ in
            if command == "swift", arguments == ["test", "--enable-code-coverage", "--filter", "SymphonyServerTests"] {
                return StubProcessRunner.success("coverage ok")
            }
            if command == "swift", arguments == ["test", "--show-code-coverage-path"] {
                struct GenericFailure: Error {}
                throw GenericFailure()
            }
            return StubProcessRunner.success()
        }
        let throwingCoverageTool = makeCoverageTool(workspace: workspace, runner: throwingCoverageRunner, statusSink: { _ in })
        do {
            _ = try throwingCoverageTool.coverage(
                CoverageCommandRequest(product: .server, scheme: nil, platform: nil, simulator: nil, workerID: 0, dryRun: false, onlyTesting: [], skipTesting: [], json: false, showFiles: false, includeTestTargets: false, outputMode: .filtered, currentDirectory: repoRoot)
            )
            Issue.record("Expected generic SwiftPM coverage export errors to surface.")
        } catch let error as SymphonyBuildCommandFailure {
            #expect(error.message == "Coverage export failed.")
        }

        let binPathFailureRunner = RoutedProcessRunner { command, arguments, _, _, _ in
            if command == "swift", arguments == ["build", "--product", "SymphonyServer"] {
                return StubProcessRunner.success("built")
            }
            if command == "swift", arguments == ["build", "--show-bin-path"] {
                return StubProcessRunner.failure("bin path failed")
            }
            return StubProcessRunner.success()
        }
        let binPathFailureTool = SymphonyBuildTool(
            workspaceDiscovery: StubWorkspaceDiscovery(workspace: workspace),
            executionContextBuilder: ExecutionContextBuilder(),
            simulatorResolver: SimulatorResolver(catalog: StubSimulatorCatalog(devices: []), processRunner: binPathFailureRunner),
            processRunner: binPathFailureRunner,
            artifactManager: ArtifactManager(processRunner: binPathFailureRunner),
            endpointOverrideStore: EndpointOverrideStore(),
            doctorService: StubDoctorService(report: DiagnosticsReport(issues: [], checkedPaths: [], checkedExecutables: []), rendered: "ok"),
            productLocator: ProductLocator(processRunner: binPathFailureRunner),
            commitHarness: CommitHarness(processRunner: binPathFailureRunner),
            gitHookInstaller: GitHookInstaller(processRunner: binPathFailureRunner),
            statusSink: { _ in }
        )
        do {
            _ = try binPathFailureTool.run(
                RunCommandRequest(product: .server, scheme: nil, platform: nil, simulator: nil, workerID: 0, dryRun: false, serverURL: nil, host: nil, port: nil, environment: [:], outputMode: .filtered, currentDirectory: repoRoot)
            )
            Issue.record("Expected failing bin-path lookups to fail launch.")
        } catch let error as SymphonyBuildCommandFailure {
            #expect(error.message == "The launch step failed.")
        }

        let emptyBinPathRunner = RoutedProcessRunner { command, arguments, _, _, _ in
            if command == "swift", arguments == ["build", "--product", "SymphonyServer"] {
                return StubProcessRunner.success("built")
            }
            if command == "swift", arguments == ["build", "--show-bin-path"] {
                return StubProcessRunner.success("\n")
            }
            return StubProcessRunner.success()
        }
        let emptyBinPathTool = SymphonyBuildTool(
            workspaceDiscovery: StubWorkspaceDiscovery(workspace: workspace),
            executionContextBuilder: ExecutionContextBuilder(),
            simulatorResolver: SimulatorResolver(catalog: StubSimulatorCatalog(devices: []), processRunner: emptyBinPathRunner),
            processRunner: emptyBinPathRunner,
            artifactManager: ArtifactManager(processRunner: emptyBinPathRunner),
            endpointOverrideStore: EndpointOverrideStore(),
            doctorService: StubDoctorService(report: DiagnosticsReport(issues: [], checkedPaths: [], checkedExecutables: []), rendered: "ok"),
            productLocator: ProductLocator(processRunner: emptyBinPathRunner),
            commitHarness: CommitHarness(processRunner: emptyBinPathRunner),
            gitHookInstaller: GitHookInstaller(processRunner: emptyBinPathRunner),
            statusSink: { _ in }
        )
        do {
            _ = try emptyBinPathTool.run(
                RunCommandRequest(product: .server, scheme: nil, platform: nil, simulator: nil, workerID: 0, dryRun: false, serverURL: nil, host: nil, port: nil, environment: [:], outputMode: .filtered, currentDirectory: repoRoot)
            )
            Issue.record("Expected empty bin-path responses to fail launch.")
        } catch let error as SymphonyBuildCommandFailure {
            #expect(error.message == "The launch step failed.")
        }
    }
}

@Test func buildToolCoversRemainingClientEdgeCasesAndFallbackMessages() throws {
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

        let buildForTestingFailRunner = RoutedProcessRunner { command, arguments, _, _, _ in
            if command == "xcodebuild", arguments.last == "build-for-testing" {
                return CommandResult(exitStatus: 1, stdout: "", stderr: "")
            }
            return StubProcessRunner.success()
        }
        let buildForTestingFailTool = SymphonyBuildTool(
            workspaceDiscovery: StubWorkspaceDiscovery(workspace: workspace),
            executionContextBuilder: ExecutionContextBuilder(),
            simulatorResolver: SimulatorResolver(catalog: StubSimulatorCatalog(devices: devices), processRunner: buildForTestingFailRunner),
            processRunner: buildForTestingFailRunner,
            artifactManager: ArtifactManager(processRunner: buildForTestingFailRunner),
            endpointOverrideStore: EndpointOverrideStore(),
            doctorService: StubDoctorService(report: DiagnosticsReport(issues: [], checkedPaths: [], checkedExecutables: []), rendered: "ok"),
            productLocator: ProductLocator(processRunner: buildForTestingFailRunner),
            commitHarness: CommitHarness(processRunner: buildForTestingFailRunner),
            gitHookInstaller: GitHookInstaller(processRunner: buildForTestingFailRunner),
            statusSink: { _ in }
        )
        do {
            _ = try buildForTestingFailTool.build(
                BuildCommandRequest(product: .client, scheme: nil, platform: nil, simulator: "iPhone 17", workerID: 0, dryRun: false, buildForTesting: true, outputMode: .filtered, currentDirectory: repoRoot)
            )
            Issue.record("Expected build-for-testing failures to keep their specific error message.")
        } catch let error as SymphonyBuildCommandFailure {
            #expect(error.message == "xcodebuild build-for-testing failed.")
        }

        let genericCoverageRunner = RoutedProcessRunner { command, arguments, _, _, _ in
            if command == "xcodebuild", arguments.last == "test", arguments.contains("-enableCodeCoverage"), arguments.contains("YES") {
                return StubProcessRunner.success("coverage ok")
            }
            if command == "xcrun", arguments.prefix(4) == ["xccov", "view", "--report", "--json"] {
                struct GenericCoverageFailure: Error {}
                throw GenericCoverageFailure()
            }
            return StubProcessRunner.success()
        }
        let genericCoverageTool = SymphonyBuildTool(
            workspaceDiscovery: StubWorkspaceDiscovery(workspace: workspace),
            executionContextBuilder: ExecutionContextBuilder(),
            simulatorResolver: SimulatorResolver(catalog: StubSimulatorCatalog(devices: devices), processRunner: genericCoverageRunner),
            processRunner: genericCoverageRunner,
            artifactManager: ArtifactManager(processRunner: genericCoverageRunner),
            endpointOverrideStore: EndpointOverrideStore(),
            doctorService: StubDoctorService(report: DiagnosticsReport(issues: [], checkedPaths: [], checkedExecutables: []), rendered: "ok"),
            productLocator: ProductLocator(processRunner: genericCoverageRunner),
            commitHarness: CommitHarness(processRunner: genericCoverageRunner),
            gitHookInstaller: GitHookInstaller(processRunner: genericCoverageRunner),
            statusSink: { _ in }
        )
        do {
            _ = try genericCoverageTool.coverage(
                CoverageCommandRequest(product: .client, scheme: nil, platform: nil, simulator: "iPhone 17", workerID: 0, dryRun: false, onlyTesting: [], skipTesting: [], json: false, showFiles: false, includeTestTargets: false, outputMode: .filtered, currentDirectory: repoRoot)
            )
            Issue.record("Expected generic xccov export errors to surface as coverage export failures.")
        } catch let error as SymphonyBuildCommandFailure {
            #expect(error.message == "Coverage export failed.")
        }

        let emptyInstallOutputRunner = RoutedProcessRunner { command, arguments, _, _, _ in
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
                return CommandResult(exitStatus: 1, stdout: "", stderr: "")
            }
            return StubProcessRunner.success()
        }
        let emptyInstallOutputTool = SymphonyBuildTool(
            workspaceDiscovery: StubWorkspaceDiscovery(workspace: workspace),
            executionContextBuilder: ExecutionContextBuilder(),
            simulatorResolver: SimulatorResolver(catalog: StubSimulatorCatalog(devices: devices), processRunner: emptyInstallOutputRunner),
            processRunner: emptyInstallOutputRunner,
            artifactManager: ArtifactManager(processRunner: emptyInstallOutputRunner),
            endpointOverrideStore: EndpointOverrideStore(),
            doctorService: StubDoctorService(report: DiagnosticsReport(issues: [], checkedPaths: [], checkedExecutables: []), rendered: "ok"),
            productLocator: ProductLocator(processRunner: emptyInstallOutputRunner),
            commitHarness: CommitHarness(processRunner: emptyInstallOutputRunner),
            gitHookInstaller: GitHookInstaller(processRunner: emptyInstallOutputRunner),
            statusSink: { _ in }
        )
        do {
            _ = try emptyInstallOutputTool.run(
                RunCommandRequest(product: .client, scheme: nil, platform: nil, simulator: "iPhone 17", workerID: 0, dryRun: false, serverURL: nil, host: nil, port: nil, environment: [:], outputMode: .filtered, currentDirectory: repoRoot)
            )
            Issue.record("Expected empty install failures to use the fallback simulator install message.")
        } catch let error as SymphonyBuildCommandFailure {
            #expect(error.message == "The launch step failed.")
        }

        let emptyLaunchOutputRunner = RoutedProcessRunner { command, arguments, _, _, _ in
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
                return CommandResult(exitStatus: 1, stdout: "", stderr: "")
            }
            return StubProcessRunner.success()
        }
        let emptyLaunchOutputTool = SymphonyBuildTool(
            workspaceDiscovery: StubWorkspaceDiscovery(workspace: workspace),
            executionContextBuilder: ExecutionContextBuilder(),
            simulatorResolver: SimulatorResolver(catalog: StubSimulatorCatalog(devices: devices), processRunner: emptyLaunchOutputRunner),
            processRunner: emptyLaunchOutputRunner,
            artifactManager: ArtifactManager(processRunner: emptyLaunchOutputRunner),
            endpointOverrideStore: EndpointOverrideStore(),
            doctorService: StubDoctorService(report: DiagnosticsReport(issues: [], checkedPaths: [], checkedExecutables: []), rendered: "ok"),
            productLocator: ProductLocator(processRunner: emptyLaunchOutputRunner),
            commitHarness: CommitHarness(processRunner: emptyLaunchOutputRunner),
            gitHookInstaller: GitHookInstaller(processRunner: emptyLaunchOutputRunner),
            statusSink: { _ in }
        )
        do {
            _ = try emptyLaunchOutputTool.run(
                RunCommandRequest(product: .client, scheme: nil, platform: nil, simulator: "iPhone 17", workerID: 0, dryRun: false, serverURL: nil, host: nil, port: nil, environment: [:], outputMode: .filtered, currentDirectory: repoRoot)
            )
            Issue.record("Expected empty launch failures to use the fallback simulator launch message.")
        } catch let error as SymphonyBuildCommandFailure {
            #expect(error.message == "The launch step failed.")
        }

        let missingUDIDRunner = RoutedProcessRunner { command, arguments, _, _, _ in
            if command == "xcodebuild", arguments.last == "build" {
                return StubProcessRunner.success("built")
            }
            if ([command] + arguments).joined(separator: " ").contains("-showBuildSettings") {
                return StubProcessRunner.success(#"[{"buildSettings":{"TARGET_BUILD_DIR":"/tmp/Build","FULL_PRODUCT_NAME":"Symphony.app","PRODUCT_BUNDLE_IDENTIFIER":"com.example.client"}}]"#)
            }
            return StubProcessRunner.success()
        }
        let missingUDIDTool = SymphonyBuildTool(
            workspaceDiscovery: StubWorkspaceDiscovery(workspace: workspace),
            executionContextBuilder: ExecutionContextBuilder(),
            simulatorResolver: SimulatorResolver(catalog: StubSimulatorCatalog(devices: devices), processRunner: missingUDIDRunner),
            processRunner: missingUDIDRunner,
            artifactManager: ArtifactManager(processRunner: missingUDIDRunner),
            endpointOverrideStore: EndpointOverrideStore(),
            doctorService: StubDoctorService(report: DiagnosticsReport(issues: [], checkedPaths: [], checkedExecutables: []), rendered: "ok"),
            productLocator: ProductLocator(processRunner: missingUDIDRunner),
            commitHarness: CommitHarness(processRunner: missingUDIDRunner),
            gitHookInstaller: GitHookInstaller(processRunner: missingUDIDRunner),
            statusSink: { _ in }
        )
        do {
            _ = try missingUDIDTool.run(
                RunCommandRequest(product: .client, scheme: nil, platform: .macos, simulator: nil, workerID: 0, dryRun: false, serverURL: nil, host: nil, port: nil, environment: [:], outputMode: .filtered, currentDirectory: repoRoot)
            )
            Issue.record("Expected non-simulator client launches to fail with missing launch metadata.")
        } catch let error as SymphonyBuildError {
            #expect(error.code == "missing_launch_metadata")
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
