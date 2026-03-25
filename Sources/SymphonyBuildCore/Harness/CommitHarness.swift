import Foundation

public struct CommitHarnessExecution: Sendable {
    public let report: HarnessReport
    public let clientInspection: CoverageInspectionReport?
    public let serverInspection: CoverageInspectionReport?

    public init(report: HarnessReport, clientInspection: CoverageInspectionReport?, serverInspection: CoverageInspectionReport?) {
        self.report = report
        self.clientInspection = clientInspection
        self.serverInspection = serverInspection
    }
}

public struct CommitHarness {
    private let processRunner: ProcessRunning
    private let coverageReporter: PackageCoverageReporter
    private let statusSink: @Sendable (String) -> Void
    private let clientCoverageLoader: (@Sendable (WorkspaceContext) throws -> CoverageReport)?
    private let serverCoverageLoader: (@Sendable (WorkspaceContext) throws -> CoverageReport)?
    private let toolchainCapabilitiesResolver: ToolchainCapabilitiesResolving

    public init(
        processRunner: ProcessRunning = SystemProcessRunner(),
        coverageReporter: PackageCoverageReporter = PackageCoverageReporter(),
        statusSink: @escaping @Sendable (String) -> Void = { _ in },
        clientCoverageLoader: (@Sendable (WorkspaceContext) throws -> CoverageReport)? = nil,
        serverCoverageLoader: (@Sendable (WorkspaceContext) throws -> CoverageReport)? = nil,
        toolchainCapabilitiesResolver: ToolchainCapabilitiesResolving? = nil
    ) {
        self.processRunner = processRunner
        self.coverageReporter = coverageReporter
        self.statusSink = statusSink
        self.clientCoverageLoader = clientCoverageLoader
        self.serverCoverageLoader = serverCoverageLoader
        self.toolchainCapabilitiesResolver = toolchainCapabilitiesResolver ?? ProcessToolchainCapabilitiesResolver(processRunner: processRunner)
    }

    public func run(workspace: WorkspaceContext, request: HarnessCommandRequest) throws -> HarnessReport {
        let execution = try execute(workspace: workspace, request: request)
        let report = execution.report

        guard report.meetsCoverageThreshold else {
            throw SymphonyBuildCommandFailure(
                message: """
                Commit harness failed because one or more required coverage suites are below the required threshold.
                \(coverageReporter.renderHuman(report: report))
                """
            )
        }

        return report
    }

    public func execute(workspace: WorkspaceContext, request: HarnessCommandRequest) throws -> CommitHarnessExecution {
        guard request.minimumCoveragePercent >= 0, request.minimumCoveragePercent <= 100 else {
            throw SymphonyBuildError(code: "invalid_coverage_threshold", message: "The minimum coverage threshold must be between 0 and 100.")
        }

        let testsInvocation = ShellQuoting.render(command: "swift", arguments: ["test", "--enable-code-coverage"])
        let coveragePathInvocation = ShellQuoting.render(command: "swift", arguments: ["test", "--show-code-coverage-path"])

        statusSink("[symphony-build] running commit harness tests")
        let testResult = try processRunner.run(
            command: "swift",
            arguments: ["test", "--enable-code-coverage"],
            environment: [:],
            currentDirectory: workspace.projectRoot,
            observation: forwardingObservation(label: "swift test")
        )
        guard testResult.exitStatus == 0 else {
            throw SymphonyBuildCommandFailure(message: "Commit harness failed because `swift test --enable-code-coverage` did not pass.")
        }

        let coveragePathResult = try processRunner.run(
            command: "swift",
            arguments: ["test", "--show-code-coverage-path"],
            environment: [:],
            currentDirectory: workspace.projectRoot,
            observation: nil
        )
        guard coveragePathResult.exitStatus == 0 else {
            throw SymphonyBuildCommandFailure(message: "Commit harness failed because SwiftPM did not return a coverage JSON path.")
        }

        let rawPath = coveragePathResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawPath.isEmpty else {
            throw SymphonyBuildError(code: "missing_package_coverage_path", message: "SwiftPM returned an empty coverage JSON path.")
        }

        let coverageReport = try coverageReporter.loadReport(
            at: URL(fileURLWithPath: rawPath),
            projectRoot: workspace.projectRoot
        )
        let clientCoverageInvocation = ShellQuoting.render(
            command: Self.currentExecutablePath(workingDirectory: workspace.projectRoot),
            arguments: [
                "coverage",
                "--product", "client",
                "--platform", "macos",
                "--show-files",
                "--show-functions",
                "--show-missing-lines",
                "--json",
            ]
        )
        let serverCoverageInvocation = ShellQuoting.render(
            command: Self.currentExecutablePath(workingDirectory: workspace.projectRoot),
            arguments: [
                "coverage",
                "--product", "server",
                "--show-files",
                "--show-functions",
                "--show-missing-lines",
                "--json",
            ]
        )
        let capabilities = try toolchainCapabilitiesResolver.resolve()
        let clientExecution: CoverageSuiteExecution?
        let clientCoverageInvocationForReport: String?
        let clientCoverageSkipReason: String?
        if let clientCoverageLoader {
            clientExecution = CoverageSuiteExecution(report: try clientCoverageLoader(workspace), inspection: nil)
            clientCoverageInvocationForReport = clientCoverageInvocation
            clientCoverageSkipReason = nil
        } else if !capabilities.supportsXcodeCommands {
            clientExecution = nil
            clientCoverageInvocationForReport = nil
            clientCoverageSkipReason = Self.noXcodeMessage
        } else {
            clientExecution = try Self.runCoverageSuiteExecution(
                processRunner: processRunner,
                executablePath: Self.currentExecutablePath(workingDirectory: workspace.projectRoot),
                arguments: [
                    "coverage",
                    "--product", "client",
                    "--platform", "macos",
                    "--show-files",
                    "--show-functions",
                    "--show-missing-lines",
                    "--json",
                ],
                currentDirectory: workspace.projectRoot,
                statusSink: statusSink
            )
            clientCoverageInvocationForReport = clientCoverageInvocation
            clientCoverageSkipReason = nil
        }
        let serverExecution: CoverageSuiteExecution
        if let serverCoverageLoader {
            serverExecution = CoverageSuiteExecution(report: try serverCoverageLoader(workspace), inspection: nil)
        } else {
            serverExecution = try Self.runCoverageSuiteExecution(
                processRunner: processRunner,
                executablePath: Self.currentExecutablePath(workingDirectory: workspace.projectRoot),
                arguments: [
                    "coverage",
                    "--product", "server",
                    "--show-files",
                    "--show-functions",
                    "--show-missing-lines",
                    "--json",
                ],
                currentDirectory: workspace.projectRoot,
                statusSink: statusSink
            )
        }
        let clientCoverage = clientExecution?.report
        let serverCoverage = serverExecution.report
        let threshold = request.minimumCoveragePercent / 100
        let packageFileViolations = coverageReporter.makePackageFileViolations(report: coverageReport, minimumLineCoverage: threshold)
        let clientTargetViolations = clientCoverage.map {
            coverageReporter.makeTargetViolations(report: $0, suite: "client", minimumLineCoverage: threshold)
        } ?? []
        let clientFileViolations = clientCoverage.map {
            coverageReporter.makeFileViolations(report: $0, suite: "client", minimumLineCoverage: threshold)
        } ?? []
        let serverTargetViolations = coverageReporter.makeTargetViolations(report: serverCoverage, suite: "server", minimumLineCoverage: threshold)
        let serverFileViolations = coverageReporter.makeFileViolations(report: serverCoverage, suite: "server", minimumLineCoverage: threshold)

        let report = HarnessReport(
            minimumCoveragePercent: request.minimumCoveragePercent,
            testsInvocation: testsInvocation,
            coveragePathInvocation: coveragePathInvocation,
            packageCoverage: coverageReport,
            clientCoverageInvocation: clientCoverageInvocationForReport,
            clientCoverage: clientCoverage,
            clientCoverageSkipReason: clientCoverageSkipReason,
            serverCoverageInvocation: serverCoverageInvocation,
            serverCoverage: serverCoverage,
            packageFileViolations: packageFileViolations,
            clientTargetViolations: clientTargetViolations,
            clientFileViolations: clientFileViolations,
            serverTargetViolations: serverTargetViolations,
            serverFileViolations: serverFileViolations
        )

        return CommitHarnessExecution(
            report: report,
            clientInspection: clientExecution?.inspection,
            serverInspection: serverExecution.inspection
        )
    }

    public func renderHuman(report: HarnessReport) -> String {
        coverageReporter.renderHuman(report: report)
    }

    func forwardingObservation(label: String) -> ProcessObservation {
        ProcessObservation(
            label: label,
            onStaleSignal: { [statusSink] message in
                statusSink(message)
            },
            onLine: { [statusSink] _, line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    return
                }
                statusSink(trimmed)
            }
        )
    }

    static func runCoverageSuite(
        processRunner: ProcessRunning,
        executablePath: String,
        arguments: [String],
        currentDirectory: URL,
        statusSink: @escaping @Sendable (String) -> Void
    ) throws -> CoverageReport {
        try runCoverageSuiteExecution(
            processRunner: processRunner,
            executablePath: executablePath,
            arguments: arguments,
            currentDirectory: currentDirectory,
            statusSink: statusSink
        ).report
    }

    static func runCoverageSuiteExecution(
        processRunner: ProcessRunning,
        executablePath: String,
        arguments: [String],
        currentDirectory: URL,
        statusSink: @escaping @Sendable (String) -> Void
    ) throws -> CoverageSuiteExecution {
        let label = "symphony-build " + arguments.joined(separator: " ")
        let result = try processRunner.run(
            command: executablePath,
            arguments: arguments,
            environment: [:],
            currentDirectory: currentDirectory,
            observation: ProcessObservation(
                label: label,
                onStaleSignal: { message in
                    statusSink(message)
                },
                onLine: { stream, line in
                    guard stream == .stderr else {
                        return
                    }
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else {
                        return
                    }
                    statusSink(trimmed)
                }
            )
        )

        guard result.exitStatus == 0 else {
            throw SymphonyBuildCommandFailure(
                message: "Commit harness failed because `\(ShellQuoting.render(command: executablePath, arguments: arguments))` did not pass."
            )
        }
        guard !result.stdout.isEmpty else {
            throw SymphonyBuildError(code: "missing_bootstrap_coverage_json", message: "The coverage command did not emit JSON output.")
        }

        do {
            let data = Data(result.stdout.utf8)
            if let wrapped = try? JSONDecoder().decode(CoverageInspectionResponse.self, from: data) {
                let inspection: CoverageInspectionReport?
                switch wrapped.inspection {
                case .normalized(let report):
                    inspection = report
                case .raw:
                    inspection = nil
                }
                return CoverageSuiteExecution(report: wrapped.coverage, inspection: inspection)
            }
            return CoverageSuiteExecution(report: try JSONDecoder().decode(CoverageReport.self, from: data), inspection: nil)
        } catch {
            throw SymphonyBuildError(code: "bootstrap_coverage_decode_failed", message: "The coverage command JSON output could not be decoded.")
        }
    }

    static func currentExecutablePath(workingDirectory: URL) -> String {
        var rawPath = ProcessInfo.processInfo.processName
        if let firstArgument = CommandLine.arguments.first {
            rawPath = firstArgument
        }
        return resolvedExecutablePath(raw: rawPath, workingDirectory: workingDirectory)
    }

    static func resolvedExecutablePath(raw: String, workingDirectory: URL) -> String {
        if raw.hasPrefix("/") {
            return raw
        }
        return URL(fileURLWithPath: raw, relativeTo: workingDirectory).standardizedFileURL.path
    }
}

private extension CommitHarness {
    static let noXcodeMessage = "not supported because the current environment has no Xcode available; Editing those sources is not encouraged"
}

struct CoverageSuiteExecution: Sendable {
    let report: CoverageReport
    let inspection: CoverageInspectionReport?
}

public struct GitHookInstaller {
    private let processRunner: ProcessRunning

    public init(processRunner: ProcessRunning = SystemProcessRunner()) {
        self.processRunner = processRunner
    }

    public func install(workspace: WorkspaceContext) throws -> String {
        let result = try processRunner.run(
            command: "git",
            arguments: ["config", "core.hooksPath", ".githooks"],
            environment: [:],
            currentDirectory: workspace.projectRoot,
            observation: nil
        )

        guard result.exitStatus == 0 else {
            throw SymphonyBuildError(
                code: "git_hooks_install_failed",
                message: result.combinedOutput.isEmpty ? "Failed to configure core.hooksPath." : result.combinedOutput
            )
        }

        return workspace.projectRoot.appendingPathComponent(".githooks", isDirectory: true).path
    }
}
