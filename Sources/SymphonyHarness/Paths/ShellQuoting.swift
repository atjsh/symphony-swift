import Foundation

enum ShellQuoting {
  static func render(command: String, arguments: [String]) -> String {
    ([command] + arguments).map(quote).joined(separator: " ")
  }

  static func quote(_ value: String) -> String {
    guard !value.isEmpty else {
      return "''"
    }

    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "/:._-="))
    if value.unicodeScalars.allSatisfy({ allowed.contains($0) }) {
      return value
    }

    return "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
  }

  static func slugify(_ value: String) -> String {
    let allowed = CharacterSet(
      charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")
    return String(value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
      .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
      .lowercased()
  }
}
