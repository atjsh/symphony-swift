import ArgumentParser
import Foundation
import SymphonyXcodeValidation

public enum ValidationArtifactRetentionOption: String, ExpressibleByArgument {
  case canonicalOnly = "canonical-only"
  case debugFriendly = "debug-friendly"
  case keepEverything = "keep-everything"

  var value: ValidationArtifactRetention {
    switch self {
    case .canonicalOnly:
      .canonicalOnly
    case .debugFriendly:
      .debugFriendly
    case .keepEverything:
      .keepEverything
    }
  }
}

public enum ValidationBuildProfileOption: String, ExpressibleByArgument {
  case fast
  case standard

  var value: ValidationBuildProfile {
    switch self {
    case .fast:
      .fast
    case .standard:
      .standard
    }
  }
}

public enum ValidationExecutionProfileOption: String, ExpressibleByArgument {
  case aggressive
  case balanced
  case serial

  var value: ValidationExecutionProfile {
    switch self {
    case .aggressive:
      .aggressive
    case .balanced:
      .balanced
    case .serial:
      .serial
    }
  }
}

public enum ValidationLogLevelOption: String, ExpressibleByArgument {
  case quiet
  case info
  case debug

  var value: ValidationLogLevel {
    switch self {
    case .quiet:
      .quiet
    case .info:
      .info
    case .debug:
      .debug
    }
  }
}

public enum ValidationSubjectOption: String, ExpressibleByArgument {
  case symphonySwiftUIApp = "symphony-swift-ui-app"
  case xcodeValidationGalleryApp = "xcode-validation-gallery-app"

  var value: ValidationSubject {
    switch self {
    case .symphonySwiftUIApp:
      .symphonySwiftUIApp
    case .xcodeValidationGalleryApp:
      .xcodeValidationGalleryApp
    }
  }
}

public struct SymphonyXcodeValidationRunnerCommand: ParsableCommand {
  public static let configuration = CommandConfiguration(
    commandName: "SymphonyXcodeValidationRunner",
    abstract: "Run direct Xcode-backed validation, media capture, and accessibility audits for an Xcode validation subject."
  )

  @Option(name: .long, help: "Write artifacts under the provided output directory.")
  public var outputRoot: String?

  @Option(name: .long, help: "Choose which Xcode validation subject to run.")
  public var subject: ValidationSubjectOption = .symphonySwiftUIApp

  @Option(
    name: .long,
    help: "Choose how much intermediate validation state to retain."
  )
  public var artifactRetention: ValidationArtifactRetentionOption = .canonicalOnly

  @Option(
    name: .long,
    help: "Choose the build profile used for xcodebuild build-for-testing and test-without-building."
  )
  public var buildProfile: ValidationBuildProfileOption = .fast

  @Option(
    name: .long,
    help: "Choose the execution profile used to schedule validation work across build and destination lanes."
  )
  public var executionProfile: ValidationExecutionProfileOption = .aggressive

  @Option(name: .long, help: "Override the maximum number of concurrent build-for-testing jobs.")
  public var maxParallelBuilds: Int?

  @Option(name: .long, help: "Override the maximum number of concurrent destination test lanes.")
  public var maxParallelDestinations: Int?

  @Option(name: .long, help: "Override the maximum number of concurrent simulator test lanes.")
  public var maxParallelSimulators: Int?

  @Flag(
    name: .long,
    help: "Disable warm build-for-testing jobs for non-mitigation scenarios while mitigation is still running."
  )
  public var noWarmBuildsBeforeMitigationPass = false

  @Option(
    name: .long,
    help: "Choose how much live diagnostic logging the validation runner emits to stderr."
  )
  public var logLevel: ValidationLogLevelOption = .info

  @Flag(name: .long, help: "Skip the rich media walkthrough runs.")
  public var skipRichCapture = false

  @Flag(name: .long, help: "Skip the full cross-platform plan matrix.")
  public var skipFullMatrix = false

  public init() {}

  public func validate() throws {
    for (label, value) in [
      ("max-parallel-builds", maxParallelBuilds),
      ("max-parallel-destinations", maxParallelDestinations),
      ("max-parallel-simulators", maxParallelSimulators),
    ] {
      if let value, value < 1 {
        throw ValidationError("--\(label) must be greater than or equal to 1.")
      }
    }

    if let maxParallelSimulators, let maxParallelDestinations,
      maxParallelSimulators > maxParallelDestinations
    {
      throw ValidationError("--max-parallel-simulators must be less than or equal to --max-parallel-destinations.")
    }
  }

  public mutating func run() throws {
    let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    let runner = XcodeValidationRunner()
    let summary = try runner.run(makeRequest(projectRoot: projectRoot))

    for line in Self.summaryLines(for: summary) {
      Swift.print(line)
    }
  }

  func makeRequest(projectRoot: URL) -> ValidationRequest {
    let resolvedConcurrency =
      hasConcurrencyOverrides
      ? Self.resolveConcurrency(
        executionProfile: executionProfile.value,
        maxParallelBuilds: maxParallelBuilds,
        maxParallelDestinations: maxParallelDestinations,
        maxParallelSimulators: maxParallelSimulators,
        warmBuildsBeforeMitigationPass: noWarmBuildsBeforeMitigationPass ? false : nil
      )
      : nil

    return ValidationRequest(
      projectRoot: projectRoot,
      subject: subject.value,
      outputRoot: outputRoot.map { URL(fileURLWithPath: $0, isDirectory: true) },
      artifactRetention: artifactRetention.value,
      buildProfile: buildProfile.value,
      executionProfile: executionProfile.value,
      concurrency: resolvedConcurrency,
      logLevel: logLevel.value,
      skipRichCapture: skipRichCapture,
      skipFullMatrix: skipFullMatrix
    )
  }

  static func resolveConcurrency(
    executionProfile: ValidationExecutionProfile,
    maxParallelBuilds: Int?,
    maxParallelDestinations: Int?,
    maxParallelSimulators: Int?,
    warmBuildsBeforeMitigationPass: Bool?
  ) -> ValidationConcurrency {
    let defaults = executionProfile.defaultConcurrency
    return ValidationConcurrency(
      maxParallelBuilds: maxParallelBuilds ?? defaults.maxParallelBuilds,
      maxParallelDestinations: maxParallelDestinations ?? defaults.maxParallelDestinations,
      maxParallelSimulators: maxParallelSimulators ?? defaults.maxParallelSimulators,
      warmBuildsBeforeMitigationPass: warmBuildsBeforeMitigationPass
        ?? defaults.warmBuildsBeforeMitigationPass
    )
  }

  private var hasConcurrencyOverrides: Bool {
    maxParallelBuilds != nil
      || maxParallelDestinations != nil
      || maxParallelSimulators != nil
      || noWarmBuildsBeforeMitigationPass
  }

  static func summaryLines(for summary: ValidationSummary) -> [String] {
    var lines = [
      "status: \(summary.status.rawValue)",
      "output: \(summary.outputRoot)",
      "runs: \(summary.runRecords.count)",
      "media_artifacts: \(summary.mediaArtifacts.count)",
      "audit_issues: \(summary.auditIssues.count)",
    ]
    if summary.unresolvedBlockers.isEmpty == false {
      lines.append("unresolved_blockers:")
      lines.append(contentsOf: summary.unresolvedBlockers.map { "- \($0)" })
    }
    return lines
  }
}
