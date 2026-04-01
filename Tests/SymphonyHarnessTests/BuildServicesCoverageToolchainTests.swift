import Foundation
import Testing

@testable import SymphonyHarness

@Test func endpointOverrideStoreFallsBackToPersistedHostAndPortWhenOnlySchemeOverrides() throws {
  try withTemporaryDirectory { directory in
    let workspace = WorkspaceContext(
      projectRoot: directory,
      buildStateRoot: directory.appendingPathComponent(".build/harness", isDirectory: true),
      xcodeWorkspacePath: nil,
      xcodeProjectPath: nil
    )
    let store = EndpointOverrideStore()
    _ = try store.save(
      try RuntimeEndpoint(scheme: "http", host: "persisted.example.com", port: 9555), in: workspace)

    let resolved = try store.resolve(
      workspace: workspace,
      serverURL: nil,
      scheme: "https",
      host: nil,
      port: nil
    )

    #expect(resolved.scheme == "https")
    #expect(resolved.host == "persisted.example.com")
    #expect(resolved.port == 9555)
  }
}

@Test func processToolchainCapabilitiesResolverDetectsAvailableAndUnavailableTooling() throws {
  let xcodeCapabilities = try ProcessToolchainCapabilitiesResolver(
    processRunner: StubProcessRunner(results: [
      "which swift": StubProcessRunner.success("/usr/bin/swift\n"),
      "which xcodebuild": StubProcessRunner.success("/usr/bin/xcodebuild\n"),
      "which xcrun": StubProcessRunner.success("/usr/bin/xcrun\n"),
      "xcrun simctl help": StubProcessRunner.success("simctl help"),
      "xcrun xcresulttool help": StubProcessRunner.success("xcresulttool help"),
      "xcrun llvm-cov --version": StubProcessRunner.success("llvm-cov version"),
    ])
  ).resolve()
  #expect(xcodeCapabilities.swiftAvailable)
  #expect(xcodeCapabilities.supportsXcodeCommands)
  #expect(xcodeCapabilities.supportsSimulatorCommands)
  #expect(xcodeCapabilities.supportsXCResultTools)
  #expect(xcodeCapabilities.llvmCovCommand == .xcrun)
  #expect(xcodeCapabilities.supportsSwiftPMCoverageInspection)

  let directLLVMCovCapabilities = try ProcessToolchainCapabilitiesResolver(
    processRunner: StubProcessRunner(results: [
      "which swift": StubProcessRunner.success("/usr/bin/swift\n"),
      "which xcodebuild": StubProcessRunner.failure(""),
      "which xcrun": StubProcessRunner.failure(""),
      "which llvm-cov": StubProcessRunner.success("/usr/bin/llvm-cov\n"),
    ])
  ).resolve()
  #expect(directLLVMCovCapabilities.swiftAvailable)
  #expect(!directLLVMCovCapabilities.supportsXcodeCommands)
  #expect(!directLLVMCovCapabilities.supportsSimulatorCommands)
  #expect(!directLLVMCovCapabilities.supportsXCResultTools)
  #expect(directLLVMCovCapabilities.llvmCovCommand == .direct)
  #expect(directLLVMCovCapabilities.supportsSwiftPMCoverageInspection)

  let unavailableCapabilities = try ProcessToolchainCapabilitiesResolver(
    processRunner: StubProcessRunner(results: [
      "which swift": StubProcessRunner.failure(""),
      "which xcodebuild": StubProcessRunner.failure(""),
      "which xcrun": StubProcessRunner.failure(""),
      "which llvm-cov": StubProcessRunner.failure(""),
    ])
  ).resolve()
  #expect(!unavailableCapabilities.swiftAvailable)
  #expect(!unavailableCapabilities.supportsXcodeCommands)
  #expect(!unavailableCapabilities.supportsSwiftPMCoverageInspection)
  #expect(unavailableCapabilities.llvmCovCommand == nil)

  let xcrunWithoutSubtools = try ProcessToolchainCapabilitiesResolver(
    processRunner: StubProcessRunner(results: [
      "which swift": StubProcessRunner.success("/usr/bin/swift\n"),
      "which xcodebuild": StubProcessRunner.success("/usr/bin/xcodebuild\n"),
      "which xcrun": StubProcessRunner.success("/usr/bin/xcrun\n"),
      "xcrun simctl help": StubProcessRunner.failure(""),
      "xcrun xcresulttool help": StubProcessRunner.failure(""),
      "xcrun llvm-cov --version": StubProcessRunner.failure(""),
      "which llvm-cov": StubProcessRunner.failure(""),
    ])
  ).resolve()
  #expect(xcrunWithoutSubtools.supportsXcodeCommands)
  #expect(!xcrunWithoutSubtools.supportsSimulatorCommands)
  #expect(!xcrunWithoutSubtools.supportsXCResultTools)
  #expect(xcrunWithoutSubtools.llvmCovCommand == nil)
  #expect(!xcrunWithoutSubtools.supportsSwiftPMCoverageInspection)
}

@Test func processToolchainCapabilitiesResolverTreatsThrownProbesAsUnavailable() throws {
  struct ProbeFailure: Error {}

  let runner = RoutedBuildServicesProcessRunner { _, _, _, _, _ in
    throw ProbeFailure()
  }
  let capabilities = try ProcessToolchainCapabilitiesResolver(processRunner: runner).resolve()

  #expect(!capabilities.swiftAvailable)
  #expect(!capabilities.xcodebuildAvailable)
  #expect(!capabilities.xcrunAvailable)
  #expect(!capabilities.simctlAvailable)
  #expect(!capabilities.xcresulttoolAvailable)
  #expect(capabilities.llvmCovCommand == nil)
  #expect(!capabilities.supportsSwiftPMCoverageInspection)
}

@Test func processToolchainCapabilitiesResolverTreatsThrownSubtoolProbeAsUnavailable() throws {
  struct ProbeFailure: Error {}

  let runner = RoutedBuildServicesProcessRunner { command, arguments, _, _, _ in
    switch (command, arguments) {
    case ("which", ["swift"]), ("which", ["xcodebuild"]), ("which", ["xcrun"]):
      return StubProcessRunner.success("/usr/bin/\(arguments[0])\n")
    case ("xcrun", ["simctl", "help"]):
      throw ProbeFailure()
    case ("xcrun", ["xcresulttool", "help"]), ("xcrun", ["llvm-cov", "--version"]):
      return StubProcessRunner.success("ok")
    default:
      Issue.record("Unexpected probe: \(command) \(arguments)")
      return StubProcessRunner.failure("")
    }
  }

  let capabilities = try ProcessToolchainCapabilitiesResolver(processRunner: runner).resolve()

  #expect(capabilities.swiftAvailable)
  #expect(capabilities.xcrunAvailable)
  #expect(capabilities.xcodebuildAvailable)
  #expect(!capabilities.simctlAvailable)
  #expect(capabilities.xcresulttoolAvailable)
  #expect(capabilities.llvmCovCommand == .xcrun)
}

