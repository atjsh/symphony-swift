import XCTest
@testable import XcodeSupport

final class BootstrapSupportTests: XCTestCase {
    func testEffectiveServerEndpointUsesDefaults() {
        let endpoint = BootstrapEnvironment.effectiveServerEndpoint(environment: [:])

        XCTAssertEqual(endpoint, .defaultEndpoint)
        XCTAssertEqual(endpoint.displayString, "http://localhost:8080")
    }

    func testEffectiveServerEndpointUsesEnvironmentOverrides() {
        let endpoint = BootstrapEnvironment.effectiveServerEndpoint(
            environment: [
                BootstrapEnvironment.serverSchemeKey: "https",
                BootstrapEnvironment.serverHostKey: "example.com",
                BootstrapEnvironment.serverPortKey: "9443"
            ]
        )

        XCTAssertEqual(endpoint.scheme, "https")
        XCTAssertEqual(endpoint.host, "example.com")
        XCTAssertEqual(endpoint.port, 9443)
        XCTAssertEqual(endpoint.displayString, "https://example.com:9443")
    }

    func testStartupStateIncludesEndpointAndComponentName() {
        let state = BootstrapServerRunner.startupState(
            componentName: "SymphonyServer",
            environment: [:],
            processIdentifier: 1234,
            launchArguments: ["symphony-server", "--verbose"],
            startedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        XCTAssertEqual(state.componentName, "SymphonyServer")
        XCTAssertTrue(state.startupLogLines.contains("[SymphonyServer] pid=1234"))
        XCTAssertTrue(state.startupLogLines.contains("[SymphonyServer] endpoint=http://localhost:8080"))
    }
}
