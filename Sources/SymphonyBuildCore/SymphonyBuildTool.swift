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
        statusSink: @escaping @Sendable (String) -> Void = { message in
            guard let data = (message + "\n").data(using: .utf8) else {
                return
            }
            FileHandle.standardError.write(data)
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
    }

    public func build(_ request: BuildCommandRequest) throws -> String {
        let workspace = try workspaceDiscovery.discover(from: request.currentDirectory)
        let worker = try WorkerScope(id: request.workerID)
        let selector = SchemeSelector(product: request.product, scheme: request.scheme, platform: request.platform)
        let destination = try simulatorResolver.resolve(destinationSelector(platform: selector.platform, simulator: request.simulator))
        let executionContext = try executionContextBuilder.make(workspace: workspace, worker: worker, command: .build, runID: selector.runIdentifier)
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

    public func test(_ request: TestCommandRequest) throws -> String {
        let workspace = try workspaceDiscovery.discover(from: request.currentDirectory)
        let worker = try WorkerScope(id: request.workerID)
        let selector = SchemeSelector(product: request.product, scheme: request.scheme, platform: request.platform)
        let destination = try simulatorResolver.resolve(destinationSelector(platform: selector.platform, simulator: request.simulator))
        let executionContext = try executionContextBuilder.make(workspace: workspace, worker: worker, command: .test, runID: selector.runIdentifier)
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

    public func coverage(_ request: CoverageCommandRequest) throws -> String {
        let workspace = try workspaceDiscovery.discover(from: request.currentDirectory)
        let worker = try WorkerScope(id: request.workerID)
        let selector = SchemeSelector(product: request.product, scheme: request.scheme, platform: request.platform)
        let destination = try simulatorResolver.resolve(destinationSelector(platform: selector.platform, simulator: request.simulator))
        let executionContext = try executionContextBuilder.make(workspace: workspace, worker: worker, command: .coverage, runID: selector.runIdentifier)
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

    public func run(_ request: RunCommandRequest) throws -> String {
        let workspace = try workspaceDiscovery.discover(from: request.currentDirectory)
        let worker = try WorkerScope(id: request.workerID)
        let selector = SchemeSelector(product: request.product, scheme: request.scheme, platform: request.platform)
        let destination = try simulatorResolver.resolve(destinationSelector(platform: selector.platform, simulator: request.simulator))
        let executionContext = try executionContextBuilder.make(workspace: workspace, worker: worker, command: .run, runID: selector.runIdentifier)
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
            target: request.product == .server ? .server : .client,
            scheme: selector.scheme,
            destination: destination,
            endpoint: endpoint,
            environment: request.environment
        )

        if request.dryRun {
            return try renderRunSequence(
                workspace: workspace,
                executionContext: executionContext,
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
            switch request.product {
            case .server:
                let details = try productLocator.locateProduct(workspace: workspace, scheme: selector.scheme, destination: destination, derivedDataPath: executionContext.derivedDataPath)
                resolvedProductDetails = details
                let executable = executableURL(for: details)
                let processLog = executionContext.artifactRoot.appendingPathComponent("process-stdout-stderr.txt")
                let pid = try processRunner.startDetached(
                    executablePath: executable.path,
                    arguments: [],
                    environment: request.environment,
                    currentDirectory: workspace.projectRoot,
                    output: processLog
                )
                commandOutput.append("launched server pid=\(pid) executable=\(executable.path)")
            case .client:
                try simulatorResolver.boot(resolved: destination)
                let details = try productLocator.locateProduct(workspace: workspace, scheme: selector.scheme, destination: destination, derivedDataPath: executionContext.derivedDataPath)
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
            invocation: try renderRunSequence(
                workspace: workspace,
                executionContext: executionContext,
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

    public func simList(currentDirectory: URL) throws -> String {
        _ = try workspaceDiscovery.discover(from: currentDirectory)
        let devices = try simulatorResolverCatalog().availableDevices()
        return devices.map { "\($0.name) (\($0.udid))" }.joined(separator: "\n")
    }

    public func simBoot(_ request: SimBootRequest) throws -> String {
        _ = try workspaceDiscovery.discover(from: request.currentDirectory)
        let destination = try simulatorResolver.resolve(destinationSelector(platform: .iosSimulator, simulator: request.simulator))
        try simulatorResolver.boot(resolved: destination)
        return destination.displayName
    }

    public func simSetServer(_ request: SimSetServerRequest) throws -> String {
        let workspace = try workspaceDiscovery.discover(from: request.currentDirectory)
        let endpoint = try endpointOverrideStore.resolve(
            workspace: workspace,
            serverURL: request.serverURL,
            scheme: request.scheme,
            host: request.host,
            port: request.port
        )
        let path = try endpointOverrideStore.save(endpoint, in: workspace)
        return path.path
    }

    public func simClearServer(currentDirectory: URL) throws -> String {
        let workspace = try workspaceDiscovery.discover(from: currentDirectory)
        let path = endpointOverrideStore.storeURL(in: workspace)
        try endpointOverrideStore.clear(in: workspace)
        return path.path
    }

    private func destinationSelector(platform: PlatformKind, simulator: String?) -> DestinationSelector {
        if platform == .iosSimulator, let simulator, looksLikeUDID(simulator) {
            return DestinationSelector(platform: platform, simulatorName: nil, simulatorUDID: simulator)
        }
        return DestinationSelector(platform: platform, simulatorName: simulator, simulatorUDID: nil)
    }

    private func looksLikeUDID(_ value: String) -> Bool {
        let pattern = /^[A-Fa-f0-9-]{36}$/
        return value.wholeMatch(of: pattern) != nil
    }

    private func renderRunSequence(
        workspace: WorkspaceContext,
        executionContext: ExecutionContext,
        xcodeRequest: XcodeCommandRequest,
        configuration: LaunchConfiguration,
        productDetails: ProductDetails?
    ) throws -> String {
        var commands = [try xcodeRequest.renderedCommandLine()]

        switch configuration.target {
        case .server:
            let executable = productDetails.map(executableURL(for:))?.path ?? "<built-product>"
            commands.append(ShellQuoting.render(command: executable, arguments: []))
        case .client:
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
                    commands.append(prefix.isEmpty ? launch : "\(prefix) \(launch)")
                } else {
                    commands.append("xcrun simctl install \(simulatorUDID) <app>")
                    commands.append("xcrun simctl launch \(simulatorUDID) <bundle-id>")
                }
            }
        }

        return commands.joined(separator: "\n")
    }

    private func executableURL(for details: ProductDetails) -> URL {
        if let executablePath = details.executablePath {
            return details.targetBuildDirectory.appendingPathComponent(executablePath)
        }
        return details.productURL
    }

    private func simctlEnvironment(endpoint: RuntimeEndpoint, overrides: [String: String]) -> [String: String] {
        endpointOverrideStore.clientEnvironment(for: endpoint)
            .merging(overrides, uniquingKeysWith: { _, rhs in rhs })
            .reduce(into: [String: String]()) { partial, pair in
                partial["SIMCTL_CHILD_\(pair.key)"] = pair.value
            }
    }

    private func simulatorResolverCatalog() -> SimulatorCataloging {
        SimctlSimulatorCatalog(processRunner: processRunner)
    }
}
