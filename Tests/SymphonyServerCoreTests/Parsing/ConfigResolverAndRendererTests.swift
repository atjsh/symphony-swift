import Foundation
import SymphonyShared
import Testing

@testable import SymphonyServerCore

// MARK: - ConfigResolver Tests

@Test func configResolverResolveEnvironmentVariables() throws {
  let result = try ConfigResolver.resolveEnvironmentVariables(
    in: "hello $FOO world $BAR",
    environment: ["FOO": "one", "BAR": "two"]
  )
  #expect(result == "hello one world two")
}

@Test func configResolverResolveEnvironmentVariablesMissing() throws {
  let result = try ConfigResolver.resolveEnvironmentVariables(
    in: "hello $MISSING_VAR world",
    environment: [:]
  )
  #expect(result == "hello $MISSING_VAR world")
}

@Test func configResolverResolveEnvironmentVariablesEmpty() throws {
  let result = try ConfigResolver.resolveEnvironmentVariables(
    in: "no variables",
    environment: [:]
  )
  #expect(result == "no variables")
}

@Test func configResolverExpandPath() {
  let expanded = ConfigResolver.expandPath("~/somedir")
  #expect(!expanded.hasPrefix("~"))
  #expect(expanded.hasSuffix("/somedir"))
}

@Test func configResolverExpandPathAbsolute() {
  let expanded = ConfigResolver.expandPath("/absolute/path")
  #expect(expanded == "/absolute/path")
}

@Test func configResolverResolveAPIKeyWithEnvVar() throws {
  let result = try ConfigResolver.resolveAPIKey(
    "$MY_API_KEY", environment: ["MY_API_KEY": "secret123"])
  #expect(result == "secret123")
}

@Test func configResolverResolveAPIKeyLiteral() throws {
  let result = try ConfigResolver.resolveAPIKey("literal-key", environment: [:])
  #expect(result == "literal-key")
}

@Test func configResolverResolveAPIKeyNil() throws {
  let result = try ConfigResolver.resolveAPIKey(nil, environment: [:])
  #expect(result == nil)
}

// MARK: - PromptRenderer Tests

@Test func promptRendererRenderWithVariables() throws {
  let issue = Issue(
    id: IssueID("test-id"),
    identifier: try IssueIdentifier(validating: "owner/repo#42"),
    repository: "owner/repo",
    number: 42,
    title: "Fix the bug",
    description: "Something is broken",
    priority: 1,
    state: "In Progress",
    issueState: "OPEN",
    projectItemID: nil,
    url: "https://github.com/owner/repo/issues/42",
    labels: ["bug"],
    blockedBy: [],
    createdAt: nil,
    updatedAt: nil
  )

  let template = "Fix {{issue.title}} in {{issue.repository}} (attempt {{attempt}})"
  let rendered = try PromptRenderer.render(template: template, issue: issue, attempt: 2)
  #expect(rendered == "Fix Fix the bug in owner/repo (attempt 2)")
}

@Test func promptRendererRenderAllVariables() throws {
  let issue = Issue(
    id: IssueID("id-1"),
    identifier: try IssueIdentifier(validating: "org/proj#10"),
    repository: "org/proj",
    number: 10,
    title: "Title",
    description: "Desc",
    priority: nil,
    state: "Active",
    issueState: "OPEN",
    projectItemID: nil,
    url: "https://example.com/10",
    labels: [],
    blockedBy: [],
    createdAt: nil,
    updatedAt: nil
  )

  let template =
    "{{issue.title}} {{issue.description}} {{issue.identifier}} {{issue.number}} {{issue.repository}} {{issue.state}} {{issue.url}} {{attempt}}"
  let rendered = try PromptRenderer.render(template: template, issue: issue, attempt: 1)
  #expect(rendered.contains("Title"))
  #expect(rendered.contains("Desc"))
  #expect(rendered.contains("org/proj#10"))
  #expect(rendered.contains("10"))
  #expect(rendered.contains("org/proj"))
  #expect(rendered.contains("Active"))
  #expect(rendered.contains("https://example.com/10"))
  #expect(rendered.contains("1"))
}

@Test func promptRendererRenderEmptyTemplate() throws {
  let issue = Issue(
    id: IssueID("id-1"),
    identifier: try IssueIdentifier(validating: "org/proj#10"),
    repository: "org/proj",
    number: 10,
    title: "My Title",
    description: "My Description",
    priority: nil,
    state: "Active",
    issueState: "OPEN",
    projectItemID: nil,
    url: nil,
    labels: [],
    blockedBy: [],
    createdAt: nil,
    updatedAt: nil
  )

  let rendered = try PromptRenderer.render(template: "", issue: issue, attempt: 1)
  #expect(rendered.contains("My Title"))
  #expect(rendered.contains("My Description"))
}

@Test func promptRendererUnknownVariableThrows() throws {
  let issue = Issue(
    id: IssueID("id-1"),
    identifier: try IssueIdentifier(validating: "org/proj#10"),
    repository: "org/proj",
    number: 10,
    title: "Title",
    description: nil,
    priority: nil,
    state: "Active",
    issueState: "OPEN",
    projectItemID: nil,
    url: nil,
    labels: [],
    blockedBy: [],
    createdAt: nil,
    updatedAt: nil
  )

  #expect(throws: PromptRenderError.unknownVariable("custom.thing")) {
    _ = try PromptRenderer.render(template: "Hello {{custom.thing}}", issue: issue, attempt: 1)
  }
}

@Test func promptRendererNilDescriptionBecomesEmpty() throws {
  let issue = Issue(
    id: IssueID("id-1"),
    identifier: try IssueIdentifier(validating: "org/proj#10"),
    repository: "org/proj",
    number: 10,
    title: "Title",
    description: nil,
    priority: nil,
    state: "Active",
    issueState: "OPEN",
    projectItemID: nil,
    url: nil,
    labels: [],
    blockedBy: [],
    createdAt: nil,
    updatedAt: nil
  )

  let rendered = try PromptRenderer.render(
    template: "Desc: {{issue.description}} URL: {{issue.url}}", issue: issue, attempt: 1)
  #expect(rendered == "Desc:  URL: ")
}

