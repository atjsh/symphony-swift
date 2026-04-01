import CoreFoundation
import Darwin
import Foundation
import SymphonyShared
import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore

func bootstrapMakeTemporaryDirectory() throws -> URL {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    UUID().uuidString, isDirectory: true)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  return root
}

func bootstrapAvailableLoopbackPort() throws -> Int {
  let descriptor = socket(AF_INET, SOCK_STREAM, 0)
  guard descriptor >= 0 else {
    throw POSIXError(.EIO)
  }
  defer { close(descriptor) }

  var address = sockaddr_in()
  address.sin_len = UInt8(MemoryLayout<sockaddr_in>.stride)
  address.sin_family = sa_family_t(AF_INET)
  address.sin_port = in_port_t(0).bigEndian
  address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

  let bindResult = withUnsafePointer(to: &address) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
      Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.stride))
    }
  }
  guard bindResult == 0 else {
    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
  }

  var length = socklen_t(MemoryLayout<sockaddr_in>.stride)
  let nameResult = withUnsafeMutablePointer(to: &address) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
      getsockname(descriptor, $0, &length)
    }
  }
  guard nameResult == 0 else {
    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
  }

  return Int(UInt16(bigEndian: address.sin_port))
}

func bootstrapMakeListeningSocket(port: Int) throws -> Int32 {
  let descriptor = socket(AF_INET, SOCK_STREAM, 0)
  guard descriptor >= 0 else {
    throw POSIXError(.EIO)
  }

  var reuseAddress = 1
  setsockopt(
    descriptor, SOL_SOCKET, SO_REUSEADDR, &reuseAddress, socklen_t(MemoryLayout<Int32>.size))

  var address = sockaddr_in()
  address.sin_len = UInt8(MemoryLayout<sockaddr_in>.stride)
  address.sin_family = sa_family_t(AF_INET)
  address.sin_port = in_port_t(UInt16(port).bigEndian)
  address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

  let bindResult = withUnsafePointer(to: &address) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
      Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.stride))
    }
  }
  guard bindResult == 0 else {
    close(descriptor)
    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
  }

  guard listen(descriptor, 1) == 0 else {
    close(descriptor)
    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
  }

  return descriptor
}

func bootstrapListeningPort(for descriptor: Int32) throws -> Int {
  var address = sockaddr_in()
  var length = socklen_t(MemoryLayout<sockaddr_in>.stride)
  let result = withUnsafeMutablePointer(to: &address) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
      getsockname(descriptor, $0, &length)
    }
  }
  guard result == 0 else {
    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
  }

  return Int(UInt16(bigEndian: address.sin_port))
}

final class BootstrapLockedFlag: @unchecked Sendable {
  private let lock = NSLock()
  private var storedValue = false

  var value: Bool {
    lock.lock()
    defer { lock.unlock() }
    return storedValue
  }

  func setTrue() {
    lock.lock()
    storedValue = true
    lock.unlock()
  }
}

func bootstrapWaitUntil(
  _ description: String,
  timeout: Duration = .seconds(2),
  interval: Duration = .milliseconds(20),
  condition: @escaping @Sendable () async -> Bool
) async throws {
  let deadline = ContinuousClock.now + timeout
  while ContinuousClock.now < deadline {
    if await condition() {
      return
    }
    try await Task.sleep(for: interval)
  }

  Issue.record("Timed out waiting for \(description).")
  throw POSIXError(.ETIMEDOUT)
}

func bootstrapTerminateProcessIfRunning(
  _ process: Process,
  timeout: Duration = .seconds(2)
) async throws {
  guard process.isRunning else { return }

  process.terminate()
  do {
    try await bootstrapWaitUntil(
      "process \(process.processIdentifier) exits after SIGTERM", timeout: timeout
    ) {
      !process.isRunning
    }
  } catch {
    guard process.isRunning else { return }
    kill(process.processIdentifier, SIGKILL)
    try await bootstrapWaitUntil(
      "process \(process.processIdentifier) exits after SIGKILL", timeout: timeout
    ) {
      !process.isRunning
    }
  }
}

let bootstrapRuntimeHooksLock = NSLock()

func withBootstrapRuntimeHooksLock(_ body: () throws -> Void) rethrows {
  bootstrapRuntimeHooksLock.lock()
  defer { bootstrapRuntimeHooksLock.unlock() }
  try body()
}

func bootstrapBuiltProductsDirectory() -> URL {
  Bundle(for: BootstrapBundleLocator.self).bundleURL.deletingLastPathComponent()
}

final class BootstrapBundleLocator {}

final class EmptyApplicationSupportFileManager: FileManager, @unchecked Sendable {
  private let testHomeDirectory: URL

  init(homeDirectory: URL) {
    self.testHomeDirectory = homeDirectory
    super.init()
  }

  override func urls(
    for directory: FileManager.SearchPathDirectory, in domainMask: FileManager.SearchPathDomainMask
  ) -> [URL] {
    []
  }

  override var homeDirectoryForCurrentUser: URL {
    testHomeDirectory
  }
}

final class BootstrapLockedErrorBox: @unchecked Sendable {
  private let lock = NSLock()
  private var storage: Error?

  var error: Error? {
    get { lock.withLock { storage } }
    set { lock.withLock { storage = newValue } }
  }
}

final class RecordingBootstrapEngine: BootstrapEngineRunning, BootstrapWorkflowReloading,
  @unchecked Sendable
{
  private let lock = NSLock()
  private var _started = false
  private var _stopped = false
  private var _reloadedWorkflows: [WorkflowDefinition] = []

  var started: Bool {
    lock.withLock { _started }
  }

  var stopped: Bool {
    lock.withLock { _stopped }
  }

  var reloadedWorkflows: [WorkflowDefinition] {
    lock.withLock { _reloadedWorkflows }
  }

  func start() throws {
    lock.withLock { _started = true }
  }

  func stop() {
    lock.withLock { _stopped = true }
  }

  func reloadWorkflow(_ workflow: WorkflowDefinition) {
    lock.withLock { _reloadedWorkflows.append(workflow) }
  }
}

final class RefreshableRecordingBootstrapEngine: BootstrapEngineRunning,
  BootstrapWorkflowReloading, OrchestratorEngineRefreshing, @unchecked Sendable
{
  private let lock = NSLock()
  private var _started = false
  private var _stopped = false
  private var _reloadedWorkflows: [WorkflowDefinition] = []
  private var _refreshRequests = 0

  var started: Bool {
    lock.withLock { _started }
  }

  var stopped: Bool {
    lock.withLock { _stopped }
  }

  var reloadedWorkflows: [WorkflowDefinition] {
    lock.withLock { _reloadedWorkflows }
  }

  var refreshRequests: Int {
    lock.withLock { _refreshRequests }
  }

  func start() throws {
    lock.withLock { _started = true }
  }

  func stop() {
    lock.withLock { _stopped = true }
  }

  func reloadWorkflow(_ workflow: WorkflowDefinition) {
    lock.withLock { _reloadedWorkflows.append(workflow) }
  }

  func requestRefresh() {
    lock.withLock { _refreshRequests += 1 }
  }
}
