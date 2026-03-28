import ArgumentParser
import Foundation
import SymphonyHarness

protocol SymphonyHarnessTooling {
  func build(_ request: ExecutionRequest) throws -> String
  func test(_ request: ExecutionRequest) throws -> String
  func run(_ request: ExecutionRequest) throws -> String
  func validate(_ request: ExecutionRequest) throws -> String
  func doctor(_ request: DoctorCommandRequest) throws -> String
}

extension SymphonyHarnessTool: SymphonyHarnessTooling {}

enum CLIContext {
  private static let lock = NSLock()
  nonisolated(unsafe) private static var toolFactoryOverride: (() -> any SymphonyHarnessTooling)?
  nonisolated(unsafe) private static var printerOverride: ((String) -> Void)?
  nonisolated(unsafe) private static var currentDirectoryProviderOverride: (() -> URL)?

  static func makeTool() -> any SymphonyHarnessTooling {
    if let toolFactoryOverride {
      return toolFactoryOverride()
    }
    return SymphonyHarnessTool()
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
    toolFactory: (() -> any SymphonyHarnessTooling)?,
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

public struct SymphonyHarnessCommand: ParsableCommand {
  public static let configuration = CommandConfiguration(
    commandName: "harness",
    abstract: "Repository-local build, test, run, validate, and diagnostics workflows for Symphony.",
    subcommands: [
      Build.self,
      Test.self,
      Run.self,
      Validate.self,
      Doctor.self,
    ]
  )

  public init() {}
}

extension SymphonyHarnessCommand {
  struct Build: ParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Build one or more canonical production subjects.")

    @Argument var subjects: [String] = []
    @Option(name: .long, help: .hidden) var product: String?
    @Option(name: .long) var xcodeOutputMode: XcodeOutputMode = .filtered

    mutating func validate() throws {
      if product != nil {
        throw ValidationError(
          "Legacy --product parsing is unavailable. Pass canonical subjects instead.")
      }
      guard !subjects.isEmpty else {
        throw ValidationError("build requires at least one canonical production subject.")
      }
      try validateSubjects(subjects, allowExplicitTests: false)
    }

    mutating func run() throws {
      let request = try makeExecutionRequest(
        command: .build,
        subjects: subjects,
        environment: [:],
        outputMode: xcodeOutputMode
      )
      CLIContext.emit(try CLIContext.makeTool().build(request))
    }
  }

  struct Test: ParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Test zero or more canonical production or explicit test subjects.")

    @Argument var subjects: [String] = []
    @Option(name: .long) var xcodeOutputMode: XcodeOutputMode = .filtered

    mutating func validate() throws {
      try validateSubjects(subjects, allowExplicitTests: true)
    }

    mutating func run() throws {
      let request = try makeExecutionRequest(
        command: .test,
        subjects: subjects,
        environment: [:],
        outputMode: xcodeOutputMode
      )
      CLIContext.emit(try CLIContext.makeTool().test(request))
    }
  }

  struct Run: ParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Run one canonical runnable subject.")

    @Argument var subject: String
    @Option(name: .long) var serverURL: String?
    @Option(name: .long) var host: String?
    @Option(name: .long) var port: Int?
    @Option(name: .long, parsing: .upToNextOption) var env: [String] = []
    @Option(name: .long) var xcodeOutputMode: XcodeOutputMode = .filtered

    mutating func validate() throws {
      try validateRunnableSubject(subject)
    }

    mutating func run() throws {
      let request = try makeExecutionRequest(
        command: .run,
        subjects: [subject],
        environment: try makeRunEnvironment(
          rawValues: env,
          serverURL: serverURL,
          host: host,
          port: port
        ),
        outputMode: xcodeOutputMode
      )
      CLIContext.emit(try CLIContext.makeTool().run(request))
    }
  }

  struct Validate: ParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Validate zero or more canonical subjects against the repository policy.")

    @Argument var subjects: [String] = []
    @Option(name: .long) var xcodeOutputMode: XcodeOutputMode = .filtered

    mutating func validate() throws {
      try validateSubjects(subjects, allowExplicitTests: true)
    }

    mutating func run() throws {
      let request = try makeExecutionRequest(
        command: .validate,
        subjects: subjects,
        environment: [:],
        outputMode: xcodeOutputMode
      )
      CLIContext.emit(try CLIContext.makeTool().validate(request))
    }
  }

  struct Doctor: ParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Verify toolchain availability and Symphony repository readiness.")

    @Flag(name: .long) var strict = false
    @Flag(name: .long) var json = false
    @Flag(name: .long) var quiet = false

    mutating func run() throws {
      let output = try CLIContext.makeTool().doctor(
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

private func makeExecutionRequest(
  command: HarnessCommand,
  subjects: [String],
  environment: [String: String],
  outputMode: XcodeOutputMode
) throws -> ExecutionRequest {
  let resolvedSubjects = try subjects.map(resolveSubject(named:))
  let explicitTestSubjects = resolvedSubjects
    .filter { $0.kind == .test || $0.kind == .uiTest }
    .map(\.name)
  let productionSubjects = resolvedSubjects
    .filter { $0.kind != .test && $0.kind != .uiTest }
    .map(\.name)
  return ExecutionRequest(
    command: command,
    subjects: productionSubjects,
    explicitTestSubjects: explicitTestSubjects,
    environment: environment,
    outputMode: outputMode
  )
}

private func validateSubjects(_ subjects: [String], allowExplicitTests: Bool) throws {
  for name in subjects {
    let subject = try resolveSubject(named: name)
    if !allowExplicitTests, subject.kind == .test || subject.kind == .uiTest {
      throw ValidationError("build accepts only production subjects.")
    }
  }
}

private func validateRunnableSubject(_ subjectName: String) throws {
  let subject = try resolveSubject(named: subjectName)
  guard HarnessSubjects.runnableSubjectNames.contains(subject.name) else {
    throw ValidationError("run requires a canonical runnable subject.")
  }
}

private func resolveSubject(named name: String) throws -> HarnessSubject {
  guard let subject = HarnessSubjects.subject(named: name) else {
    throw ValidationError("Unknown subject '\(name)'.")
  }
  return subject
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

private func makeRunEnvironment(
  rawValues: [String],
  serverURL: String?,
  host: String?,
  port: Int?
) throws -> [String: String] {
  var environment = try parseEnvironment(rawValues)
  if let serverURL {
    guard let components = URLComponents(string: serverURL),
      let scheme = components.scheme,
      let host = components.host,
      let port = components.port
    else {
      throw ValidationError("Server URL overrides must include a scheme, host, and port.")
    }
    environment["SYMPHONY_SERVER_SCHEME"] = scheme
    environment["SYMPHONY_SERVER_HOST"] = host
    environment["SYMPHONY_SERVER_PORT"] = String(port)
  }
  if let host {
    environment["SYMPHONY_SERVER_HOST"] = host
  }
  if let port {
    environment["SYMPHONY_SERVER_PORT"] = String(port)
  }
  return environment
}

extension XcodeOutputMode: ExpressibleByArgument {}
