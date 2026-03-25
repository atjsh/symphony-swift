import Foundation
import SymphonyShared
import Testing

@testable import SymphonyRuntime

// MARK: - Helper

private func makeTempRoot() throws -> (path: String, cleanup: () -> Void) {
  let root = NSTemporaryDirectory() + "symphony_test_\(UUID().uuidString)"
  try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
  return (root, { try? FileManager.default.removeItem(atPath: root) })
}

// MARK: - WorkspaceManager Tests

@Test func workspaceManagerWorkspacePath() throws {
  let (root, cleanup) = try makeTempRoot()
  defer { cleanup() }

  let manager = WorkspaceManager(root: root)
  let key = WorkspaceKey("owner_repo_42")
  let path = manager.workspacePath(for: key)
  #expect(path == (root as NSString).appendingPathComponent("owner_repo_42"))
}

@Test func workspaceManagerEnsureWorkspaceCreatesDirectory() throws {
  let (root, cleanup) = try makeTempRoot()
  defer { cleanup() }

  let manager = WorkspaceManager(root: root)
  let key = WorkspaceKey("test_workspace")
  let hooks = HooksConfig.defaults

  let path = try manager.ensureWorkspace(for: key, hooks: hooks)
  #expect(FileManager.default.fileExists(atPath: path))
}

@Test func workspaceManagerEnsureWorkspaceIdempotent() throws {
  let (root, cleanup) = try makeTempRoot()
  defer { cleanup() }

  let hookRunner = StubHookRunner()
  let manager = WorkspaceManager(root: root, hookRunner: hookRunner)
  let key = WorkspaceKey("test_workspace")
  let hooks = HooksConfig(afterCreate: "echo hello")

  // First call creates it and runs after_create
  let path1 = try manager.ensureWorkspace(for: key, hooks: hooks)
  #expect(hookRunner.invocations.count == 1)
  #expect(hookRunner.invocations[0].name == "after_create")

  // Second call is idempotent - no additional hooks
  let path2 = try manager.ensureWorkspace(for: key, hooks: hooks)
  #expect(path1 == path2)
  #expect(hookRunner.invocations.count == 1)
}

@Test func workspaceManagerEnsureWorkspaceRunsAfterCreateHook() throws {
  let (root, cleanup) = try makeTempRoot()
  defer { cleanup() }

  let hookRunner = StubHookRunner()
  let manager = WorkspaceManager(root: root, hookRunner: hookRunner)
  let key = WorkspaceKey("hook_test")
  let hooks = HooksConfig(afterCreate: "git init")

  _ = try manager.ensureWorkspace(for: key, hooks: hooks)

  #expect(hookRunner.invocations.count == 1)
  #expect(hookRunner.invocations[0].name == "after_create")
  #expect(hookRunner.invocations[0].script == "git init")
}

@Test func workspaceManagerEnsureWorkspaceNoAfterCreateHook() throws {
  let (root, cleanup) = try makeTempRoot()
  defer { cleanup() }

  let hookRunner = StubHookRunner()
  let manager = WorkspaceManager(root: root, hookRunner: hookRunner)
  let key = WorkspaceKey("no_hook_test")
  let hooks = HooksConfig.defaults

  _ = try manager.ensureWorkspace(for: key, hooks: hooks)
  #expect(hookRunner.invocations.isEmpty)
}

@Test func workspaceManagerRemoveWorkspace() throws {
  let (root, cleanup) = try makeTempRoot()
  defer { cleanup() }

  let manager = WorkspaceManager(root: root)
  let key = WorkspaceKey("to_remove")
  let hooks = HooksConfig.defaults

  let path = try manager.ensureWorkspace(for: key, hooks: hooks)
  #expect(FileManager.default.fileExists(atPath: path))

  try manager.removeWorkspace(for: key, hooks: hooks)
  #expect(!FileManager.default.fileExists(atPath: path))
}

@Test func workspaceManagerRemoveNonexistentWorkspace() throws {
  let (root, cleanup) = try makeTempRoot()
  defer { cleanup() }

  let manager = WorkspaceManager(root: root)
  let key = WorkspaceKey("nonexistent")
  let hooks = HooksConfig.defaults

  // Should not throw for nonexistent workspace
  try manager.removeWorkspace(for: key, hooks: hooks)
}

@Test func workspaceManagerRemoveWorkspaceRunsBeforeRemoveHook() throws {
  let (root, cleanup) = try makeTempRoot()
  defer { cleanup() }

  let hookRunner = StubHookRunner()
  let manager = WorkspaceManager(root: root, hookRunner: hookRunner)
  let key = WorkspaceKey("hook_remove")
  let hooks = HooksConfig(beforeRemove: "cleanup.sh")

  _ = try manager.ensureWorkspace(for: key, hooks: hooks)
  try manager.removeWorkspace(for: key, hooks: hooks)

  let removeInvocations = hookRunner.invocations.filter { $0.name == "before_remove" }
  #expect(removeInvocations.count == 1)
  #expect(removeInvocations[0].script == "cleanup.sh")
}

@Test func workspaceManagerRemoveWorkspaceBeforeRemoveFailureIgnored() throws {
  let (root, cleanup) = try makeTempRoot()
  defer { cleanup() }

  let hookRunner = StubHookRunner()
  hookRunner.setBehavior { name in
    if name == "before_remove" {
      throw WorkspaceError.hookFailed(hook: name, exitCode: 1)
    }
  }
  let manager = WorkspaceManager(root: root, hookRunner: hookRunner)
  let key = WorkspaceKey("hook_fail_remove")
  let hooks = HooksConfig(beforeRemove: "fail.sh")

  _ = try manager.ensureWorkspace(for: key, hooks: hooks)
  // Should not throw even though before_remove fails
  try manager.removeWorkspace(for: key, hooks: hooks)
}

@Test func workspaceManagerContainmentValidation() throws {
  let (root, cleanup) = try makeTempRoot()
  defer { cleanup() }

  let manager = WorkspaceManager(root: root)

  // Valid paths
  try manager.validateContainment(path: root + "/subdir")
  try manager.validateContainment(path: root + "/deep/nested/path")

  // Invalid paths
  #expect(throws: WorkspaceError.self) {
    try manager.validateContainment(path: "/etc/passwd")
  }
  #expect(throws: WorkspaceError.self) {
    try manager.validateContainment(path: root + "/../escape")
  }
}

@Test func workspaceManagerEnsureWorkspaceContainmentViolation() throws {
  let (root, cleanup) = try makeTempRoot()
  defer { cleanup() }

  // WorkspaceKey sanitizes path-traversal characters, so test validateContainment directly
  let manager = WorkspaceManager(root: root + "/subdir")
  try FileManager.default.createDirectory(
    atPath: root + "/subdir", withIntermediateDirectories: true)
  let escapingPath = root + "/subdir/../escape"

  #expect(throws: WorkspaceError.self) {
    try manager.validateContainment(path: escapingPath)
  }
}

@Test func workspaceManagerBeforeRunHook() throws {
  let hookRunner = StubHookRunner()
  let (root, cleanup) = try makeTempRoot()
  defer { cleanup() }

  let manager = WorkspaceManager(root: root, hookRunner: hookRunner)
  let hooks = HooksConfig(beforeRun: "prepare.sh")
  let path = root + "/workspace"
  try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)

  try manager.runBeforeRunHook(workspacePath: path, hooks: hooks)
  #expect(hookRunner.invocations.count == 1)
  #expect(hookRunner.invocations[0].name == "before_run")
  #expect(hookRunner.invocations[0].script == "prepare.sh")
}

@Test func workspaceManagerBeforeRunHookNotConfigured() throws {
  let hookRunner = StubHookRunner()
  let (root, cleanup) = try makeTempRoot()
  defer { cleanup() }

  let manager = WorkspaceManager(root: root, hookRunner: hookRunner)
  let hooks = HooksConfig.defaults

  try manager.runBeforeRunHook(workspacePath: root, hooks: hooks)
  #expect(hookRunner.invocations.isEmpty)
}

@Test func workspaceManagerAfterRunHook() throws {
  let hookRunner = StubHookRunner()
  let (root, cleanup) = try makeTempRoot()
  defer { cleanup() }

  let manager = WorkspaceManager(root: root, hookRunner: hookRunner)
  let hooks = HooksConfig(afterRun: "test.sh")

  manager.runAfterRunHook(workspacePath: root, hooks: hooks)
  #expect(hookRunner.invocations.count == 1)
  #expect(hookRunner.invocations[0].name == "after_run")
}

@Test func workspaceManagerAfterRunHookFailureIgnored() throws {
  let hookRunner = StubHookRunner()
  hookRunner.setBehavior { name in
    if name == "after_run" {
      throw WorkspaceError.hookFailed(hook: name, exitCode: 1)
    }
  }
  let (root, cleanup) = try makeTempRoot()
  defer { cleanup() }

  let manager = WorkspaceManager(root: root, hookRunner: hookRunner)
  let hooks = HooksConfig(afterRun: "fail.sh")

  // Should not throw
  manager.runAfterRunHook(workspacePath: root, hooks: hooks)
}

@Test func workspaceManagerAfterRunHookNotConfigured() throws {
  let hookRunner = StubHookRunner()
  let (root, cleanup) = try makeTempRoot()
  defer { cleanup() }

  let manager = WorkspaceManager(root: root, hookRunner: hookRunner)
  let hooks = HooksConfig.defaults

  manager.runAfterRunHook(workspacePath: root, hooks: hooks)
  #expect(hookRunner.invocations.isEmpty)
}

// MARK: - WorkspaceError Tests

@Test func workspaceErrorEquatable() {
  let a = WorkspaceError.rootContainmentViolation(path: "/a", root: "/b")
  let b = WorkspaceError.rootContainmentViolation(path: "/a", root: "/b")
  let c = WorkspaceError.hookFailed(hook: "test", exitCode: 1)
  #expect(a == b)
  #expect(a != c)

  #expect(
    WorkspaceError.hookTimedOut(hook: "h", timeoutMS: 1000)
      == .hookTimedOut(hook: "h", timeoutMS: 1000))
  #expect(WorkspaceError.workspaceCreationFailed("err") == .workspaceCreationFailed("err"))
}

// MARK: - StubHookRunner Tests

@Test func stubHookRunnerRecordsInvocations() throws {
  let runner = StubHookRunner()
  try runner.run(name: "test", script: "echo hi", workspacePath: "/tmp", timeoutMS: 1000)
  #expect(runner.invocations.count == 1)
  #expect(runner.invocations[0].name == "test")
  #expect(runner.invocations[0].script == "echo hi")
  #expect(runner.invocations[0].workspacePath == "/tmp")
}

@Test func stubHookRunnerCustomBehavior() {
  let runner = StubHookRunner()
  runner.setBehavior { name in
    throw WorkspaceError.hookFailed(hook: name, exitCode: 99)
  }
  #expect(throws: WorkspaceError.self) {
    try runner.run(name: "failing", script: "fail", workspacePath: "/tmp", timeoutMS: 1000)
  }
}

@Test func workspaceManagerAfterCreateHookFailureAbortsCreation() throws {
  let (root, cleanup) = try makeTempRoot()
  defer { cleanup() }

  let hookRunner = StubHookRunner()
  hookRunner.setBehavior { name in
    if name == "after_create" {
      throw WorkspaceError.hookFailed(hook: name, exitCode: 1)
    }
  }
  let manager = WorkspaceManager(root: root, hookRunner: hookRunner)
  let key = WorkspaceKey("fail_create")
  let hooks = HooksConfig(afterCreate: "fail.sh")

  #expect(throws: WorkspaceError.self) {
    _ = try manager.ensureWorkspace(for: key, hooks: hooks)
  }
}

@Test func workspaceManagerCreationFailedError() throws {
  let (root, cleanup) = try makeTempRoot()
  defer { cleanup() }

  // Create a file where the workspace directory should be, so directory creation fails
  let blockingPath = root + "/blocker"
  FileManager.default.createFile(atPath: blockingPath, contents: nil)
  let manager = WorkspaceManager(root: root)
  // The key sanitized to "blocker_nested" and we create a file at root/blocker,
  // then try to create root/blocker/nested — directory creation will fail because blocker is a file.
  // Actually, let's use the blocking file directly.
  let key = WorkspaceKey("blocker")
  // Since the file exists, ensureWorkspace is idempotent (file exists check passes).
  // We need the key to map to a path that conflicts.
  // Better approach: make the root read-only
  let readOnlyRoot = root + "/readonly"
  try FileManager.default.createDirectory(atPath: readOnlyRoot, withIntermediateDirectories: true)

  // Create a file at the exact path where workspace directory would be created
  let keyName = "workspace_dir"
  let filePath = readOnlyRoot + "/" + keyName
  FileManager.default.createFile(atPath: filePath, contents: Data("block".utf8))

  // Now remove the file and make parent unwritable
  try FileManager.default.removeItem(atPath: filePath)
  try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: readOnlyRoot)
  defer {
    try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: readOnlyRoot)
  }

  let roManager = WorkspaceManager(root: readOnlyRoot)
  let roKey = WorkspaceKey(keyName)
  let hooks = HooksConfig.defaults

  #expect(throws: WorkspaceError.self) {
    _ = try roManager.ensureWorkspace(for: roKey, hooks: hooks)
  }
}

// MARK: - ProcessHookRunner Tests

@Test func processHookRunnerSuccess() throws {
  let runner = ProcessHookRunner()
  let tmpDir = NSTemporaryDirectory()
  try runner.run(name: "test_hook", script: "echo hello", workspacePath: tmpDir, timeoutMS: 5000)
}

@Test func processHookRunnerFailure() throws {
  let runner = ProcessHookRunner()
  let tmpDir = NSTemporaryDirectory()
  #expect(throws: WorkspaceError.self) {
    try runner.run(name: "fail_hook", script: "exit 1", workspacePath: tmpDir, timeoutMS: 5000)
  }
}

@Test func processHookRunnerTimeout() throws {
  let runner = ProcessHookRunner()
  let tmpDir = NSTemporaryDirectory()
  #expect(throws: WorkspaceError.self) {
    try runner.run(name: "timeout_hook", script: "sleep 60", workspacePath: tmpDir, timeoutMS: 100)
  }
}
