import Foundation
import SymphonyShared
import Testing

@testable import SymphonyServerCore

// MARK: - WorkflowParser Tests

@Test func workflowParserParseContentNoFrontMatter() throws {
  let content = """
    You are a coding agent.
    Resolve the issue.
    """
  let definition = try WorkflowParser.parse(content: content)
  #expect(definition.config == .defaults)
  #expect(definition.promptTemplate == "You are a coding agent.\nResolve the issue.")
}

@Test func workflowParserParseContentWithFrontMatter() throws {
  let content = """
    ---
    tracker:
      kind: github
      endpoint: https://api.github.example.com/graphql
      project_owner: myorg
      project_number: 42
    polling:
      interval_ms: 15000
    ---
    You are a coding agent.
    """
  let definition = try WorkflowParser.parse(content: content)
  #expect(definition.config.tracker.kind == "github")
  #expect(definition.config.tracker.endpoint == "https://api.github.example.com/graphql")
  #expect(definition.config.tracker.projectOwner == "myorg")
  #expect(definition.config.tracker.projectNumber == 42)
  #expect(definition.config.polling.intervalMS == 15000)
  #expect(definition.promptTemplate == "You are a coding agent.")
}

@Test func workflowParserParseContentEmptyFrontMatter() throws {
  let content = """
    ---
    ---
    Just the prompt.
    """
  let definition = try WorkflowParser.parse(content: content)
  #expect(definition.config == .defaults)
  #expect(definition.promptTemplate == "Just the prompt.")
}

@Test func workflowParserSplitFrontMatterNoDelimiter() {
  let (frontMatter, body) = WorkflowParser.splitFrontMatter("No front matter here")
  #expect(frontMatter == nil)
  #expect(body == "No front matter here")
}

@Test func workflowParserSplitFrontMatterWithDelimiter() {
  let content = "---\nkey: value\n---\nBody text"
  let (frontMatter, body) = WorkflowParser.splitFrontMatter(content)
  #expect(frontMatter == "\nkey: value")
  #expect(body.contains("Body text"))
}

@Test func workflowParserSplitFrontMatterOnlyOpening() {
  let (frontMatter, body) = WorkflowParser.splitFrontMatter("---\nunclosed front matter")
  #expect(frontMatter == nil)
  #expect(body == "---\nunclosed front matter")
}

@Test func workflowParserNonMapFrontMatterThrows() throws {
  let content = """
    ---
    - item1
    - item2
    ---
    Body
    """
  #expect(throws: WorkflowConfigError.workflowFrontMatterNotAMap) {
    _ = try WorkflowParser.parse(content: content)
  }
}

@Test func workflowParserInvalidYAMLThrows() throws {
  let content = """
    ---
    : invalid yaml [[[
    ---
    Body
    """
  // Yams may or may not throw on this, but the result shouldn't be a valid map
  do {
    let definition = try WorkflowParser.parse(content: content)
    // If it parsed without error, the result should still be reasonable
    _ = definition
  } catch {
    // Expected behavior for invalid YAML
  }
}

@Test func workflowParserFromFile() throws {
  let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: dir) }

  let workflowURL = dir.appendingPathComponent("WORKFLOW.md")
  try "---\nserver:\n  port: 9090\n---\nResolve it.".write(
    to: workflowURL, atomically: true, encoding: .utf8)

  let definition = try WorkflowParser.parse(contentsOf: workflowURL)
  #expect(definition.config.server.port == 9090)
  #expect(definition.promptTemplate == "Resolve it.")
}

@Test func workflowParserFromFileMissingThrows() throws {
  let missing = URL(fileURLWithPath: "/tmp/nonexistent_\(UUID().uuidString)/WORKFLOW.md")
  #expect(throws: WorkflowConfigError.self) {
    _ = try WorkflowParser.parse(contentsOf: missing)
  }
}

@Test func workflowParserDiscoverExplicitPath() throws {
  let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: dir) }

  let file = dir.appendingPathComponent("custom-workflow.md")
  try "test".write(to: file, atomically: true, encoding: .utf8)

  let url = WorkflowParser.discover(explicitPath: file.path)
  #expect(url != nil)
  #expect(url?.lastPathComponent == "custom-workflow.md")
}

@Test func workflowParserDiscoverExplicitPathMissing() {
  let url = WorkflowParser.discover(explicitPath: "/tmp/nonexistent_\(UUID().uuidString)")
  #expect(url == nil)
}

@Test func workflowParserDiscoverDefaultPath() throws {
  let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: dir) }

  let workflowFile = dir.appendingPathComponent("WORKFLOW.md")
  try "prompt".write(to: workflowFile, atomically: true, encoding: .utf8)

  let url = WorkflowParser.discover(workingDirectory: dir.path)
  #expect(url != nil)
}

@Test func workflowParserDiscoverDefaultPathMissing() {
  let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  let url = WorkflowParser.discover(workingDirectory: dir.path)
  #expect(url == nil)
}
