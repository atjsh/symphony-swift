import Foundation
import SymphonyShared

public final class SymphonyBuildTool {
    private let workspaceDiscovery: WorkspaceDiscovering
    private let executionContextBuilder: ExecutionContextBuilder
    private let simulatorResolver: SimulatorResolver
    private let processRunner: ProcessRunning
    private let artifactManager: ArtifactManager
    private let endpointOverrideStore: EndpointOverrideStore
    private let doctorService: DoctorServicing
    private let productLocator: ProductLocator
    private let commitHarness: CommitHarness
    private let gitHookInstaller: GitHookInstaller
    private let statusSink: @Sendable (String) -> Void

    public init(
        workspaceDiscovery: WorkspaceDiscovering = WorkspaceDiscovery(),
        executionContextBuilder: ExecutionContextBuilder = ExecutionContextBuilder(),
        simulatorResolver: SimulatorResolver = SimulatorResolver(),
        processRunner: ProcessRunning = SystemProcessRunner(),
        artifactManager: ArtifactManager = ArtifactManager(),
        endpointOverrideStore: EndpointOverrideStore = EndpointOverrideStore(),
        doctorService: DoctorServicing = DoctorService(),
        productLocator: ProductLocator = ProductLocator(),
        commitHarness: CommitHarness? = nil,
        gitHookInstaller: GitHookInstaller? = nil,
        statusSink: @escaping @Sendable (String) -> Void = { message in
            FileHandle.standardError.write(Data((message + "\n").utf8))
        }
    ) {
        self.workspaceDiscovery = workspaceDiscovery
        self.executionContextBuilder = executionContextBuilder
        self.simulatorResolver = simulatorResolver
        self.processRunner = processRunner
        self.artifactManager = artifactManager
        self.endpointOverrideStore = endpointOverrideStore
        self.doctorService = doctorService
        self.productLocator = productLocator
        self.statusSink = statusSink
        self.commitHarness = commitHarness ?? CommitHarness(processRunner: processRunner, statusSink: statusSink)
        self.gitHookInstaller = gitHookInstaller ?? GitHookInstaller(processRunner: processRunner)
    }

    public func build(_ request: BuildCommandRequest) throws -> String {
        let workspace = try workspaceDiscovery.discover(from: request.currentDirectory)
        let worker = try WorkerScope(id: request.workerID)
        let selector = SchemeSelector(product: request.product, scheme: request.scheme, platform: request.platform)
        let destination = try simulatorResolver.resolve(destinationSelector(platform: selector.platform, simulator: request.simulator))
        let executionContext = try executionContextBuilder.make(workspace: workspace, worker: worker, command: .build, runID: selector.runIdentifier)
        switch selector.product.defaultBackend {
        case .xcode:
            return try buildXcode(
                request: request,
                workspace: workspace,
                selector: selector,
                destination: destination,
                executionContext: executionContext
            )
        case .swiftPM:
            return try buildSwiftPM(
                request: request,
                workspace: workspace,
                selector: selector,
                destination: destination,
                executionContext: executionContext
            )
        }
    }

    public func test(_ request: TestCommandRequest) throws -> String {
        let workspace = try workspaceDiscovery.discover(from: request.currentDirectory)
        let worker = try WorkerScope(id: request.workerID)
        let selector = SchemeSelector(product: request.product, scheme: request.scheme, platform: request.platform)
        let destination = try simulatorResolver.resolve(destinationSelector(platform: selector.platform, simulator: request.simulator))
        let executionContext = try executionContextBuilder.make(workspace: workspace, worker: worker, command: .test, runID: selector.runIdentifier)
        switch selector.product.defaultBackend {
        case .xcode:
            return try testXcode(
                request: request,
                workspace: workspace,
                selector: selector,
                destination: destination,
                executionContext: executionContext
            )
        case .swiftPM:
            return try testSwiftPM(
                request: request,
                workspace: workspace,
                selector: selector,
                destination: destination,
                executionContext: executionContext
            )
        }
    }

    public func coverage(_ request: CoverageCommandRequest) throws -> String {
        let workspace = try workspaceDiscovery.discover(from: request.currentDirectory)
        let worker = try WorkerScope(id: request.workerID)
        let selector = SchemeSelector(product: request.product, scheme: request.scheme, platform: request.platform)
        let destination = try simulatorResolver.resolve(destinationSelector(platform: selector.platform, simulator: request.simulator))
        let executionContext = try executionContextBuilder.make(workspace: workspace, worker: worker, command: .coverage, runID: selector.runIdentifier)
        switch selector.product.defaultBackend {
        case .xcode:
            return try coverageXcode(
                request: request,
                workspace: workspace,
                selector: selector,
                destination: destination,
                executionContext: executionContext
            )
        case .swiftPM:
            return try coverageSwiftPM(
                request: request,
                workspace: workspace,
                selector: selector,
                destination: destination,
                executionContext: executionContext
            )
        }
    }

    public func run(_ request: RunCommandRequest) throws -> String {
        let workspace = try workspaceDiscovery.discover(from: request.currentDirectory)
        let worker = try WorkerScope(id: request.workerID)
        let selector = SchemeSelector(product: request.product, scheme: request.scheme, platform: request.platform)
        let destination = try simulatorResolver.resolve(destinationSelector(platform: selector.platform, simulator: request.simulator))
        let executionContext = try executionContextBuilder.make(workspace: workspace, worker: worker, command: .run, runID: selector.runIdentifier)
        switch selector.product.defaultBackend {
        case .xcode:
            return try runXcode(
                request: request,
                workspace: workspace,
                selector: selector,
                destination: destination,
                executionContext: executionContext
            )
        case .swiftPM:
            return try runSwiftPM(
                request: request,
                workspace: workspace,
                selector: selector,
                destination: destination,
                executionContext: executionContext
            )
        }
    }

    private func buildXcode(
        request: BuildCommandRequest,
        workspace: WorkspaceContext,
        selector: SchemeSelector,
        destination: ResolvedDestination,
        executionContext: ExecutionContext
    ) throws -> String {
        let xcodeRequest = XcodeCommandRequest(
            action: request.buildForTesting ? .buildForTesting : .build,
            scheme: selector.scheme,
            destination: destination,
            derivedDataPath: executionContext.derivedDataPath,
            resultBundlePath: executionContext.resultBundlePath,
            outputMode: request.outputMode,
            environment: [:],
            workspacePath: workspace.xcodeWorkspacePath,
            projectPath: workspace.xcodeProjectPath
        )

        if request.dryRun {
            return try xcodeRequest.renderedCommandLine()
        }

        let startedAt = Date()
        let reporter = XcodeOutputReporter(mode: request.outputMode, sink: statusSink)
        defer { reporter.finish() }
        let result = try processRunner.run(
            command: "xcodebuild",
            arguments: try xcodeRequest.renderedArguments(),
            environment: [:],
            currentDirectory: workspace.projectRoot,
            observation: reporter.makeObservation(label: "xcodebuild build")
        )
        let endedAt = Date()
        let record = try artifactManager.recordXcodeExecution(
            workspace: workspace,
            executionContext: executionContext,
            command: .build,
            product: request.product,
            scheme: selector.scheme,
            destination: destination,
            invocation: try xcodeRequest.renderedCommandLine(),
            exitStatus: result.exitStatus,
            combinedOutput: result.combinedOutput,
            startedAt: startedAt,
            endedAt: endedAt
        )

        guard result.exitStatus == 0 else {
            throw SymphonyBuildCommandFailure(message: "xcodebuild \(request.buildForTesting ? "build-for-testing" : "build") failed.", summaryPath: record.run.summaryPath)
        }
        return record.run.summaryPath.path
    }

    private func buildSwiftPM(
        request: BuildCommandRequest,
        workspace: WorkspaceContext,
        selector: SchemeSelector,
        destination: ResolvedDestination,
        executionContext: ExecutionContext
    ) throws -> String {
        let productName = "SymphonyServer"
        let invocation = renderSwiftBuildCommandLine(productName: productName)

        if request.dryRun {
            return invocation
        }

        let startedAt = Date()
        let result = try processRunner.run(
            command: "swift",
            arguments: ["build", "--product", productName],
            environment: [:],
            currentDirectory: workspace.projectRoot,
            observation: nil
        )
        let endedAt = Date()
        let record = try artifactManager.recordSwiftPMExecution(
            workspace: workspace,
            executionContext: executionContext,
            command: .build,
            product: request.product,
            scheme: selector.scheme,
            destination: destination,
            invocation: invocation,
            exitStatus: result.exitStatus,
            combinedOutput: result.combinedOutput,
            startedAt: startedAt,
            endedAt: endedAt
        )

        guard result.exitStatus == 0 else {
            throw SymphonyBuildCommandFailure(message: "swift build failed.", summaryPath: record.run.summaryPath)
        }
        return record.run.summaryPath.path
    }

    private func testXcode(
        request: TestCommandRequest,
        workspace: WorkspaceContext,
        selector: SchemeSelector,
        destination: ResolvedDestination,
        executionContext: ExecutionContext
    ) throws -> String {
        let xcodeRequest = XcodeCommandRequest(
            action: .test,
            scheme: selector.scheme,
            destination: destination,
            derivedDataPath: executionContext.derivedDataPath,
            resultBundlePath: executionContext.resultBundlePath,
            outputMode: request.outputMode,
            environment: [:],
            workspacePath: workspace.xcodeWorkspacePath,
            projectPath: workspace.xcodeProjectPath,
            onlyTesting: request.onlyTesting,
            skipTesting: request.skipTesting
        )

        if request.dryRun {
            return try xcodeRequest.renderedCommandLine()
        }

        let startedAt = Date()
        let reporter = XcodeOutputReporter(mode: request.outputMode, sink: statusSink)
        defer { reporter.finish() }
        let result = try processRunner.run(
            command: "xcodebuild",
            arguments: try xcodeRequest.renderedArguments(),
            environment: [:],
            currentDirectory: workspace.projectRoot,
            observation: reporter.makeObservation(label: "xcodebuild test")
        )
        let endedAt = Date()
        let record = try artifactManager.recordXcodeExecution(
            workspace: workspace,
            executionContext: executionContext,
            command: .test,
            product: request.product,
            scheme: selector.scheme,
            destination: destination,
            invocation: try xcodeRequest.renderedCommandLine(),
            exitStatus: result.exitStatus,
            combinedOutput: result.combinedOutput,
            startedAt: startedAt,
            endedAt: endedAt
        )

        guard result.exitStatus == 0 else {
            throw SymphonyBuildCommandFailure(message: "xcodebuild test failed.", summaryPath: record.run.summaryPath)
        }
        return record.run.summaryPath.path
    }

    private func testSwiftPM(
        request: TestCommandRequest,
        workspace: WorkspaceContext,
        selector: SchemeSelector,
        destination: ResolvedDestination,
        executionContext: ExecutionContext
    ) throws -> String {
        let testFilter = "SymphonyServerTests"
        let invocation = renderSwiftTestCommandLine(filter: testFilter, enableCodeCoverage: false)

        if request.dryRun {
            return invocation
        }

        let startedAt = Date()
        let result = try processRunner.run(
            command: "swift",
            arguments: ["test", "--filter", testFilter],
            environment: [:],
            currentDirectory: workspace.projectRoot,
            observation: nil
        )
        let endedAt = Date()
        let record = try artifactManager.recordSwiftPMExecution(
            workspace: workspace,
            executionContext: executionContext,
            command: .test,
            product: request.product,
            scheme: selector.scheme,
            destination: destination,
            invocation: invocation,
            exitStatus: result.exitStatus,
            combinedOutput: result.combinedOutput,
            startedAt: startedAt,
            endedAt: endedAt
        )

        guard result.exitStatus == 0 else {
            throw SymphonyBuildCommandFailure(message: "swift test failed.", summaryPath: record.run.summaryPath)
        }
        return record.run.summaryPath.path
    }

    private func coverageXcode(
        request: CoverageCommandRequest,
        workspace: WorkspaceContext,
        selector: SchemeSelector,
        destination: ResolvedDestination,
        executionContext: ExecutionContext
    ) throws -> String {
        let xcodeRequest = XcodeCommandRequest(
            action: .test,
            scheme: selector.scheme,
            destination: destination,
            derivedDataPath: executionContext.derivedDataPath,
            resultBundlePath: executionContext.resultBundlePath,
            enableCodeCoverage: true,
            outputMode: request.outputMode,
            environment: [:],
            workspacePath: workspace.xcodeWorkspacePath,
            projectPath: workspace.xcodeProjectPath,
            onlyTesting: request.onlyTesting,
            skipTesting: request.skipTesting
        )
        let coverageReporter = CoverageReporter(processRunner: processRunner)
        let coverageCommand = coverageReporter.renderedCommandLine(resultBundlePath: executionContext.resultBundlePath)

        if request.dryRun {
            return [
                try xcodeRequest.renderedCommandLine(),
                coverageCommand,
            ].joined(separator: "\n")
        }

        let startedAt = Date()
        let reporter = XcodeOutputReporter(mode: request.outputMode, sink: statusSink)
        defer { reporter.finish() }
        let result = try processRunner.run(
            command: "xcodebuild",
            arguments: try xcodeRequest.renderedArguments(),
            environment: [:],
            currentDirectory: workspace.projectRoot,
            observation: reporter.makeObservation(label: "xcodebuild coverage")
        )
        let endedAt = Date()

        var coverageArtifacts: CoverageArtifacts?
        var coverageAnomalies = [ArtifactAnomaly]()
        if result.exitStatus == 0 {
            do {
                coverageArtifacts = try coverageReporter.export(
                    resultBundlePath: executionContext.resultBundlePath,
                    artifactRoot: executionContext.artifactRoot,
                    includeTestTargets: request.includeTestTargets,
                    showFiles: request.showFiles
                )
            } catch let error as SymphonyBuildError {
                coverageAnomalies.append(ArtifactAnomaly(code: error.code, message: error.message, phase: "coverage"))
            } catch {
                coverageAnomalies.append(
                    ArtifactAnomaly(code: "coverage_export_failed", message: error.localizedDescription, phase: "coverage")
                )
            }
        }

        let record = try artifactManager.recordXcodeExecution(
            workspace: workspace,
            executionContext: executionContext,
            command: .coverage,
            product: request.product,
            scheme: selector.scheme,
            destination: destination,
            invocation: [
                try xcodeRequest.renderedCommandLine(),
                coverageCommand,
            ].joined(separator: "\n"),
            exitStatus: result.exitStatus == 0 && coverageAnomalies.isEmpty ? 0 : (result.exitStatus == 0 ? 1 : result.exitStatus),
            combinedOutput: result.combinedOutput,
            startedAt: startedAt,
            endedAt: endedAt,
            extraAnomalies: coverageAnomalies
        )

        guard result.exitStatus == 0 else {
            throw SymphonyBuildCommandFailure(message: "xcodebuild test with code coverage failed.", summaryPath: record.run.summaryPath)
        }
        guard coverageAnomalies.isEmpty, let coverageArtifacts else {
            throw SymphonyBuildCommandFailure(message: "Coverage export failed.", summaryPath: record.run.summaryPath)
        }
        return request.json ? coverageArtifacts.jsonOutput : coverageArtifacts.textOutput
    }

    private func coverageSwiftPM(
        request: CoverageCommandRequest,
        workspace: WorkspaceContext,
        selector: SchemeSelector,
        destination: ResolvedDestination,
        executionContext: ExecutionContext
    ) throws -> String {
        let testFilter = "SymphonyServerTests"
        let coverageCommand = renderSwiftTestCommandLine(filter: testFilter, enableCodeCoverage: true)
        let coveragePathCommand = SwiftPMCoverageReporter().renderedCoveragePathCommandLine()

        if request.dryRun {
            return [coverageCommand, coveragePathCommand].joined(separator: "\n")
        }

        let startedAt = Date()
        let result = try processRunner.run(
            command: "swift",
            arguments: ["test", "--enable-code-coverage", "--filter", testFilter],
            environment: [:],
            currentDirectory: workspace.projectRoot,
            observation: nil
        )

        var coverageArtifacts: CoverageArtifacts?
        var coverageAnomalies = [ArtifactAnomaly]()
        var coveragePathOutput = ""
        if result.exitStatus == 0 {
            do {
                let coveragePathResult = try processRunner.run(
                    command: "swift",
                    arguments: ["test", "--show-code-coverage-path"],
                    environment: [:],
                    currentDirectory: workspace.projectRoot,
                    observation: nil
                )
                coveragePathOutput = coveragePathResult.combinedOutput
                guard coveragePathResult.exitStatus == 0 else {
                    throw SymphonyBuildError(
                        code: "swiftpm_coverage_path_failed",
                        message: coveragePathResult.combinedOutput.isEmpty ? "SwiftPM did not return a coverage JSON path." : coveragePathResult.combinedOutput
                    )
                }

                let rawPath = coveragePathResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !rawPath.isEmpty else {
                    throw SymphonyBuildError(code: "missing_swiftpm_coverage_path", message: "SwiftPM returned an empty coverage JSON path.")
                }

                coverageArtifacts = try SwiftPMCoverageReporter().exportServerCoverage(
                    coverageJSONPath: URL(fileURLWithPath: rawPath),
                    projectRoot: workspace.projectRoot,
                    artifactRoot: executionContext.artifactRoot,
                    showFiles: request.showFiles
                )
            } catch let error as SymphonyBuildError {
                coverageAnomalies.append(ArtifactAnomaly(code: error.code, message: error.message, phase: "coverage"))
            } catch {
                coverageAnomalies.append(ArtifactAnomaly(code: "coverage_export_failed", message: error.localizedDescription, phase: "coverage"))
            }
        }

        let endedAt = Date()
        let record = try artifactManager.recordSwiftPMExecution(
            workspace: workspace,
            executionContext: executionContext,
            command: .coverage,
            product: request.product,
            scheme: selector.scheme,
            destination: destination,
            invocation: [coverageCommand, coveragePathCommand].joined(separator: "\n"),
            exitStatus: result.exitStatus == 0 && coverageAnomalies.isEmpty ? 0 : (result.exitStatus == 0 ? 1 : result.exitStatus),
            combinedOutput: [result.combinedOutput, coveragePathOutput].filter { !$0.isEmpty }.joined(separator: "\n"),
            startedAt: startedAt,
            endedAt: endedAt,
            extraAnomalies: coverageAnomalies
        )

        guard result.exitStatus == 0 else {
            throw SymphonyBuildCommandFailure(message: "swift test with code coverage failed.", summaryPath: record.run.summaryPath)
        }
        guard coverageAnomalies.isEmpty, let coverageArtifacts else {
            throw SymphonyBuildCommandFailure(message: "Coverage export failed.", summaryPath: record.run.summaryPath)
        }
        return request.json ? coverageArtifacts.jsonOutput : coverageArtifacts.textOutput
    }

    private func runXcode(
        request: RunCommandRequest,
        workspace: WorkspaceContext,
        selector: SchemeSelector,
        destination: ResolvedDestination,
        executionContext: ExecutionContext
    ) throws -> String {
        let xcodeRequest = XcodeCommandRequest(
            action: .build,
            scheme: selector.scheme,
            destination: destination,
            derivedDataPath: executionContext.derivedDataPath,
            resultBundlePath: executionContext.resultBundlePath,
            outputMode: request.outputMode,
            environment: [:],
            workspacePath: workspace.xcodeWorkspacePath,
            projectPath: workspace.xcodeProjectPath
        )

        let endpoint = try endpointOverrideStore.resolve(workspace: workspace, serverURL: request.serverURL, host: request.host, port: request.port)
        let launchConfiguration = LaunchConfiguration(
            target: .client,
            scheme: selector.scheme,
            destination: destination,
            endpoint: endpoint,
            environment: request.environment
        )

        if request.dryRun {
            return try renderXcodeRunSequence(
                xcodeRequest: xcodeRequest,
                configuration: launchConfiguration,
                productDetails: nil
            )
        }

        var commandOutput = [String]()
        var resolvedProductDetails: ProductDetails?
        let startedAt = Date()
        let reporter = XcodeOutputReporter(mode: request.outputMode, sink: statusSink)
        defer { reporter.finish() }
        let buildResult = try processRunner.run(
            command: "xcodebuild",
            arguments: try xcodeRequest.renderedArguments(),
            environment: [:],
            currentDirectory: workspace.projectRoot,
            observation: reporter.makeObservation(label: "xcodebuild run build step")
        )
        commandOutput.append(buildResult.combinedOutput)
        var anomalies = [ArtifactAnomaly]()

        if buildResult.exitStatus == 0 {
            try simulatorResolver.boot(resolved: destination)
            let details = try productLocator.locateProduct(
                workspace: workspace,
                scheme: selector.scheme,
                destination: destination,
                derivedDataPath: executionContext.derivedDataPath
            )
            resolvedProductDetails = details
            guard let bundleIdentifier = details.bundleIdentifier, let simulatorUDID = destination.simulatorUDID else {
                throw SymphonyBuildError(code: "missing_launch_metadata", message: "The client launch is missing the simulator destination or product bundle identifier.")
            }
            let install = try processRunner.run(
                command: "xcrun",
                arguments: ["simctl", "install", simulatorUDID, details.productURL.path],
                environment: [:],
                currentDirectory: workspace.projectRoot,
                observation: ProcessObservation(label: "simctl install")
            )
            commandOutput.append(install.combinedOutput)
            if install.exitStatus != 0 {
                anomalies.append(ArtifactAnomaly(code: "simulator_install_failed", message: install.combinedOutput.isEmpty ? "Failed to install the app in the simulator." : install.combinedOutput, phase: "launch"))
            } else {
                let launchEnvironment = simctlEnvironment(endpoint: endpoint, overrides: request.environment)
                let launch = try processRunner.run(
                    command: "xcrun",
                    arguments: ["simctl", "launch", simulatorUDID, bundleIdentifier],
                    environment: launchEnvironment,
                    currentDirectory: workspace.projectRoot,
                    observation: ProcessObservation(label: "simctl launch")
                )
                commandOutput.append(launch.combinedOutput)
                if launch.exitStatus != 0 {
                    anomalies.append(ArtifactAnomaly(code: "simulator_launch_failed", message: launch.combinedOutput.isEmpty ? "Failed to launch the app in the simulator." : launch.combinedOutput, phase: "launch"))
                }
            }
        }

        let endedAt = Date()
        let combinedOutput = commandOutput.filter { !$0.isEmpty }.joined(separator: "\n")
        let record = try artifactManager.recordXcodeExecution(
            workspace: workspace,
            executionContext: executionContext,
            command: .run,
            product: request.product,
            scheme: selector.scheme,
            destination: destination,
            invocation: try renderXcodeRunSequence(
                xcodeRequest: xcodeRequest,
                configuration: launchConfiguration,
                productDetails: resolvedProductDetails
            ),
            exitStatus: buildResult.exitStatus == 0 && anomalies.isEmpty ? 0 : (buildResult.exitStatus == 0 ? 1 : buildResult.exitStatus),
            combinedOutput: combinedOutput,
            startedAt: startedAt,
            endedAt: endedAt,
            extraAnomalies: anomalies
        )

        guard buildResult.exitStatus == 0 else {
            throw SymphonyBuildCommandFailure(message: "The run build step failed.", summaryPath: record.run.summaryPath)
        }
        if !anomalies.isEmpty {
            throw SymphonyBuildCommandFailure(message: "The launch step failed.", summaryPath: record.run.summaryPath)
        }
        return record.run.summaryPath.path
    }

    private func runSwiftPM(
        request: RunCommandRequest,
        workspace: WorkspaceContext,
        selector: SchemeSelector,
        destination: ResolvedDestination,
        executionContext: ExecutionContext
    ) throws -> String {
        let productName = "SymphonyServer"

        if request.dryRun {
            return renderSwiftPMRunSequence(productName: productName, binPath: nil)
        }

        let startedAt = Date()
        let buildResult = try processRunner.run(
            command: "swift",
            arguments: ["build", "--product", productName],
            environment: [:],
            currentDirectory: workspace.projectRoot,
            observation: nil
        )

        var combinedOutput = [buildResult.combinedOutput].filter { !$0.isEmpty }
        var executablePath: String?
        var exitStatus = buildResult.exitStatus
        if buildResult.exitStatus == 0 {
            let binPathResult = try processRunner.run(
                command: "swift",
                arguments: ["build", "--show-bin-path"],
                environment: [:],
                currentDirectory: workspace.projectRoot,
                observation: nil
            )
            if !binPathResult.combinedOutput.isEmpty {
                combinedOutput.append(binPathResult.combinedOutput)
            }
            if binPathResult.exitStatus == 0 {
                let rawBinPath = binPathResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                if !rawBinPath.isEmpty {
                    executablePath = URL(fileURLWithPath: rawBinPath).appendingPathComponent(productName).path
                    let processLog = executionContext.artifactRoot.appendingPathComponent("process-stdout-stderr.txt")
                    let pid = try processRunner.startDetached(
                        executablePath: executablePath!,
                        arguments: [],
                        environment: request.environment,
                        currentDirectory: workspace.projectRoot,
                        output: processLog
                    )
                    combinedOutput.append("launched server pid=\(pid) executable=\(executablePath!)")
                } else {
                    exitStatus = 1
                }
            } else {
                exitStatus = binPathResult.exitStatus
            }
        }

        let endedAt = Date()
        let record = try artifactManager.recordSwiftPMExecution(
            workspace: workspace,
            executionContext: executionContext,
            command: .run,
            product: request.product,
            scheme: selector.scheme,
            destination: destination,
            invocation: renderSwiftPMRunSequence(productName: productName, binPath: executablePath.map { URL(fileURLWithPath: $0).deletingLastPathComponent().path }),
            exitStatus: exitStatus,
            combinedOutput: combinedOutput.joined(separator: "\n"),
            startedAt: startedAt,
            endedAt: endedAt
        )

        guard buildResult.exitStatus == 0 else {
            throw SymphonyBuildCommandFailure(message: "The run build step failed.", summaryPath: record.run.summaryPath)
        }
        guard exitStatus == 0 else {
            throw SymphonyBuildCommandFailure(message: "The launch step failed.", summaryPath: record.run.summaryPath)
        }
        return record.run.summaryPath.path
    }

    public func artifacts(_ request: ArtifactsCommandRequest) throws -> String {
        let workspace = try workspaceDiscovery.discover(from: request.currentDirectory)
        return try artifactManager.resolveArtifacts(workspace: workspace, request: request)
    }

    public func doctor(_ request: DoctorCommandRequest) throws -> String {
        let report = try doctorService.makeReport(from: request)
        if request.strict {
            if !report.issues.isEmpty {
                throw SymphonyBuildCommandFailure(message: try doctorService.render(report: report, json: request.json, quiet: request.quiet))
            }
        } else if !report.isHealthy {
            throw SymphonyBuildCommandFailure(message: try doctorService.render(report: report, json: request.json, quiet: request.quiet))
        }
        return try doctorService.render(report: report, json: request.json, quiet: request.quiet)
    }

    public func harness(_ request: HarnessCommandRequest) throws -> String {
        let workspace = try workspaceDiscovery.discover(from: request.currentDirectory)
        let report = try commitHarness.run(workspace: workspace, request: request)
        if request.json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return String(decoding: try encoder.encode(report), as: UTF8.self)
        }
        return commitHarness.renderHuman(report: report)
    }

    public func hooksInstall(_ request: HooksInstallRequest) throws -> String {
        let workspace = try workspaceDiscovery.discover(from: request.currentDirectory)
        return try gitHookInstaller.install(workspace: workspace)
    }

    public func simList(currentDirectory: URL) throws -> String {
        _ = try workspaceDiscovery.discover(from: currentDirectory)
        return try SimctlSimulatorCatalog(processRunner: processRunner).availableDevices().map { "\($0.name) (\($0.udid))" }.joined(separator: "\n")
    }

    public func simBoot(_ request: SimBootRequest) throws -> String {
        _ = try workspaceDiscovery.discover(from: request.currentDirectory)
        let destination = try simulatorResolver.resolve(destinationSelector(platform: .iosSimulator, simulator: request.simulator)); try simulatorResolver.boot(resolved: destination)
        return destination.displayName
    }

    public func simSetServer(_ request: SimSetServerRequest) throws -> String {
        let workspace = try workspaceDiscovery.discover(from: request.currentDirectory)
        let endpoint = try endpointOverrideStore.resolve(workspace: workspace, serverURL: request.serverURL, scheme: request.scheme, host: request.host, port: request.port)
        let path = try endpointOverrideStore.save(endpoint, in: workspace)
        return path.path
    }

    public func simClearServer(currentDirectory: URL) throws -> String {
        let workspace = try workspaceDiscovery.discover(from: currentDirectory)
        let path = endpointOverrideStore.storeURL(in: workspace); try endpointOverrideStore.clear(in: workspace)
        return path.path
    }

    private func renderSwiftBuildCommandLine(productName: String) -> String { ShellQuoting.render(command: "swift", arguments: ["build", "--product", productName]) }

    private func renderSwiftTestCommandLine(filter: String, enableCodeCoverage: Bool) -> String {
        var arguments = ["test"]; if enableCodeCoverage { arguments.append("--enable-code-coverage") }; arguments += ["--filter", filter]
        return ShellQuoting.render(command: "swift", arguments: arguments)
    }

    private func renderSwiftPMRunSequence(productName: String, binPath: String?) -> String {
        let resolvedBinPath = binPath.map { "\($0)/\(productName)" } ?? "<built-product>/\(productName)"
        return [renderSwiftBuildCommandLine(productName: productName), ShellQuoting.render(command: "swift", arguments: ["build", "--show-bin-path"]), ShellQuoting.render(command: resolvedBinPath, arguments: [])].joined(separator: "\n")
    }

    private func destinationSelector(platform: PlatformKind, simulator: String?) -> DestinationSelector {
        if platform == .iosSimulator, let simulator, looksLikeUDID(simulator) { return DestinationSelector(platform: platform, simulatorName: nil, simulatorUDID: simulator) }
        return DestinationSelector(platform: platform, simulatorName: simulator, simulatorUDID: nil)
    }

    private func looksLikeUDID(_ value: String) -> Bool { value.wholeMatch(of: /^[A-Fa-f0-9-]{36}$/) != nil }

    private func renderXcodeRunSequence(
        xcodeRequest: XcodeCommandRequest,
        configuration: LaunchConfiguration,
        productDetails: ProductDetails?
    ) throws -> String {
        var commands = [try xcodeRequest.renderedCommandLine()]

        if let simulatorUDID = configuration.destination.simulatorUDID {
            commands.append(ShellQuoting.render(command: "xcrun", arguments: ["simctl", "bootstatus", simulatorUDID, "-b"]))
            if let productDetails, let bundleIdentifier = productDetails.bundleIdentifier {
                commands.append(ShellQuoting.render(command: "xcrun", arguments: ["simctl", "install", simulatorUDID, productDetails.productURL.path]))
                let launchEnvironment = simctlEnvironment(endpoint: configuration.endpoint, overrides: configuration.environment)
                let prefix = launchEnvironment
                    .sorted(by: { $0.key < $1.key })
                    .map { "\($0.key)=\(ShellQuoting.quote($0.value))" }
                    .joined(separator: " ")
                let launch = ShellQuoting.render(command: "xcrun", arguments: ["simctl", "launch", simulatorUDID, bundleIdentifier])
                commands.append("\(prefix) \(launch)")
            } else {
                commands.append("xcrun simctl install \(simulatorUDID) <app>")
                commands.append("xcrun simctl launch \(simulatorUDID) <bundle-id>")
            }
        }

        return commands.joined(separator: "\n")
    }

    private func simctlEnvironment(endpoint: RuntimeEndpoint, overrides: [String: String]) -> [String: String] {
        var merged = endpointOverrideStore.clientEnvironment(for: endpoint)
        for (key, value) in overrides {
            merged[key] = value
        }

        var prefixed = [String: String]()
        for (key, value) in merged {
            prefixed["SIMCTL_CHILD_\(key)"] = value
        }
        return prefixed
    }

}
