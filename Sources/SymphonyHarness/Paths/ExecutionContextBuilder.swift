import Foundation

public struct ExecutionContextBuilder {
  private let fileManager: FileManager

  public init(fileManager: FileManager = .default) {
    self.fileManager = fileManager
  }

  public func make(
    workspace: WorkspaceContext,
    worker: WorkerScope,
    command: BuildCommandFamily,
    runID: String,
    date: Date = Date()
  ) throws -> ExecutionContext {
    let timestamp = DateFormatting.runTimestamp(for: date)
    let buildStateRoot = workspace.buildStateRoot
    let artifactRoot = buildStateRoot.appendingPathComponent(
      "artifacts/\(command.rawValue)/\(timestamp)-\(runID)", isDirectory: true)
    let derivedDataPath = buildStateRoot.appendingPathComponent(
      "derived-data/\(worker.slug)", isDirectory: true)
    let resultBundlePath = buildStateRoot.appendingPathComponent(
      "results/\(command.rawValue)/\(timestamp)-\(runID).xcresult", isDirectory: true)
    let logPath = buildStateRoot.appendingPathComponent(
      "logs/\(command.rawValue)/\(timestamp)-\(runID).log", isDirectory: false)
    let runtimeRoot = buildStateRoot.appendingPathComponent(
      "runtime/\(worker.slug)", isDirectory: true)

    for url in [
      artifactRoot, derivedDataPath, resultBundlePath.deletingLastPathComponent(),
      logPath.deletingLastPathComponent(), runtimeRoot,
    ] {
      guard fileManager.isContained(url, within: workspace.projectRoot) else {
        throw SymphonyHarnessError(
          code: "artifact_root_out_of_bounds",
          message: "Derived build paths must remain within the repository root.")
      }
    }

    return ExecutionContext(
      worker: worker,
      timestamp: timestamp,
      runID: runID,
      artifactRoot: artifactRoot,
      derivedDataPath: derivedDataPath,
      resultBundlePath: resultBundlePath,
      logPath: logPath,
      runtimeRoot: runtimeRoot
    )
  }
}
