import Foundation

enum BootstrapRuntimeHooks {
    nonisolated(unsafe) static var outputOverride: ((String) -> Void)?
    nonisolated(unsafe) static var keepAliveOverride: (() -> Void)?
    nonisolated(unsafe) static var runLoopRunner: () -> Void = RunLoop.main.run

    static func defaultOutput(_ line: String) {
        if let outputOverride {
            outputOverride(line)
        } else {
            print(line)
        }
    }

    static func keepAlive() {
        if let keepAliveOverride {
            keepAliveOverride()
        } else {
            runLoopRunner()
        }
    }
}

public enum BootstrapEnvironment {
    public static let serverSchemeKey = "SYMPHONY_SERVER_SCHEME"
    public static let serverHostKey = "SYMPHONY_SERVER_HOST"
    public static let serverPortKey = "SYMPHONY_SERVER_PORT"

    public static func effectiveServerEndpoint(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> BootstrapServerEndpoint {
        BootstrapServerEndpoint.resolved(from: environment)
    }
}

public struct BootstrapServerEndpoint: Equatable, Sendable, CustomStringConvertible {
    public var scheme: String
    public var host: String
    public var port: Int

    public init(scheme: String, host: String, port: Int) {
        self.scheme = Self.normalizedScheme(scheme) ?? Self.defaultEndpoint.scheme
        self.host = Self.normalizedHost(host) ?? Self.defaultEndpoint.host
        self.port = Self.normalizedPort(port) ?? Self.defaultEndpoint.port
    }

    public static let defaultEndpoint = BootstrapServerEndpoint(
        scheme: "http",
        host: "localhost",
        port: 8080
    )

    public var url: URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = port
        return components.url
    }

    public var displayString: String {
        url?.absoluteString ?? "\(scheme)://\(host):\(port)"
    }

    public var description: String {
        displayString
    }

    public static func resolved(from environment: [String: String]) -> Self {
        var endpoint = defaultEndpoint

        if let scheme = normalizedScheme(environment[BootstrapEnvironment.serverSchemeKey]) {
            endpoint.scheme = scheme
        }

        if let host = normalizedHost(environment[BootstrapEnvironment.serverHostKey]) {
            endpoint.host = host
        }

        if let port = normalizedPort(environment[BootstrapEnvironment.serverPortKey]) {
            endpoint.port = port
        }

        return endpoint
    }

    private static func normalizedScheme(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        return trimmed.lowercased()
    }

    private static func normalizedHost(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizedPort(_ value: Int) -> Int? {
        (1...65535).contains(value) ? value : nil
    }

    private static func normalizedPort(_ value: String?) -> Int? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let port = Int(trimmed) else {
            return nil
        }

        return normalizedPort(port)
    }
}

public struct BootstrapStartupState: Sendable, CustomStringConvertible {
    public let componentName: String
    public let processIdentifier: Int32
    public let launchArguments: [String]
    public let startedAt: Date
    public let endpoint: BootstrapServerEndpoint

    public init(
        componentName: String,
        processIdentifier: Int32,
        launchArguments: [String],
        startedAt: Date = Date(),
        endpoint: BootstrapServerEndpoint
    ) {
        self.componentName = componentName
        self.processIdentifier = processIdentifier
        self.launchArguments = launchArguments
        self.startedAt = startedAt
        self.endpoint = endpoint
    }

    public static func current(
        componentName: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        processIdentifier: Int32 = getpid(),
        launchArguments: [String] = ProcessInfo.processInfo.arguments,
        startedAt: Date = Date()
    ) -> Self {
        Self(
            componentName: componentName,
            processIdentifier: processIdentifier,
            launchArguments: launchArguments,
            startedAt: startedAt,
            endpoint: BootstrapEnvironment.effectiveServerEndpoint(environment: environment)
        )
    }

    public var startupLogLines: [String] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        return [
            "[\(componentName)] starting",
            "[\(componentName)] pid=\(processIdentifier)",
            "[\(componentName)] started_at=\(formatter.string(from: startedAt))",
            "[\(componentName)] endpoint=\(endpoint.displayString)",
            "[\(componentName)] arguments=\(launchArguments.joined(separator: " "))"
        ]
    }

    public var description: String {
        startupLogLines.joined(separator: "\n")
    }
}

public enum BootstrapServerRunner {
    public static func run(
        componentName: String = "SymphonyServer",
        environment: [String: String] = ProcessInfo.processInfo.environment,
        processIdentifier: Int32 = getpid(),
        launchArguments: [String] = ProcessInfo.processInfo.arguments,
        startedAt: Date = Date(),
        output: ((String) -> Void)? = nil,
        keepAlive: (() -> Void)? = nil
    ) {
        let output = output ?? BootstrapRuntimeHooks.defaultOutput
        let keepAlive = keepAlive ?? BootstrapRuntimeHooks.keepAlive
        let state = BootstrapStartupState.current(
            componentName: componentName,
            environment: environment,
            processIdentifier: processIdentifier,
            launchArguments: launchArguments,
            startedAt: startedAt
        )

        state.startupLogLines.forEach(output)
        keepAlive()
    }

    public static func startupState(
        componentName: String = "SymphonyServer",
        environment: [String: String] = ProcessInfo.processInfo.environment,
        processIdentifier: Int32 = getpid(),
        launchArguments: [String] = ProcessInfo.processInfo.arguments,
        startedAt: Date = Date()
    ) -> BootstrapStartupState {
        BootstrapStartupState.current(
            componentName: componentName,
            environment: environment,
            processIdentifier: processIdentifier,
            launchArguments: launchArguments,
            startedAt: startedAt
        )
    }
}

public enum BootstrapKeepAlivePolicy {
    public static let exitAfterStartupKey = "SYMPHONY_EXIT_AFTER_STARTUP"

    public static func shouldExitAfterStartup(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        environment[exitAfterStartupKey] == "1"
    }

    public static func makeKeepAlive(environment: [String: String] = ProcessInfo.processInfo.environment) -> () -> Void {
        shouldExitAfterStartup(environment: environment) ? {} : { BootstrapRuntimeHooks.keepAlive() }
    }
}
