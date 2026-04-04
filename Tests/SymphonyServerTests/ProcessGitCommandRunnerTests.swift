import Foundation
import Testing

@testable import SymphonyServer

// MARK: - Stub Process Runner

struct StubProcessRunner: ProcessRunning {
  var result: Result<Data, Error> = .success(Data())
  private(set) var lastArguments: [String]?
  private(set) var lastStandardInput: Data?

  // Record-capable variant using a class wrapper for mutation tracking
  final class Recorder: ProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    var result: Result<Data, Error> = .success(Data())
    private(set) var calls: [(executable: String, arguments: [String], standardInput: Data?)] = []

    func run(
      executable: String,
      arguments: [String],
      currentDirectoryPath: String?,
      standardInput: Data?
    ) throws -> Data {
      lock.withLock {
        calls.append((executable, arguments, standardInput))
      }
      return try result.get()
    }
  }

  func run(
    executable: String,
    arguments: [String],
    currentDirectoryPath: String?,
    standardInput: Data?
  ) throws -> Data {
    try result.get()
  }
}

// MARK: - ProcessGitCommandRunner Tests

@Suite("ProcessGitCommandRunner")
struct ProcessGitCommandRunnerTests {

  @Test func runDelegatesArgumentsToProcessRunner() throws {
    let recorder = StubProcessRunner.Recorder()
    recorder.result = .success(Data("output\n".utf8))
    let runner = ProcessGitCommandRunner(processRunner: recorder)

    let data = try runner.run(in: "/tmp/repo", arguments: ["status", "--short"])
    #expect(String(decoding: data, as: UTF8.self) == "output\n")
    #expect(recorder.calls.count == 1)
    #expect(recorder.calls[0].executable == "/usr/bin/env")
    #expect(recorder.calls[0].arguments == ["git", "-C", "/tmp/repo", "status", "--short"])
    #expect(recorder.calls[0].standardInput == nil)
  }

  @Test func loadBlobMetricsReturnsEmptyForEmptyBlobIDs() throws {
    let recorder = StubProcessRunner.Recorder()
    let runner = ProcessGitCommandRunner(processRunner: recorder)

    let result = try runner.loadBlobMetrics(in: "/tmp/repo", blobIDs: [])
    #expect(result.isEmpty)
    #expect(recorder.calls.isEmpty)
  }

  @Test func loadBlobMetricsParsesSingleBlob() throws {
    // Build cat-file --batch output: "<sha> blob <size>\n<content>\n"
    let content = "let x = 1\nlet y = 2\n"
    let header = "abc123 blob \(content.utf8.count)"
    var payload = Data()
    payload.append(Data(header.utf8))
    payload.append(10) // newline after header
    payload.append(Data(content.utf8))
    payload.append(10) // trailing newline separator

    let recorder = StubProcessRunner.Recorder()
    recorder.result = .success(payload)
    let runner = ProcessGitCommandRunner(processRunner: recorder)

    let result = try runner.loadBlobMetrics(in: "/tmp/repo", blobIDs: ["abc123"])
    #expect(result.count == 1)
    #expect(result["abc123"]?.textMetrics?.lineCount == 2)
    #expect(result["abc123"]?.textMetrics?.characterCount == content.count)

    // Verify stdin was piped
    #expect(recorder.calls.count == 1)
    #expect(recorder.calls[0].standardInput == Data("abc123\n".utf8))
    #expect(recorder.calls[0].arguments.contains("cat-file"))
  }

  @Test func loadBlobMetricsHandlesMalformedHeader() throws {
    // Header with only 2 fields instead of 3
    var payload = Data("abc123 blob".utf8)
    payload.append(10) // newline

    let recorder = StubProcessRunner.Recorder()
    recorder.result = .success(payload)
    let runner = ProcessGitCommandRunner(processRunner: recorder)

    let result = try runner.loadBlobMetrics(in: "/tmp/repo", blobIDs: ["abc123"])
    #expect(result.isEmpty)
  }

  @Test func loadBlobMetricsHandlesMissingNewline() throws {
    // No newline at all → firstIndex(of: 10) returns nil → break
    let payload = Data("abc123 blob 5 extra".utf8)

    let recorder = StubProcessRunner.Recorder()
    recorder.result = .success(payload)
    let runner = ProcessGitCommandRunner(processRunner: recorder)

    let result = try runner.loadBlobMetrics(in: "/tmp/repo", blobIDs: ["abc123"])
    #expect(result.isEmpty)
  }

  @Test func loadBlobMetricsMultipleBlobs() throws {
    let content1 = "line1\n"
    let content2 = "a\nb\nc\n"
    var payload = Data()

    // First blob
    payload.append(Data("blob1 blob \(content1.utf8.count)".utf8))
    payload.append(10)
    payload.append(Data(content1.utf8))
    payload.append(10) // separator newline

    // Second blob
    payload.append(Data("blob2 blob \(content2.utf8.count)".utf8))
    payload.append(10)
    payload.append(Data(content2.utf8))
    payload.append(10) // separator newline

    let recorder = StubProcessRunner.Recorder()
    recorder.result = .success(payload)
    let runner = ProcessGitCommandRunner(processRunner: recorder)

    let result = try runner.loadBlobMetrics(in: "/tmp/repo", blobIDs: ["blob1", "blob2"])
    #expect(result.count == 2)
    #expect(result["blob1"]?.textMetrics?.lineCount == 1)
    #expect(result["blob2"]?.textMetrics?.lineCount == 3)
  }

  @Test func processRunnerErrorPropagates() throws {
    let recorder = StubProcessRunner.Recorder()
    recorder.result = .failure(
      IssueProgressReportError.repositoryHistoryUnavailable("git failed")
    )
    let runner = ProcessGitCommandRunner(processRunner: recorder)

    #expect(throws: IssueProgressReportError.self) {
      _ = try runner.run(in: "/tmp/repo", arguments: ["log"])
    }
  }
}

// MARK: - ProcessShellCommandRunner Tests

@Suite("ProcessShellCommandRunner")
struct ProcessShellCommandRunnerTests {

  @Test func runDelegatesCommandToProcessRunner() throws {
    let recorder = StubProcessRunner.Recorder()
    recorder.result = .success(Data("hello\n".utf8))
    let runner = ProcessShellCommandRunner(processRunner: recorder)

    let output = try runner.run(command: "echo hello", in: "/tmp")
    #expect(output == "hello\n")
    #expect(recorder.calls.count == 1)
    #expect(recorder.calls[0].executable == "/bin/bash")
    #expect(recorder.calls[0].arguments == ["-lc", "echo hello"])
  }

  @Test func processRunnerErrorPropagates() throws {
    let recorder = StubProcessRunner.Recorder()
    recorder.result = .failure(
      IssueProgressReportError.repositoryHistoryUnavailable("bash failed")
    )
    let runner = ProcessShellCommandRunner(processRunner: recorder)

    #expect(throws: IssueProgressReportError.self) {
      _ = try runner.run(command: "fail", in: "/tmp")
    }
  }
}

// MARK: - DefaultProcessRunner Integration

@Suite("DefaultProcessRunner")
struct DefaultProcessRunnerTests {

  @Test func defaultProcessRunnerRunsRealCommand() throws {
    let runner = DefaultProcessRunner()
    let data = try runner.run(
      executable: "/bin/echo",
      arguments: ["hello"]
    )
    let output = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    #expect(output == "hello")
  }

  @Test func defaultProcessRunnerPipesStandardInput() throws {
    let runner = DefaultProcessRunner()
    let input = Data("hello from stdin\n".utf8)
    let data = try runner.run(
      executable: "/bin/cat",
      arguments: [],
      standardInput: input
    )
    let output = String(decoding: data, as: UTF8.self)
    #expect(output == "hello from stdin\n")
  }

  @Test func defaultProcessRunnerThrowsOnNonZeroExit() throws {
    let runner = DefaultProcessRunner()
    #expect(throws: IssueProgressReportError.self) {
      _ = try runner.run(
        executable: "/usr/bin/false",
        arguments: []
      )
    }
  }

  @Test func defaultProcessRunnerSetsCurrentDirectory() throws {
    let runner = DefaultProcessRunner()
    let data = try runner.run(
      executable: "/bin/pwd",
      arguments: [],
      currentDirectoryPath: "/tmp"
    )
    let output = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    #expect(output.hasSuffix("tmp"))
  }
}

// MARK: - Deprecated ProcessRunner Alias

@Suite("DeprecatedProcessRunner")
struct DeprecatedProcessRunnerTests {

  @Test func deprecatedProcessRunnerRunsRealCommand() throws {
    let data = try ProcessRunner.run(executable: "/bin/echo", arguments: ["deprecated-test"])
    let output = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    #expect(output == "deprecated-test")
  }

  @Test func deprecatedProcessRunnerPipesStandardInput() throws {
    let input = Data("pipe-test\n".utf8)
    let data = try ProcessRunner.run(
      executable: "/bin/cat",
      arguments: [],
      standardInput: input
    )
    let output = String(decoding: data, as: UTF8.self)
    #expect(output == "pipe-test\n")
  }
}

// MARK: - UnavailableRepositoryLanguageDetector

@Suite("UnavailableRepositoryLanguageDetector")
struct UnavailableRepositoryLanguageDetectorTests {

  @Test func unavailableDetectorVersionIsUnavailable() {
    let detector = UnavailableRepositoryLanguageDetector()
    #expect(detector.version == "unavailable")
  }

  @Test func unavailableDetectorIsBinaryThrows() {
    let detector = UnavailableRepositoryLanguageDetector()
    #expect(throws: IssueProgressReportError.self) {
      _ = try detector.isBinary(content: Data())
    }
  }

  @Test func unavailableDetectorDelegateMethodsReturnDefaults() throws {
    let detector = UnavailableRepositoryLanguageDetector()
    #expect(try detector.isConfiguration(path: "package.json") == false)
    #expect(try detector.isDocumentation(path: "README.md") == false)
    #expect(try detector.isDotFile(path: ".gitignore") == false)
    #expect(try detector.isImage(path: "photo.png") == false)
    #expect(try detector.isVendor(path: "vendor/lib.js") == false)
    #expect(try detector.isGenerated(path: "generated.pb.swift", content: Data()) == false)
    #expect(try detector.isTest(path: "tests/test_main.py") == false)
    #expect(try detector.language(path: "main.swift", content: Data()) == nil)
    #expect(try detector.languageType(language: "Swift") == nil)
  }
}
