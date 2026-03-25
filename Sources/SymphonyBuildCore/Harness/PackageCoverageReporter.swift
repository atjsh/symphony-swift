import Foundation

public struct PackageCoverageReporter {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func loadReport(at coverageJSONPath: URL, projectRoot: URL) throws -> PackageCoverageReport {
        guard fileManager.fileExists(atPath: coverageJSONPath.path) else {
            throw SymphonyBuildError(code: "missing_package_coverage_json", message: "SwiftPM did not produce a coverage JSON file at \(coverageJSONPath.path).")
        }

        let data = try Data(contentsOf: coverageJSONPath)
        let export: RawPackageCoverageExport
        do {
            export = try JSONDecoder().decode(RawPackageCoverageExport.self, from: data)
        } catch {
            throw SymphonyBuildError(code: "package_coverage_decode_failed", message: "SwiftPM coverage JSON could not be decoded.")
        }

        let sourcesRoot = projectRoot.resolvingSymlinksInPath().appendingPathComponent("Sources", isDirectory: true).path + "/"
        let files = export.data
            .flatMap(\.files)
            .compactMap { file -> PackageCoverageFileReport? in
                guard file.filename.hasPrefix(sourcesRoot) else {
                    return nil
                }
                let executableLines = file.summary.lines.count
                guard executableLines > 0 else {
                    return nil
                }

                let relativePath = String(file.filename.dropFirst(projectRoot.resolvingSymlinksInPath().path.count + 1))
                let coveredLines = file.summary.lines.covered
                return PackageCoverageFileReport(
                    path: relativePath,
                    coveredLines: coveredLines,
                    executableLines: executableLines,
                    lineCoverage: Self.normalizedCoverage(coveredLines: coveredLines, executableLines: executableLines)
                )
            }
            .sorted(by: Self.packageFileSort)

        guard !files.isEmpty else {
            throw SymphonyBuildError(code: "package_coverage_sources_missing", message: "SwiftPM coverage did not include any first-party files under Sources/.")
        }

        let coveredLines = files.reduce(0) { $0 + $1.coveredLines }
        let executableLines = files.reduce(0) { $0 + $1.executableLines }
        return PackageCoverageReport(
            scope: "first_party_sources",
            coveredLines: coveredLines,
            executableLines: executableLines,
            lineCoverage: Self.normalizedCoverage(coveredLines: coveredLines, executableLines: executableLines),
            coverageJSONPath: coverageJSONPath.path,
            files: files
        )
    }

    public func renderHuman(report: HarnessReport) -> String {
        let threshold = String(format: "%.2f%%", locale: Locale(identifier: "en_US_POSIX"), report.minimumCoveragePercent)
        var lines = [
            "tests passed",
            "package coverage \(percentage(report.packageCoverage.lineCoverage)) (\(report.packageCoverage.coveredLines)/\(report.packageCoverage.executableLines))",
            "server coverage \(percentage(report.serverCoverage.lineCoverage)) (\(report.serverCoverage.coveredLines)/\(report.serverCoverage.executableLines))",
            "threshold \(threshold)",
            "coverage_json \(report.packageCoverage.coverageJSONPath)",
        ]

        if let clientCoverage = report.clientCoverage {
            lines.insert(
                "client coverage \(percentage(clientCoverage.lineCoverage)) (\(clientCoverage.coveredLines)/\(clientCoverage.executableLines))",
                at: 2
            )
        } else if let skippedReason = report.clientCoverageSkipReason {
            lines.insert("client coverage skipped: \(skippedReason)", at: 2)
        }

        if !report.packageCoverage.files.isEmpty {
            lines.append("lowest_coverage_files")
            for file in report.packageCoverage.files.prefix(10) {
                lines.append("file \(file.path) \(percentage(file.lineCoverage)) (\(file.coveredLines)/\(file.executableLines))")
            }
        }

        if let clientCoverage = report.clientCoverage {
            lines.append("client_targets")
            for target in clientCoverage.targets {
                lines.append("target \(target.name) \(percentage(target.lineCoverage)) (\(target.coveredLines)/\(target.executableLines))")
            }
        }

        lines.append("server_targets")
        for target in report.serverCoverage.targets {
            lines.append("target \(target.name) \(percentage(target.lineCoverage)) (\(target.coveredLines)/\(target.executableLines))")
        }

        if !report.violations.isEmpty {
            lines.append("violations")
            for violation in report.violations.sorted(by: violationSort) {
                lines.append("\(violation.suite) \(violation.kind) \(violation.name) \(percentage(violation.lineCoverage)) (\(violation.coveredLines)/\(violation.executableLines))")
            }
        }

        return lines.joined(separator: "\n")
    }

    public func makePackageFileViolations(report: PackageCoverageReport, minimumLineCoverage: Double) -> [HarnessCoverageViolation] {
        report.files.compactMap { file in
            guard file.lineCoverage + 0.000_001 < minimumLineCoverage else {
                return nil
            }
            return HarnessCoverageViolation(
                suite: "package",
                kind: "file",
                name: file.path,
                coveredLines: file.coveredLines,
                executableLines: file.executableLines,
                lineCoverage: file.lineCoverage
            )
        }
    }

    public func makeTargetViolations(report: CoverageReport, suite: String, minimumLineCoverage: Double) -> [HarnessCoverageViolation] {
        report.targets.compactMap { target in
            guard target.executableLines > 0 else {
                return nil
            }
            guard target.lineCoverage + 0.000_001 < minimumLineCoverage else {
                return nil
            }
            return HarnessCoverageViolation(
                suite: suite,
                kind: "target",
                name: target.name,
                coveredLines: target.coveredLines,
                executableLines: target.executableLines,
                lineCoverage: target.lineCoverage
            )
        }
    }

    public func makeFileViolations(report: CoverageReport, suite: String, minimumLineCoverage: Double) -> [HarnessCoverageViolation] {
        report.targets.flatMap { target in
            (target.files ?? []).compactMap { file in
                guard file.lineCoverage + 0.000_001 < minimumLineCoverage else {
                    return nil
                }
                return HarnessCoverageViolation(
                    suite: suite,
                    kind: "file",
                    name: file.path,
                    coveredLines: file.coveredLines,
                    executableLines: file.executableLines,
                    lineCoverage: file.lineCoverage
                )
            }
        }
    }

    static func normalizedCoverage(coveredLines: Int, executableLines: Int) -> Double {
        guard executableLines > 0 else {
            return 0
        }
        return Double(coveredLines) / Double(executableLines)
    }

    static func packageFileSort(lhs: PackageCoverageFileReport, rhs: PackageCoverageFileReport) -> Bool {
        if lhs.lineCoverage == rhs.lineCoverage {
            return lhs.path < rhs.path
        }
        return lhs.lineCoverage < rhs.lineCoverage
    }

    private func percentage(_ coverage: Double) -> String {
        String(format: "%.2f%%", locale: Locale(identifier: "en_US_POSIX"), coverage * 100)
    }

    private func violationSort(lhs: HarnessCoverageViolation, rhs: HarnessCoverageViolation) -> Bool {
        if lhs.suite == rhs.suite {
            if lhs.kind == rhs.kind {
                return lhs.name < rhs.name
            }
            return lhs.kind < rhs.kind
        }
        return lhs.suite < rhs.suite
    }
}

private struct RawPackageCoverageExport: Decodable {
    let data: [RawPackageCoverageChunk]
}

private struct RawPackageCoverageChunk: Decodable {
    let files: [RawPackageCoverageFile]
}

private struct RawPackageCoverageFile: Decodable {
    let filename: String
    let summary: RawPackageCoverageSummary
}

private struct RawPackageCoverageSummary: Decodable {
    let lines: RawPackageCoverageLines
}

private struct RawPackageCoverageLines: Decodable {
    let count: Int
    let covered: Int
}
