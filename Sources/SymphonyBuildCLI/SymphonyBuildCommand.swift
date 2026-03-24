import ArgumentParser
import Foundation
import SymphonyBuildCore

protocol SymphonyBuildTooling {
    func build(_ request: BuildCommandRequest) throws -> String
    func test(_ request: TestCommandRequest) throws -> String
    func coverage(_ request: CoverageCommandRequest) throws -> String
    func run(_ request: RunCommandRequest) throws -> String
    func harness(_ request: HarnessCommandRequest) throws -> String
    func hooksInstall(_ request: HooksInstallRequest) throws -> String
    func simList(currentDirectory: URL) throws -> String
    func simBoot(_ request: SimBootRequest) throws -> String
    func simSetServer(_ request: SimSetServerRequest) throws -> String
    func simClearServer(currentDirectory: URL) throws -> String
    func artifacts(_ request: ArtifactsCommandRequest) throws -> String
    func doctor(_ request: DoctorCommandRequest) throws -> String
}

extension SymphonyBuildTool: SymphonyBuildTooling {}

enum CLIContext {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var toolFactoryOverride: (() -> any SymphonyBuildTooling)?
    nonisolated(unsafe) private static var printerOverride: ((String) -> Void)?
    nonisolated(unsafe) private static var currentDirectoryProviderOverride: (() -> URL)?

    static func makeTool() -> any SymphonyBuildTooling {
        if let toolFactoryOverride {
            return toolFactoryOverride()
        }
        return SymphonyBuildTool()
    }

    static func emit(_ output: String) {
        if let printerOverride {
            printerOverride(output)
        } else {
            Swift.print(output)
        }
    }

    static func currentDirectory() -> URL {
        if let currentDirectoryProviderOverride {
            return currentDirectoryProviderOverride()
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    }

    static func withOverrides<T>(
        toolFactory: (() -> any SymphonyBuildTooling)?,
        printer: ((String) -> Void)?,
        currentDirectoryProvider: (() -> URL)?,
        operation: () throws -> T
    ) rethrows -> T {
        lock.lock()
        let previousFactory = self.toolFactoryOverride
        let previousPrinter = self.printerOverride
        let previousDirectoryProvider = self.currentDirectoryProviderOverride
        self.toolFactoryOverride = toolFactory
        self.printerOverride = printer
        self.currentDirectoryProviderOverride = currentDirectoryProvider
        defer {
            self.toolFactoryOverride = previousFactory
            self.printerOverride = previousPrinter
            self.currentDirectoryProviderOverride = previousDirectoryProvider
            lock.unlock()
        }
        return try operation()
    }
}

public struct SymphonyBuildCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "symphony-build",
        abstract: "Repository-local build, test, coverage, run, simulator, artifact, and diagnostics workflows for Symphony.",
        subcommands: [
            Build.self,
            Test.self,
            Coverage.self,
            Run.self,
            Harness.self,
            Hooks.self,
            Sim.self,
            Artifacts.self,
            Doctor.self,
        ],
        defaultSubcommand: Build.self
    )

    public init() {}
}

extension SymphonyBuildCommand {
    struct Build: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Prepare Symphony build artifacts through xcodebuild.")

        @Option var product: ProductKind = .client
        @Option var scheme: String?
        @Option var platform: PlatformKind?
        @Option var simulator: String?
        @Option(name: .long) var worker: Int = 0
        @Flag(name: .long) var dryRun = false
        @Flag(name: .long) var buildForTesting = false
        @Option(name: .long) var xcodeOutputMode: XcodeOutputMode = .filtered

        mutating func run() throws {
            let tool = CLIContext.makeTool()
            let output = try tool.build(
                BuildCommandRequest(
                    product: product,
                    scheme: scheme,
                    platform: platform,
                    simulator: simulator,
                    workerID: worker,
                    dryRun: dryRun,
                    buildForTesting: buildForTesting,
                    outputMode: xcodeOutputMode,
                    currentDirectory: CLIContext.currentDirectory()
                )
            )
            CLIContext.emit(output)
        }
    }

    struct Test: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Prepare Symphony test artifacts through xcodebuild.")

        @Option var product: ProductKind = .client
        @Option var scheme: String?
        @Option var platform: PlatformKind?
        @Option var simulator: String?
        @Option(name: .long) var worker: Int = 0
        @Flag(name: .long) var dryRun = false
        @Option(name: .long, parsing: .upToNextOption) var onlyTesting: [String] = []
        @Option(name: .long, parsing: .upToNextOption) var skipTesting: [String] = []
        @Option(name: .long) var xcodeOutputMode: XcodeOutputMode = .filtered

        mutating func run() throws {
            let tool = CLIContext.makeTool()
            let output = try tool.test(
                TestCommandRequest(
                    product: product,
                    scheme: scheme,
                    platform: platform,
                    simulator: simulator,
                    workerID: worker,
                    dryRun: dryRun,
                    onlyTesting: onlyTesting,
                    skipTesting: skipTesting,
                    outputMode: xcodeOutputMode,
                    currentDirectory: CLIContext.currentDirectory()
                )
            )
            CLIContext.emit(output)
        }
    }

    struct Run: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Launch a local Symphony product for development.")

        @Option var product: ProductKind = .server
        @Option var scheme: String?
        @Option var platform: PlatformKind?
        @Option var simulator: String?
        @Option(name: .long) var worker: Int = 0
        @Flag(name: .long) var dryRun = false
        @Option(name: .long) var serverURL: String?
        @Option(name: .long) var host: String?
        @Option(name: .long) var port: Int?
        @Option(name: .long, parsing: .upToNextOption) var env: [String] = []
        @Option(name: .long) var xcodeOutputMode: XcodeOutputMode = .filtered

        mutating func run() throws {
            let tool = CLIContext.makeTool()
            let output = try tool.run(
                RunCommandRequest(
                    product: product,
                    scheme: scheme,
                    platform: platform,
                    simulator: simulator,
                    workerID: worker,
                    dryRun: dryRun,
                    serverURL: serverURL,
                    host: host,
                    port: port,
                    environment: try parseEnvironment(env),
                    outputMode: xcodeOutputMode,
                    currentDirectory: CLIContext.currentDirectory()
                )
            )
            CLIContext.emit(output)
        }
    }

    struct Coverage: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Run a coverage-enabled test pass and report filtered line coverage.")

        @Option var product: ProductKind = .client
        @Option var scheme: String?
        @Option var platform: PlatformKind?
        @Option var simulator: String?
        @Option(name: .long) var worker: Int = 0
        @Flag(name: .long) var dryRun = false
        @Option(name: .long, parsing: .upToNextOption) var onlyTesting: [String] = []
        @Option(name: .long, parsing: .upToNextOption) var skipTesting: [String] = []
        @Flag(name: .long) var json = false
        @Flag(name: .long) var showFiles = false
        @Flag(name: .long) var includeTestTargets = false
        @Option(name: .long) var xcodeOutputMode: XcodeOutputMode = .filtered

        mutating func run() throws {
            let tool = CLIContext.makeTool()
            let output = try tool.coverage(
                CoverageCommandRequest(
                    product: product,
                    scheme: scheme,
                    platform: platform,
                    simulator: simulator,
                    workerID: worker,
                    dryRun: dryRun,
                    onlyTesting: onlyTesting,
                    skipTesting: skipTesting,
                    json: json,
                    showFiles: showFiles,
                    includeTestTargets: includeTestTargets,
                    outputMode: xcodeOutputMode,
                    currentDirectory: CLIContext.currentDirectory()
                )
            )
            CLIContext.emit(output)
        }
    }

    struct Sim: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Inspect simulator availability, boot a simulator, and manage local client endpoint injection.",
            subcommands: [List.self, Boot.self, SetServer.self, ClearServer.self]
        )
    }

    struct Harness: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Run the commit harness: package tests plus first-party source coverage gating.")

        @Option(name: .long) var minimumCoverage: Double = 100
        @Flag(name: .long) var json = false

        mutating func run() throws {
            let tool = CLIContext.makeTool()
            let output = try tool.harness(
                HarnessCommandRequest(
                    minimumCoveragePercent: minimumCoverage,
                    json: json,
                    currentDirectory: CLIContext.currentDirectory()
                )
            )
            CLIContext.emit(output)
        }
    }

    struct Hooks: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Install repository-local Git hooks backed by symphony-build.",
            subcommands: [Install.self]
        )
    }

    struct Artifacts: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Print stable inspection paths for the latest or selected run.")

        @Argument(help: "The command family to inspect.") var command: BuildCommandFamily = .build
        @Flag(name: .long) var latest = false
        @Option(name: .customLong("run")) var runID: String?

        mutating func run() throws {
            let tool = CLIContext.makeTool()
            let output = try tool.artifacts(
                ArtifactsCommandRequest(
                    command: command,
                    latest: latest || runID == nil,
                    runID: runID,
                    currentDirectory: CLIContext.currentDirectory()
                )
            )
            CLIContext.emit(output)
        }
    }

    struct Doctor: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Verify toolchain availability and Symphony repository readiness.")

        @Flag(name: .long) var strict = false
        @Flag(name: .long) var json = false
        @Flag(name: .long) var quiet = false

        mutating func run() throws {
            let tool = CLIContext.makeTool()
            let output = try tool.doctor(
                DoctorCommandRequest(
                    strict: strict,
                    json: json,
                    quiet: quiet,
                    currentDirectory: CLIContext.currentDirectory()
                )
            )
            CLIContext.emit(output)
        }
    }
}

extension SymphonyBuildCommand.Sim {
    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List available simulator names and UDIDs.")

        mutating func run() throws {
            CLIContext.emit(try CLIContext.makeTool().simList(currentDirectory: CLIContext.currentDirectory()))
        }
    }

    struct Boot: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Boot the selected simulator.")

        @Option(name: .long) var simulator: String?

        mutating func run() throws {
            CLIContext.emit(try CLIContext.makeTool().simBoot(SimBootRequest(simulator: simulator, currentDirectory: CLIContext.currentDirectory())))
        }
    }

    struct SetServer: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Record local endpoint values for future client launches.")

        @Option(name: .long) var serverURL: String?
        @Option(name: .long) var scheme: String?
        @Option(name: .long) var host: String?
        @Option(name: .long) var port: Int?

        mutating func run() throws {
            CLIContext.emit(
                try CLIContext.makeTool().simSetServer(
                    SimSetServerRequest(
                        serverURL: serverURL,
                        scheme: scheme,
                        host: host,
                        port: port,
                        currentDirectory: CLIContext.currentDirectory()
                    )
                )
            )
        }
    }

    struct ClearServer: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Remove the persisted local endpoint override.")

        mutating func run() throws {
            CLIContext.emit(try CLIContext.makeTool().simClearServer(currentDirectory: CLIContext.currentDirectory()))
        }
    }
}

extension SymphonyBuildCommand.Hooks {
    struct Install: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Configure Git to use the committed .githooks directory for this clone/worktree set.")

        mutating func run() throws {
            CLIContext.emit(try CLIContext.makeTool().hooksInstall(HooksInstallRequest(currentDirectory: CLIContext.currentDirectory())))
        }
    }
}

private func parseEnvironment(_ rawValues: [String]) throws -> [String: String] {
    try rawValues.reduce(into: [String: String]()) { partial, item in
        let parts = item.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty else {
            throw ValidationError("Environment overrides must use KEY=VALUE format.")
        }
        partial[String(parts[0])] = String(parts[1])
    }
}

extension ProductKind: ExpressibleByArgument {}
extension PlatformKind: ExpressibleByArgument {}
extension XcodeOutputMode: ExpressibleByArgument {}
extension BuildCommandFamily: ExpressibleByArgument {}
