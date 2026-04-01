import Foundation

#if os(macOS)

extension XcodeValidationRunner {

  func renderMarkdownSummary(_ summary: ValidationSummary) -> String {
    var lines = [String]()
    lines.append("# Xcode Validation Summary")
    lines.append("")
    lines.append("- Status: \(summary.status.rawValue)")
    lines.append("- Output root: \(summary.outputRoot)")
    lines.append("- Media artifacts: \(summary.mediaArtifacts.count)")
    lines.append("- Audit issues: \(summary.auditIssues.count)")
    lines.append("")

    if summary.unresolvedBlockers.isEmpty == false {
      lines.append("## Unresolved Blockers")
      for blocker in summary.unresolvedBlockers {
        lines.append("- \(blocker)")
      }
      lines.append("")
    }

    lines.append("## Runs")
    for record in summary.runRecords {
      lines.append(
        "- \(record.phase.rawValue) | \(record.destination.platformDirectoryName) | \(record.plan.slug) | \(record.runName) | \(record.outcome.rawValue)"
      )
      for failure in record.summary.testFailures {
        lines.append("  - \(failure.testIdentifier): \(failure.failureText)")
      }
    }

    return lines.joined(separator: "\n")
  }

  func makeSyntheticFailureRunRecord(
    scenario: ValidationScenario,
    context: ValidationExecutionContext,
    startedAt: Date,
    endedAt: Date,
    failureText: String
  ) -> ValidationRunRecord {
    ValidationRunRecord(
      phase: scenario.phase,
      destination: scenario.destination,
      plan: scenario.plan,
      runName: scenario.runName,
      outcome: .failed,
      resultBundlePath: context.resultBundlePath,
      summary: ValidationTestSummary(
        result: "Failed",
        passedTests: 0,
        failedTests: 1,
        testFailures: [
        ValidationTestFailure(
          testIdentifier: scenario.defaultTestIdentifier,
          failureText: failureText
        )
      ]
      ),
      startedAt: startedAt,
      endedAt: endedAt
    )
  }

  func defaultOutputRoot(projectRoot: URL) -> URL {
    projectRoot
      .appendingPathComponent(".build/xcode-validation", isDirectory: true)
      .appendingPathComponent(Self.timestampFormatter.string(from: now()), isDirectory: true)
  }

  func stableFileName(for artifact: MediaArtifact, pathExtension: String) -> String {
    sanitizedFileName(
      "platform=\(artifact.platform)__plan=\(artifact.plan)__checkpoint=\(artifact.checkpoint)__surface=\(artifact.surface)__orientation=\(artifact.orientation)__variant=\(artifact.variant)__artifact=\(artifact.artifactType.rawValue).\(pathExtension)"
    )
  }

  func parseSummaryPayload(from data: Data) throws -> ValidationTestSummary {
    let payload = try JSONDecoder().decode(XCResultSummaryPayload.self, from: data)
    return ValidationTestSummary(
      result: payload.result,
      passedTests: payload.passedTests,
      failedTests: payload.failedTests,
      testFailures: payload.testFailures.map {
        ValidationTestFailure(
          testIdentifier: $0.testIdentifierString ?? $0.testIdentifierURL ?? "unknown-test",
          failureText: $0.failureText
        )
      }
    )
  }

  func makeRunnerFailureSummary(_ failureText: String) -> ValidationTestSummary {
    ValidationTestSummary(
      result: "Failed",
      passedTests: 0,
      failedTests: 1,
      testFailures: [
        ValidationTestFailure(
          testIdentifier: "validation-runner",
          failureText: failureText
        )
      ]
    )
  }

  func sanitizedFileName(_ name: String) -> String {
    name.replacingOccurrences(of: "/", with: "-")
      .replacingOccurrences(of: ":", with: "-")
      .replacingOccurrences(of: " ", with: "-")
  }

  func checkpoint(from suggestedName: String) -> String? {
    let trimmedName = URL(fileURLWithPath: suggestedName).deletingPathExtension().lastPathComponent
    guard trimmedName.hasPrefix("audit__checkpoint=") else {
      return nil
    }
    return trimmedName
      .components(separatedBy: "__")
      .first?
      .replacingOccurrences(of: "audit__checkpoint=", with: "")
  }

  func runCommand(
    label: String,
    command: ValidationCommand,
    logger: ValidationRunLogger
  ) throws -> ValidationCommandResult {
    logger.debug("Launching command label=\(label) command=\(render(command: command))")
    let startedAt = now()
    let result = try processExecutor.run(command)
    logger.debug(
      """
      Finished command label=\(label) exit_status=\(result.exitStatus) elapsed=\(formatElapsed(since: startedAt))
      """
    )
    return result
  }

  func startCommand(
    label: String,
    command: ValidationCommand,
    logger: ValidationRunLogger
  ) throws -> RunningValidationCommand {
    logger.debug("Launching long-running command label=\(label) command=\(render(command: command))")
    return try processExecutor.start(command)
  }

  func render(command: ValidationCommand) -> String {
    ([command.executable] + command.arguments)
      .map(shellQuoted)
      .joined(separator: " ")
  }

  func shellQuoted(_ value: String) -> String {
    guard value.contains(where: { $0.isWhitespace || $0 == "\"" || $0 == "'" }) else {
      return value
    }

    return "\"\(value.replacingOccurrences(of: "\"", with: "\\\""))\""
  }

  func formatElapsed(since startedAt: Date) -> String {
    String(format: "%.2fs", now().timeIntervalSince(startedAt))
  }

  func trimmedOutputExcerpt(from output: String, maxLength: Int = 240) -> String {
    let collapsed = output
      .split(whereSeparator: \.isNewline)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { $0.isEmpty == false }
      .joined(separator: " | ")

    guard collapsed.count > maxLength else {
      return collapsed.isEmpty ? "<empty>" : collapsed
    }

    let limitIndex = collapsed.index(collapsed.startIndex, offsetBy: maxLength)
    return "\(collapsed[..<limitIndex])..."
  }

  static let timestampFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone.current
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return formatter
  }()

}

#endif
