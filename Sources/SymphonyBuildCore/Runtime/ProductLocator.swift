import Foundation

public struct ProductDetails: Sendable {
  public let targetBuildDirectory: URL
  public let fullProductName: String
  public let executablePath: String?
  public let bundleIdentifier: String?

  public var productURL: URL {
    targetBuildDirectory.appendingPathComponent(
      fullProductName, isDirectory: fullProductName.hasSuffix(".app"))
  }
}

public struct ProductLocator {
  private let processRunner: ProcessRunning

  public init(processRunner: ProcessRunning = SystemProcessRunner()) {
    self.processRunner = processRunner
  }

  public func locateProduct(
    workspace: WorkspaceContext,
    scheme: String,
    destination: ResolvedDestination,
    derivedDataPath: URL
  ) throws -> ProductDetails {
    var arguments = [
      "-showBuildSettings", "-json", "-scheme", scheme, "-destination",
      destination.xcodeDestination, "-derivedDataPath", derivedDataPath.path,
    ]
    if let workspacePath = workspace.xcodeWorkspacePath {
      arguments += ["-workspace", workspacePath.path]
    } else if let projectPath = workspace.xcodeProjectPath {
      arguments += ["-project", projectPath.path]
    }

    let result = try processRunner.run(
      command: "xcodebuild", arguments: arguments, environment: [:],
      currentDirectory: workspace.projectRoot)
    guard result.exitStatus == 0 else {
      throw SymphonyBuildError(
        code: "show_build_settings_failed",
        message: result.combinedOutput.isEmpty
          ? "Failed to query build settings." : result.combinedOutput)
    }

    let decoded = try JSONDecoder().decode(
      [BuildSettingsContainer].self, from: Data(result.stdout.utf8))
    guard let settings = decoded.first?.buildSettings else {
      throw SymphonyBuildError(
        code: "missing_build_settings",
        message: "xcodebuild did not return build settings for the selected scheme.")
    }

    guard let targetBuildDirectory = settings["TARGET_BUILD_DIR"]?.stringValue,
      let fullProductName = settings["FULL_PRODUCT_NAME"]?.stringValue
    else {
      throw SymphonyBuildError(
        code: "incomplete_build_settings",
        message: "xcodebuild returned incomplete product settings.")
    }

    return ProductDetails(
      targetBuildDirectory: URL(fileURLWithPath: targetBuildDirectory, isDirectory: true),
      fullProductName: fullProductName,
      executablePath: settings["EXECUTABLE_PATH"]?.stringValue,
      bundleIdentifier: settings["PRODUCT_BUNDLE_IDENTIFIER"]?.stringValue
    )
  }

  private struct BuildSettingsContainer: Decodable {
    let buildSettings: [String: AnyDecodable]

    enum CodingKeys: String, CodingKey {
      case buildSettings = "buildSettings"
    }
  }
}

private struct AnyDecodable: Decodable {
  let value: Any

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let int = try? container.decode(Int.self) {
      value = int
    } else if let bool = try? container.decode(Bool.self) {
      value = bool
    } else if let string = try? container.decode(String.self) {
      value = string
    } else if let array = try? container.decode([AnyDecodable].self) {
      value = array.map(\.value)
    } else if let dict = try? container.decode([String: AnyDecodable].self) {
      value = dict.mapValues(\.value)
    } else {
      value = NSNull()
    }
  }

  var stringValue: String? {
    value as? String
  }
}
