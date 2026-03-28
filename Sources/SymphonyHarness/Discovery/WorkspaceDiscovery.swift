import Foundation

public protocol WorkspaceDiscovering {
  func discover(from startDirectory: URL) throws -> WorkspaceContext
}

public struct WorkspaceDiscovery: WorkspaceDiscovering {
  private let fileManager: FileManager
  private let processRunner: ProcessRunning

  public init(
    fileManager: FileManager = .default, processRunner: ProcessRunning = SystemProcessRunner()
  ) {
    self.fileManager = fileManager
    self.processRunner = processRunner
  }

  public func discover(from startDirectory: URL) throws -> WorkspaceContext {
    let projectRoot = try repositoryRoot(from: startDirectory)
    let rootPackagePath = projectRoot.appendingPathComponent("Package.swift", isDirectory: false)
    guard fileManager.fileExists(atPath: rootPackagePath.path) else {
      throw SymphonyHarnessError(
        code: "missing_root_package",
        message: "The repository root must contain one canonical Package.swift manifest.")
    }
    try validateNoExtraPackageManifests(in: projectRoot)
    let candidates = try collectCandidates(from: startDirectory, upTo: projectRoot)

    let workspaces = candidates.filter { $0.pathExtension == "xcworkspace" }
    let projects = candidates.filter { $0.pathExtension == "xcodeproj" }

    if workspaces.count > 1 {
      throw SymphonyHarnessError(
        code: "ambiguous_workspace",
        message:
          "Multiple Xcode workspaces were found. Leave exactly one checked-in workspace or remove the ambiguity."
      )
    }
    if workspaces.isEmpty && projects.count > 1 {
      throw SymphonyHarnessError(
        code: "ambiguous_project",
        message:
          "Multiple Xcode projects were found and no workspace was available. Leave exactly one checked-in project or add a workspace."
      )
    }
    if workspaces.isEmpty && projects.isEmpty {
      throw SymphonyHarnessError(
        code: "missing_build_definition",
        message:
          "No checked-in Xcode workspace or project was found between the current directory and the repository root."
      )
    }

    let workspacePath = workspaces.first
    let projectPath = workspacePath == nil ? projects.first : nil
    let buildStateRoot = Self.buildStateRoot(for: projectRoot)
    try Self.validateBuildStateRoot(buildStateRoot, within: projectRoot, fileManager: fileManager)
    let repositoryLayout = RepositoryLayout(
      projectRoot: projectRoot,
      rootPackagePath: rootPackagePath,
      xcodeWorkspacePath: workspacePath,
      xcodeProjectPath: projectPath,
      applicationsRoot: projectRoot.appendingPathComponent("Applications", isDirectory: true)
    )

    return WorkspaceContext(
      projectRoot: repositoryLayout.projectRoot,
      buildStateRoot: buildStateRoot,
      xcodeWorkspacePath: repositoryLayout.xcodeWorkspacePath,
      xcodeProjectPath: repositoryLayout.xcodeProjectPath,
      repositoryLayout: repositoryLayout
    )
  }

  private func repositoryRoot(from startDirectory: URL) throws -> URL {
    if let root = try? processRunner.run(
      command: "git", arguments: ["rev-parse", "--show-toplevel"], environment: [:],
      currentDirectory: startDirectory),
      root.exitStatus == 0
    {
      let path = root.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
      if !path.isEmpty {
        return URL(fileURLWithPath: path, isDirectory: true)
      }
    }

    var cursor = startDirectory.standardizedFileURL
    while !fileManager.fileExists(atPath: cursor.appendingPathComponent(".git").path) {
      let parent = cursor.deletingLastPathComponent()
      if parent == cursor {
        throw SymphonyHarnessError(
          code: "missing_repository_root",
          message: "Could not determine the repository root from the current directory.")
      }
      cursor = parent
    }
    return cursor
  }

  private func collectCandidates(from startDirectory: URL, upTo projectRoot: URL) throws -> [URL] {
    var collected = [URL]()
    var cursor = startDirectory.standardizedFileURL

    while true {
      collected.append(contentsOf: try directoryCandidates(in: cursor))
      if cursor == projectRoot {
        break
      }
      cursor = cursor.deletingLastPathComponent()
    }

    return collected.sorted { $0.path < $1.path }
  }

  private func directoryCandidates(in directory: URL) throws -> [URL] {
    let urls = try fileManager.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    )

    return urls.filter {
      $0.pathExtension == "xcworkspace" || $0.pathExtension == "xcodeproj"
    }
  }

  static func buildStateRoot(for projectRoot: URL) -> URL {
    projectRoot.appendingPathComponent(".build/harness", isDirectory: true)
  }

  static func validateBuildStateRoot(
    _ buildStateRoot: URL, within projectRoot: URL, fileManager: FileManager = .default
  ) throws {
    guard fileManager.isContained(buildStateRoot, within: projectRoot) else {
      throw SymphonyHarnessError(
        code: "artifact_root_out_of_bounds",
        message: "The canonical build state root must stay within the repository root.")
    }
  }

  private func validateNoExtraPackageManifests(in projectRoot: URL) throws {
    let enumerator = fileManager.enumerator(
      at: projectRoot,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    )
    let canonicalManifestPath =
      projectRoot
      .appendingPathComponent("Package.swift", isDirectory: false)
      .resolvingSymlinksInPath()
      .standardizedFileURL
      .path

    while let next = enumerator?.nextObject() as? URL {
      guard next.lastPathComponent == "Package.swift" else {
        continue
      }
      let nextPath = next.resolvingSymlinksInPath().standardizedFileURL.path
      guard nextPath != canonicalManifestPath else {
        continue
      }

      throw SymphonyHarnessError(
        code: "extra_package_manifest",
        message:
          "Found an extra package manifest at \(next.path). The migration target allows only the root Package.swift."
      )
    }
  }
}
