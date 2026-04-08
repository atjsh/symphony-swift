import Foundation
import SymphonyShared
import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore

// MARK: - RepositoryFileClassifier Mutation Hardening

@Suite("RepositoryFileClassifier Mutations")
struct RepositoryFileClassifierMutationTests {
  private let emptyHistory = AnalysisHistoryConfig(sourcePaths: [], testPaths: [])
  private let emptyContent = Data()

  // MARK: - classify: test path glob overrides detector

  @Test func testPathGlobOverridesDetectorClassification() throws {
    let detector = StubRepositoryLanguageDetector(
      testPaths: [],
      languagesByPath: ["Tests/FooTest.swift": "Swift"],
      languageTypes: ["Swift": "programming"]
    )
    let classifier = RepositoryFileClassifier(detector: detector)
    let history = AnalysisHistoryConfig(sourcePaths: [], testPaths: ["Tests/**"])

    // With glob matching, should be .test even though detector says programming
    let result = try classifier.classify(
      path: "Tests/FooTest.swift", content: Data("code".utf8), historyConfig: history)
    #expect(result == .test, "testPaths glob must override detector language classification")
  }

  @Test func sourcePathGlobOverridesDetectorClassification() throws {
    let detector = StubRepositoryLanguageDetector(
      testPaths: ["Generated/file.swift"],
      languagesByPath: [:],
      languageTypes: [:]
    )
    let classifier = RepositoryFileClassifier(detector: detector)
    let history = AnalysisHistoryConfig(sourcePaths: ["Generated/**"], testPaths: [])

    let result = try classifier.classify(
      path: "Generated/file.swift", content: emptyContent, historyConfig: history)
    #expect(result == .source, "sourcePaths glob must override detector test paths")
  }

  // MARK: - classify: detector other-pathways

  @Test func binaryContentClassifiedAsOther() throws {
    let detector = BinaryDetector()
    let classifier = RepositoryFileClassifier(detector: detector)

    let result = try classifier.classify(
      path: "image.png", content: Data([0xFF, 0xD8]), historyConfig: emptyHistory)
    #expect(result == .other, "Binary content must be classified as other")
  }

  @Test func vendorPathClassifiedAsOther() throws {
    let detector = StubRepositoryLanguageDetector(
      testPaths: [],
      languagesByPath: [:],
      languageTypes: [:],
      vendorPaths: ["vendor/lib.js"]
    )
    let classifier = RepositoryFileClassifier(detector: detector)

    let result = try classifier.classify(
      path: "vendor/lib.js", content: emptyContent, historyConfig: emptyHistory)
    #expect(result == .other, "Vendor path must be classified as other")
  }

  @Test func dotFileClassifiedAsOther() throws {
    let detector = StubRepositoryLanguageDetector(
      testPaths: [],
      languagesByPath: [:],
      languageTypes: [:],
      dotFiles: [".gitignore"]
    )
    let classifier = RepositoryFileClassifier(detector: detector)

    let result = try classifier.classify(
      path: ".gitignore", content: emptyContent, historyConfig: emptyHistory)
    #expect(result == .other, "Dot files must be classified as other")
  }

  // MARK: - classify: detector isTest fallback

  @Test func detectorIsTestReturnsTrueClassifiesAsTest() throws {
    let detector = StubRepositoryLanguageDetector(
      testPaths: ["src/Foo.test.ts"],
      languagesByPath: [:],
      languageTypes: [:]
    )
    let classifier = RepositoryFileClassifier(detector: detector)

    let result = try classifier.classify(
      path: "src/Foo.test.ts", content: emptyContent, historyConfig: emptyHistory)
    #expect(result == .test, "Detector isTest=true must yield .test via fallback path")
  }

  // MARK: - classify: isFallbackTestPath patterns

  @Test func fallbackTestPathPrefixTest_() throws {
    let detector = StubRepositoryLanguageDetector(
      testPaths: [],
      languagesByPath: [:],
      languageTypes: [:]
    )
    let classifier = RepositoryFileClassifier(detector: detector)

    let result = try classifier.classify(
      path: "test_something.py", content: emptyContent, historyConfig: emptyHistory)
    #expect(result == .test, "Path starting with test_ must match fallback pattern")
  }

  @Test func fallbackTestPathContainsDotTest() throws {
    let detector = StubRepositoryLanguageDetector(
      testPaths: [],
      languagesByPath: [:],
      languageTypes: [:]
    )
    let classifier = RepositoryFileClassifier(detector: detector)

    let result = try classifier.classify(
      path: "foo.test.js", content: emptyContent, historyConfig: emptyHistory)
    #expect(result == .test, "Path containing .test. must match fallback pattern")
  }

  @Test func fallbackTestPathContainsDotSpec() throws {
    let detector = StubRepositoryLanguageDetector(
      testPaths: [],
      languagesByPath: [:],
      languageTypes: [:]
    )
    let classifier = RepositoryFileClassifier(detector: detector)

    let result = try classifier.classify(
      path: "foo.spec.ts", content: emptyContent, historyConfig: emptyHistory)
    #expect(result == .test, "Path containing .spec. must match fallback pattern")
  }

  @Test func fallbackTestPathContains_test() throws {
    let detector = StubRepositoryLanguageDetector(
      testPaths: [],
      languagesByPath: [:],
      languageTypes: [:]
    )
    let classifier = RepositoryFileClassifier(detector: detector)

    let result = try classifier.classify(
      path: "foo_test.go", content: emptyContent, historyConfig: emptyHistory)
    #expect(result == .test, "Path containing _test. must match fallback pattern")
  }

  @Test func fallbackTestPathContains_tests() throws {
    let detector = StubRepositoryLanguageDetector(
      testPaths: [],
      languagesByPath: [:],
      languageTypes: [:]
    )
    let classifier = RepositoryFileClassifier(detector: detector)

    let result = try classifier.classify(
      path: "module_tests.rb", content: emptyContent, historyConfig: emptyHistory)
    #expect(result == .test, "Path containing _tests. must match fallback pattern")
  }

  // MARK: - classify: language-based classification

  @Test func programmingLanguageClassifiesAsSource() throws {
    let detector = StubRepositoryLanguageDetector(
      testPaths: [],
      languagesByPath: ["main.swift": "Swift"],
      languageTypes: ["Swift": "programming"]
    )
    let classifier = RepositoryFileClassifier(detector: detector)

    let result = try classifier.classify(
      path: "main.swift", content: Data("import Foundation".utf8), historyConfig: emptyHistory)
    #expect(result == .source, "Programming language must classify as source")
  }

  @Test func markupLanguageClassifiesAsSource() throws {
    let detector = StubRepositoryLanguageDetector(
      testPaths: [],
      languagesByPath: ["page.html": "HTML"],
      languageTypes: ["HTML": "Markup"]
    )
    let classifier = RepositoryFileClassifier(detector: detector)

    let result = try classifier.classify(
      path: "page.html", content: Data("<html>".utf8), historyConfig: emptyHistory)
    #expect(result == .source, "Markup language must classify as source")
  }

  @Test func dataLanguageClassifiesAsOther() throws {
    let detector = StubRepositoryLanguageDetector(
      testPaths: [],
      languagesByPath: ["data.json": "JSON"],
      languageTypes: ["JSON": "data"]
    )
    let classifier = RepositoryFileClassifier(detector: detector)

    let result = try classifier.classify(
      path: "data.json", content: Data("{}".utf8), historyConfig: emptyHistory)
    #expect(result == .other, "Data language type must classify as other")
  }

  @Test func emptyLanguageClassifiesAsOther() throws {
    let detector = StubRepositoryLanguageDetector(
      testPaths: [],
      languagesByPath: ["unknown": ""],
      languageTypes: ["": "programming"]
    )
    let classifier = RepositoryFileClassifier(detector: detector)

    let result = try classifier.classify(
      path: "unknown", content: emptyContent, historyConfig: emptyHistory)
    #expect(result == .other, "Empty language must classify as other (tests !language.isEmpty)")
  }

  @Test func nilLanguageClassifiesAsOther() throws {
    let detector = StubRepositoryLanguageDetector(
      testPaths: [],
      languagesByPath: [:],
      languageTypes: [:]
    )
    let classifier = RepositoryFileClassifier(detector: detector)

    let result = try classifier.classify(
      path: "mystery.xyz", content: emptyContent, historyConfig: emptyHistory)
    #expect(result == .other, "nil language must classify as other")
  }

  @Test func nilLanguageTypeClassifiesAsOther() throws {
    let detector = StubRepositoryLanguageDetector(
      testPaths: [],
      languagesByPath: ["file.lang": "ExoticLang"],
      languageTypes: [:]
    )
    let classifier = RepositoryFileClassifier(detector: detector)

    let result = try classifier.classify(
      path: "file.lang", content: emptyContent, historyConfig: emptyHistory)
    #expect(result == .other, "Known language with nil type must classify as other")
  }

  // MARK: - classify: precedence chain order

  @Test func testPathsGlobHasHighestPrecedence() throws {
    let detector = StubRepositoryLanguageDetector(
      testPaths: [],
      languagesByPath: ["Tests/main.swift": "Swift"],
      languageTypes: ["Swift": "programming"],
      vendorPaths: ["Tests/main.swift"]
    )
    let classifier = RepositoryFileClassifier(detector: detector)
    let history = AnalysisHistoryConfig(
      sourcePaths: ["Tests/**"],
      testPaths: ["Tests/**"]
    )

    // testPaths checked before sourcePaths
    let result = try classifier.classify(
      path: "Tests/main.swift", content: emptyContent, historyConfig: history)
    #expect(result == .test, "testPaths glob must be checked before sourcePaths")
  }

  @Test func sourcePathsGlobBeforeDetector() throws {
    let detector = StubRepositoryLanguageDetector(
      testPaths: [],
      languagesByPath: [:],
      languageTypes: [:],
      vendorPaths: ["Generated/file.g.swift"]
    )
    let classifier = RepositoryFileClassifier(detector: detector)
    let history = AnalysisHistoryConfig(sourcePaths: ["Generated/**"], testPaths: [])

    // sourcePaths checked before detector.isVendor
    let result = try classifier.classify(
      path: "Generated/file.g.swift", content: emptyContent, historyConfig: history)
    #expect(result == .source, "sourcePaths glob must be checked before vendor detection")
  }

  // MARK: - version passthrough

  @Test func classifierVersionDelegatesToDetector() {
    let detector = StubRepositoryLanguageDetector(
      testPaths: [],
      languagesByPath: [:],
      languageTypes: [:],
      version: "test-v42"
    )
    let classifier = RepositoryFileClassifier(detector: detector)
    #expect(classifier.version == "test-v42")
  }
}

// MARK: - ProcessRepositorySyntaxHealthRunner Mutation Hardening

@Suite("SyntaxHealth Mutations")
struct SyntaxHealthMutationTests {
  @Test func nilCommandReturnsUnsupported() {
    let runner = ProcessRepositorySyntaxHealthRunner()
    let config = AnalysisSyntaxConfig(command: nil)
    let result = runner.syntaxHealth(in: "/tmp", syntaxConfig: config)
    #expect(result.status == .unsupported, "nil command must return unsupported")
    #expect(result.checkedFileCount == 0)
    #expect(result.diagnosticCount == 0)
  }

  @Test func emptyCommandReturnsUnsupported() {
    let runner = ProcessRepositorySyntaxHealthRunner()
    let config = AnalysisSyntaxConfig(command: "")
    let result = runner.syntaxHealth(in: "/tmp", syntaxConfig: config)
    #expect(result.status == .unsupported, "Empty command must return unsupported (tests !isEmpty)")
  }

  @Test func whitespaceOnlyCommandReturnsUnsupported() {
    let runner = ProcessRepositorySyntaxHealthRunner()
    let config = AnalysisSyntaxConfig(command: "   \t  ")
    let result = runner.syntaxHealth(in: "/tmp", syntaxConfig: config)
    #expect(
      result.status == .unsupported,
      "Whitespace-only command must return unsupported (tests trimmingCharacters + isEmpty)"
    )
  }
}

// MARK: - Helpers

private struct BinaryDetector: RepositoryLanguageDetecting {
  var version: String { "binary-stub" }
  func isBinary(content: Data) throws -> Bool { true }
  func isConfiguration(path: String) throws -> Bool { false }
  func isDocumentation(path: String) throws -> Bool { false }
  func isDotFile(path: String) throws -> Bool { false }
  func isImage(path: String) throws -> Bool { false }
  func isVendor(path: String) throws -> Bool { false }
  func isGenerated(path: String, content: Data) throws -> Bool { false }
  func isTest(path: String) throws -> Bool { false }
  func language(path: String, content: Data) throws -> String? { nil }
  func languageType(language: String) throws -> String? { nil }
}
