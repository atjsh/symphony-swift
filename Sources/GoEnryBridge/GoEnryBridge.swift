import CGoEnryBridge
import Foundation

public struct GoEnryLanguageDetector: Sendable {
  public let version: String

  public init(version: String = "go-enry@v2.9.5") {
    self.version = version
  }

  public func isBinary(content: Data) -> Bool {
    content.withUnsafeBytes { rawBuffer in
      SymphonyGoEnryIsBinary(
        rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self),
        rawBuffer.count
      )
    }
  }

  public func isConfiguration(path: String) -> Bool {
    path.withCString { SymphonyGoEnryIsConfiguration($0) }
  }

  public func isDocumentation(path: String) -> Bool {
    path.withCString { SymphonyGoEnryIsDocumentation($0) }
  }

  public func isDotFile(path: String) -> Bool {
    path.withCString { SymphonyGoEnryIsDotFile($0) }
  }

  public func isImage(path: String) -> Bool {
    path.withCString { SymphonyGoEnryIsImage($0) }
  }

  public func isVendor(path: String) -> Bool {
    path.withCString { SymphonyGoEnryIsVendor($0) }
  }

  public func isGenerated(path: String, content: Data) -> Bool {
    path.withCString { cPath in
      content.withUnsafeBytes { rawBuffer in
        SymphonyGoEnryIsGenerated(
          cPath,
          rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self),
          rawBuffer.count
        )
      }
    }
  }

  public func isTest(path: String) -> Bool {
    path.withCString { SymphonyGoEnryIsTest($0) }
  }

  public func language(path: String, content: Data) -> String? {
    path.withCString { cPath in
      content.withUnsafeBytes { rawBuffer in
        makeString {
          SymphonyGoEnryGetLanguage(
            cPath,
            rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self),
            rawBuffer.count
          )
        }
      }
    }
  }

  public func languageType(language: String) -> String? {
    language.withCString { cLanguage in
      makeString {
        SymphonyGoEnryGetLanguageType(cLanguage)
      }
    }
  }

  private func makeString(_ body: () -> UnsafeMutablePointer<CChar>?) -> String? {
    guard let pointer = body() else {
      return nil
    }
    defer { SymphonyGoEnryFreeCString(pointer) }
    let value = String(cString: pointer)
    return value.isEmpty ? nil : value
  }
}
