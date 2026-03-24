import Foundation

public struct CommitHarness {
    private let processRunner: ProcessRunning
    private let coverageReporter: PackageCoverageReporter
    private let statusSink: @Sendable (String) -> Void

    public init(
        processRunner: ProcessRunning = SystemProcessRunner(),
        coverageReporter: PackageCoverageReporter = PackageCoverageReporter(),
        statusSink: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.processRunner = processRunner
        self.coverageReporter = coverageReporter
        self.statusSink = statusSink
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

        let report = HarnessReport(
            minimumCoveragePercent: request.minimumCoveragePercent,
            testsInvocation: testsInvocation,
            coveragePathInvocation: coveragePathInvocation,
            packageCoverage: coverageReport
        )

        guard report.meetsCoverageThreshold else {
            throw SymphonyBuildCommandFailure(
                message: """
                Commit harness failed because first-party package coverage is below the required threshold.
                \(coverageReporter.renderHuman(report: report))
                """
            )
        }

        return report
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
