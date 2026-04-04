import Foundation
import SymphonyXcodeValidation

/// Cross-platform configuration for a validation run.
///
/// Mirrors the configurable parts of `ValidationRequest` (macOS-only)
/// so that both the server and the client can share a common contract.
public struct ValidationRunConfiguration: Codable, Equatable, Sendable {
  public var subject: ValidationSubject
  public var outputRoot: String?
  public var artifactRetention: ValidationArtifactRetention
  public var buildProfile: ValidationBuildProfile
  public var executionProfile: ValidationExecutionProfile
  public var concurrency: ValidationConcurrency?
  public var logLevel: ValidationLogLevel
  public var skipRichCapture: Bool
  public var skipFullMatrix: Bool

  public init(
    subject: ValidationSubject = .symphonySwiftUIApp,
    outputRoot: String? = nil,
    artifactRetention: ValidationArtifactRetention = .canonicalOnly,
    buildProfile: ValidationBuildProfile = .fast,
    executionProfile: ValidationExecutionProfile = .aggressive,
    concurrency: ValidationConcurrency? = nil,
    logLevel: ValidationLogLevel = .info,
    skipRichCapture: Bool = false,
    skipFullMatrix: Bool = false
  ) {
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
