import Foundation

public struct SimulatorDevice: Codable, Hashable, Sendable {
    public let name: String
    public let udid: String
    public let state: String
    public let runtime: String

    public init(name: String, udid: String, state: String, runtime: String) {
        self.name = name
        self.udid = udid
        self.state = state
        self.runtime = runtime
    }
}

public protocol SimulatorCataloging {
    func availableDevices() throws -> [SimulatorDevice]
}

public struct SimctlSimulatorCatalog: SimulatorCataloging {
    private let processRunner: ProcessRunning

    public init(processRunner: ProcessRunning = SystemProcessRunner()) {
        self.processRunner = processRunner
    }

    public func availableDevices() throws -> [SimulatorDevice] {
        let result = try processRunner.run(command: "xcrun", arguments: ["simctl", "list", "devices", "available", "-j"], environment: [:], currentDirectory: nil)
        guard result.exitStatus == 0 else {
            throw SymphonyBuildError(code: "simctl_failed", message: result.combinedOutput.isEmpty ? "Failed to query available simulators." : result.combinedOutput)
        }

        let data = Data(result.stdout.utf8)
        let decoded = try JSONDecoder().decode(SimctlListResponse.self, from: data)
        return decoded.devices
            .flatMap(Self.devicesForRuntime)
            .sorted(by: Self.deviceSort)
    }

    private struct SimctlListResponse: Decodable {
        let devices: [String: [SimctlDevice]]
    }

    private struct SimctlDevice: Decodable {
        let name: String
        let udid: String
        let state: String
    }

    private static func devicesForRuntime(runtime: String, devices: [SimctlDevice]) -> [SimulatorDevice] {
        devices.map { SimulatorDevice(name: $0.name, udid: $0.udid, state: $0.state, runtime: runtime) }
    }

    private static func deviceSort(lhs: SimulatorDevice, rhs: SimulatorDevice) -> Bool {
        if lhs.name == rhs.name {
            return lhs.udid < rhs.udid
        }
        return lhs.name < rhs.name
    }
}

public struct SimulatorResolver {
    private let catalog: SimulatorCataloging
    private let processRunner: ProcessRunning

    public init(catalog: SimulatorCataloging = SimctlSimulatorCatalog(), processRunner: ProcessRunning = SystemProcessRunner()) {
        self.catalog = catalog
        self.processRunner = processRunner
    }

    public func resolve(_ selector: DestinationSelector) throws -> ResolvedDestination {
        switch selector.platform {
        case .macos:
            return ResolvedDestination(
                platform: .macos,
                displayName: "macOS",
                simulatorName: nil,
                simulatorUDID: nil,
                xcodeDestination: Self.hostMacOSDestination
            )
        case .iosSimulator:
            let requested = selector.simulatorUDID ?? selector.simulatorName ?? "iPhone 17"
            let devices = try catalog.availableDevices()

            if let exactUDID = devices.first(where: { $0.udid == requested }) {
                return ResolvedDestination(
                    platform: .iosSimulator,
                    displayName: "\(exactUDID.name) (\(exactUDID.udid))",
                    simulatorName: exactUDID.name,
                    simulatorUDID: exactUDID.udid,
                    xcodeDestination: "platform=iOS Simulator,id=\(exactUDID.udid)"
                )
            }

            let exactNameMatches = devices.filter { $0.name == requested }
            if exactNameMatches.count > 1 {
                throw SymphonyBuildError(code: "ambiguous_simulator_name", message: "Simulator name '\(requested)' matches multiple devices. Use a UDID instead.")
            }
            if let exactName = exactNameMatches.first {
                return ResolvedDestination(
                    platform: .iosSimulator,
                    displayName: "\(exactName.name) (\(exactName.udid))",
                    simulatorName: exactName.name,
                    simulatorUDID: exactName.udid,
                    xcodeDestination: "platform=iOS Simulator,id=\(exactName.udid)"
                )
            }

            let fuzzyMatches = devices.filter { $0.name.localizedCaseInsensitiveContains(requested) }
            if fuzzyMatches.count > 1 {
                throw SymphonyBuildError(code: "ambiguous_simulator_match", message: "Simulator search '\(requested)' matched multiple devices. Use a more specific name or a UDID.")
            }
            guard let fuzzy = fuzzyMatches.first else {
                throw SymphonyBuildError(code: "missing_simulator", message: "No available simulator matched '\(requested)'.")
            }

            return ResolvedDestination(
                platform: .iosSimulator,
                displayName: "\(fuzzy.name) (\(fuzzy.udid))",
                simulatorName: fuzzy.name,
                simulatorUDID: fuzzy.udid,
                xcodeDestination: "platform=iOS Simulator,id=\(fuzzy.udid)"
            )
        }
    }

    public func boot(resolved destination: ResolvedDestination) throws {
        guard let udid = destination.simulatorUDID else {
            return
        }

        let result = try processRunner.run(command: "xcrun", arguments: ["simctl", "bootstatus", udid, "-b"], environment: [:], currentDirectory: nil)
        if result.exitStatus == 0 {
            return
        }

        let boot = try processRunner.run(command: "xcrun", arguments: ["simctl", "boot", udid], environment: [:], currentDirectory: nil)
        if boot.exitStatus != 0 && !boot.combinedOutput.contains("Unable to boot device in current state") {
            throw SymphonyBuildError(code: "simulator_boot_failed", message: boot.combinedOutput.isEmpty ? "Failed to boot simulator \(udid)." : boot.combinedOutput)
        }

        let ready = try processRunner.run(command: "xcrun", arguments: ["simctl", "bootstatus", udid, "-b"], environment: [:], currentDirectory: nil)
        guard ready.exitStatus == 0 else {
            throw SymphonyBuildError(code: "simulator_boot_failed", message: ready.combinedOutput.isEmpty ? "Failed to confirm simulator boot." : ready.combinedOutput)
        }
    }
}

private extension SimulatorResolver {
    static var hostMacOSDestination: String {
        #if arch(arm64)
        "platform=macOS,arch=arm64"
        #elseif arch(x86_64)
        "platform=macOS,arch=x86_64"
        #else
        "platform=macOS"
        #endif
    }
}
