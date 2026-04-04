import CoreFoundation
import Foundation

enum BootstrapRuntimeHooks {
  // SAFETY: @unchecked Sendable — all mutable closures accessed through `lock`.
  private final class Storage: @unchecked Sendable {
    private let lock = NSLock()
    private var output: ((String) -> Void)?
    private var keepAlive: (() -> Void)?
    private var runLoopOverride: (() -> Void)?
    private var defaultRunLoopOverride: (() -> Void)?

    var outputOverride: ((String) -> Void)? {
      get {
        lock.lock()
        defer { lock.unlock() }
        return output
      }
      set {
        lock.lock()
        output = newValue
        lock.unlock()
      }
    }

    var keepAliveOverride: (() -> Void)? {
      get {
        lock.lock()
        defer { lock.unlock() }
        return keepAlive
      }
      set {
        lock.lock()
        keepAlive = newValue
        lock.unlock()
      }
    }

    var runLoopRunnerOverride: (() -> Void)? {
      get {
        lock.lock()
        defer { lock.unlock() }
        return runLoopOverride
      }
      set {
        lock.lock()
        runLoopOverride = newValue
        lock.unlock()
      }
    }

    func setDefaultRunLoopActionOverride(_ action: (() -> Void)?) {
      lock.lock()
      defaultRunLoopOverride = action
      lock.unlock()
    }

    func runDefaultRunLoopAction() {
      let override: (() -> Void)?
      lock.lock()
      override = defaultRunLoopOverride
      lock.unlock()
      if let override {
        override()
        return
      }

      CFRunLoopRun()
    }
  }

  private static let storage = Storage()

  static var outputOverride: ((String) -> Void)? {
    get { storage.outputOverride }
    set { storage.outputOverride = newValue }
  }

  static var keepAliveOverride: (() -> Void)? {
    get { storage.keepAliveOverride }
    set { storage.keepAliveOverride = newValue }
  }

  static var runLoopRunnerOverride: (() -> Void)? {
    get { storage.runLoopRunnerOverride }
    set { storage.runLoopRunnerOverride = newValue }
  }

  static func withDefaultRunLoopAction(_ action: @escaping () -> Void) {
    storage.setDefaultRunLoopActionOverride(action)
  }

  static func resetDefaultRunLoopAction() {
    storage.setDefaultRunLoopActionOverride(nil)
  }

  static func defaultOutput(_ line: String) {
    if let outputOverride {
      outputOverride(line)
    } else {
      print(line)
    }
  }

  @inline(never)
  static func keepAlive() {
    if let keepAliveOverride {
      keepAliveOverride()
    } else if let runLoopRunnerOverride {
      runLoopRunnerOverride()
    } else {
      storage.runDefaultRunLoopAction()
    }
  }
}
