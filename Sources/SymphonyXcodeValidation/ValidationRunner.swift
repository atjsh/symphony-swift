import Foundation

#if os(macOS)

public struct ValidationRequest: Sendable {
  public let projectRoot: URL
  public let subject: ValidationSubject
  public let outputRoot: URL?
  public let artifactRetention: ValidationArtifactRetention
  public let buildProfile: ValidationBuildProfile
  public let executionProfile: ValidationExecutionProfile
  public let concurrency: ValidationConcurrency?
  public let logLevel: ValidationLogLevel
  public let skipRichCapture: Bool
  public let skipFullMatrix: Bool

  public init(
    projectRoot: URL,
    subject: ValidationSubject = .symphonySwiftUIApp,
    outputRoot: URL? = nil,
    artifactRetention: ValidationArtifactRetention = .canonicalOnly,
    buildProfile: ValidationBuildProfile = .fast,
    executionProfile: ValidationExecutionProfile = .aggressive,
    concurrency: ValidationConcurrency? = nil,
    logLevel: ValidationLogLevel = .info,
    skipRichCapture: Bool = false,
    skipFullMatrix: Bool = false
  ) {
    self.projectRoot = projectRoot
    self.subject = subject
    self.outputRoot = outputRoot
    self.artifactRetention = artifactRetention
    self.buildProfile = buildProfile
    self.executionProfile = executionProfile
    self.concurrency = concurrency
    self.logLevel = logLevel
    self.skipRichCapture = skipRichCapture
    self.skipFullMatrix = skipFullMatrix
  }
}

extension ValidationRequest {
  func resolvedConcurrency() -> ValidationConcurrency {
    concurrency ?? executionProfile.defaultConcurrency
  }

  var subjectConfiguration: ValidationSubjectConfiguration {
    subject.configuration
  }
}

public struct ValidationCommandResult: Sendable {
  public let exitStatus: Int32
  public let stdout: String
  public let stderr: String

  public var combinedOutput: String {
    if stdout.isEmpty {
      return stderr
    }
    if stderr.isEmpty {
      return stdout
    }
    return "\(stdout)\n\(stderr)"
  }
}


public final class XcodeValidationRunner: @unchecked Sendable {
  let processExecutor: ValidationProcessExecuting
  let fileManager: FileManager
  let now: @Sendable () -> Date
  let logSink: (@Sendable (String) -> Void)?

  public init(
    processExecutor: ValidationProcessExecuting = SystemValidationProcessExecutor(),
    fileManager: FileManager = .default,
    now: @escaping @Sendable () -> Date = Date.init,
    logSink: (@Sendable (String) -> Void)? = nil
  ) {
    self.processExecutor = processExecutor
    self.fileManager = fileManager
    self.now = now
    self.logSink = logSink
  }
}

#endif
