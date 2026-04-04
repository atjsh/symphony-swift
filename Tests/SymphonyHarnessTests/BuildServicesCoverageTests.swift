import Foundation
import Testing

@testable import SymphonyHarness

@Test func buildErrorsAndCommandFailuresRenderDescriptions() {
  let error = SymphonyHarnessError(code: "sample_error", message: "something broke")
  #expect(error.errorDescription == "[sample_error] something broke")
  #expect(error.description == "[sample_error] something broke")

  let failureWithSummary = SymphonyHarnessCommandFailure(
    message: "build failed",
    summaryPath: URL(fileURLWithPath: "/tmp/summary.txt")
  )
  #expect(failureWithSummary.errorDescription == "build failed Summary: /tmp/summary.txt")

  let failureWithoutSummary = SymphonyHarnessCommandFailure(message: "build failed")
  #expect(failureWithoutSummary.errorDescription == "build failed")
}

@Test func productLocatorCoversSuccessAndFailureModes() throws {
  let workspace = WorkspaceContext(
    projectRoot: URL(fileURLWithPath: "/tmp/repo", isDirectory: true),
    buildStateRoot: URL(fileURLWithPath: "/tmp/repo/.build/harness", isDirectory: true),
    xcodeWorkspacePath: URL(fileURLWithPath: "/tmp/repo/Symphony.xcworkspace"),
    xcodeProjectPath: nil
  )
  let destination = ResolvedDestination(
    platform: .macos,
    displayName: "macOS",
    simulatorName: nil,
    simulatorUDID: nil,
    xcodeDestination: expectedHostMacOSDestination()
  )
  let derivedDataPath = URL(fileURLWithPath: "/tmp/repo/.build/DerivedData", isDirectory: true)
  let buildSettingsJSON = #"""
    [
      {
        "buildSettings": {
          "TARGET_BUILD_DIR": "/tmp/repo/Build/Products/Debug",
          "FULL_PRODUCT_NAME": "Symphony.app",
          "EXECUTABLE_PATH": "Symphony.app/Contents/MacOS/Symphony",
          "PRODUCT_BUNDLE_IDENTIFIER": "com.example.Symphony",
          "INT_VALUE": 1,
          "BOOL_VALUE": true,
          "ARRAY_VALUE": ["a", 2, false],
          "DICT_VALUE": {"nested": "value"},
          "NULL_VALUE": null
        }
      }
    ]
    """#
  let workspaceCommand =
    "xcodebuild -showBuildSettings -json -scheme SymphonySwiftUIApp -destination \(expectedHostMacOSDestination()) -derivedDataPath \(derivedDataPath.path) -workspace /tmp/repo/Symphony.xcworkspace"
  let locator = ProductLocator(
    processRunner: StubProcessRunner(results: [
      workspaceCommand: StubProcessRunner.success(buildSettingsJSON)
    ]))

  let details = try locator.locateProduct(
    workspace: workspace,
    scheme: "SymphonySwiftUIApp",
    destination: destination,
    derivedDataPath: derivedDataPath
  )
  #expect(details.fullProductName == "Symphony.app")
  #expect(details.productURL.path.hasSuffix("Symphony.app"))
  #expect(details.executablePath == "Symphony.app/Contents/MacOS/Symphony")
  #expect(details.bundleIdentifier == "com.example.Symphony")

  let projectWorkspace = WorkspaceContext(
    projectRoot: workspace.projectRoot,
    buildStateRoot: workspace.buildStateRoot,
    xcodeWorkspacePath: nil,
    xcodeProjectPath: URL(fileURLWithPath: "/tmp/repo/SymphonyApps.xcodeproj")
  )
  let projectCommand =
    "xcodebuild -showBuildSettings -json -scheme SymphonySwiftUIApp -destination \(expectedHostMacOSDestination()) -derivedDataPath \(derivedDataPath.path) -project /tmp/repo/SymphonyApps.xcodeproj"
  let projectLocator = ProductLocator(
    processRunner: StubProcessRunner(results: [
      projectCommand: StubProcessRunner.success(
        buildSettingsJSON.replacingOccurrences(of: "Symphony.app", with: "SymphonyServer"))
    ]))
  let projectDetails = try projectLocator.locateProduct(
    workspace: projectWorkspace,
    scheme: "SymphonySwiftUIApp",
    destination: destination,
    derivedDataPath: derivedDataPath
  )
  #expect(projectDetails.productURL.path.hasSuffix("SymphonyServer"))

  do {
    _ = try ProductLocator(
      processRunner: StubProcessRunner(results: [
        workspaceCommand: StubProcessRunner.failure("boom")
      ])
    ).locateProduct(
      workspace: workspace, scheme: "SymphonySwiftUIApp", destination: destination,
      derivedDataPath: derivedDataPath)
    Issue.record("Expected showBuildSettings failures to surface.")
  } catch let error as SymphonyHarnessError {
    #expect(error.code == "show_build_settings_failed")
    #expect(error.message == "boom")
  }

  do {
    _ = try ProductLocator(
      processRunner: StubProcessRunner(results: [
        workspaceCommand: CommandResult(exitStatus: 1, stdout: "", stderr: "")
      ])
    ).locateProduct(
      workspace: workspace, scheme: "SymphonySwiftUIApp", destination: destination,
      derivedDataPath: derivedDataPath)
    Issue.record("Expected empty showBuildSettings failures to use the fallback message.")
  } catch let error as SymphonyHarnessError {
    #expect(error.message == "Failed to query build settings.")
  }

  do {
    _ = try ProductLocator(
      processRunner: StubProcessRunner(results: [
        workspaceCommand: StubProcessRunner.success("[]")
      ])
    ).locateProduct(
      workspace: workspace, scheme: "SymphonySwiftUIApp", destination: destination,
      derivedDataPath: derivedDataPath)
    Issue.record("Expected missing build settings to fail.")
  } catch let error as SymphonyHarnessError {
    #expect(error.code == "missing_build_settings")
  }

  let incompleteJSON = #"""
    [
      {
        "buildSettings": {
          "TARGET_BUILD_DIR": "/tmp/repo/Build/Products/Debug",
          "FULL_PRODUCT_NAME": 17
        }
      }
    ]
    """#
  do {
    _ = try ProductLocator(
      processRunner: StubProcessRunner(results: [
        workspaceCommand: StubProcessRunner.success(incompleteJSON)
      ])
    ).locateProduct(
      workspace: workspace, scheme: "SymphonySwiftUIApp", destination: destination,
      derivedDataPath: derivedDataPath)
    Issue.record("Expected incomplete build settings to fail.")
  } catch let error as SymphonyHarnessError {
    #expect(error.code == "incomplete_build_settings")
  }
}

@Test func simulatorCatalogAndResolverCoverResolutionAndBootBranches() throws {
  let listJSON = #"""
    {
      "devices": {
        "iOS 18.0": [
          {"name":"iPhone 17 Pro","udid":"BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB","state":"Shutdown"},
          {"name":"iPhone 17","udid":"AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA","state":"Shutdown"}
        ],
        "iOS 18.1": [
          {"name":"iPhone 17 Plus","udid":"CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC","state":"Booted"}
        ]
      }
    }
    """#
  let catalogRunner = StubProcessRunner(results: [
    "xcrun simctl list devices available -j": StubProcessRunner.success(listJSON)
  ])
  let catalog = SimctlSimulatorCatalog(processRunner: catalogRunner)
  let devices = try catalog.availableDevices()
  #expect(devices.map(\.name) == ["iPhone 17", "iPhone 17 Plus", "iPhone 17 Pro"])

  do {
    _ = try SimctlSimulatorCatalog(
      processRunner: StubProcessRunner(results: [
        "xcrun simctl list devices available -j": StubProcessRunner.failure("simctl broke")
      ])
    ).availableDevices()
    Issue.record("Expected simctl failures to surface.")
  } catch let error as SymphonyHarnessError {
    #expect(error.code == "simctl_failed")
  }

  let catalogStub = StubSimulatorCatalog(devices: devices)
  let resolver = SimulatorResolver(catalog: catalogStub, processRunner: StubProcessRunner())
  #expect(
    try resolver.resolve(DestinationSelector(platform: .iosSimulator, simulatorName: "plus"))
      .simulatorUDID == "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")

  do {
    _ = try resolver.resolve(
      DestinationSelector(platform: .iosSimulator, simulatorName: "iphone 17"))
    Issue.record("Expected fuzzy duplicate matches to fail.")
  } catch let error as SymphonyHarnessError {
    #expect(error.code == "ambiguous_simulator_match")
  }

  do {
    _ = try resolver.resolve(
      DestinationSelector(platform: .iosSimulator, simulatorName: "does-not-exist"))
    Issue.record("Expected missing simulators to fail.")
  } catch let error as SymphonyHarnessError {
    #expect(error.code == "missing_simulator")
  }

  try SimulatorResolver(catalog: catalogStub, processRunner: StubProcessRunner()).boot(
    resolved: ResolvedDestination(
      platform: .macos, displayName: "macOS", simulatorName: nil, simulatorUDID: nil,
      xcodeDestination: expectedHostMacOSDestination())
  )

  let bootDestination = ResolvedDestination(
    platform: .iosSimulator,
    displayName: "iPhone 17 (AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA)",
    simulatorName: "iPhone 17",
    simulatorUDID: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
    xcodeDestination: "platform=iOS Simulator,id=AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
  )
  let alreadyBootingRunner = BootSequenceProcessRunner(
    responses: [
      StubProcessRunner.failure("not booted"),
      CommandResult(exitStatus: 1, stdout: "", stderr: "Unable to boot device in current state"),
      StubProcessRunner.success(""),
    ]
  )
  try SimulatorResolver(catalog: catalogStub, processRunner: alreadyBootingRunner).boot(
    resolved: bootDestination)

  do {
    try SimulatorResolver(
      catalog: catalogStub,
      processRunner: StubProcessRunner(results: [
        "xcrun simctl bootstatus AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA -b":
          StubProcessRunner.failure("not booted"),
        "xcrun simctl boot AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA": StubProcessRunner.failure(
          "boot failed"),
      ])
    ).boot(resolved: bootDestination)
    Issue.record("Expected boot failures to surface.")
  } catch let error as SymphonyHarnessError {
    #expect(error.code == "simulator_boot_failed")
    #expect(error.message == "boot failed")
  }

  do {
    try SimulatorResolver(
      catalog: catalogStub,
      processRunner: StubProcessRunner(results: [
        "xcrun simctl bootstatus AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA -b":
          StubProcessRunner.failure("not booted"),
        "xcrun simctl boot AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA":
          CommandResult(exitStatus: 1, stdout: "", stderr: ""),
      ])
    ).boot(resolved: bootDestination)
    Issue.record("Expected empty-output boot failures to surface a fallback message.")
  } catch let error as SymphonyHarnessError {
    #expect(error.code == "simulator_boot_failed")
    #expect(error.message == "Failed to boot simulator AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA.")
  }

  let readyFailRunner = BootSequenceProcessRunner(
    responses: [
      StubProcessRunner.failure("bootstatus 1"),
      StubProcessRunner.success(""),
      StubProcessRunner.failure("bootstatus 2"),
    ]
  )
  do {
    try SimulatorResolver(catalog: catalogStub, processRunner: readyFailRunner).boot(
      resolved: bootDestination)
    Issue.record("Expected boot confirmation failures to surface.")
  } catch let error as SymphonyHarnessError {
    #expect(error.code == "simulator_boot_failed")
    #expect(error.message == "bootstatus 2")
  }
}

@Test func simulatorCatalogSortsMatchingNamesByUDID() throws {
  let listJSON = #"""
    {
      "devices": {
        "iOS 18.0": [
          {"name":"iPhone 17","udid":"BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB","state":"Shutdown"},
          {"name":"iPhone 17","udid":"AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA","state":"Shutdown"}
        ]
      }
    }
    """#
  let devices = try SimctlSimulatorCatalog(
    processRunner: StubProcessRunner(results: [
      "xcrun simctl list devices available -j": StubProcessRunner.success(listJSON)
    ])
  ).availableDevices()

  #expect(
    devices.map(\.udid) == [
      "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
      "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB",
    ])
}

@Test func simulatorResolverDefaultSelectionFallsBackToFirstAvailableNonIPhoneDevice() throws {
  let resolver = SimulatorResolver(
    catalog: StubSimulatorCatalog(
      devices: [
        SimulatorDevice(
          name: "iPad Air",
          udid: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB",
          state: "Shutdown",
          runtime: "iOS 18"
        ),
        SimulatorDevice(
          name: "iPad mini",
          udid: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
          state: "Shutdown",
          runtime: "iOS 18"
        ),
      ]
    ),
    processRunner: StubProcessRunner()
  )

  let resolved = try resolver.resolve(DestinationSelector(platform: .iosSimulator))

  #expect(resolved.simulatorName == "iPad Air")
  #expect(resolved.simulatorUDID == "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")
}

@Test func simulatorResolverDefaultSelectionPrefersIPhoneOverEarlierNonPhoneDevices() throws {
  let resolver = SimulatorResolver(
    catalog: StubSimulatorCatalog(
      devices: [
        SimulatorDevice(
          name: "iPad Air",
          udid: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
          state: "Shutdown",
          runtime: "iOS 18"
        ),
        SimulatorDevice(
          name: "iPhone 17",
          udid: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB",
          state: "Shutdown",
          runtime: "iOS 18"
        ),
      ]
    ),
    processRunner: StubProcessRunner()
  )

  let resolved = try resolver.resolve(DestinationSelector(platform: .iosSimulator))

  #expect(resolved.simulatorName == "iPhone 17")
  #expect(resolved.simulatorUDID == "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")
}

@Test func simulatorResolverCoversAvailableDevicesAndApprovedValidationDestinations() throws {
  let devices = [
    SimulatorDevice(
      name: "iPhone 17",
      udid: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
      state: "Shutdown",
      runtime: "iOS 18"
    ),
    SimulatorDevice(
      name: "iPad Pro (M4)",
      udid: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB",
      state: "Shutdown",
      runtime: "iOS 18"
    ),
  ]
  let resolver = SimulatorResolver(
    catalog: StubSimulatorCatalog(devices: devices),
    processRunner: StubProcessRunner()
  )

  #expect(try resolver.availableDevices() == devices)

  let destinations = try resolver.approvedValidationDestinations()
  #expect(destinations.map(\.simulatorName) == ["iPhone 17", "iPad Pro (M4)"])
  #expect(destinations.map(\.xcodeDestination) == [
    "platform=iOS Simulator,id=AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
    "platform=iOS Simulator,id=BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB",
  ])
}
