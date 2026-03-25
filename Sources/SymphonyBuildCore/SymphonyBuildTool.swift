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
    private let toolchainCapabilitiesResolver: ToolchainCapabilitiesResolving
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
        doctorService: DoctorServicing? = nil,
        toolchainCapabilitiesResolver: ToolchainCapabilitiesResolving? = nil,
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
        let resolvedToolchainCapabilitiesResolver = toolchainCapabilitiesResolver ?? ProcessToolchainCapabilitiesResolver(processRunner: processRunner)
        self.toolchainCapabilitiesResolver = resolvedToolchainCapabilitiesResolver
        self.doctorService = doctorService ?? DoctorService(
            workspaceDiscovery: workspaceDiscovery,
            processRunner: processRunner,
            toolchainCapabilitiesResolver: resolvedToolchainCapabilitiesResolver
        )
        self.productLocator = productLocator
        self.statusSink = statusSink
        self.commitHarness = commitHarness ?? CommitHarness(
            processRunner: processRunner,
            statusSink: statusSink,
            toolchainCapabilitiesResolver: resolvedToolchainCapabilitiesResolver
        )
        self.gitHookInstaller = gitHookInstaller ?? GitHookInstaller(processRunner: processRunner)
    }

    public func build(_ request: BuildCommandRequest) throws -> String {
        let workspace = try workspaceDiscovery.discover(from: request.currentDirectory)
        let worker = try WorkerScope(id: request.workerID)
        let selector = SchemeSelector(product: request.product, scheme: request.scheme, platform: request.platform)
        let executionContext = try executionContextBuilder.make(workspace: workspace, worker: worker, command: .build, runID: selector.runIdentifier)
        switch selector.product.defaultBackend {
        case .xcode:
            if !request.dryRun {
                try ensureXcodeSupport(for: selector.platform)
            }
            let destination = try xcodeDestination(platform: selector.platform, simulator: request.simulator, dryRun: request.dryRun)
            return try buildXcode(
                request: request,
                workspace: workspace,
                selector: selector,
                destination: destination,
                executionContext: executionContext
            )
        case .swiftPM:
            let destination = try simulatorResolver.resolve(destinationSelector(platform: selector.platform, simulator: request.simulator))
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
        let executionContext = try executionContextBuilder.make(workspace: workspace, worker: worker, command: .test, runID: selector.runIdentifier)
        switch selector.product.defaultBackend {
        case .xcode:
            if !request.dryRun {
                try ensureXcodeSupport(for: selector.platform)
            }
            let destination = try xcodeDestination(platform: selector.platform, simulator: request.simulator, dryRun: request.dryRun)
            return try testXcode(
                request: request,
                workspace: workspace,
                selector: selector,
                destination: destination,
                executionContext: executionContext
            )
        case .swiftPM:
            let destination = try simulatorResolver.resolve(destinationSelector(platform: selector.platform, simulator: request.simulator))
            return try testSwiftPM(
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
        let executionContext = try executionContextBuilder.make(workspace: workspace, worker: worker, command: .run, runID: selector.runIdentifier)
        switch selector.product.defaultBackend {
        case .xcode:
            if !request.dryRun {
                try ensureXcodeSupport(for: selector.platform)
            }
            let destination = try xcodeDestination(platform: selector.platform, simulator: request.simulator, dryRun: request.dryRun)
            return try runXcode(
                request: request,
                workspace: workspace,
                selector: selector,
                destination: destination,
                executionContext: executionContext
            )
        case .swiftPM:
            let destination = try simulatorResolver.resolve(destinationSelector(platform: selector.platform, simulator: request.simulator))
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
            observation: reporter.makeObservation(label: "xcodebuild test")
        )
        let endedAt = Date()

        var coverageAnomalies = [ArtifactAnomaly]()
        if result.exitStatus == 0 {
            do {
                let exportedArtifacts = try coverageReporter.export(
                    resultBundlePath: executionContext.resultBundlePath,
                    artifactRoot: executionContext.artifactRoot,
                    product: request.product,
                    includeTestTargets: false,
                    showFiles: true
                )
                _ = try displayedCoverageArtifacts(
                    from: exportedArtifacts,
                    showFiles: true,
                    artifactRoot: executionContext.artifactRoot
                )

                let inspection = try XcodeCoverageInspector(processRunner: processRunner).inspect(
                    resultBundlePath: executionContext.resultBundlePath,
                    candidates: inspectionCandidates(from: exportedArtifacts.report),
                    includeFunctions: true,
                    includeMissingLines: true
                )
                let normalizedInspection = CoverageInspectionReport(
                    backend: .xcode,
                    product: request.product,
                    generatedAt: DateFormatting.iso8601(endedAt),
                    files: inspection.files
                )
                let rawInspection = CoverageInspectionRawReport(
                    backend: .xcode,
                    product: request.product,
                    commands: inspection.rawCommands
                )
                try writeCoverageInspectionArtifacts(
                    artifactRoot: executionContext.artifactRoot,
                    normalizedReport: normalizedInspection,
                    rawReport: rawInspection
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
            command: .test,
            product: request.product,
            scheme: selector.scheme,
            destination: destination,
            invocation: [
                try xcodeRequest.renderedCommandLine(),
                coverageCommand,
            ].joined(separator: "\n"),
            exitStatus: result.exitStatus,
            combinedOutput: result.combinedOutput,
            startedAt: startedAt,
            endedAt: endedAt,
            extraAnomalies: coverageAnomalies
        )

        guard result.exitStatus == 0 else {
            throw SymphonyBuildCommandFailure(message: "xcodebuild test failed.", summaryPath: record.run.summaryPath)
        }
        return record.run.artifactRoot.path
    }

    private func testSwiftPM(
        request: TestCommandRequest,
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

                let exportedArtifacts = try SwiftPMCoverageReporter().exportServerCoverage(
                    coverageJSONPath: URL(fileURLWithPath: rawPath),
                    projectRoot: workspace.projectRoot,
                    artifactRoot: executionContext.artifactRoot,
                    showFiles: true
                )
                _ = try displayedCoverageArtifacts(
                    from: exportedArtifacts,
                    showFiles: true,
                    artifactRoot: executionContext.artifactRoot
                )

                let inspection = try SwiftPMCoverageInspector(
                    processRunner: processRunner,
                    llvmCovCommand: try toolchainCapabilitiesResolver.resolve().llvmCovCommand
                ).inspect(
                    coverageJSONPath: URL(fileURLWithPath: rawPath),
                    projectRoot: workspace.projectRoot,
                    candidates: inspectionCandidates(from: exportedArtifacts.report),
                    includeFunctions: true,
                    includeMissingLines: true
                )
                let normalizedInspection = CoverageInspectionReport(
                    backend: .swiftPM,
                    product: request.product,
                    generatedAt: DateFormatting.iso8601(Date()),
                    files: inspection.files
                )
                let rawInspection = CoverageInspectionRawReport(
                    backend: .swiftPM,
                    product: request.product,
                    commands: inspection.rawCommands
                )
                try writeCoverageInspectionArtifacts(
                    artifactRoot: executionContext.artifactRoot,
                    normalizedReport: normalizedInspection,
                    rawReport: rawInspection
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
            command: .test,
            product: request.product,
            scheme: selector.scheme,
            destination: destination,
            invocation: [coverageCommand, coveragePathCommand].joined(separator: "\n"),
            exitStatus: result.exitStatus,
            combinedOutput: [result.combinedOutput, coveragePathOutput].filter { !$0.isEmpty }.joined(separator: "\n"),
            startedAt: startedAt,
            endedAt: endedAt,
            extraAnomalies: coverageAnomalies
        )

        guard result.exitStatus == 0 else {
            throw SymphonyBuildCommandFailure(message: "swift test failed.", summaryPath: record.run.summaryPath)
        }
        return record.run.artifactRoot.path
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
        let startedAt = Date()
        let execution = try commitHarness.execute(workspace: workspace, request: request)
        let generatedAt = DateFormatting.iso8601(Date())
        let worker = try WorkerScope(id: 0)
        let executionContext = try executionContextBuilder.make(
            workspace: workspace,
            worker: worker,
            command: .harness,
            runID: "commit-harness"
        )

        let packageInspection = try makePackageHarnessInspectionArtifact(
            workspace: workspace,
            report: execution.report.packageCoverage,
            generatedAt: generatedAt
        )
        let clientInspection = HarnessCoverageInspectionArtifact(
            suite: "client",
            backend: ProductKind.client.defaultBackend,
            generatedAt: generatedAt,
            files: execution.clientInspection?.files ?? [],
            skippedReason: execution.report.clientCoverageSkipReason
        )
        let serverInspection = HarnessCoverageInspectionArtifact(
            suite: "server",
            backend: ProductKind.server.defaultBackend,
            generatedAt: generatedAt,
            files: execution.serverInspection?.files ?? []
        )

        try writeHarnessInspectionArtifacts(
            packageInspection: packageInspection,
            clientInspection: clientInspection,
            serverInspection: serverInspection,
            artifactRoot: executionContext.artifactRoot
        )

        let reportJSON = try encodePrettyJSON(execution.report)
        let summaryText = commitHarness.renderHuman(report: execution.report)
        let endedAt = Date()
        let record = try artifactManager.recordHarnessExecution(
            workspace: workspace,
            executionContext: executionContext,
            invocation: renderedHarnessCommandLine(request: request),
            exitStatus: execution.report.meetsCoverageThreshold ? 0 : 1,
            summaryJSON: reportJSON,
            summaryText: summaryText,
            startedAt: startedAt,
            endedAt: endedAt
        )

        guard execution.report.meetsCoverageThreshold else {
            throw SymphonyBuildCommandFailure(
                message: compactHarnessFailureMessage(report: execution.report, artifactRoot: record.run.artifactRoot),
                summaryPath: record.run.summaryPath
            )
        }

        return request.json ? reportJSON : summaryText
    }

    public func hooksInstall(_ request: HooksInstallRequest) throws -> String {
        let workspace = try workspaceDiscovery.discover(from: request.currentDirectory)
        return try gitHookInstaller.install(workspace: workspace)
    }

    public func simList(currentDirectory: URL) throws -> String {
        _ = try workspaceDiscovery.discover(from: currentDirectory)
        try ensureXcodeSupport(for: .iosSimulator)
        return try SimctlSimulatorCatalog(processRunner: processRunner).availableDevices().map { "\($0.name) (\($0.udid))" }.joined(separator: "\n")
    }

    public func simBoot(_ request: SimBootRequest) throws -> String {
        _ = try workspaceDiscovery.discover(from: request.currentDirectory)
        try ensureXcodeSupport(for: .iosSimulator)
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

    private func makePackageHarnessInspectionArtifact(
        workspace: WorkspaceContext,
        report: PackageCoverageReport,
        generatedAt: String
    ) throws -> HarnessCoverageInspectionArtifact {
        let candidates = report.files.compactMap { file -> CoverageInspectionFileCandidate? in
            guard file.executableLines > 0, file.coveredLines < file.executableLines else {
                return nil
            }
            let components = file.path.split(separator: "/")
            let targetName = components.count > 2 ? String(components[1]) : "Sources"
            return CoverageInspectionFileCandidate(
                targetName: targetName,
                path: file.path,
                coveredLines: file.coveredLines,
                executableLines: file.executableLines,
                lineCoverage: file.lineCoverage
            )
        }
        let inspection: CoverageInspectionResult
        do {
            inspection = try SwiftPMCoverageInspector(
                processRunner: processRunner,
                llvmCovCommand: try toolchainCapabilitiesResolver.resolve().llvmCovCommand
            ).inspect(
                coverageJSONPath: URL(fileURLWithPath: report.coverageJSONPath),
                projectRoot: workspace.projectRoot,
                candidates: candidates,
                includeFunctions: true,
                includeMissingLines: true
            )
        } catch let error as SymphonyBuildError
            where error.code == "missing_swiftpm_profdata" || error.code == "missing_swiftpm_test_binary" || error.code == "missing_llvm_cov" {
            inspection = CoverageInspectionResult(files: [], rawCommands: [])
        }
        return HarnessCoverageInspectionArtifact(
            suite: "package",
            backend: .swiftPM,
            generatedAt: generatedAt,
            files: inspection.files
        )
    }

    private func writeHarnessInspectionArtifacts(
        packageInspection: HarnessCoverageInspectionArtifact,
        clientInspection: HarnessCoverageInspectionArtifact,
        serverInspection: HarnessCoverageInspectionArtifact,
        artifactRoot: URL
    ) throws {
        try FileManager.default.createDirectory(at: artifactRoot, withIntermediateDirectories: true)
        try (encodePrettyJSON(packageInspection) + "\n").write(
            to: artifactRoot.appendingPathComponent("package-inspection.json"),
            atomically: true,
            encoding: .utf8
        )
        try (renderHarnessInspectionHuman(artifact: packageInspection) + "\n").write(
            to: artifactRoot.appendingPathComponent("package-inspection.txt"),
            atomically: true,
            encoding: .utf8
        )
        try (encodePrettyJSON(clientInspection) + "\n").write(
            to: artifactRoot.appendingPathComponent("client-inspection.json"),
            atomically: true,
            encoding: .utf8
        )
        try (renderHarnessInspectionHuman(artifact: clientInspection) + "\n").write(
            to: artifactRoot.appendingPathComponent("client-inspection.txt"),
            atomically: true,
            encoding: .utf8
        )
        try (encodePrettyJSON(serverInspection) + "\n").write(
            to: artifactRoot.appendingPathComponent("server-inspection.json"),
            atomically: true,
            encoding: .utf8
        )
        try (renderHarnessInspectionHuman(artifact: serverInspection) + "\n").write(
            to: artifactRoot.appendingPathComponent("server-inspection.txt"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func displayedCoverageArtifacts(
        from artifacts: CoverageArtifacts,
        showFiles: Bool,
        artifactRoot: URL
    ) throws -> CoverageArtifacts {
        let report = showFiles ? artifacts.report : strippedCoverageReport(artifacts.report)
        let jsonOutput = try encodePrettyJSON(report)
        let textOutput = CoverageReporter().renderHuman(report: report)
        try (jsonOutput + "\n").write(to: artifactRoot.appendingPathComponent("coverage.json"), atomically: true, encoding: .utf8)
        try (textOutput + "\n").write(to: artifactRoot.appendingPathComponent("coverage.txt"), atomically: true, encoding: .utf8)
        return CoverageArtifacts(
            report: report,
            jsonPath: artifactRoot.appendingPathComponent("coverage.json"),
            textPath: artifactRoot.appendingPathComponent("coverage.txt"),
            jsonOutput: jsonOutput,
            textOutput: textOutput
        )
    }

    private func writeCoverageInspectionArtifacts(
        artifactRoot: URL,
        normalizedReport: CoverageInspectionReport,
        rawReport: CoverageInspectionRawReport
    ) throws {
        let normalizedJSON = try encodePrettyJSON(normalizedReport)
        let normalizedText = renderInspectionHuman(report: normalizedReport)
        try (normalizedJSON + "\n").write(
            to: artifactRoot.appendingPathComponent("coverage-inspection.json"),
            atomically: true,
            encoding: .utf8
        )
        try (normalizedText + "\n").write(
            to: artifactRoot.appendingPathComponent("coverage-inspection.txt"),
            atomically: true,
            encoding: .utf8
        )

        let rawJSON = try encodePrettyJSON(rawReport)
        let rawText = renderRawInspectionHuman(report: rawReport)
        try (rawJSON + "\n").write(
            to: artifactRoot.appendingPathComponent("coverage-inspection-raw.json"),
            atomically: true,
            encoding: .utf8
        )
        try (rawText + "\n").write(
            to: artifactRoot.appendingPathComponent("coverage-inspection-raw.txt"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func renderedHarnessCommandLine(request: HarnessCommandRequest) -> String {
        var arguments = ["harness", "--minimum-coverage", String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), request.minimumCoveragePercent)]
        if request.json {
            arguments.append("--json")
        }
        if request.outputMode != .filtered {
            arguments += ["--output-mode", request.outputMode.rawValue]
        }
        return ShellQuoting.render(command: "symphony-build", arguments: arguments)
    }

    private func compactHarnessFailureMessage(report: HarnessReport, artifactRoot: URL) -> String {
        let preview = report.violations.prefix(3).map { violation in
            let percentage = String(format: "%.2f%%", locale: Locale(identifier: "en_US_POSIX"), violation.lineCoverage * 100)
            return "\(violation.suite) \(violation.kind) \(violation.name) \(percentage) (\(violation.coveredLines)/\(violation.executableLines))"
        }
        let previewLines = preview.isEmpty ? [] : preview
        return (
            [
                "Commit harness failed because one or more required coverage suites are below the required threshold.",
            ] + previewLines + [
                "Harness artifacts: \(artifactRoot.path)",
            ]
        ).joined(separator: "\n")
    }

    private func ensureXcodeSupport(for platform: PlatformKind) throws {
        let capabilities = try toolchainCapabilitiesResolver.resolve()
        guard capabilities.supportsXcodeCommands else {
            throw SymphonyBuildCommandFailure(message: Self.noXcodeMessage)
        }
        if platform == .iosSimulator, !capabilities.supportsSimulatorCommands {
            throw SymphonyBuildCommandFailure(message: Self.noXcodeMessage)
        }
    }

    private func xcodeDestination(platform: PlatformKind, simulator: String?, dryRun: Bool) throws -> ResolvedDestination {
        if dryRun {
            let capabilities = try toolchainCapabilitiesResolver.resolve()
            if !capabilities.supportsXcodeCommands || (platform == .iosSimulator && !capabilities.supportsSimulatorCommands) {
                return assumedDryRunDestination(platform: platform, simulator: simulator)
            }
        }
        return try simulatorResolver.resolve(destinationSelector(platform: platform, simulator: simulator))
    }

    private func assumedDryRunDestination(platform: PlatformKind, simulator: String?) -> ResolvedDestination {
        switch platform {
        case .macos:
            return ResolvedDestination(
                platform: .macos,
                displayName: "macOS",
                simulatorName: nil,
                simulatorUDID: nil,
                xcodeDestination: expectedHostMacOSDestination()
            )
        case .iosSimulator:
            if let simulator, looksLikeUDID(simulator) {
                return ResolvedDestination(
                    platform: .iosSimulator,
                    displayName: simulator,
                    simulatorName: nil,
                    simulatorUDID: simulator,
                    xcodeDestination: "platform=iOS Simulator,id=\(simulator)"
                )
            }
            let simulatorName = simulator ?? "iPhone 17"
            return ResolvedDestination(
                platform: .iosSimulator,
                displayName: simulatorName,
                simulatorName: simulatorName,
                simulatorUDID: nil,
                xcodeDestination: "platform=iOS Simulator,name=\(simulatorName)"
            )
        }
    }

    private func destinationSelector(platform: PlatformKind, simulator: String?) -> DestinationSelector {
        if platform == .iosSimulator, let simulator, looksLikeUDID(simulator) { return DestinationSelector(platform: platform, simulatorName: nil, simulatorUDID: simulator) }
        return DestinationSelector(platform: platform, simulatorName: simulator, simulatorUDID: nil)
    }

    private func looksLikeUDID(_ value: String) -> Bool { value.wholeMatch(of: /^[A-Fa-f0-9-]{36}$/) != nil }

    private func expectedHostMacOSDestination() -> String {
        #if arch(arm64)
        "platform=macOS,arch=arm64"
        #elseif arch(x86_64)
        "platform=macOS,arch=x86_64"
        #else
        "platform=macOS"
        #endif
    }

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

private extension SymphonyBuildTool {
    static let noXcodeMessage = "not supported because the current environment has no Xcode available; Editing those sources is not encouraged"
}
