import Foundation

final class SynchronizedOutputRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var storage = [String]()

  var lines: [String] {
    lock.lock()
    defer { lock.unlock() }
    return storage
  }

  func append(_ line: String) {
    lock.lock()
    storage.append(line)
    lock.unlock()
  }
}
