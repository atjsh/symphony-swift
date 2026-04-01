import Foundation

extension Data {
  package init?(base64URLEncoded rawValue: String) {
    var base64 =
      rawValue
      .replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")

    let remainder = base64.count % 4
    if remainder != 0 {
      base64 += String(repeating: "=", count: 4 - remainder)
    }

    self.init(base64Encoded: base64)
  }

  package func base64URLEncodedString() -> String {
    base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}
