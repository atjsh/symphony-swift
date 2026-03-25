import Foundation
import Testing
@testable import SymphonyBuildCore
import SymphonyShared

@Test func buildModelsExposeExpectedDefaultsAndComputedValues() throws {
    #expect(BuildCommandFamily.allCases == [.build, .test, .run, .harness])
    #expect(ProductKind.server.defaultBackend == .swiftPM)
    #expect(ProductKind.client.defaultBackend == .xcode)
    #expect(ProductKind.server.defaultScheme == "SymphonyServer")
    #expect(ProductKind.client.defaultScheme == "Symphony")
    #expect(ProductKind.server.defaultSwiftPMProduct == "SymphonyServer")
    #expect(ProductKind.client.defaultSwiftPMProduct == nil)
    #expect(ProductKind.server.defaultSwiftPMTestFilter == "SymphonyServerTests")
    #expect(ProductKind.client.defaultSwiftPMTestFilter == nil)
    #expect(ProductKind.server.defaultPlatform == .macos)
    #expect(ProductKind.client.defaultPlatform == .iosSimulator)

    #expect(PlatformKind.macos.xcodeDestinationPlatform == "macOS")
    #expect(PlatformKind.iosSimulator.xcodeDestinationPlatform == "iOS Simulator")

    #expect(XcodeAction.build.xcodebuildAction == "build")
    #expect(XcodeAction.buildForTesting.xcodebuildAction == "build-for-testing")
    #expect(XcodeAction.test.xcodebuildAction == "test")
    #expect(XcodeAction.launch.xcodebuildAction == nil)

    do {
        _ = try WorkerScope(id: -1)
        Issue.record("Expected a negative worker id to fail.")
    } catch let error as SymphonyBuildError {
        #expect(error.code == "invalid_worker_id")
    }

    let worker = try WorkerScope(id: 4)
    #expect(worker.slug == "worker-4")

    let selector = SchemeSelector(product: .client, scheme: "My Fancy Scheme", platform: .macos)
    #expect(selector.product == .client)
    #expect(selector.scheme == "My Fancy Scheme")
    #expect(selector.platform == .macos)
    #expect(selector.runIdentifier == "my-fancy-scheme")

    let defaultSelector = SchemeSelector(product: .server, scheme: nil, platform: nil)
    #expect(defaultSelector.scheme == "SymphonyServer")
    #expect(defaultSelector.platform == .macos)
    #expect(defaultSelector.runIdentifier == "symphonyserver")

    let destinationSelector = DestinationSelector(
        platform: .iosSimulator,
        simulatorName: "iPhone 17",
        simulatorUDID: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
    )
    #expect(destinationSelector.platform == .iosSimulator)
    #expect(destinationSelector.simulatorName == "iPhone 17")
    #expect(destinationSelector.simulatorUDID == "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")

    let destination = ResolvedDestination(
        platform: .macos,
        displayName: "macOS",
        simulatorName: nil,
        simulatorUDID: nil,
        xcodeDestination: expectedHostMacOSDestination()
    )
    let workspacePath = URL(fileURLWithPath: "/tmp/Symphony.xcworkspace")
    let derivedDataPath = URL(fileURLWithPath: "/tmp/DerivedData")
    let resultBundlePath = URL(fileURLWithPath: "/tmp/result.xcresult")

    let workspaceRequest = XcodeCommandRequest(
        action: .buildForTesting,
        scheme: "Symphony",
        destination: destination,
        derivedDataPath: derivedDataPath,
        resultBundlePath: resultBundlePath,
        enableCodeCoverage: true,
        outputMode: .full,
        environment: ["FOO": "bar"],
        workspacePath: workspacePath,
        projectPath: nil,
        onlyTesting: ["Suite/testA"],
        skipTesting: ["Suite/testB"]
    )
    let workspaceArguments = try workspaceRequest.renderedArguments()
    #expect(workspaceArguments.contains("-workspace"))
    #expect(workspaceArguments.contains(workspacePath.path))
    #expect(workspaceArguments.contains("-enableCodeCoverage"))
    #expect(workspaceArguments.contains("YES"))
    #expect(workspaceArguments.contains("-only-testing:Suite/testA"))
    #expect(workspaceArguments.contains("-skip-testing:Suite/testB"))
    #expect(workspaceArguments.last == "build-for-testing")
    #expect(try workspaceRequest.renderedCommandLine().contains("xcodebuild"))

    let projectPath = URL(fileURLWithPath: "/tmp/SymphonyApps.xcodeproj")
    let projectRequest = XcodeCommandRequest(
        action: .test,
        scheme: "SymphonyServer",
        destination: destination,
        derivedDataPath: derivedDataPath,
        resultBundlePath: resultBundlePath,
        outputMode: .filtered,
        environment: [:],
        workspacePath: nil,
        projectPath: projectPath
    )
    #expect(try projectRequest.renderedArguments().contains(projectPath.path))

    do {
        _ = try XcodeCommandRequest(
            action: .launch,
            scheme: "Symphony",
            destination: destination,
            derivedDataPath: derivedDataPath,
            resultBundlePath: resultBundlePath,
            outputMode: .quiet,
            environment: [:],
            workspacePath: workspacePath,
            projectPath: nil
        ).renderedArguments()
        Issue.record("Expected launch requests to reject xcodebuild rendering.")
    } catch let error as SymphonyBuildError {
        #expect(error.code == "invalid_xcode_action")
    }

    do {
        _ = try XcodeCommandRequest(
            action: .build,
            scheme: "Symphony",
            destination: destination,
            derivedDataPath: derivedDataPath,
            resultBundlePath: resultBundlePath,
            outputMode: .filtered,
            environment: [:],
            workspacePath: nil,
            projectPath: nil
        ).renderedArguments()
        Issue.record("Expected missing build definitions to fail.")
    } catch let error as SymphonyBuildError {
        #expect(error.code == "missing_build_definition")
    }
}

@Test func buildModelsCoverRuntimeDiagnosticsRequestsAndUtilities() throws {
    let runResult = XcodeRunResult(
        exitStatus: 0,
        invocation: "xcodebuild build",
        startedAt: Date(timeIntervalSince1970: 10),
        endedAt: Date(timeIntervalSince1970: 20),
        resultBundlePath: URL(fileURLWithPath: "/tmp/result.xcresult"),
        logPath: URL(fileURLWithPath: "/tmp/log.txt")
    )
    #expect(runResult.exitStatus == 0)
    #expect(runResult.invocation == "xcodebuild build")

    let coverageFile = CoverageFileReport(name: "Foo.swift", path: "/tmp/Foo.swift", coveredLines: 10, executableLines: 10, lineCoverage: 1)
    let coverageTarget = CoverageTargetReport(name: "Symphony", buildProductPath: "/tmp/Symphony.app", coveredLines: 10, executableLines: 10, lineCoverage: 1, files: [coverageFile])
    let coverageReport = CoverageReport(coveredLines: 10, executableLines: 10, lineCoverage: 1, includeTestTargets: false, excludedTargets: ["SymphonyTests.xctest"], targets: [coverageTarget])
    #expect(coverageReport.targets.first?.files?.first == coverageFile)
    let inspectionFunction = CoverageInspectionFunctionReport(name: "Foo.bar()", coveredLines: 2, executableLines: 3, lineCoverage: 2.0 / 3.0)
    let inspectionFile = CoverageInspectionFileReport(
        targetName: "Symphony",
        path: "/tmp/Foo.swift",
        coveredLines: 8,
        executableLines: 10,
        lineCoverage: 0.8,
        missingLineRanges: [CoverageLineRange(startLine: 10, endLine: 12)],
        functions: [inspectionFunction]
    )
    let inspectionReport = CoverageInspectionReport(
        backend: .swiftPM,
        product: .server,
        generatedAt: "2026-03-25T00:00:00Z",
        files: [inspectionFile]
    )
    let rawReport = CoverageInspectionRawReport(
        backend: .xcode,
        product: .client,
        commands: [
            CoverageInspectionRawCommand(
                commandLine: "xcrun xccov view --archive --file /tmp/Foo.swift /tmp/result.xcresult",
                scope: "missing-lines",
                filePath: "/tmp/Foo.swift",
                format: "text",
                output: "10: 0"
            )
        ]
    )
    #expect(inspectionReport.files.count == 1)
    #expect(rawReport.commands.count == 1)

    let packageFile = PackageCoverageFileReport(path: "Sources/Foo.swift", coveredLines: 5, executableLines: 5, lineCoverage: 1)
    let packageReport = PackageCoverageReport(scope: "first_party_sources", coveredLines: 5, executableLines: 5, lineCoverage: 1, coverageJSONPath: "/tmp/package.json", files: [packageFile])
    let violation = HarnessCoverageViolation(suite: "client", kind: "file", name: "/tmp/Foo.swift", coveredLines: 4, executableLines: 5, lineCoverage: 0.8)
    let harness = HarnessReport(
        minimumCoveragePercent: 100,
        testsInvocation: "swift test --enable-code-coverage",
        coveragePathInvocation: "swift test --show-code-coverage-path",
        packageCoverage: packageReport,
        clientCoverageInvocation: "symphony-build test --product client --json",
        clientCoverage: coverageReport,
        clientCoverageSkipReason: nil,
        serverCoverageInvocation: "symphony-build test --product server --json",
        serverCoverage: coverageReport,
        packageFileViolations: [violation],
        clientTargetViolations: [],
        clientFileViolations: [],
        serverTargetViolations: [],
        serverFileViolations: []
    )
    #expect(harness.violations == [violation])
    #expect(harness.meetsCoverageThreshold == false)

    let cleanHarness = HarnessReport(
        minimumCoveragePercent: 100,
        testsInvocation: "swift test --enable-code-coverage",
        coveragePathInvocation: "swift test --show-code-coverage-path",
        packageCoverage: packageReport,
        clientCoverageInvocation: "client",
        clientCoverage: coverageReport,
        clientCoverageSkipReason: nil,
        serverCoverageInvocation: "server",
        serverCoverage: coverageReport,
        packageFileViolations: [],
        clientTargetViolations: [],
        clientFileViolations: [],
        serverTargetViolations: [],
        serverFileViolations: []
    )
    #expect(cleanHarness.meetsCoverageThreshold)

    let artifactRun = ArtifactRun(
        command: .run,
        runID: "run-1",
        timestamp: "20260324-100000",
        artifactRoot: URL(fileURLWithPath: "/tmp/artifacts/run-1"),
        summaryPath: URL(fileURLWithPath: "/tmp/artifacts/run-1/summary.txt"),
        indexPath: URL(fileURLWithPath: "/tmp/artifacts/run-1/index.json")
    )
    let anomaly = ArtifactAnomaly(code: "missing_recording", message: "No recording.", phase: "xcresult")
    let entry = ArtifactIndexEntry(name: "recording.mp4", relativePath: "recording.mp4", kind: "missing", createdAt: "2026-03-24T00:00:00Z", anomaly: anomaly)
    let index = ArtifactIndex(entries: [entry], command: .run, runID: artifactRun.runID, timestamp: artifactRun.timestamp, anomalies: [anomaly])
    #expect(index.entries.first?.anomaly == anomaly)

    let expectedServerEndpoint = try ServerEndpoint(scheme: "https", host: "example.com", port: 9443)
    let runtimeEndpoint = RuntimeEndpoint(serverEndpoint: expectedServerEndpoint)
    #expect(runtimeEndpoint.url?.absoluteString == "https://example.com:9443")
    #expect(try runtimeEndpoint.serverEndpoint == expectedServerEndpoint)

    let invalidRuntime = try JSONDecoder().decode(RuntimeEndpoint.self, from: Data(#"{"scheme":"","host":"","port":0}"#.utf8))
    #expect(invalidRuntime.url == nil)
    do {
        _ = try invalidRuntime.serverEndpoint
        Issue.record("Expected invalid decoded runtime endpoints to fail validation.")
    } catch let error as SymphonySharedValidationError {
        #expect(error == .invalidServerEndpoint)
    }

    #expect(DiagnosticSeverity.error < .warning)
    #expect(DiagnosticSeverity.warning < .info)

    let diagnostics = DiagnosticsReport(
        issues: [
            DiagnosticIssue(severity: .warning, code: "warning", message: "warning"),
            DiagnosticIssue(severity: .error, code: "error-b", message: "error-b"),
            DiagnosticIssue(severity: .error, code: "error-a", message: "error-a"),
            DiagnosticIssue(severity: .info, code: "info", message: "info"),
        ],
        notes: ["xcode-backed checks were skipped"],
        checkedPaths: ["/tmp/repo"],
        checkedExecutables: ["swift"]
    )
    #expect(diagnostics.issues.map(\.code) == ["error-a", "error-b", "warning", "info"])
    #expect(diagnostics.notes == ["xcode-backed checks were skipped"])
    #expect(diagnostics.isHealthy == false)
    #expect(DiagnosticsReport(issues: [DiagnosticIssue(severity: .warning, code: "warn", message: "warn")], notes: ["note"], checkedPaths: [], checkedExecutables: []).isHealthy)

    let skippedHarness = HarnessReport(
        minimumCoveragePercent: 100,
        testsInvocation: "swift test --enable-code-coverage",
        coveragePathInvocation: "swift test --show-code-coverage-path",
        packageCoverage: packageReport,
        clientCoverageInvocation: nil,
        clientCoverage: nil,
        clientCoverageSkipReason: "not supported because the current environment has no Xcode available; Editing those sources is not encouraged",
        serverCoverageInvocation: "server",
        serverCoverage: coverageReport,
        packageFileViolations: [],
        clientTargetViolations: [],
        clientFileViolations: [],
        serverTargetViolations: [],
        serverFileViolations: []
    )
    #expect(skippedHarness.clientCoverage == nil)
    #expect(skippedHarness.clientCoverageSkipReason?.contains("no Xcode available") == true)
    #expect(skippedHarness.meetsCoverageThreshold)

    let skippedInspection = HarnessCoverageInspectionArtifact(
        suite: "client",
        backend: .xcode,
        generatedAt: "2026-03-25T00:00:00Z",
        files: [],
        skippedReason: "not supported because the current environment has no Xcode available; Editing those sources is not encouraged"
    )
    #expect(try JSONDecoder().decode(HarnessCoverageInspectionArtifact.self, from: JSONEncoder().encode(skippedInspection)) == skippedInspection)

    let directLLVMCovCapabilities = ToolchainCapabilities(
        swiftAvailable: true,
        xcodebuildAvailable: false,
        xcrunAvailable: false,
        simctlAvailable: false,
        xcresulttoolAvailable: false,
        llvmCovCommand: .direct
    )
    #expect(!directLLVMCovCapabilities.supportsXcodeCommands)
    #expect(!directLLVMCovCapabilities.supportsSimulatorCommands)
    #expect(!directLLVMCovCapabilities.supportsXCResultTools)
    #expect(directLLVMCovCapabilities.supportsSwiftPMCoverageInspection)

    let buildRequest = BuildCommandRequest(product: .server, scheme: "Server", platform: .macos, simulator: nil, workerID: 1, dryRun: true, buildForTesting: true, outputMode: .quiet, currentDirectory: URL(fileURLWithPath: "/tmp"))
    let testRequest = TestCommandRequest(product: .client, scheme: "Client", platform: .iosSimulator, simulator: "UDID", workerID: 2, dryRun: false, onlyTesting: ["Suite/test"], skipTesting: ["Suite/skip"], outputMode: .filtered, currentDirectory: URL(fileURLWithPath: "/tmp"))
    let runRequest = RunCommandRequest(product: .server, scheme: "Server", platform: .macos, simulator: nil, workerID: 3, dryRun: false, serverURL: "http://localhost:8080", host: nil, port: nil, environment: ["FOO": "bar"], outputMode: .full, currentDirectory: URL(fileURLWithPath: "/tmp"))
    let harnessRequest = HarnessCommandRequest(minimumCoveragePercent: 100, json: true, currentDirectory: URL(fileURLWithPath: "/tmp"))
    let hooksRequest = HooksInstallRequest(currentDirectory: URL(fileURLWithPath: "/tmp"))
    let artifactsRequest = ArtifactsCommandRequest(command: .harness, latest: false, runID: "run-1", currentDirectory: URL(fileURLWithPath: "/tmp"))
    let doctorRequest = DoctorCommandRequest(strict: true, json: true, quiet: true, currentDirectory: URL(fileURLWithPath: "/tmp"))
    let simSetRequest = SimSetServerRequest(serverURL: nil, scheme: "https", host: "example.com", port: 9443, currentDirectory: URL(fileURLWithPath: "/tmp"))
    let simBootRequest = SimBootRequest(simulator: "AAAA-BBBB", currentDirectory: URL(fileURLWithPath: "/tmp"))
    #expect(buildRequest.buildForTesting)
    #expect(testRequest.skipTesting == ["Suite/skip"])
    #expect(runRequest.environment["FOO"] == "bar")
    #expect(harnessRequest.minimumCoveragePercent == 100)
    #expect(hooksRequest.currentDirectory.path == "/tmp")
    #expect(artifactsRequest.command == .harness)
    #expect(artifactsRequest.runID == "run-1")
    #expect(doctorRequest.strict)
    #expect(simSetRequest.host == "example.com")
    #expect(simBootRequest.simulator == "AAAA-BBBB")
}

@Test func pathUtilitiesHandleQuotingContainmentAndOutOfBoundsExecutionContexts() throws {
    let fileManager = FileManager.default
    try withTemporaryDirectory { directory in
        let nested = directory.appendingPathComponent("nested/path", isDirectory: true)
        try fileManager.ensureDirectory(nested)
        #expect(fileManager.fileExists(atPath: nested.path))
        #expect(fileManager.isContained(nested, within: directory))
        #expect(fileManager.isContained(directory, within: directory))
        #expect(!fileManager.isContained(URL(fileURLWithPath: "/tmp/outside"), within: nested))
    }

    #expect(ShellQuoting.quote("") == "''")
    #expect(ShellQuoting.quote("alpha:/._-=") == "alpha:/._-=")
    #expect(ShellQuoting.quote("needs space") == "'needs space'")
    #expect(ShellQuoting.slugify("Symphony Server! v1") == "symphony-server--v1")

    let workspace = WorkspaceContext(
        projectRoot: URL(fileURLWithPath: "/tmp/repo", isDirectory: true),
        buildStateRoot: URL(fileURLWithPath: "/tmp/repo/.build/symphony-build", isDirectory: true),
        xcodeWorkspacePath: nil,
        xcodeProjectPath: nil
    )
    let context = try ExecutionContextBuilder().make(
        workspace: workspace,
        worker: try WorkerScope(id: 9),
        command: .test,
        runID: "run-1",
        date: Date(timeIntervalSince1970: 1_700_000_000)
    )
    #expect(context.worker.slug == "worker-9")
    #expect(context.runtimeRoot.path.contains("runtime/worker-9"))

    do {
        _ = try ExecutionContextBuilder().make(
            workspace: WorkspaceContext(
                projectRoot: URL(fileURLWithPath: "/tmp/repo", isDirectory: true),
                buildStateRoot: URL(fileURLWithPath: "/tmp/outside", isDirectory: true),
                xcodeWorkspacePath: nil,
                xcodeProjectPath: nil
            ),
            worker: try WorkerScope(id: 0),
            command: .build,
            runID: "run-2",
            date: Date(timeIntervalSince1970: 1_700_000_000)
        )
        Issue.record("Expected out-of-bounds build paths to fail.")
    } catch let error as SymphonyBuildError {
        #expect(error.code == "artifact_root_out_of_bounds")
    }
}
