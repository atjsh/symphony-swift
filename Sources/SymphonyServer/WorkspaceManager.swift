import Foundation
import SymphonyShared
import SymphonyServerCore

// MARK: - Workspace Manager Error

public enum WorkspaceError: Error, Equatable, Sendable {
  case rootContainmentViolation(path: String, root: String)
  case hookFailed(hook: String, exitCode: Int32)
  case hookTimedOut(hook: String, timeoutMS: Int)
  case workspaceCreationFailed(String)
}

// MARK: - Workspace Manager Protocol

public protocol WorkspaceManaging: Sendable {
  func workspacePath(for key: WorkspaceKey) -> String
  func ensureWorkspace(for key: WorkspaceKey, hooks: HooksConfig) throws -> String
  func removeWorkspace(for key: WorkspaceKey, hooks: HooksConfig) throws
  func validateContainment(path: String) throws
}

// MARK: - Workspace Manager (Section 9)

public final class WorkspaceManager: WorkspaceManaging, @unchecked Sendable {
  private let root: String
  private let fileManager: FileManager
  private let hookRunner: HookRunning

  public init(root: String, fileManager: FileManager = .default, hookRunner: HookRunning? = nil) {
    self.root = (root as NSString).standardizingPath
    self.fileManager = fileManager
    self.hookRunner = hookRunner ?? ProcessHookRunner()
  }

  public func workspacePath(for key: WorkspaceKey) -> String {
    (root as NSString).appendingPathComponent(key.rawValue)
  }

  public func ensureWorkspace(for key: WorkspaceKey, hooks: HooksConfig) throws -> String {
    let path = workspacePath(for: key)
    try validateContainment(path: path)

    let isNew = !fileManager.fileExists(atPath: path)
    if isNew {
      do {
        try fileManager.createDirectory(atPath: path, withIntermediateDirectories: true)
      } catch {
        throw WorkspaceError.workspaceCreationFailed(error.localizedDescription)
      }

      if let afterCreate = hooks.afterCreate {
        try runHook(
          name: "after_create", script: afterCreate, workspacePath: path, timeoutMS: hooks.timeoutMS
        )
      }
    }
    return path
  }

  public func removeWorkspace(for key: WorkspaceKey, hooks: HooksConfig) throws {
    let path = workspacePath(for: key)
    try validateContainment(path: path)

    guard fileManager.fileExists(atPath: path) else { return }

    if let beforeRemove = hooks.beforeRemove {
      do {
        try runHook(
          name: "before_remove", script: beforeRemove, workspacePath: path,
          timeoutMS: hooks.timeoutMS)
      } catch {
        RuntimeLogger.log(
          level: .warning,
          event: "workspace_hook_failure_ignored",
          context: hookContext(name: "before_remove", workspacePath: path),
          error: String(describing: error),
          sensitiveValues: [beforeRemove]
        )
      }
    }

    try? fileManager.removeItem(atPath: path)
  }

  public func validateContainment(path: String) throws {
    let standardizedPath = (path as NSString).standardizingPath
    let standardizedRoot = (root as NSString).standardizingPath

    guard standardizedPath.hasPrefix(standardizedRoot + "/") || standardizedPath == standardizedRoot
    else {
      throw WorkspaceError.rootContainmentViolation(path: path, root: root)
    }
  }

  public func runBeforeRunHook(workspacePath: String, hooks: HooksConfig) throws {
    if let beforeRun = hooks.beforeRun {
      try runHook(
        name: "before_run", script: beforeRun, workspacePath: workspacePath,
        timeoutMS: hooks.timeoutMS)
    }
  }

  public func runAfterRunHook(workspacePath: String, hooks: HooksConfig) {
    guard let afterRun = hooks.afterRun else { return }
    do {
      try runHook(
        name: "after_run", script: afterRun, workspacePath: workspacePath,
        timeoutMS: hooks.timeoutMS)
    } catch {
      RuntimeLogger.log(
        level: .warning,
        event: "workspace_hook_failure_ignored",
        context: hookContext(name: "after_run", workspacePath: workspacePath),
        error: String(describing: error),
        sensitiveValues: [afterRun]
      )
    }
  }

  private func runHook(name: String, script: String, workspacePath: String, timeoutMS: Int) throws {
    let context = hookContext(name: name, workspacePath: workspacePath)
    RuntimeLogger.log(
      level: .info,
      event: "workspace_hook_started",
      context: context,
      sensitiveValues: [script]
    )
    do {
      try hookRunner.run(
        name: name, script: script, workspacePath: workspacePath, timeoutMS: timeoutMS)
      RuntimeLogger.log(
        level: .info,
        event: "workspace_hook_succeeded",
        context: context,
        sensitiveValues: [script]
      )
    } catch {
      RuntimeLogger.log(
        level: .error,
        event: "workspace_hook_failed",
        context: context,
        error: String(describing: error),
        sensitiveValues: [script]
      )
      throw error
    }
  }

  private func hookContext(name: String, workspacePath: String) -> RuntimeLogContext {
    RuntimeLogContext(
      metadata: [
        "hook": name,
        "workspace_path": workspacePath,
      ]
    )
  }
}

// MARK: - Hook Runner Protocol

public protocol HookRunning: Sendable {
  func run(name: String, script: String, workspacePath: String, timeoutMS: Int) throws
}

// MARK: - Process-Based Hook Runner

public final class ProcessHookRunner: HookRunning, Sendable {
  public init() {}

  public func run(name: String, script: String, workspacePath: String, timeoutMS: Int) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = ["-lc", script]
    process.currentDirectoryURL = URL(fileURLWithPath: workspacePath)
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice

    try process.run()

    let deadline = DispatchTime.now() + .milliseconds(timeoutMS)
    let semaphore = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in
      semaphore.signal()
    }

    let result = semaphore.wait(timeout: deadline)
    if result == .timedOut {
      process.terminate()
      process.waitUntilExit()
      throw WorkspaceError.hookTimedOut(hook: name, timeoutMS: timeoutMS)
    }

    guard process.terminationStatus == 0 else {
      throw WorkspaceError.hookFailed(hook: name, exitCode: process.terminationStatus)
    }
  }
}

// MARK: - Stub Hook Runner (for testing)

public final class StubHookRunner: HookRunning, @unchecked Sendable {
  private let lock = NSLock()
  private var _invocations: [(name: String, script: String, workspacePath: String)] = []
  private var _behavior: (String) throws -> Void = { _ in }

  public init() {}

  public var invocations: [(name: String, script: String, workspacePath: String)] {
    lock.lock()
    defer { lock.unlock() }
    return _invocations
  }

  public func setBehavior(_ behavior: @escaping (String) throws -> Void) {
    lock.lock()
    _behavior = behavior
    lock.unlock()
  }

  public func run(name: String, script: String, workspacePath: String, timeoutMS: Int) throws {
    lock.lock()
    _invocations.append((name: name, script: script, workspacePath: workspacePath))
    let behavior = _behavior
    lock.unlock()
    try behavior(name)
  }
}
