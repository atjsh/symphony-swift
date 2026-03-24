import XCTest
@testable import XcodeSupport

final class BootstrapServerRunnerTests: XCTestCase {
    func testStartupStateUsesProvidedLaunchArguments() {
        let state = BootstrapServerRunner.startupState(
            componentName: "SymphonyServer",
            environment: [:],
            processIdentifier: 4321,
            launchArguments: ["server", "--port", "8080"],
            startedAt: Date(timeIntervalSince1970: 1_700_000_123)
        )

        XCTAssertEqual(state.launchArguments, ["server", "--port", "8080"])
        XCTAssertTrue(state.description.contains("[SymphonyServer] starting"))
        XCTAssertTrue(state.description.contains("[SymphonyServer] arguments=server --port 8080"))
    }
}
