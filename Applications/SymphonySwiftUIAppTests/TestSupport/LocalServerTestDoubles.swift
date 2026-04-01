#if os(macOS)
  import Foundation

  @testable import SymphonySwiftUIApp

  final class RecordingLocalServerManager: LocalServerManaging {
    var onStatusChange: ((LocalServerStatusSnapshot) -> Void)?
    private(set) var statusSnapshot = LocalServerStatusSnapshot(
      state: .needsSetup,
      endpoint: .defaultEndpoint
    )
    private(set) var startedRequests = [LocalServerLaunchRequest]()
    private(set) var restartRequests = [LocalServerLaunchRequest]()
    private(set) var stopCallCount = 0
    var nextStartSnapshot = LocalServerStatusSnapshot(
      state: .running,
      endpoint: .defaultEndpoint
    )
    var nextRestartSnapshot: LocalServerStatusSnapshot?

    func start(request: LocalServerLaunchRequest) async {
      startedRequests.append(request)
      statusSnapshot = nextStartSnapshot
      await MainActor.run {
        onStatusChange?(statusSnapshot)
      }
    }

    func stop() async {
      stopCallCount += 1
      statusSnapshot = LocalServerStatusSnapshot(
        state: .idle,
        endpoint: statusSnapshot.endpoint,
        transcript: statusSnapshot.transcript
      )
      await MainActor.run {
        onStatusChange?(statusSnapshot)
      }
    }

    func restart(request: LocalServerLaunchRequest) async {
      restartRequests.append(request)
      statusSnapshot = nextRestartSnapshot ?? nextStartSnapshot
      await MainActor.run {
        onStatusChange?(statusSnapshot)
      }
    }
  }

  final class RecordingWorkflowSaver: LocalWorkflowSaving {
    let saveURL: URL
    private(set) var savedFileNames = [String]()
    private(set) var savedContents = [String]()

    init(saveURL: URL) {
      self.saveURL = saveURL
    }

    func saveWorkflow(
      named fileName: String,
      suggestedDirectoryURL _: URL?,
      content: String
    ) throws -> URL? {
      savedFileNames.append(fileName)
      savedContents.append(content)
      try FileManager.default.createDirectory(
        at: saveURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try content.write(to: saveURL, atomically: true, encoding: .utf8)
      return saveURL
    }
  }

  func makeTemporaryWorkflowFile(
    contents: String = """
      ---
      tracker:
        project_owner: atjsh
        project_owner_type: organization
        project_number: 1
      ---
      Resolve {{issue.title}}
      """
  ) throws -> URL {
    let workflowURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
      .appendingPathComponent("WORKFLOW.md", isDirectory: false)
    try FileManager.default.createDirectory(
      at: workflowURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try contents.write(to: workflowURL, atomically: true, encoding: .utf8)
    return workflowURL
  }
#endif
