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
                    lineCoverage: normalizedCoverage(coveredLines: coveredLines, executableLines: executableLines)
                )
            }
            .sorted {
                if $0.lineCoverage == $1.lineCoverage {
                    return $0.path < $1.path
                }
                return $0.lineCoverage < $1.lineCoverage
            }

        guard !files.isEmpty else {
            throw SymphonyBuildError(code: "package_coverage_sources_missing", message: "SwiftPM coverage did not include any first-party files under Sources/.")
        }

        let coveredLines = files.reduce(0) { $0 + $1.coveredLines }
        let executableLines = files.reduce(0) { $0 + $1.executableLines }
        return PackageCoverageReport(
            scope: "first_party_sources",
            coveredLines: coveredLines,
            executableLines: executableLines,
            lineCoverage: normalizedCoverage(coveredLines: coveredLines, executableLines: executableLines),
            coverageJSONPath: coverageJSONPath.path,
            files: files
        )
    }

    public func renderHuman(report: HarnessReport) -> String {
        let threshold = String(format: "%.2f%%", locale: Locale(identifier: "en_US_POSIX"), report.minimumCoveragePercent)
        var lines = [
            "tests passed",
            "coverage scope \(report.packageCoverage.scope)",
            "coverage \(percentage(report.packageCoverage.lineCoverage)) (\(report.packageCoverage.coveredLines)/\(report.packageCoverage.executableLines))",
            "threshold \(threshold)",
            "coverage_json \(report.packageCoverage.coverageJSONPath)",
        ]

        if !report.packageCoverage.files.isEmpty {
            lines.append("lowest_coverage_files")
            for file in report.packageCoverage.files.prefix(10) {
                lines.append("file \(file.path) \(percentage(file.lineCoverage)) (\(file.coveredLines)/\(file.executableLines))")
            }
        }

        return lines.joined(separator: "\n")
    }

    private func normalizedCoverage(coveredLines: Int, executableLines: Int) -> Double {
        guard executableLines > 0 else {
            return 0
        }
        return Double(coveredLines) / Double(executableLines)
    }

    private func percentage(_ coverage: Double) -> String {
        String(format: "%.2f%%", locale: Locale(identifier: "en_US_POSIX"), coverage * 100)
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
