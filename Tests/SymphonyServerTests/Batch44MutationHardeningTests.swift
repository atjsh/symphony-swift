// Batch 44 – Mutation hardening for WorkspaceManager catch-block
// log emissions and post-failure state assertions.
//
// Targets:
//   WorkspaceManager.removeWorkspace – beforeRemove hook failure
//     catch block logs "workspace_hook_failure_ignored" AND workspace
//     is still removed despite hook failure.
//   WorkspaceManager.removeWorkspace – fileManager.removeItem failure
//     catch block logs "workspace_removal_failed" with workspace_path.
//   WorkspaceManager.ensureWorkspace – afterCreate hook failure
//     propagates error but leaves directory on disk.

import Foundation
import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore
@testable import SymphonyShared

// MARK: - Helpers

private func makeTempRoot() throws -> (path: String, cleanup: () -> Void) {
  let root = NSTemporaryDirectory() + "symphony_batch44_\(UUID().uuidString)"
  try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
  return (root, { try? FileManager.default.removeItem(atPath: root) })
}

// MARK: - removeWorkspace: beforeRemove failure log and removal

@Suite("WorkspaceManager removeWorkspace Catch Blocks")
struct WorkspaceManagerRemoveCatchBlockTests {

  /// When beforeRemove hook throws, removeWorkspace must:
  ///   1. Log "workspace_hook_failure_ignored" (kills RemoveSideEffects on catch-block log).
  ///   2. Still delete the workspace directory (kills mutation removing removeItem after catch).
  @Test func beforeRemoveFailureEmitsLogAndStillRemovesDirectory() async throws {
    let (root, cleanup) = try makeTempRoot()
    defer { cleanup() }

    let hookRunner = StubHookRunner()
    hookRunner.setBehavior { name in
      if name == "before_remove" {
        throw WorkspaceError.hookFailed(hook: name, exitCode: 1)
      }
    }
    let manager = WorkspaceManager(root: root, hookRunner: hookRunner)
    let key = WorkspaceKey("hook_fail_44")
    let hooks = HooksConfig(beforeRemove: "fail.sh")

    let path = try manager.ensureWorkspace(for: key, hooks: .defaults)
    #expect(FileManager.default.fileExists(atPath: path))

    let (_, logs) = try await withCapturedRuntimeLogs {
      try manager.removeWorkspace(for: key, hooks: hooks)
    }

    // Verify log emission — kills mutation removing RuntimeLogger.log in catch block
    let ignoredLogs = logs.filter { $0.entry.event == "workspace_hook_failure_ignored" }
    #expect(ignoredLogs.count == 1)
    #expect(ignoredLogs[0].entry.hook == "before_remove")
    #expect(ignoredLogs[0].entry.workspacePath == path)

    // Verify workspace was actually removed despite hook failure
    #expect(!FileManager.default.fileExists(atPath: path))
  }

  /// When fileManager.removeItem throws, removeWorkspace must log
  /// "workspace_removal_failed" instead of propagating the error.
  /// Kills RemoveSideEffects on catch-block log call.
  @Test func removalFailureEmitsWarningLog() async throws {
    let (root, cleanup) = try makeTempRoot()

    let manager = WorkspaceManager(root: root)
    let key = WorkspaceKey("locked_44")

    // Create workspace directory via manager
    let path = try manager.ensureWorkspace(for: key, hooks: .defaults)
    #expect(FileManager.default.fileExists(atPath: path))

    // Make root dir read-only so removeItem(atPath: path) fails
    // (parent directory needs write permission to delete a child entry)
    try FileManager.default.setAttributes(
      [.posixPermissions: NSNumber(value: Int16(0o555))],
      ofItemAtPath: root
    )
    defer {
      // Restore permissions before cleanup
      try? FileManager.default.setAttributes(
        [.posixPermissions: NSNumber(value: Int16(0o755))],
        ofItemAtPath: root
      )
      cleanup()
    }

    let (_, logs) = try await withCapturedRuntimeLogs {
      try manager.removeWorkspace(for: key, hooks: .defaults)
    }

    // Verify log emission — kills mutation removing log call inside removeItem catch
    let failureLogs = logs.filter { $0.entry.event == "workspace_removal_failed" }
    #expect(failureLogs.count == 1)
    #expect(failureLogs[0].entry.workspacePath == path)
    #expect(failureLogs[0].entry.error != nil)

    // The directory still exists because removal failed
    #expect(FileManager.default.fileExists(atPath: path))
  }
}

// MARK: - ensureWorkspace: afterCreate hook failure directory state

@Suite("WorkspaceManager ensureWorkspace Hook Failure State")
struct WorkspaceManagerEnsureHookFailureTests {

  /// When afterCreate hook throws, the directory must already exist on disk.
  /// Kills mutation that reorders directory creation vs hook execution.
  @Test func afterCreateFailureLeavesDirectoryOnDisk() throws {
    let (root, cleanup) = try makeTempRoot()
    defer { cleanup() }

    let hookRunner = StubHookRunner()
    hookRunner.setBehavior { name in
      if name == "after_create" {
        throw WorkspaceError.hookFailed(hook: name, exitCode: 1)
      }
    }
    let manager = WorkspaceManager(root: root, hookRunner: hookRunner)
    let key = WorkspaceKey("create_fail_44")
    let hooks = HooksConfig(afterCreate: "fail.sh")

    let expectedPath = manager.workspacePath(for: key)

    #expect(throws: WorkspaceError.self) {
      _ = try manager.ensureWorkspace(for: key, hooks: hooks)
    }

    // Directory was created BEFORE the hook ran, so it must still exist
    #expect(FileManager.default.fileExists(atPath: expectedPath))
  }
}
