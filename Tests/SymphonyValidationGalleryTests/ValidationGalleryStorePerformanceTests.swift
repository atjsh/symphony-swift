import XCTest

@testable import SymphonyValidationGallery

/// Focused in-process performance tests for the store's hot paths.
///
/// Each test targets a single signpost interval so results are fast
/// to run and easy to attribute. Uses 3 iterations to keep wall-clock
/// under 15 s per test.
@MainActor
final class ValidationGalleryStorePerformanceTests: XCTestCase {

  private static let sub = "dev.atjsh.xcode-validation-gallery.performance"
  private static let cat = "store"

  private var store: ValidationGalleryStore!

  override func setUp() async throws {
    let url = try XCTUnwrap(ValidationGalleryFixtureLocator.bundledFixtureURL)
    let snap = try await ValidationBundleLoader().load(from: .folder(url))
    store = ValidationGalleryStore(
      loader: StubValidationBundleLoader(snapshot: snap),
      recentBundleStore: InMemoryRecentBundleStore(),
      workspacePreferencesStore: InMemoryWorkspacePreferencesStore(),
      searchDebounceInterval: .zero
    )
    await store.open(.folder(url), rememberRecent: false)
    XCTAssertFalse(store.filteredArtifacts.isEmpty)
  }

  override func tearDown() async throws { store = nil }

  private func opts(_ n: Int = 3) -> XCTMeasureOptions {
    let o = XCTMeasureOptions(); o.iterationCount = n; return o
  }

  // MARK: - Selection path (the user-reported bottleneck)

  /// End-to-end `selectArtifact` — covers recomputeSelectedArtifact,
  /// normalizeSelectionAfterFilterChange, normalizeSelectedComment.
  func testSelectArtifact() {
    let ids = Array(store.filteredArtifacts.prefix(5).map(\.id))
    measure(metrics: [
      XCTOSSignpostMetric(subsystem: Self.sub, category: Self.cat, name: "selectArtifact"),
      XCTClockMetric(),
    ], options: opts()) {
      for id in ids { store.selectArtifact(id) }
    }
  }

  /// Just the inner recomputeSelectedArtifact (linear scan + audit filter).
  func testRecomputeSelectedArtifact() {
    let ids = Array(store.filteredArtifacts.prefix(5).map(\.id))
    measure(metrics: [
      XCTOSSignpostMetric(subsystem: Self.sub, category: Self.cat, name: "recomputeSelectedArtifact"),
      XCTClockMetric(),
    ], options: opts()) {
      for id in ids { store.selectArtifact(id) }
    }
  }

  // MARK: - Filter / recompute path

  func testRecomputeFilteredState() {
    measure(metrics: [
      XCTOSSignpostMetric(subsystem: Self.sub, category: Self.cat, name: "recomputeFilteredState"),
      XCTClockMetric(),
    ], options: opts()) {
      store.sidebarSelection = .platform("iOS")
      store.sidebarSelection = .all
    }
  }

  func testFilterArtifacts() {
    measure(metrics: [
      XCTOSSignpostMetric(subsystem: Self.sub, category: Self.cat, name: "filterArtifacts"),
      XCTClockMetric(),
    ], options: opts()) {
      store.sidebarSelection = .platform("iOS")
      store.sidebarSelection = .all
    }
  }

  func testMakePlatformSections() {
    measure(metrics: [
      XCTOSSignpostMetric(subsystem: Self.sub, category: Self.cat, name: "makePlatformSections"),
      XCTClockMetric(),
    ], options: opts()) {
      store.sidebarSelection = .platform("iOS")
      store.sidebarSelection = .all
    }
  }

  // MARK: - Comment numbering

  func testNumberedCurrentBundleComments() {
    measure(metrics: [
      XCTOSSignpostMetric(subsystem: Self.sub, category: Self.cat, name: "numberedCurrentBundleComments"),
      XCTClockMetric(),
    ], options: opts()) {
      _ = store.numberedCurrentBundleComments()
    }
  }

  func testSearchRecompute() {
    measure(metrics: [
      XCTOSSignpostMetric(subsystem: Self.sub, category: Self.cat, name: "recomputeFilteredState"),
      XCTClockMetric(),
    ], options: opts()) {
      store.searchText = "screenshot"
      store.searchText = ""
    }
  }

  // MARK: - A → B → A selection cycle

  /// Measures the A → B → A re-selection pattern that was the user-reported
  /// bottleneck. Each `selectArtifact` call should complete in under 1 ms
  /// for any dataset size supported by the bundled fixture.
  func testSelectArtifactCycleABA() {
    let ids = Array(store.filteredArtifacts.prefix(10).map(\.id))
    guard ids.count >= 2 else {
      XCTFail("Need at least 2 artifacts to cycle A→B→A")
      return
    }

    measure(metrics: [XCTClockMetric()], options: opts(5)) {
      for i in 0..<ids.count {
        let a = ids[i]
        let b = ids[(i + 1) % ids.count]

        store.selectArtifact(a)
        XCTAssertEqual(store.selectedArtifact?.id, a)

        store.selectArtifact(b)
        XCTAssertEqual(store.selectedArtifact?.id, b)

        // Re-select A — this is the path that was historically slow
        store.selectArtifact(a)
        XCTAssertEqual(store.selectedArtifact?.id, a)
      }
    }
  }

  /// Asserts that a single selectArtifact call never exceeds a wall-clock
  /// threshold. This is a regression gate — if the @FocusedValue cascade
  /// fix regresses, this test will catch it at the store level.
  func testSelectArtifactWallClockBudget() {
    let ids = Array(store.filteredArtifacts.map(\.id))
    guard ids.count >= 2 else {
      XCTFail("Need at least 2 artifacts")
      return
    }

    // Warm up
    store.selectArtifact(ids[0])

    for id in ids.dropFirst() {
      let start = CFAbsoluteTimeGetCurrent()
      store.selectArtifact(id)
      let elapsed = CFAbsoluteTimeGetCurrent() - start

      // Budget: each selectArtifact must complete in under 5 ms.
      // Profiling showed 0.14–0.20 ms, so 5 ms is a generous ceiling.
      XCTAssertLessThan(elapsed, 0.005, "selectArtifact(\(id)) took \(elapsed * 1000)ms — exceeds 5ms budget")
      XCTAssertEqual(store.selectedArtifact?.id, id)
    }
  }
}
