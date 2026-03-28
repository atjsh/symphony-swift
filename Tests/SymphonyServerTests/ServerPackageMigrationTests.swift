import Foundation
import Testing

@testable import SymphonyServer
@testable import SymphonyServerCore

@Test func rootManifestPublishesCanonicalServerProductsAndTargets() throws {
  let repoRoot = currentRepositoryRoot()
  let manifest = try String(
    contentsOf: repoRoot.appendingPathComponent("Package.swift"),
    encoding: .utf8
  )

  #expect(manifest.contains(#".library(name: "SymphonyServerCore""#))
  #expect(manifest.contains(#".library(name: "SymphonyServer""#))
  #expect(manifest.contains(#".executable(name: "symphony-server""#))
  #expect(manifest.contains(#"name: "SymphonyServerCore""#))
  #expect(manifest.contains(#"name: "SymphonyServerCLI""#))
  #expect(!manifest.contains(#"SymphonyRuntime"#))
  #expect(!manifest.contains(#".executable(name: "SymphonyServer""#))
}

@Test func repositoryUsesCanonicalServerSourceAndTestRoots() {
  let repoRoot = currentRepositoryRoot()
  let fileManager = FileManager.default

  #expect(
    fileManager.fileExists(atPath: repoRoot.appendingPathComponent("Sources/SymphonyServerCore").path))
  #expect(
    fileManager.fileExists(atPath: repoRoot.appendingPathComponent("Sources/SymphonyServer").path))
  #expect(
    fileManager.fileExists(atPath: repoRoot.appendingPathComponent("Sources/SymphonyServerCLI").path))
  #expect(
    fileManager.fileExists(
      atPath: repoRoot.appendingPathComponent("Tests/SymphonyServerCoreTests").path))
  #expect(
    fileManager.fileExists(
      atPath: repoRoot.appendingPathComponent("Tests/SymphonyServerCLITests").path))

  #expect(
    !fileManager.fileExists(atPath: repoRoot.appendingPathComponent("Sources/SymphonyRuntime").path))
}

@Test func serverSplitKeepsHostImportsOutOfCoreAndCLI() throws {
  let repoRoot = currentRepositoryRoot()

  let coreSources = try swiftSources(
    under: repoRoot.appendingPathComponent("Sources/SymphonyServerCore", isDirectory: true)
  )
  #expect(!coreSources.isEmpty)
  for source in coreSources {
    let contents = try String(contentsOf: source, encoding: .utf8)
    #expect(!contents.contains("import Hummingbird"))
    #expect(!contents.contains("import HummingbirdWebSocket"))
    #expect(!contents.contains("import SQLite3"))
  }

  let cliSource = repoRoot.appendingPathComponent("Sources/SymphonyServerCLI/main.swift", isDirectory: false)
  let cliContents = try String(contentsOf: cliSource, encoding: .utf8)
  #expect(cliContents.contains("import SymphonyServer"))
  #expect(!cliContents.contains("import Hummingbird"))
  #expect(!cliContents.contains("import HummingbirdWebSocket"))
  #expect(!cliContents.contains("import SQLite3"))

  let hostTransportSource = try String(
    contentsOf: repoRoot.appendingPathComponent(
      "Sources/SymphonyServer/HTTPServerTransport.swift",
      isDirectory: false
    ),
    encoding: .utf8
  )
  #expect(hostTransportSource.contains("import Hummingbird"))
  #expect(hostTransportSource.contains("import HummingbirdWebSocket"))

  let hostStateSource = try String(
    contentsOf: repoRoot.appendingPathComponent(
      "Sources/SymphonyServer/ServerState.swift",
      isDirectory: false
    ),
    encoding: .utf8
  )
  #expect(hostStateSource.contains("import SQLite3"))
}

@Test func serverCLIEntryPointRemainsThinWrapperAroundBootstrapRunner() throws {
  let repoRoot = currentRepositoryRoot()
  let cliContents = try String(
    contentsOf: repoRoot.appendingPathComponent("Sources/SymphonyServerCLI/main.swift"),
    encoding: .utf8
  )

  #expect(cliContents.contains("try BootstrapServerRunner.run("))
  #expect(cliContents.contains("BootstrapKeepAlivePolicy.shouldExitAfterStartup"))
  #expect(cliContents.contains("BootstrapKeepAlivePolicy.makeKeepAlive"))
}

private func currentRepositoryRoot() -> URL {
  URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
}

private func swiftSources(under root: URL) throws -> [URL] {
  let fileManager = FileManager.default
  guard let enumerator = fileManager.enumerator(
    at: root,
    includingPropertiesForKeys: nil,
    options: [.skipsHiddenFiles]
  ) else {
    return []
  }

  return enumerator.compactMap { entry in
    guard let url = entry as? URL, url.pathExtension == "swift" else {
      return nil
    }
    return url
  }
}
