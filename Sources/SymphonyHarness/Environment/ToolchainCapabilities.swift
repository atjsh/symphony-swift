import Foundation

public enum LLVMCovCommand: String, Codable, Hashable, Sendable {
  case xcrun
  case direct
}

public struct ToolchainCapabilities: Codable, Hashable, Sendable {
  public let swiftAvailable: Bool
  public let xcodebuildAvailable: Bool
  public let xcrunAvailable: Bool
  public let simctlAvailable: Bool
  public let xcresulttoolAvailable: Bool
  public let llvmCovCommand: LLVMCovCommand?

  public init(
    swiftAvailable: Bool,
    xcodebuildAvailable: Bool,
    xcrunAvailable: Bool,
    simctlAvailable: Bool,
    xcresulttoolAvailable: Bool,
    llvmCovCommand: LLVMCovCommand?
  ) {
    self.swiftAvailable = swiftAvailable
    self.xcodebuildAvailable = xcodebuildAvailable
    self.xcrunAvailable = xcrunAvailable
    self.simctlAvailable = simctlAvailable
    self.xcresulttoolAvailable = xcresulttoolAvailable
    self.llvmCovCommand = llvmCovCommand
  }

  public var supportsXcodeCommands: Bool {
    xcodebuildAvailable && xcrunAvailable
  }

  public var supportsSimulatorCommands: Bool {
    supportsXcodeCommands && simctlAvailable
  }

  public var supportsXCResultTools: Bool {
    supportsXcodeCommands && xcresulttoolAvailable
  }

  public var supportsSwiftPMCoverageInspection: Bool {
    llvmCovCommand != nil
  }
}

public protocol ToolchainCapabilitiesResolving {
  func resolve() throws -> ToolchainCapabilities
}

public struct ProcessToolchainCapabilitiesResolver: ToolchainCapabilitiesResolving {
  private let processRunner: ProcessRunning

  public init(processRunner: ProcessRunning = SystemProcessRunner()) {
    self.processRunner = processRunner
  }

  public func resolve() throws -> ToolchainCapabilities {
    let swiftAvailable = executableExists("swift")
    let xcodebuildAvailable = executableExists("xcodebuild")
    let xcrunAvailable = executableExists("xcrun")
    let simctlAvailable = xcrunAvailable && subtoolAvailable(["simctl", "help"])
    let xcresulttoolAvailable = xcrunAvailable && subtoolAvailable(["xcresulttool", "help"])

    let llvmCovCommand: LLVMCovCommand?
    if xcrunAvailable && subtoolAvailable(["llvm-cov", "--version"]) {
      llvmCovCommand = .xcrun
    } else if executableExists("llvm-cov") {
      llvmCovCommand = .direct
    } else {
      llvmCovCommand = nil
    }

    return ToolchainCapabilities(
      swiftAvailable: swiftAvailable,
      xcodebuildAvailable: xcodebuildAvailable,
      xcrunAvailable: xcrunAvailable,
      simctlAvailable: simctlAvailable,
      xcresulttoolAvailable: xcresulttoolAvailable,
      llvmCovCommand: llvmCovCommand
    )
  }

  private func executableExists(_ executable: String) -> Bool {
    guard
      let result = try? processRunner.run(
        command: "which",
        arguments: [executable],
        environment: [:],
        currentDirectory: nil
      )
    else {
      return false
    }
    return result.exitStatus == 0
  }

  private func subtoolAvailable(_ arguments: [String]) -> Bool {
    guard
      let result = try? processRunner.run(
        command: "xcrun",
        arguments: arguments,
        environment: [:],
        currentDirectory: nil
      )
    else {
      return false
    }
    return result.exitStatus == 0
  }
}
