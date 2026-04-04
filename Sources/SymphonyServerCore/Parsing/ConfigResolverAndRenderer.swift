import Foundation
import SymphonyShared

// MARK: - Config Resolver (Section 6.4)

public enum ConfigResolver {
  public static func resolveEnvironmentVariables(
    in value: String,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) throws -> String {
    var result = value
    let pattern = "\\$([A-Za-z_][A-Za-z0-9_]*)"
    let regex = try NSRegularExpression(pattern: pattern)

    let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
    for match in matches.reversed() {
      guard let fullRange = Range(match.range, in: result),
        let varNameRange = Range(match.range(at: 1), in: result)
      else { continue }
      let varName = String(result[varNameRange])
      if let envValue = environment[varName] {
        result.replaceSubrange(fullRange, with: envValue)
      }
    }
    return result
  }

  public static func expandPath(_ path: String) -> String {
    NSString(string: path).expandingTildeInPath
  }

  public static func resolveAPIKey(
    _ rawKey: String?,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) throws -> String? {
    guard let rawKey else { return nil }
    if rawKey.hasPrefix("$") {
      return try resolveEnvironmentVariables(in: rawKey, environment: environment)
    }
    return rawKey
  }
}

// MARK: - Prompt Renderer (Section 6.5)

public enum PromptRenderError: Error, Equatable, Sendable {
  case unknownVariable(String)
}

public enum PromptRenderer {
  public static func render(
    template: String,
    issue: Issue,
    attempt: Int
  ) throws -> String {
    guard !template.isEmpty else {
      return "Resolve the following issue:\n\(issue.title)\n\(issue.description ?? "")"
    }

    var result = template
    let variables: [String: String] = [
      "{{issue.title}}": issue.title,
      "{{issue.description}}": issue.description ?? "",
      "{{issue.identifier}}": issue.identifier.rawValue,
      "{{issue.number}}": String(issue.number),
      "{{issue.repository}}": issue.repository,
      "{{issue.state}}": issue.state,
      "{{issue.url}}": issue.url ?? "",
      "{{attempt}}": String(attempt),
    ]

    for (placeholder, value) in variables {
      result = result.replacingOccurrences(of: placeholder, with: value)
    }

    let unknownPattern = "\\{\\{([^}]+)\\}\\}"
    if let regex = try? NSRegularExpression(pattern: unknownPattern),
      let match = regex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)),
      let range = Range(match.range(at: 1), in: result)
    {
      throw PromptRenderError.unknownVariable(String(result[range]))
    }

    return result
  }
}
