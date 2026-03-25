import Foundation

public struct CoverageArtifacts: Sendable {
    public let report: CoverageReport
    public let jsonPath: URL
    public let textPath: URL
    public let jsonOutput: String
    public let textOutput: String

    public init(report: CoverageReport, jsonPath: URL, textPath: URL, jsonOutput: String, textOutput: String) { self.report = report; self.jsonPath = jsonPath; self.textPath = textPath; self.jsonOutput = jsonOutput; self.textOutput = textOutput }
}

public struct CoverageReporter {
    private let processRunner: ProcessRunning
    private let fileManager: FileManager

    public init(processRunner: ProcessRunning = SystemProcessRunner(), fileManager: FileManager = .default) { self.processRunner = processRunner; self.fileManager = fileManager }

    public func renderedCommandLine(resultBundlePath: URL) -> String { ShellQuoting.render(command: "xcrun", arguments: ["xccov", "view", "--report", "--json", resultBundlePath.path]) }

    public func export(
        resultBundlePath: URL,
        artifactRoot: URL,
        product: ProductKind,
        includeTestTargets: Bool,
        showFiles: Bool
    ) throws -> CoverageArtifacts {
        let result = try processRunner.run(
            command: "xcrun",
            arguments: ["xccov", "view", "--report", "--json", resultBundlePath.path],
            environment: [:],
            currentDirectory: nil
        )

        guard result.exitStatus == 0, !result.stdout.isEmpty else {
            throw SymphonyBuildError(
                code: "coverage_export_failed",
                message: result.combinedOutput.isEmpty ? "Failed to export coverage from the xcresult bundle." : result.combinedOutput
            )
        }

        let decoder = JSONDecoder()
        let rawReport: RawCoverageReport
        do {
            rawReport = try decoder.decode(RawCoverageReport.self, from: Data(result.stdout.utf8))
        } catch {
            throw SymphonyBuildError(code: "coverage_report_decode_failed", message: "The xccov JSON output could not be decoded.")
        }

        let filteredTargets = rawReport.targets.filter { target in
            if !includeTestTargets, target.isTestBundle {
                return false
            }
            if product == .client, target.isSwiftPackageProduct {
                return false
            }
            return true
        }
        let excludedTargets = rawReport.targets
            .filter { candidate in !filteredTargets.contains(where: { $0.name == candidate.name && $0.buildProductPath == candidate.buildProductPath }) }
            .map(\.name)
        let includedTargets = filteredTargets
        guard !includedTargets.isEmpty else { throw SymphonyBuildError(code: "coverage_targets_missing", message: includeTestTargets ? "The xcresult bundle did not contain any coverage targets." : "The xcresult bundle did not contain any non-test coverage targets.") }

        let targets = includedTargets.map { target in
            CoverageTargetReport(
                name: target.name,
                buildProductPath: target.buildProductPath,
                coveredLines: target.coveredLines,
                executableLines: target.executableLines,
                lineCoverage: Self.normalizedCoverage(coveredLines: target.coveredLines, executableLines: target.executableLines),
                files: showFiles ? target.files.map { file in
                    CoverageFileReport(
                        name: file.name,
                        path: file.path,
                        coveredLines: file.coveredLines,
                        executableLines: file.executableLines,
                        lineCoverage: Self.normalizedCoverage(coveredLines: file.coveredLines, executableLines: file.executableLines)
                    )
                } : nil
            )
        }

        let coveredLines = targets.reduce(0) { $0 + $1.coveredLines }
        let executableLines = targets.reduce(0) { $0 + $1.executableLines }
        let report = CoverageReport(
            coveredLines: coveredLines,
            executableLines: executableLines,
            lineCoverage: Self.normalizedCoverage(coveredLines: coveredLines, executableLines: executableLines),
            includeTestTargets: includeTestTargets,
            excludedTargets: excludedTargets,
            targets: targets
        )

        try fileManager.createDirectory(at: artifactRoot, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(report)
        let jsonOutput = String(decoding: jsonData, as: UTF8.self)
        let textOutput = renderHuman(report: report)

        let jsonPath = artifactRoot.appendingPathComponent("coverage.json")
        let textPath = artifactRoot.appendingPathComponent("coverage.txt")
        try (jsonOutput + "\n").write(to: jsonPath, atomically: true, encoding: .utf8)
        try (textOutput + "\n").write(to: textPath, atomically: true, encoding: .utf8)

        return CoverageArtifacts(
            report: report,
            jsonPath: jsonPath,
            textPath: textPath,
            jsonOutput: jsonOutput,
            textOutput: textOutput
        )
    }

    func renderHuman(report: CoverageReport) -> String {
        var lines = [
            "overall \(percentage(report.lineCoverage)) (\(report.coveredLines)/\(report.executableLines))",
            report.includeTestTargets ? "scope including_test_targets" : "scope excluding_test_targets",
        ]

        if !report.excludedTargets.isEmpty {
            lines.append("excluded_targets \(report.excludedTargets.joined(separator: ", "))")
        }

        for target in report.targets {
            lines.append("target \(target.name) \(percentage(target.lineCoverage)) (\(target.coveredLines)/\(target.executableLines))")
            if let files = target.files {
                for file in files {
                    lines.append("file \(target.name) \(file.name) \(percentage(file.lineCoverage)) (\(file.coveredLines)/\(file.executableLines))")
                }
            }
        }

        return lines.joined(separator: "\n")
    }

    static func normalizedCoverage(coveredLines: Int, executableLines: Int) -> Double { executableLines > 0 ? Double(coveredLines) / Double(executableLines) : 0 }

    private func percentage(_ coverage: Double) -> String { String(format: "%.2f%%", locale: Locale(identifier: "en_US_POSIX"), coverage * 100) }
}

private struct RawCoverageReport: Decodable {
    let targets: [RawCoverageTarget]
}

private struct RawCoverageTarget: Decodable {
    let buildProductPath: String?
    let coveredLines: Int
    let executableLines: Int
    let files: [RawCoverageFile]
    let name: String

    var isTestBundle: Bool { name.hasSuffix(".xctest") || buildProductPath?.contains(".xctest/") == true }
    var isSwiftPackageProduct: Bool { buildProductPath?.contains("/PackageFrameworks/") == true }
}

private struct RawCoverageFile: Decodable {
    let coveredLines: Int
    let executableLines: Int
    let name: String
    let path: String
}
