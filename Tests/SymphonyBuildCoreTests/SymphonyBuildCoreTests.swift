import Foundation
import Testing
@testable import SymphonyBuildCore

@Test func workspaceDiscoveryPrefersWorkspaceOverProject() throws {
    try withTemporaryDirectory { directory in
        let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repoRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: repoRoot.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: repoRoot.appendingPathComponent("Symphony.xcworkspace"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: repoRoot.appendingPathComponent("SymphonyApps.xcodeproj"), withIntermediateDirectories: true)

        let discovered = try WorkspaceDiscovery(processRunner: StubProcessRunner()).discover(from: repoRoot)

        #expect(discovered.projectRoot.path == repoRoot.path)
        #expect(discovered.xcodeWorkspacePath?.lastPathComponent == "Symphony.xcworkspace")
        #expect(discovered.xcodeProjectPath == nil)
    }
}

@Test func workspaceDiscoveryRejectsAmbiguousWorkspaces() throws {
    try withTemporaryDirectory { directory in
        let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repoRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: repoRoot.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: repoRoot.appendingPathComponent("One.xcworkspace"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: repoRoot.appendingPathComponent("Two.xcworkspace"), withIntermediateDirectories: true)

        do {
            _ = try WorkspaceDiscovery(processRunner: StubProcessRunner()).discover(from: repoRoot)
            Issue.record("Expected ambiguous checked-in workspaces to fail discovery.")
        } catch let error as SymphonyBuildError {
            #expect(error.code == "ambiguous_workspace")
        }
    }
}

@Test func executionContextUsesWorkerScopedCanonicalPaths() throws {
    let workspace = WorkspaceContext(
        projectRoot: URL(fileURLWithPath: "/tmp/symphony-tests", isDirectory: true),
        buildStateRoot: URL(fileURLWithPath: "/tmp/symphony-tests/.build/symphony-build", isDirectory: true),
        xcodeWorkspacePath: nil,
        xcodeProjectPath: nil
    )

    let worker = try WorkerScope(id: 7)
    let context = try ExecutionContextBuilder().make(
        workspace: workspace,
        worker: worker,
        command: .build,
        runID: "symphony",
        date: Date(timeIntervalSince1970: 1_700_000_000)
    )

    #expect(context.derivedDataPath.path.contains("derived-data/worker-7"))
    #expect(context.logPath.path.contains("logs/build/"))
    #expect(context.resultBundlePath.path.hasSuffix(".xcresult"))
    #expect(context.artifactRoot.lastPathComponent == "20231114-221320-symphony")
}

@Test func simulatorResolverRejectsDuplicateExactNames() throws {
    let catalog = StubSimulatorCatalog(
        devices: [
            SimulatorDevice(name: "iPhone 17", udid: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", state: "Shutdown", runtime: "iOS 18"),
            SimulatorDevice(name: "iPhone 17", udid: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB", state: "Shutdown", runtime: "iOS 18"),
        ]
    )
    let resolver = SimulatorResolver(catalog: catalog, processRunner: StubProcessRunner())

    do {
        _ = try resolver.resolve(DestinationSelector(platform: .iosSimulator, simulatorName: "iPhone 17"))
        Issue.record("Expected duplicate exact-name simulators to fail.")
    } catch let error as SymphonyBuildError {
        #expect(error.code == "ambiguous_simulator_name")
    }
}

@Test func simulatorResolverSupportsUniqueFuzzyMatchAndExplicitUDID() throws {
    let catalog = StubSimulatorCatalog(
        devices: [
            SimulatorDevice(name: "iPhone 17", udid: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", state: "Shutdown", runtime: "iOS 18"),
            SimulatorDevice(name: "iPhone 17 Pro", udid: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB", state: "Shutdown", runtime: "iOS 18"),
            SimulatorDevice(name: "iPhone 17 Plus", udid: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC", state: "Shutdown", runtime: "iOS 18"),
        ]
    )
    let resolver = SimulatorResolver(catalog: catalog, processRunner: StubProcessRunner())

    let fuzzy = try resolver.resolve(DestinationSelector(platform: .iosSimulator, simulatorName: "plus"))
    #expect(fuzzy.simulatorUDID == "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")

    let explicitUDID = try resolver.resolve(
        DestinationSelector(
            platform: .iosSimulator,
            simulatorName: "iPhone 17",
            simulatorUDID: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"
        )
    )
    #expect(explicitUDID.simulatorUDID == "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")
}

@Test func simulatorResolverUsesHostArchitectureForMacOSDestination() throws {
    let resolver = SimulatorResolver(catalog: StubSimulatorCatalog(devices: []), processRunner: StubProcessRunner())
    let destination = try resolver.resolve(DestinationSelector(platform: .macos))

    #expect(destination.displayName == "macOS")
    #expect(destination.xcodeDestination == expectedHostMacOSDestination())
}

@Test func endpointOverridePrecedenceUsesCLIThenPersistedThenDefault() throws {
    try withTemporaryDirectory { directory in
        let workspace = WorkspaceContext(
            projectRoot: directory,
            buildStateRoot: directory.appendingPathComponent(".build/symphony-build", isDirectory: true),
            xcodeWorkspacePath: nil,
            xcodeProjectPath: nil
        )
        let store = EndpointOverrideStore()
        _ = try store.save(try RuntimeEndpoint(scheme: "https", host: "persisted.example.com", port: 9443), in: workspace)

        let cli = try store.resolve(workspace: workspace, serverURL: "http://cli.example.com:8081", host: "ignored.example.com", port: 1234)
        #expect(cli.host == "cli.example.com")
        #expect(cli.port == 8081)

        let split = try store.resolve(workspace: workspace, serverURL: nil, host: "split.example.com", port: 9090)
        #expect(split.host == "split.example.com")
        #expect(split.port == 9090)
        #expect(split.scheme == "https")

        try store.clear(in: workspace)
        let fallback = try store.resolve(workspace: workspace, serverURL: nil, host: nil, port: nil)
        #expect(fallback.host == "localhost")
        #expect(fallback.port == 8080)
    }
}

@Test func artifactManagerWritesSummaryIndexAndMissingBundleAnomaly() throws {
    try withTemporaryDirectory { directory in
        let workspace = WorkspaceContext(
            projectRoot: directory,
            buildStateRoot: directory.appendingPathComponent(".build/symphony-build", isDirectory: true),
            xcodeWorkspacePath: nil,
            xcodeProjectPath: nil
        )
        let worker = try WorkerScope(id: 0)
        let executionContext = try ExecutionContextBuilder().make(
            workspace: workspace,
            worker: worker,
            command: .build,
            runID: "symphony",
            date: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let manager = ArtifactManager(processRunner: StubProcessRunner())

        let record = try manager.recordXcodeExecution(
            workspace: workspace,
            executionContext: executionContext,
            command: .build,
            product: .client,
            scheme: "Symphony",
            destination: ResolvedDestination(platform: .macos, displayName: "macOS", simulatorName: nil, simulatorUDID: nil, xcodeDestination: "platform=macOS"),
            invocation: "xcodebuild build",
            exitStatus: 1,
            combinedOutput: "build failed",
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: Date(timeIntervalSince1970: 1_700_000_060)
        )

        let summary = try String(contentsOf: record.run.summaryPath, encoding: .utf8)
        #expect(summary.contains("command: build"))
        #expect(summary.contains("anomalies: missing_result_bundle"))

        let indexData = try Data(contentsOf: record.run.indexPath)
        let index = try JSONDecoder().decode(ArtifactIndex.self, from: indexData)
        #expect(index.anomalies.contains(where: { $0.code == "missing_result_bundle" }))
    }
}

@Test func artifactManagerExportsXCResultSummaryUsingLegacyCommand() throws {
    try withTemporaryDirectory { directory in
        let workspace = WorkspaceContext(
            projectRoot: directory,
            buildStateRoot: directory.appendingPathComponent(".build/symphony-build", isDirectory: true),
            xcodeWorkspacePath: nil,
            xcodeProjectPath: nil
        )
        let worker = try WorkerScope(id: 0)
        let executionContext = try ExecutionContextBuilder().make(
            workspace: workspace,
            worker: worker,
            command: .test,
            runID: "symphony",
            date: Date(timeIntervalSince1970: 1_700_000_100)
        )
        try FileManager.default.createDirectory(at: executionContext.resultBundlePath, withIntermediateDirectories: true)

        let runner = StubProcessRunner(results: [
            "xcrun xcresulttool get object --legacy --path \(executionContext.resultBundlePath.path) --format json": StubProcessRunner.success(#"{"kind":"ActionsInvocationRecord"}"#),
            "xcrun xcresulttool export diagnostics --path \(executionContext.resultBundlePath.path) --output-path \(executionContext.artifactRoot.appendingPathComponent("diagnostics").path)": StubProcessRunner.success(),
            "xcrun xcresulttool export attachments --path \(executionContext.resultBundlePath.path) --output-path \(executionContext.artifactRoot.appendingPathComponent("attachments").path)": StubProcessRunner.success(),
        ])
        let manager = ArtifactManager(processRunner: runner)

        let record = try manager.recordXcodeExecution(
            workspace: workspace,
            executionContext: executionContext,
            command: .test,
            product: .server,
            scheme: "SymphonyServer",
            destination: ResolvedDestination(
                platform: .macos,
                displayName: "macOS",
                simulatorName: nil,
                simulatorUDID: nil,
                xcodeDestination: expectedHostMacOSDestination()
            ),
            invocation: "xcodebuild test",
            exitStatus: 0,
            combinedOutput: "tests passed",
            startedAt: Date(timeIntervalSince1970: 1_700_000_100),
            endedAt: Date(timeIntervalSince1970: 1_700_000_140)
        )

        let summaryJSON = try String(contentsOf: record.run.artifactRoot.appendingPathComponent("summary.json"), encoding: .utf8)
        #expect(summaryJSON.contains(#""kind":"ActionsInvocationRecord""#))

        let indexData = try Data(contentsOf: record.run.indexPath)
        let index = try JSONDecoder().decode(ArtifactIndex.self, from: indexData)
        #expect(!index.anomalies.contains(where: { $0.code == "xcresult_summary_export_failed" }))
    }
}

@Test func artifactResolutionAnnotatesMissingEntries() throws {
    try withTemporaryDirectory { directory in
        let workspace = WorkspaceContext(
            projectRoot: directory,
            buildStateRoot: directory.appendingPathComponent(".build/symphony-build", isDirectory: true),
            xcodeWorkspacePath: nil,
            xcodeProjectPath: nil
        )
        let worker = try WorkerScope(id: 0)
        let executionContext = try ExecutionContextBuilder().make(
            workspace: workspace,
            worker: worker,
            command: .build,
            runID: "symphony",
            date: Date(timeIntervalSince1970: 1_700_000_200)
        )
        try FileManager.default.createDirectory(at: executionContext.resultBundlePath, withIntermediateDirectories: true)

        let runner = StubProcessRunner(results: [
            "xcrun xcresulttool get object --legacy --path \(executionContext.resultBundlePath.path) --format json": StubProcessRunner.success(#"{"kind":"ActionsInvocationRecord"}"#),
            "xcrun xcresulttool export diagnostics --path \(executionContext.resultBundlePath.path) --output-path \(executionContext.artifactRoot.appendingPathComponent("diagnostics").path)": StubProcessRunner.success(),
            "xcrun xcresulttool export attachments --path \(executionContext.resultBundlePath.path) --output-path \(executionContext.artifactRoot.appendingPathComponent("attachments").path)": StubProcessRunner.success(),
        ])
        let manager = ArtifactManager(processRunner: runner)

        _ = try manager.recordXcodeExecution(
            workspace: workspace,
            executionContext: executionContext,
            command: .build,
            product: .client,
            scheme: "Symphony",
            destination: ResolvedDestination(
                platform: .iosSimulator,
                displayName: "iPhone 17 (AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA)",
                simulatorName: "iPhone 17",
                simulatorUDID: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
                xcodeDestination: "platform=iOS Simulator,id=AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
            ),
            invocation: "xcodebuild build",
            exitStatus: 0,
            combinedOutput: "build succeeded",
            startedAt: Date(timeIntervalSince1970: 1_700_000_200),
            endedAt: Date(timeIntervalSince1970: 1_700_000_240)
        )

        let rendered = try manager.resolveArtifacts(
            workspace: workspace,
            request: ArtifactsCommandRequest(command: .build, latest: true, runID: nil, currentDirectory: directory)
        )

        #expect(rendered.contains("log.txt \(executionContext.artifactRoot.appendingPathComponent("log.txt").path)"))
        #expect(rendered.contains("recording.mp4 [missing: missing_recording] \(executionContext.artifactRoot.appendingPathComponent("recording.mp4").path)"))
        #expect(rendered.contains("screen.png [missing: missing_screen_capture] \(executionContext.artifactRoot.appendingPathComponent("screen.png").path)"))
        #expect(rendered.contains("ui-tree.txt [missing: missing_ui_tree] \(executionContext.artifactRoot.appendingPathComponent("ui-tree.txt").path)"))
    }
}

@Test func artifactManagerCoversMissingArtifactSelectionsAndOptionalExports() throws {
    try withTemporaryDirectory { directory in
        let workspace = WorkspaceContext(
            projectRoot: directory,
            buildStateRoot: directory.appendingPathComponent(".build/symphony-build", isDirectory: true),
            xcodeWorkspacePath: nil,
            xcodeProjectPath: nil
        )
        let manager = ArtifactManager(processRunner: StubProcessRunner())

        do {
            _ = try manager.resolveArtifacts(
                workspace: workspace,
                request: ArtifactsCommandRequest(command: .build, latest: true, runID: nil, currentDirectory: directory)
            )
            Issue.record("Expected missing latest artifact roots to fail.")
        } catch let error as SymphonyBuildError {
            #expect(error.code == "missing_artifacts")
        }

        let worker = try WorkerScope(id: 1)
        let executionContext = try ExecutionContextBuilder().make(
            workspace: workspace,
            worker: worker,
            command: .test,
            runID: "sample",
            date: Date(timeIntervalSince1970: 1_700_000_400)
        )
        try FileManager.default.createDirectory(at: executionContext.resultBundlePath, withIntermediateDirectories: true)
        let diagnosticsPath = executionContext.artifactRoot.appendingPathComponent("diagnostics", isDirectory: true)
        let attachmentsPath = executionContext.artifactRoot.appendingPathComponent("attachments", isDirectory: true)
        let png = attachmentsPath.appendingPathComponent("capture.png")
        let text = diagnosticsPath.appendingPathComponent("view-hierarchy.txt")

        let runner = StubProcessRunner(results: [
            "xcrun xcresulttool get object --legacy --path \(executionContext.resultBundlePath.path) --format json": StubProcessRunner.failure(""),
            "xcrun xcresulttool export diagnostics --path \(executionContext.resultBundlePath.path) --output-path \(diagnosticsPath.path)": StubProcessRunner.failure(""),
            "xcrun xcresulttool export attachments --path \(executionContext.resultBundlePath.path) --output-path \(attachmentsPath.path)": StubProcessRunner.failure(""),
        ])
        let failingManager = ArtifactManager(processRunner: runner)

        _ = try failingManager.recordXcodeExecution(
            workspace: workspace,
            executionContext: executionContext,
            command: .test,
            product: .server,
            scheme: "SymphonyServer",
            destination: ResolvedDestination(platform: .macos, displayName: "macOS", simulatorName: nil, simulatorUDID: nil, xcodeDestination: expectedHostMacOSDestination()),
            invocation: "xcodebuild test",
            exitStatus: 0,
            combinedOutput: "",
            startedAt: Date(timeIntervalSince1970: 1_700_000_400),
            endedAt: Date(timeIntervalSince1970: 1_700_000_420)
        )

        do {
            _ = try failingManager.resolveArtifacts(
                workspace: workspace,
                request: ArtifactsCommandRequest(command: .test, latest: false, runID: "missing", currentDirectory: directory)
            )
            Issue.record("Expected missing run ids to fail.")
        } catch let error as SymphonyBuildError {
            #expect(error.code == "missing_artifact_run")
        }

        try FileManager.default.createDirectory(at: diagnosticsPath, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: attachmentsPath, withIntermediateDirectories: true)
        try Data().write(to: png)
        try Data("tree".utf8).write(to: text)
        _ = try ArtifactManager(processRunner: StubProcessRunner(results: [
            "xcrun xcresulttool get object --legacy --path \(executionContext.resultBundlePath.path) --format json": StubProcessRunner.success(#"{"kind":"ActionsInvocationRecord"}"#),
            "xcrun xcresulttool export diagnostics --path \(executionContext.resultBundlePath.path) --output-path \(diagnosticsPath.path)": StubProcessRunner.success(),
            "xcrun xcresulttool export attachments --path \(executionContext.resultBundlePath.path) --output-path \(attachmentsPath.path)": StubProcessRunner.success(),
        ])).recordXcodeExecution(
            workspace: workspace,
            executionContext: executionContext,
            command: .test,
            product: .client,
            scheme: "Symphony",
            destination: ResolvedDestination(platform: .iosSimulator, displayName: "iPhone 17", simulatorName: "iPhone 17", simulatorUDID: "AAAA", xcodeDestination: "platform=iOS Simulator,id=AAAA"),
            invocation: "xcodebuild test",
            exitStatus: 0,
            combinedOutput: "",
            startedAt: Date(timeIntervalSince1970: 1_700_000_400),
            endedAt: Date(timeIntervalSince1970: 1_700_000_430)
        )

        let root = workspace.buildStateRoot.appendingPathComponent("artifacts/test/latest").resolvingSymlinksInPath()
        let manualIndex = ArtifactIndex(
            entries: [ArtifactIndexEntry(name: "manual.txt", relativePath: "manual.txt", kind: "missing", createdAt: "2026-03-24T00:00:00Z", anomaly: nil)],
            command: .test,
            runID: root.lastPathComponent,
            timestamp: "2026-03-24T00:00:00Z",
            anomalies: []
        )
        let indexPath = root.appendingPathComponent("index.json")
        try JSONEncoder().encode(manualIndex).write(to: indexPath)
        let rendered = try manager.resolveArtifacts(
            workspace: workspace,
            request: ArtifactsCommandRequest(command: .test, latest: true, runID: nil, currentDirectory: directory)
        )
        #expect(rendered.contains("manual.txt [missing] \(root.appendingPathComponent("manual.txt").path)"))
    }
}

@Test func artifactManagerInternalHelpersCoverRunSelectionAndIndexFallbacks() throws {
    try withTemporaryDirectory { directory in
        let workspace = WorkspaceContext(
            projectRoot: directory,
            buildStateRoot: directory.appendingPathComponent(".build/symphony-build", isDirectory: true),
            xcodeWorkspacePath: nil,
            xcodeProjectPath: nil
        )
        let manager = ArtifactManager(processRunner: StubProcessRunner())
        let familyRoot = workspace.buildStateRoot.appendingPathComponent("artifacts/build", isDirectory: true)
        let older = familyRoot.appendingPathComponent("20260324-120000-sample", isDirectory: true)
        let newer = familyRoot.appendingPathComponent("20260324-130000-sample", isDirectory: true)
        try FileManager.default.createDirectory(at: older, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: newer, withIntermediateDirectories: true)

        let rendered = try manager.resolveArtifacts(
            workspace: workspace,
            request: ArtifactsCommandRequest(command: .build, latest: false, runID: "sample", currentDirectory: directory)
        )
        #expect(rendered.contains(newer.path))
        #expect(try manager.loadArtifactIndexIfPresent(at: newer.appendingPathComponent("index.json")) == nil)
        #expect(manager.recursiveFiles(in: [directory.appendingPathComponent("does-not-exist", isDirectory: true)]).isEmpty)

        try manager.updateLatestLink(familyRoot: familyRoot, target: older)
        try manager.updateLatestLink(familyRoot: familyRoot, target: newer)
        #expect(familyRoot.appendingPathComponent("latest").resolvingSymlinksInPath().path == newer.path)
    }
}

@Test func artifactResolutionIncludesSupplementalCoverageReports() throws {
    try withTemporaryDirectory { directory in
        let workspace = WorkspaceContext(
            projectRoot: directory,
            buildStateRoot: directory.appendingPathComponent(".build/symphony-build", isDirectory: true),
            xcodeWorkspacePath: nil,
            xcodeProjectPath: nil
        )
        let worker = try WorkerScope(id: 0)
        let executionContext = try ExecutionContextBuilder().make(
            workspace: workspace,
            worker: worker,
            command: .coverage,
            runID: "symphony",
            date: Date(timeIntervalSince1970: 1_700_000_260)
        )
        try FileManager.default.createDirectory(at: executionContext.artifactRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: executionContext.resultBundlePath, withIntermediateDirectories: true)
        try #"{"coveredLines":96}"#.write(
            to: executionContext.artifactRoot.appendingPathComponent("coverage.json"),
            atomically: true,
            encoding: .utf8
        )
        try "overall 73.28% (96/131)\n".write(
            to: executionContext.artifactRoot.appendingPathComponent("coverage.txt"),
            atomically: true,
            encoding: .utf8
        )

        let runner = StubProcessRunner(results: [
            "xcrun xcresulttool get object --legacy --path \(executionContext.resultBundlePath.path) --format json": StubProcessRunner.success(#"{"kind":"ActionsInvocationRecord"}"#),
            "xcrun xcresulttool export diagnostics --path \(executionContext.resultBundlePath.path) --output-path \(executionContext.artifactRoot.appendingPathComponent("diagnostics").path)": StubProcessRunner.success(),
            "xcrun xcresulttool export attachments --path \(executionContext.resultBundlePath.path) --output-path \(executionContext.artifactRoot.appendingPathComponent("attachments").path)": StubProcessRunner.success(),
        ])
        let manager = ArtifactManager(processRunner: runner)

        _ = try manager.recordXcodeExecution(
            workspace: workspace,
            executionContext: executionContext,
            command: .coverage,
            product: .server,
            scheme: "SymphonyServer",
            destination: ResolvedDestination(
                platform: .macos,
                displayName: "macOS",
                simulatorName: nil,
                simulatorUDID: nil,
                xcodeDestination: expectedHostMacOSDestination()
            ),
            invocation: "xcodebuild test -enableCodeCoverage YES",
            exitStatus: 0,
            combinedOutput: "tests passed",
            startedAt: Date(timeIntervalSince1970: 1_700_000_260),
            endedAt: Date(timeIntervalSince1970: 1_700_000_320)
        )

        let rendered = try manager.resolveArtifacts(
            workspace: workspace,
            request: ArtifactsCommandRequest(command: .coverage, latest: true, runID: nil, currentDirectory: directory)
        )

        #expect(rendered.contains("coverage.json \(executionContext.artifactRoot.appendingPathComponent("coverage.json").path)"))
        #expect(rendered.contains("coverage.txt \(executionContext.artifactRoot.appendingPathComponent("coverage.txt").path)"))
    }
}

@Test func coverageReporterFiltersOutTestBundlesByDefaultAndWritesReports() throws {
    try withTemporaryDirectory { directory in
        let resultBundlePath = directory.appendingPathComponent("result.xcresult", isDirectory: true)
        let artifactRoot = directory.appendingPathComponent("artifacts", isDirectory: true)
        let coverageJSON = #"""
        {"coveredLines":113,"executableLines":148,"lineCoverage":0.7635135135,"targets":[{"buildProductPath":"/tmp/SymphonyServer","coveredLines":0,"executableLines":1,"files":[{"coveredLines":0,"executableLines":1,"lineCoverage":0,"name":"main.swift","path":"/tmp/main.swift"}],"lineCoverage":0,"name":"SymphonyServer"},{"buildProductPath":"/tmp/SymphonyServerTests.xctest/Contents/MacOS/SymphonyServerTests","coveredLines":17,"executableLines":17,"files":[{"coveredLines":17,"executableLines":17,"lineCoverage":1,"name":"BootstrapServerRunnerTests.swift","path":"/tmp/BootstrapServerRunnerTests.swift"}],"lineCoverage":1,"name":"SymphonyServerTests.xctest"},{"buildProductPath":"/tmp/libXcodeSupport.a","coveredLines":96,"executableLines":130,"files":[{"coveredLines":96,"executableLines":130,"lineCoverage":0.7384615385,"name":"BootstrapSupport.swift","path":"/tmp/BootstrapSupport.swift"}],"lineCoverage":0.7384615385,"name":"libXcodeSupport.a"}]}
        """#
        let runner = StubProcessRunner(results: [
            "xcrun xccov view --report --json \(resultBundlePath.path)": StubProcessRunner.success(coverageJSON),
        ])
        let reporter = CoverageReporter(processRunner: runner)

        let artifacts = try reporter.export(
            resultBundlePath: resultBundlePath,
            artifactRoot: artifactRoot,
            includeTestTargets: false,
            showFiles: true
        )

        #expect(artifacts.report.coveredLines == 96)
        #expect(artifacts.report.executableLines == 131)
        #expect(artifacts.report.targets.map(\.name) == ["SymphonyServer", "libXcodeSupport.a"])
        #expect(artifacts.report.excludedTargets == ["SymphonyServerTests.xctest"])
        #expect(artifacts.textOutput.contains("overall 73.28% (96/131)"))
        #expect(artifacts.textOutput.contains("file libXcodeSupport.a BootstrapSupport.swift 73.85% (96/130)"))
        #expect(FileManager.default.fileExists(atPath: artifacts.jsonPath.path))
        #expect(FileManager.default.fileExists(atPath: artifacts.textPath.path))
    }
}

@Test func packageCoverageReporterFiltersToFirstPartySources() throws {
    try withTemporaryDirectory { directory in
        let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repoRoot.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        let coveragePath = directory.appendingPathComponent("package-coverage.json")
        let json = #"""
        {
          "data": [
            {
              "files": [
                {
                  "filename": "__REPO__/Sources/Foo.swift",
                  "summary": { "lines": { "count": 20, "covered": 10 } }
                },
                {
                  "filename": "__REPO__/Tests/FooTests.swift",
                  "summary": { "lines": { "count": 50, "covered": 50 } }
                },
                {
                  "filename": "__REPO__/.build/checkouts/swift-argument-parser/Sources/Dependency.swift",
                  "summary": { "lines": { "count": 100, "covered": 0 } }
                }
              ]
            }
          ]
        }
        """#
        try json
            .replacingOccurrences(of: "__REPO__", with: repoRoot.path)
            .write(to: coveragePath, atomically: true, encoding: .utf8)

        let report = try PackageCoverageReporter().loadReport(at: coveragePath, projectRoot: repoRoot)

        #expect(report.scope == "first_party_sources")
        #expect(report.coveredLines == 10)
        #expect(report.executableLines == 20)
        #expect(report.files.map(\.path) == ["Sources/Foo.swift"])
    }
}

@Test func harnessUsesSwiftTestCoverageAndFailsBelowThreshold() throws {
    try withTemporaryDirectory { directory in
        let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repoRoot.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: repoRoot.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        let coveragePath = repoRoot.appendingPathComponent(".build/coverage/package.json")
        try FileManager.default.createDirectory(at: coveragePath.deletingLastPathComponent(), withIntermediateDirectories: true)
        let json = #"""
        {
          "data": [
            {
              "files": [
                {
                  "filename": "__REPO__/Sources/Foo.swift",
                  "summary": { "lines": { "count": 100, "covered": 60 } }
                }
              ]
            }
          ]
        }
        """#
        try json
            .replacingOccurrences(of: "__REPO__", with: repoRoot.path)
            .write(to: coveragePath, atomically: true, encoding: .utf8)

        let discovery = StubWorkspaceDiscovery(
            workspace: WorkspaceContext(
                projectRoot: repoRoot,
                buildStateRoot: repoRoot.appendingPathComponent(".build/symphony-build", isDirectory: true),
                xcodeWorkspacePath: nil,
                xcodeProjectPath: nil
            )
        )
        let runner = StubProcessRunner(results: [
            "swift test --enable-code-coverage": StubProcessRunner.success("tests passed\n"),
            "swift test --show-code-coverage-path": StubProcessRunner.success(coveragePath.path + "\n"),
        ])
        let passingCoverage = CoverageReport(
            coveredLines: 60,
            executableLines: 100,
            lineCoverage: 0.6,
            includeTestTargets: false,
            excludedTargets: [],
            targets: [
                CoverageTargetReport(name: "Symphony.app", buildProductPath: nil, coveredLines: 20, executableLines: 40, lineCoverage: 0.5, files: nil),
                CoverageTargetReport(name: "libXcodeSupport.a", buildProductPath: nil, coveredLines: 40, executableLines: 60, lineCoverage: 0.6666666667, files: nil),
            ]
        )
        let failingCoverage = CoverageReport(
            coveredLines: 20,
            executableLines: 100,
            lineCoverage: 0.2,
            includeTestTargets: false,
            excludedTargets: [],
            targets: [
                CoverageTargetReport(name: "SymphonyServer", buildProductPath: nil, coveredLines: 20, executableLines: 100, lineCoverage: 0.2, files: nil),
            ]
        )
        let tool = SymphonyBuildTool(
            workspaceDiscovery: discovery,
            processRunner: runner,
            commitHarness: CommitHarness(
                processRunner: runner,
                statusSink: { _ in },
                clientCoverageLoader: { _ in passingCoverage },
                serverCoverageLoader: { _ in passingCoverage }
            )
        )

        let output = try tool.harness(
            HarnessCommandRequest(minimumCoveragePercent: 50, json: false, currentDirectory: repoRoot)
        )
        #expect(output.contains("package coverage 60.00% (60/100)"))
        #expect(output.contains("client coverage 60.00% (60/100)"))
        #expect(output.contains("server coverage 60.00% (60/100)"))
        #expect(output.contains("file Sources/Foo.swift 60.00% (60/100)"))
        #expect(output.contains("target Symphony.app 50.00% (20/40)"))

        let jsonOutput = try tool.harness(
            HarnessCommandRequest(minimumCoveragePercent: 50, json: true, currentDirectory: repoRoot)
        )
        #expect(jsonOutput.contains("\"clientCoverage\""))
        #expect(jsonOutput.contains("\"serverCoverage\""))

        do {
            let failingTool = SymphonyBuildTool(
                workspaceDiscovery: discovery,
                processRunner: runner,
                commitHarness: CommitHarness(
                    processRunner: runner,
                    statusSink: { _ in },
                    clientCoverageLoader: { _ in passingCoverage },
                    serverCoverageLoader: { _ in failingCoverage }
                )
            )
            _ = try failingTool.harness(
                HarnessCommandRequest(minimumCoveragePercent: 80, json: false, currentDirectory: repoRoot)
            )
            Issue.record("Expected the harness to fail when coverage is below threshold.")
        } catch let error as SymphonyBuildCommandFailure {
            #expect(error.message.contains("below the required threshold"))
            #expect(error.message.contains("server coverage 20.00% (20/100)"))
        }
    }
}

@Test func hooksInstallConfiguresRepoLocalHooksPath() throws {
    try withTemporaryDirectory { directory in
        let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repoRoot.appendingPathComponent(".git"), withIntermediateDirectories: true)

        let discovery = StubWorkspaceDiscovery(
            workspace: WorkspaceContext(
                projectRoot: repoRoot,
                buildStateRoot: repoRoot.appendingPathComponent(".build/symphony-build", isDirectory: true),
                xcodeWorkspacePath: nil,
                xcodeProjectPath: nil
            )
        )
        let runner = RecordingProcessRunner()
        let tool = SymphonyBuildTool(workspaceDiscovery: discovery, processRunner: runner)

        let installedPath = try tool.hooksInstall(HooksInstallRequest(currentDirectory: repoRoot))

        #expect(installedPath == repoRoot.appendingPathComponent(".githooks", isDirectory: true).path)
        #expect(runner.commands == ["git config core.hooksPath .githooks"])
    }
}

@Test func doctorReportSortsIssuesAndRendersJSONAndHumanOutput() throws {
    let runner = StubProcessRunner(results: [
        "which swift": StubProcessRunner.success(),
        "which xcodebuild": StubProcessRunner.success(),
        "xcrun simctl help": StubProcessRunner.success(),
        "xcrun xcresulttool help": StubProcessRunner.failure("xcresulttool missing"),
        "which xcrun": StubProcessRunner.success(),
        "xcodebuild -list -json -workspace /tmp/repo/Symphony.xcworkspace": StubProcessRunner.success(#"{"workspace":{"schemes":["Symphony"]},"project":{"schemes":[]}}"#),
    ])
    let discovery = StubWorkspaceDiscovery(
        workspace: WorkspaceContext(
            projectRoot: URL(fileURLWithPath: "/tmp/repo", isDirectory: true),
            buildStateRoot: URL(fileURLWithPath: "/tmp/repo/.build/symphony-build", isDirectory: true),
            xcodeWorkspacePath: URL(fileURLWithPath: "/tmp/repo/Symphony.xcworkspace"),
            xcodeProjectPath: nil
        )
    )
    let doctor = DoctorService(workspaceDiscovery: discovery, processRunner: runner)
    let report = try doctor.makeReport(from: DoctorCommandRequest(strict: false, json: false, quiet: false, currentDirectory: URL(fileURLWithPath: "/tmp/repo")))

    #expect(report.issues.map { $0.code } == ["missing_scheme_symphonyserver", "missing_xcresulttool"])

    let human = try doctor.render(report: report, json: false, quiet: false)
    #expect(human.contains("ERROR [missing_scheme_symphonyserver]"))

    let json = try doctor.render(report: report, json: true, quiet: false)
    #expect(json.contains("\"missing_scheme_symphonyserver\""))
}

@Test func strictDoctorThrowsWhenAnyIssuesExist() throws {
    let report = DiagnosticsReport(
        issues: [
            DiagnosticIssue(severity: .warning, code: "warning_issue", message: "needs attention", suggestedFix: nil),
        ],
        checkedPaths: ["/tmp/repo"],
        checkedExecutables: ["swift"]
    )
    let tool = SymphonyBuildTool(doctorService: StubDoctorService(report: report, rendered: "diagnostics"))

    do {
        _ = try tool.doctor(
            DoctorCommandRequest(strict: true, json: false, quiet: false, currentDirectory: URL(fileURLWithPath: "/tmp/repo"))
        )
        Issue.record("Expected strict doctor mode to fail when issues are present.")
    } catch let error as SymphonyBuildCommandFailure {
        #expect(error.message == "diagnostics")
    }
}

@Test func strictDoctorSucceedsWhenReportIsClean() throws {
    let tool = SymphonyBuildTool(
        doctorService: StubDoctorService(
            report: DiagnosticsReport(issues: [], checkedPaths: ["/tmp/repo"], checkedExecutables: ["swift"]),
            rendered: "OK: environment is ready"
        )
    )

    let output = try tool.doctor(
        DoctorCommandRequest(strict: true, json: false, quiet: false, currentDirectory: URL(fileURLWithPath: "/tmp/repo"))
    )

    #expect(output == "OK: environment is ready")
}

@Test func xcodeOutputReporterFullModeStreamsStdoutAndStderr() {
    let messages = SignalBox()
    let reporter = XcodeOutputReporter(mode: .full, sink: { messages.append($0) })
    let observation = reporter.makeObservation(label: "xcodebuild build")

    observation.onLine?(.stdout, "CompileSwift Sources/Foo.swift")
    observation.onLine?(.stderr, "error: build failed")
    reporter.finish()

    #expect(messages.values.count == 2)
    #expect(messages.values.contains(where: { $0.contains("[xcodebuild/stdout] CompileSwift Sources/Foo.swift") }))
    #expect(messages.values.contains(where: { $0.contains("[xcodebuild/stderr] error: build failed") }))
}

@Test func xcodeOutputReporterFilteredModeSuppressesLowSignalLines() {
    let messages = SignalBox()
    let reporter = XcodeOutputReporter(mode: .filtered, sink: { messages.append($0) })
    let observation = reporter.makeObservation(label: "xcodebuild test")

    observation.onLine?(.stdout, "CompileSwift normal arm64 Foo.swift")
    observation.onLine?(.stderr, "warning: deprecated API")
    observation.onLine?(.stdout, "Ld /tmp/Symphony")
    reporter.finish()

    #expect(messages.values.contains(where: { $0.contains("[xcodebuild] warning: deprecated API") }))
    #expect(messages.values.contains(where: { $0.contains("suppressed 2 low-signal lines") }))
    #expect(!messages.values.contains(where: { $0.contains("CompileSwift normal arm64 Foo.swift") }))
}

@Test func xcodeOutputReporterQuietModeEmitsNothing() {
    let messages = SignalBox()
    let reporter = XcodeOutputReporter(mode: .quiet, sink: { messages.append($0) })
    let observation = reporter.makeObservation(label: "xcodebuild test")

    observation.onLine?(.stdout, "Test Suite 'All tests' started")
    observation.onLine?(.stderr, "warning: still noisy")
    reporter.finish()

    #expect(messages.values.isEmpty)
}

@Test func xcodeOutputReporterIgnoresBlankLines() {
    let messages = SignalBox()
    let reporter = XcodeOutputReporter(mode: .full, sink: { messages.append($0) })
    let observation = reporter.makeObservation(label: "xcodebuild test")

    observation.onLine?(.stdout, "   ")
    reporter.finish()

    #expect(messages.values.isEmpty)
}

@Test func xcodeOutputReporterForwardsStaleSignalsIndependentlyOfOutputMode() {
    let messages = SignalBox()
    let reporter = XcodeOutputReporter(mode: .quiet, sink: { messages.append($0) })
    let observation = reporter.makeObservation(label: "xcodebuild test")

    observation.onStaleSignal?("[symphony-build] xcodebuild test still running with no new output for 15s")
    reporter.finish()

    #expect(messages.values == ["[symphony-build] xcodebuild test still running with no new output for 15s"])
}

@Test func processRunnerEmitsStaleSignalForSilentLongRunningCommands() throws {
    let runner = SystemProcessRunner()
    let messages = SignalBox()

    let result = try runner.run(
        command: "sh",
        arguments: ["-c", "sleep 0.2"],
        environment: [:],
        currentDirectory: nil,
        observation: ProcessObservation(
            label: "test command",
            staleInterval: 0.05,
            onStaleSignal: { message in
                messages.append(message)
            }
        )
    )

    #expect(result.exitStatus == 0)
    #expect(messages.values.contains(where: { $0.contains("test command still running") }))
}

@Test func buildAndTestDryRunRenderSingleInvocationWithoutSideEffects() throws {
    try withTemporaryRepositoryFixture { repoRoot in
        let tool = makeToolForFixture(repoRoot: repoRoot)

        let buildOutput = try tool.build(
            BuildCommandRequest(
                product: .server,
                scheme: nil,
                platform: nil,
                simulator: nil,
                workerID: 0,
                dryRun: true,
                buildForTesting: false,
                outputMode: .full,
                currentDirectory: repoRoot
            )
        )
        let testOutput = try tool.test(
            TestCommandRequest(
                product: .server,
                scheme: nil,
                platform: nil,
                simulator: nil,
                workerID: 0,
                dryRun: true,
                onlyTesting: [],
                skipTesting: [],
                outputMode: .quiet,
                currentDirectory: repoRoot
            )
        )

        #expect(!buildOutput.contains("\n"))
        #expect(buildOutput.contains("-workspace "))
        #expect(buildOutput.contains("Symphony.xcworkspace"))
        #expect(buildOutput.hasSuffix(" build"))
        #expect(!testOutput.contains("\n"))
        #expect(testOutput.hasSuffix(" test"))
        #expect(!FileManager.default.fileExists(atPath: repoRoot.appendingPathComponent(".build/symphony-build").path))
    }
}

@Test func coverageDryRunRendersXcodeAndXccovCommandsWithoutSideEffects() throws {
    try withTemporaryRepositoryFixture { repoRoot in
        let tool = makeToolForFixture(repoRoot: repoRoot)
        let output = try tool.coverage(
            CoverageCommandRequest(
                product: .server,
                scheme: nil,
                platform: nil,
                simulator: nil,
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

        let lines = output.split(separator: "\n").map(String.init)
        #expect(lines.count == 2)
        #expect(lines[0].contains("-enableCodeCoverage YES"))
        #expect(lines[0].hasSuffix(" test"))
        #expect(lines[1].contains("xcrun xccov view --report --json "))
        #expect(lines[1].contains("/results/coverage/"))
        #expect(!FileManager.default.fileExists(atPath: repoRoot.appendingPathComponent(".build/symphony-build").path))
    }
}

@Test func runDryRunPrintsFullSequenceWithoutSideEffects() throws {
    try withTemporaryRepositoryFixture { repoRoot in
        let tool = makeToolForFixture(repoRoot: repoRoot)
        let output = try tool.run(
            RunCommandRequest(
                product: .client,
                scheme: nil,
                platform: nil,
                simulator: "iPhone 17 Plus",
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

        let lines = output.split(separator: "\n").map(String.init)
        #expect(lines.count == 4)
        #expect(lines[0].contains("xcodebuild"))
        #expect(lines[1].contains("xcrun simctl bootstatus CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC -b"))
        #expect(lines[2].contains("xcrun simctl install CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC <app>"))
        #expect(lines[3].contains("xcrun simctl launch CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC <bundle-id>"))
        #expect(!FileManager.default.fileExists(atPath: repoRoot.appendingPathComponent(".build/symphony-build").path))
        #expect(!FileManager.default.fileExists(atPath: repoRoot.appendingPathComponent(".build/symphony-build/runtime/server-endpoint.json").path))
    }
}

@Test func simSetServerPersistsEndpointAndClearRemovesIt() throws {
    try withTemporaryRepositoryFixture { repoRoot in
        let tool = makeToolForFixture(repoRoot: repoRoot)

        let savedPath = try tool.simSetServer(
            SimSetServerRequest(
                serverURL: nil,
                scheme: "https",
                host: "persisted.example.com",
                port: 9443,
                currentDirectory: repoRoot
            )
        )
        let savedURL = URL(fileURLWithPath: savedPath)
        let saved = try JSONDecoder().decode(RuntimeEndpoint.self, from: Data(contentsOf: savedURL))
        #expect(saved.scheme == "https")
        #expect(saved.host == "persisted.example.com")
        #expect(saved.port == 9443)

        let clearedPath = try tool.simClearServer(currentDirectory: repoRoot)
        #expect(clearedPath == savedPath)
        #expect(!FileManager.default.fileExists(atPath: savedURL.path))
    }
}

@Test func checkedInWorkspaceAndSchemesExistAtRepositoryRoot() throws {
    let repoRoot = currentRepositoryRoot()
    let fileManager = FileManager.default

    #expect(fileManager.fileExists(atPath: repoRoot.appendingPathComponent("Symphony.xcworkspace/contents.xcworkspacedata").path))
    #expect(fileManager.fileExists(atPath: repoRoot.appendingPathComponent("SymphonyApps.xcodeproj/project.pbxproj").path))
    #expect(fileManager.fileExists(atPath: repoRoot.appendingPathComponent("SymphonyApps.xcodeproj/xcshareddata/xcschemes/Symphony.xcscheme").path))
    #expect(fileManager.fileExists(atPath: repoRoot.appendingPathComponent("SymphonyApps.xcodeproj/xcshareddata/xcschemes/SymphonyServer.xcscheme").path))

    let discovery = WorkspaceDiscovery(processRunner: StubProcessRunner(results: [
        "git rev-parse --show-toplevel": StubProcessRunner.success(repoRoot.path + "\n"),
    ]))
    let workspace = try discovery.discover(from: repoRoot)
    #expect(workspace.xcodeWorkspacePath?.lastPathComponent == "Symphony.xcworkspace")
}

struct StubProcessRunner: ProcessRunning {
    static let success = CommandResult(exitStatus: 0, stdout: "", stderr: "")

    var results: [String: CommandResult] = [:]

    func run(command: String, arguments: [String], environment: [String : String], currentDirectory: URL?, observation: ProcessObservation?) throws -> CommandResult {
        let key = ([command] + arguments).joined(separator: " ")
        return results[key] ?? Self.success()
    }

    func startDetached(executablePath: String, arguments: [String], environment: [String : String], currentDirectory: URL?, output: URL) throws -> Int32 {
        1234
    }

    static func failure(_ stderr: String) -> CommandResult {
        CommandResult(exitStatus: 1, stdout: "", stderr: stderr)
    }

    static func success(_ stdout: String = "") -> CommandResult {
        CommandResult(exitStatus: 0, stdout: stdout, stderr: "")
    }
}

final class RecordingProcessRunner: ProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var storage = [String]()

    func run(command: String, arguments: [String], environment: [String : String], currentDirectory: URL?, observation: ProcessObservation?) throws -> CommandResult {
        lock.lock()
        storage.append(([command] + arguments).joined(separator: " "))
        lock.unlock()
        return StubProcessRunner.success()
    }

    func startDetached(executablePath: String, arguments: [String], environment: [String : String], currentDirectory: URL?, output: URL) throws -> Int32 {
        1234
    }

    var commands: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

final class SignalBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = [String]()

    func append(_ value: String) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }

    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

struct StubSimulatorCatalog: SimulatorCataloging {
    let devices: [SimulatorDevice]

    func availableDevices() throws -> [SimulatorDevice] {
        devices
    }
}

struct StubWorkspaceDiscovery: WorkspaceDiscovering {
    let workspace: WorkspaceContext

    func discover(from startDirectory: URL) throws -> WorkspaceContext {
        workspace
    }
}

struct StubDoctorService: DoctorServicing {
    let report: DiagnosticsReport
    let rendered: String

    func makeReport(from request: DoctorCommandRequest) throws -> DiagnosticsReport {
        report
    }

    func render(report: DiagnosticsReport, json: Bool, quiet: Bool) throws -> String {
        rendered
    }
}

func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try body(directory)
}

func withTemporaryRepositoryFixture(_ body: (URL) throws -> Void) throws {
    try withTemporaryDirectory { directory in
        let repoRoot = directory.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repoRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: repoRoot.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: repoRoot.appendingPathComponent("Symphony.xcworkspace"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: repoRoot.appendingPathComponent("SymphonyApps.xcodeproj"), withIntermediateDirectories: true)
        try body(repoRoot)
    }
}

func makeToolForFixture(repoRoot: URL) -> SymphonyBuildTool {
    let discovery = WorkspaceDiscovery(processRunner: StubProcessRunner(results: [
        "git rev-parse --show-toplevel": StubProcessRunner.success(repoRoot.path + "\n"),
    ]))
    let simulators = StubSimulatorCatalog(
        devices: [
            SimulatorDevice(name: "iPhone 17", udid: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", state: "Shutdown", runtime: "iOS 18"),
            SimulatorDevice(name: "iPhone 17 Pro", udid: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB", state: "Shutdown", runtime: "iOS 18"),
            SimulatorDevice(name: "iPhone 17 Plus", udid: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC", state: "Shutdown", runtime: "iOS 18"),
        ]
    )
    return SymphonyBuildTool(
        workspaceDiscovery: discovery,
        simulatorResolver: SimulatorResolver(catalog: simulators, processRunner: StubProcessRunner()),
        processRunner: StubProcessRunner()
    )
}

func currentRepositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

func expectedHostMacOSDestination() -> String {
    #if arch(arm64)
    "platform=macOS,arch=arm64"
    #elseif arch(x86_64)
    "platform=macOS,arch=x86_64"
    #else
    "platform=macOS"
    #endif
}
