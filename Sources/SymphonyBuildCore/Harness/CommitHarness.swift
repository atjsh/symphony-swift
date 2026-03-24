import Foundation

public struct CommitHarness {
    private let processRunner: ProcessRunning
    private let coverageReporter: PackageCoverageReporter
    private let statusSink: @Sendable (String) -> Void
    private let clientCoverageLoader: @Sendable (WorkspaceContext) throws -> CoverageReport
    private let serverCoverageLoader: @Sendable (WorkspaceContext) throws -> CoverageReport

    public init(
        processRunner: ProcessRunning = SystemProcessRunner(),
        coverageReporter: PackageCoverageReporter = PackageCoverageReporter(),
        statusSink: @escaping @Sendable (String) -> Void = { _ in },
        clientCoverageLoader: (@Sendable (WorkspaceContext) throws -> CoverageReport)? = nil,
        serverCoverageLoader: (@Sendable (WorkspaceContext) throws -> CoverageReport)? = nil
    ) {
        self.processRunner = processRunner
        self.coverageReporter = coverageReporter
        self.statusSink = statusSink
        self.clientCoverageLoader = clientCoverageLoader ?? { workspace in
            try Self.runCoverageSuite(
                processRunner: processRunner,
                executablePath: Self.currentExecutablePath(workingDirectory: workspace.projectRoot),
                arguments: ["coverage", "--product", "client", "--platform", "macos", "--json"],
                currentDirectory: workspace.projectRoot,
                statusSink: statusSink
            )
        }
        self.serverCoverageLoader = serverCoverageLoader ?? { workspace in
            try Self.runCoverageSuite(
                processRunner: processRunner,
                executablePath: Self.currentExecutablePath(workingDirectory: workspace.projectRoot),
                arguments: ["coverage", "--product", "server", "--json"],
                currentDirectory: workspace.projectRoot,
                statusSink: statusSink
            )
        }
    }

    public func run(workspace: WorkspaceContext, request: HarnessCommandRequest) throws -> HarnessReport {
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
            arguments: ["coverage", "--product", "client", "--platform", "macos", "--json"]
        )
        let serverCoverageInvocation = ShellQuoting.render(
            command: Self.currentExecutablePath(workingDirectory: workspace.projectRoot),
            arguments: ["coverage", "--product", "server", "--json"]
        )
        let clientCoverage = try clientCoverageLoader(workspace)
        let serverCoverage = try serverCoverageLoader(workspace)

        let report = HarnessReport(
            minimumCoveragePercent: request.minimumCoveragePercent,
            testsInvocation: testsInvocation,
            coveragePathInvocation: coveragePathInvocation,
            packageCoverage: coverageReport,
            clientCoverageInvocation: clientCoverageInvocation,
            clientCoverage: clientCoverage,
            serverCoverageInvocation: serverCoverageInvocation,
            serverCoverage: serverCoverage
        )

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

    public func renderHuman(report: HarnessReport) -> String {
        coverageReporter.renderHuman(report: report)
    }

    private func forwardingObservation(label: String) -> ProcessObservation {
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

    private static func runCoverageSuite(
        processRunner: ProcessRunning,
        executablePath: String,
        arguments: [String],
        currentDirectory: URL,
        statusSink: @escaping @Sendable (String) -> Void
    ) throws -> CoverageReport {
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
            return try JSONDecoder().decode(CoverageReport.self, from: Data(result.stdout.utf8))
        } catch {
            throw SymphonyBuildError(code: "bootstrap_coverage_decode_failed", message: "The coverage command JSON output could not be decoded.")
        }
    }

    private static func currentExecutablePath(workingDirectory: URL) -> String {
        let raw = CommandLine.arguments.first ?? "symphony-build"
        if raw.hasPrefix("/") {
            return raw
        }
        return URL(fileURLWithPath: raw, relativeTo: workingDirectory).standardizedFileURL.path
    }
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
