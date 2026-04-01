import Foundation
import SymphonyServerCore

// MARK: - Workflow Reloader (Section 6.6)

public final class WorkflowReloader: @unchecked Sendable {
  private let lock = NSLock()
  private let workflowPath: String
  private var _lastDefinition: WorkflowDefinition?
  private var _dispatchSource: DispatchSourceFileSystemObject?
  private var _fileDescriptor: Int32 = -1
  private let onChange: @Sendable (WorkflowDefinition) -> Void

  public init(
    workflowPath: String,
    onChange: @escaping @Sendable (WorkflowDefinition) -> Void
  ) {
    self.workflowPath = workflowPath
    self.onChange = onChange
  }

  deinit {
    stopWatching()
  }

  public func startWatching() throws {
    let fd = open(workflowPath, O_EVTONLY)
    guard fd >= 0 else {
      throw OrchestratorEngineError.workflowLoadFailed(
        "Cannot open \(workflowPath) for watching"
      )
    }

    let source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: fd,
      eventMask: [.write, .rename, .delete],
      queue: DispatchQueue.global(qos: .utility)
    )

    source.setEventHandler { [weak self] in
      self?.processFileChange()
    }

    source.setCancelHandler {
      close(fd)
    }

    lock.withLock {
      _fileDescriptor = fd
      _dispatchSource = source
    }

    source.resume()
  }

  public func stopWatching() {
    lock.lock()
    let source = _dispatchSource
    _dispatchSource = nil
    _fileDescriptor = -1
    lock.unlock()

    source?.cancel()
  }

  public func processFileChange() {
    do {
      let content = try String(contentsOfFile: workflowPath, encoding: .utf8)
      let definition = try WorkflowParser.parse(content: content)
      let previousDefinition = lock.withLock { _lastDefinition }
      if previousDefinition != definition {
        lock.withLock { _lastDefinition = definition }
        onChange(definition)
      }
    } catch {
      RuntimeLogger.log(
        level: .error,
        event: "workflow_reload_failed",
        context: RuntimeLogContext(
          metadata: [
            "workflow_path": workflowPath
          ]
        ),
        error: String(describing: error)
      )
      // Invalid reloads must not crash; keep last known good config
    }
  }

  public var isWatching: Bool {
    lock.withLock { _dispatchSource != nil }
  }
}
