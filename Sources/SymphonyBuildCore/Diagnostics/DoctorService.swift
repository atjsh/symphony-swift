import Foundation

public struct DoctorService: DoctorServicing {
    private let workspaceDiscovery: WorkspaceDiscovering
    private let processRunner: ProcessRunning
    private let fileManager: FileManager

    public init(
        workspaceDiscovery: WorkspaceDiscovering = WorkspaceDiscovery(),
        processRunner: ProcessRunning = SystemProcessRunner(),
        fileManager: FileManager = .default
    ) {
        self.workspaceDiscovery = workspaceDiscovery
        self.processRunner = processRunner
        self.fileManager = fileManager
    }

    public func makeReport(from request: DoctorCommandRequest) throws -> DiagnosticsReport {
        var issues = [DiagnosticIssue]()
        var checkedExecutables = [String]()
        let checkedPaths = [request.currentDirectory.path]

        for executable in ["swift", "xcodebuild", "xcrun", "simctl", "xcresulttool"] {
            checkedExecutables.append(executable)
            switch executable {
            case "simctl":
                let result = try processRunner.run(command: "xcrun", arguments: ["simctl", "help"], environment: [:], currentDirectory: nil)
                if result.exitStatus != 0 {
                    issues.append(DiagnosticIssue(severity: .error, code: "missing_simctl", message: "Simulator control is unavailable.", suggestedFix: "Install Xcode Simulator support and ensure `xcrun simctl` succeeds."))
                }
            case "xcresulttool":
                let result = try processRunner.run(command: "xcrun", arguments: ["xcresulttool", "help"], environment: [:], currentDirectory: nil)
                if result.exitStatus != 0 {
                    issues.append(DiagnosticIssue(severity: .error, code: "missing_xcresulttool", message: "xcresulttool is unavailable.", suggestedFix: "Install Xcode command-line tools and ensure `xcrun xcresulttool` succeeds."))
                }
            default:
                let result = try processRunner.run(command: "which", arguments: [executable], environment: [:], currentDirectory: nil)
                if result.exitStatus != 0 {
                    issues.append(DiagnosticIssue(severity: .error, code: "missing_\(executable)", message: "Required executable '\(executable)' was not found.", suggestedFix: "Install \(executable) or update PATH."))
                }
            }
        }

        do {
            let workspace = try workspaceDiscovery.discover(from: request.currentDirectory)
            let buildStateRoot = workspace.buildStateRoot
            do {
                try fileManager.createDirectory(at: buildStateRoot, withIntermediateDirectories: true)
            } catch {
                issues.append(DiagnosticIssue(severity: .error, code: "unwritable_build_state_root", message: "The canonical build state root is not writable: \(buildStateRoot.path)", suggestedFix: "Make the repository writable and ensure `.build/` can be created."))
            }

            let schemes = try listSchemes(in: workspace)
            for scheme in ["Symphony", "SymphonyServer"] {
                if !schemes.contains(scheme) {
                    issues.append(DiagnosticIssue(severity: .error, code: "missing_scheme_\(scheme.lowercased())", message: "Expected scheme '\(scheme)' was not found in the checked-in build definition.", suggestedFix: "Check in the required scheme or regenerate the Xcode project."))
                }
            }
        } catch let error as SymphonyBuildError {
            issues.append(DiagnosticIssue(severity: .error, code: error.code, message: error.message, suggestedFix: "Check that the repository contains a checked-in `Symphony.xcworkspace` or `SymphonyApps.xcodeproj`."))
        }

        return DiagnosticsReport(issues: issues, checkedPaths: checkedPaths, checkedExecutables: checkedExecutables)
    }

    public func render(report: DiagnosticsReport, json: Bool, quiet: Bool) throws -> String {
        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return String(decoding: try encoder.encode(report), as: UTF8.self)
        }

        var lines = [String]()
        if !quiet {
            lines.append("checked_paths: \(report.checkedPaths.joined(separator: ", "))")
            lines.append("checked_executables: \(report.checkedExecutables.joined(separator: ", "))")
        }
        if report.issues.isEmpty {
            lines.append("OK: environment is ready")
        } else {
            for issue in report.issues {
                let fix = issue.suggestedFix.map { " fix=\($0)" } ?? ""
                lines.append("\(issue.severity.rawValue.uppercased()) [\(issue.code)] \(issue.message)\(fix)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func listSchemes(in workspace: WorkspaceContext) throws -> Set<String> {
        var arguments = ["-list", "-json"]
        if let workspacePath = workspace.xcodeWorkspacePath {
            arguments += ["-workspace", workspacePath.path]
        } else if let projectPath = workspace.xcodeProjectPath {
            arguments += ["-project", projectPath.path]
        } else {
            return []
        }

        let result = try processRunner.run(command: "xcodebuild", arguments: arguments, environment: [:], currentDirectory: workspace.projectRoot)
        guard result.exitStatus == 0 else {
            throw SymphonyBuildError(code: "xcodebuild_list_failed", message: result.combinedOutput.isEmpty ? "Failed to list schemes." : result.combinedOutput)
        }

        let decoded = try JSONDecoder().decode(SchemeListResponse.self, from: Data(result.stdout.utf8))
        return Set((decoded.project?.schemes ?? []) + (decoded.workspace?.schemes ?? []))
    }

    private struct SchemeListResponse: Decodable {
        let project: SchemeContainer?
        let workspace: SchemeContainer?
    }

    private struct SchemeContainer: Decodable {
        let schemes: [String]
    }
}
