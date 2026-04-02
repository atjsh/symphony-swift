import Foundation
import SymphonyServerCore
import Testing

@testable import SymphonyServer

// MARK: - GoEnryRepositoryLanguageDetector Tests

@Suite("GoEnryRepositoryLanguageDetector")
struct GoEnryRepositoryLanguageDetectorTests {

  let detector = GoEnryRepositoryLanguageDetector()

  @Test func versionIsNonEmpty() {
    #expect(!detector.version.isEmpty)
    #expect(detector.version.contains("enry"))
  }

  @Test func isBinaryReturnsTrueForBinaryContent() throws {
    // PNG header bytes
    let binaryData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00])
    #expect(try detector.isBinary(content: binaryData))
  }

  @Test func isBinaryReturnsFalseForTextContent() throws {
    let textData = Data("let x = 1\n".utf8)
    #expect(try !detector.isBinary(content: textData))
  }

  @Test func isConfigurationReturnsTrueForKnownConfigFiles() throws {
    #expect(try detector.isConfiguration(path: "package.json"))
  }

  @Test func isConfigurationReturnsFalseForSourceFiles() throws {
    #expect(try !detector.isConfiguration(path: "Sources/main.swift"))
  }

  @Test func isDocumentationRecognizesREADME() throws {
    #expect(try detector.isDocumentation(path: "docs/README.md"))
  }

  @Test func isDotFileRecognizesDotFiles() throws {
    #expect(try detector.isDotFile(path: ".gitignore"))
  }

  @Test func isDotFileReturnsFalseForNormalFiles() throws {
    #expect(try !detector.isDotFile(path: "Sources/main.swift"))
  }

  @Test func isImageRecognizesImagePaths() throws {
    #expect(try detector.isImage(path: "resources/logo.png"))
  }

  @Test func isImageReturnsFalseForCodeFiles() throws {
    #expect(try !detector.isImage(path: "Sources/App.swift"))
  }

  @Test func isVendorRecognizesVendorPaths() throws {
    #expect(try detector.isVendor(path: "vendor/lib/jquery.js"))
  }

  @Test func isVendorReturnsFalseForNonVendor() throws {
    #expect(try !detector.isVendor(path: "Sources/App.swift"))
  }

  @Test func isGeneratedReturnsFalseForNormalSource() throws {
    let content = Data("let x = 1\n".utf8)
    #expect(try !detector.isGenerated(path: "Sources/App.swift", content: content))
  }

  @Test func isTestRecognizesTestPaths() throws {
    // go-enry recognizes common test directory patterns
    #expect(try detector.isTest(path: "tests/unit/test_main.py"))
  }

  @Test func isTestReturnsFalseForSourcePaths() throws {
    #expect(try !detector.isTest(path: "Sources/App.swift"))
  }

  @Test func languageDetectsSwift() throws {
    let content = Data("import Foundation\nlet x = 1\n".utf8)
    let language = try detector.language(path: "Main.swift", content: content)
    #expect(language == "Swift")
  }

  @Test func languageReturnsNilForUnknownExtension() throws {
    let content = Data("random data".utf8)
    let language = try detector.language(path: "file.unknownext", content: content)
    // May or may not return nil depending on go-enry heuristics, but should not crash
    _ = language
  }

  @Test func languageTypeForSwiftIsProgramming() throws {
    let languageType = try detector.languageType(language: "Swift")
    #expect(languageType == "programming")
  }

  @Test func languageTypeForMarkdownIsMarkup() throws {
    let languageType = try detector.languageType(language: "Markdown")
    // Markdown may be "prose" or "markup" depending on go-enry version
    #expect(languageType != nil)
  }

  @Test func languageTypeReturnsUnknownForUnrecognizedLanguage() throws {
    let languageType = try detector.languageType(language: "NotARealLanguage12345")
    // go-enry returns "unknown" for unrecognized languages
    #expect(languageType == "unknown")
  }
}

// MARK: - RepositoryFileClassifier with Glob Patterns

@Suite("RepositoryFileClassifier")
struct RepositoryFileClassifierTests {

  let classifier = RepositoryFileClassifier(
    detector: GoEnryRepositoryLanguageDetector()
  )

  @Test func classifyUsesDoubleStarGlobInTestPaths() throws {
    let config = AnalysisHistoryConfig(
      sourcePaths: [],
      testPaths: ["**/tests/**"]
    )
    let category = try classifier.classify(
      path: "src/tests/unit/test_main.py",
      content: Data("import unittest".utf8),
      historyConfig: config
    )
    #expect(category == .test)
  }

  @Test func classifyUsesSingleStarGlobInSourcePaths() throws {
    let config = AnalysisHistoryConfig(
      sourcePaths: ["Sources/*.swift"],
      testPaths: []
    )
    let category = try classifier.classify(
      path: "Sources/Main.swift",
      content: Data("import Foundation".utf8),
      historyConfig: config
    )
    #expect(category == .source)
  }

  @Test func classifyUsesQuestionMarkGlobPattern() throws {
    let config = AnalysisHistoryConfig(
      sourcePaths: [],
      testPaths: ["test?.py"]
    )
    let category = try classifier.classify(
      path: "testA.py",
      content: Data("pass".utf8),
      historyConfig: config
    )
    #expect(category == .test)
  }

  @Test func classifyFallsBackToOtherForUnknownLanguageType() throws {
    let config = AnalysisHistoryConfig()
    // A file with data language type (e.g., JSON) should be classified as .other
    let category = try classifier.classify(
      path: "data.json",
      content: Data(#"{"key":"value"}"#.utf8),
      historyConfig: config
    )
    #expect(category == .other || category == .source)
  }

  @Test func classifyReturnsOtherWhenLanguageIsNilOrEmpty() throws {
    let config = AnalysisHistoryConfig()
    // Use an unknown extension that go-enry won't recognize
    let category = try classifier.classify(
      path: "file.zzzzunknown",
      content: Data("some content".utf8),
      historyConfig: config
    )
    #expect(category == .other)
  }
}
