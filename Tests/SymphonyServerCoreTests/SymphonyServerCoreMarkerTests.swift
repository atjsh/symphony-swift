import Testing

@testable import SymphonyServerCore

@Test func serverCoreMarkerPublishesCanonicalModuleName() {
  #expect(SymphonyServerCoreMarker.name == "SymphonyServerCore")
}
