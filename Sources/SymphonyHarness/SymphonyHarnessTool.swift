import Foundation
import SymphonyShared

public final class SymphonyHarnessTool {
  let workspaceDiscovery: WorkspaceDiscovering
  let executionContextBuilder: ExecutionContextBuilder
  let simulatorResolver: SimulatorResolver
  let processRunner: ProcessRunning
  let artifactManager: ArtifactManager
  let endpointOverrideStore: EndpointOverrideStore
  let doctorService: DoctorServicing
  let toolchainCapabilitiesResolver: ToolchainCapabilitiesResolving
  let goEnryMaterializer: GoEnryMaterializing
  let productLocator: ProductLocator
  let commitHarness: CommitHarness
  let gitHookInstaller: GitHookInstaller
  let statusSink: @Sendable (String) -> Void
  let scratchPath: String

  public init(
    workspaceDiscovery: WorkspaceDiscovering = WorkspaceDiscovery(),
    executionContextBuilder: ExecutionContextBuilder = ExecutionContextBuilder(),
    simulatorResolver: SimulatorResolver = SimulatorResolver(),
    processRunner: ProcessRunning = SystemProcessRunner(),
    artifactManager: ArtifactManager = ArtifactManager(),
    endpointOverrideStore: EndpointOverrideStore = EndpointOverrideStore(),
    doctorService: DoctorServicing? = nil,
    toolchainCapabilitiesResolver: ToolchainCapabilitiesResolving? = nil,
    productLocator: ProductLocator = ProductLocator(),
    commitHarness: CommitHarness? = nil,
    gitHookInstaller: GitHookInstaller? = nil,
    scratchPath: String = ".build/swiftpm-cache",
    statusSink: @escaping @Sendable (String) -> Void = { message in
      FileHandle.standardError.write(Data((message + "\n").utf8))
    }
  ) {
    self.workspaceDiscovery = workspaceDiscovery
    self.executionContextBuilder = executionContextBuilder
    self.simulatorResolver = simulatorResolver
    self.processRunner = processRunner
    self.artifactManager = artifactManager
    self.endpointOverrideStore = endpointOverrideStore
    let resolvedToolchainCapabilitiesResolver =
      toolchainCapabilitiesResolver
      ?? ProcessToolchainCapabilitiesResolver(processRunner: processRunner)
    self.toolchainCapabilitiesResolver = resolvedToolchainCapabilitiesResolver
    self.doctorService =
      doctorService
      ?? DoctorService(
        workspaceDiscovery: workspaceDiscovery,
        processRunner: processRunner,
        toolchainCapabilitiesResolver: resolvedToolchainCapabilitiesResolver
      )
    self.goEnryMaterializer = GoEnryMaterializer(processRunner: processRunner)
    self.productLocator = productLocator
    self.statusSink = statusSink
    self.scratchPath = scratchPath
    self.commitHarness =
      commitHarness
      ?? CommitHarness(
        processRunner: processRunner,
        statusSink: statusSink,
        toolchainCapabilitiesResolver: resolvedToolchainCapabilitiesResolver,
        scratchPath: scratchPath
      )
    self.gitHookInstaller = gitHookInstaller ?? GitHookInstaller(processRunner: processRunner)
  }

  func build(_ request: BuildCommandRequest) throws -> String {
    let workspace = try workspaceDiscovery.discover(from: request.currentDirectory)
    let worker = try WorkerScope(id: request.workerID)
    let selector = SchemeSelector(
      product: request.product, scheme: request.scheme, platform: request.platform)
    let executionContext = try executionContextBuilder.make(
      workspace: workspace, worker: worker, command: .build, runID: selector.runIdentifier)
    switch selector.product.defaultBackend {
    case .xcode:
      if !request.dryRun {
        try ensureXcodeSupport(for: selector.platform)
      }
      let destination = try xcodeDestination(
        platform: selector.platform, simulator: request.simulator, dryRun: request.dryRun)
      return try buildXcode(
        request: request,
        workspace: workspace,
        selector: selector,
        destination: destination,
        executionContext: executionContext
      )
    case .swiftPM:
      let destination = try simulatorResolver.resolve(
        destinationSelector(platform: selector.platform, simulator: request.simulator))
      return try buildSwiftPM(
        request: request,
        workspace: workspace,
        selector: selector,
        destination: destination,
        executionContext: executionContext
      )
    }
  }

  func test(_ request: TestCommandRequest) throws -> String {
    let workspace = try workspaceDiscovery.discover(from: request.currentDirectory)
    let worker = try WorkerScope(id: request.workerID)
    let selector = SchemeSelector(
      product: request.product, scheme: request.scheme, platform: request.platform)
    let executionContext = try executionContextBuilder.make(
      workspace: workspace, worker: worker, command: .test, runID: selector.runIdentifier)
    switch selector.product.defaultBackend {
    case .xcode:
      if !request.dryRun {
        try ensureXcodeSupport(for: selector.platform)
      }
      let destination = try xcodeDestination(
        platform: selector.platform, simulator: request.simulator, dryRun: request.dryRun)
      return try testXcode(
        request: request,
        workspace: workspace,
        selector: selector,
        destination: destination,
        executionContext: executionContext
      )
    case .swiftPM:
      let destination = try simulatorResolver.resolve(
        destinationSelector(platform: selector.platform, simulator: request.simulator))
      return try testSwiftPM(
        request: request,
        workspace: workspace,
        selector: selector,
        destination: destination,
        executionContext: executionContext
      )
    }
  }

  func run(_ request: RunCommandRequest) throws -> String {
    let workspace = try workspaceDiscovery.discover(from: request.currentDirectory)
    let worker = try WorkerScope(id: request.workerID)
    let selector = SchemeSelector(
      product: request.product, scheme: request.scheme, platform: request.platform)
    let executionContext = try executionContextBuilder.make(
      workspace: workspace, worker: worker, command: .run, runID: selector.runIdentifier)
    switch selector.product.defaultBackend {
    case .xcode:
      if !request.dryRun {
        try ensureXcodeSupport(for: selector.platform)
      }
      let destination = try xcodeDestination(
        platform: selector.platform, simulator: request.simulator, dryRun: request.dryRun)
      return try runXcode(
        request: request,
        workspace: workspace,
        selector: selector,
        destination: destination,
        executionContext: executionContext
      )
    case .swiftPM:
      let destination = try simulatorResolver.resolve(
        destinationSelector(platform: selector.platform, simulator: request.simulator))
      return try runSwiftPM(
        request: request,
        workspace: workspace,
        selector: selector,
        destination: destination,
        executionContext: executionContext
      )
    }
  }

}

// SAFETY: @unchecked Sendable — all stored properties are immutable `let` bindings
// assigned once at init. No mutable state exists after initialization.
extension SymphonyHarnessTool: @unchecked Sendable {}

struct SubjectExecutionSelection {
  let legacyProduct: ProductKind
  let subjectName: String
  let scheme: String
  let swiftPMProduct: String?
  let swiftPMTestFilter: String?
  let onlyTesting: [String]
}

struct SharedRunIndex: Codable, Hashable, Sendable {
  let command: HarnessCommand
  let runID: String
  let startedAt: String
  let endedAt: String
  let entries: [ArtifactIndexEntry]
  let anomalies: [ArtifactAnomaly]
}

struct SyntheticSubjectSummary: Codable, Hashable, Sendable {
  let command: HarnessCommand
  let subject: String
  let outcome: SubjectRunOutcome
  let artifactRoot: String
  let reason: String
}

struct RepositoryValidationOutcome: Sendable {
  let summaryLines: [String]
  let anomalies: [ArtifactAnomaly]
  let failureMessage: String?
}

struct ValidationPlanResult: Codable, Hashable, Sendable {
  let plan: String
  let destination: String
  let outcome: SubjectRunOutcome
  let artifactRoot: String
  let includesAccessibilityCoverage: Bool
}

struct AggregatedValidationSubjectSummary: Codable, Hashable, Sendable {
  let command: HarnessCommand
  let subject: String
  let outcome: SubjectRunOutcome
  let plans: [ValidationPlanResult]
  let artifactRoot: String
}

struct ValidationPlanMetadata: Hashable, Sendable {
  let name: String
  let includesAccessibilityCoverage: Bool
}

// SAFETY: @unchecked Sendable — `results` is exclusively accessed through `lock`.
final class ScheduledRunCollector: @unchecked Sendable {
  let lock = NSLock()
  var results: [SubjectRunResult?]

  init(count: Int) {
    self.results = Array(repeating: nil, count: count)
  }

  func store(result: SubjectRunResult, at index: Int) {
    lock.lock()
    results[index] = result
    lock.unlock()
  }

  func orderedResults() throws -> [SubjectRunResult] {
    lock.lock()
    defer { lock.unlock() }
    var orderedResults = [SubjectRunResult]()
    orderedResults.reserveCapacity(results.count)
    for result in results {
      if let result {
        orderedResults.append(result)
      }
    }
    return orderedResults
  }

  func pendingIndices(total: Int) -> [Int] {
    lock.lock()
    defer { lock.unlock() }
    return (0..<total).filter { results[$0] == nil }
  }
}
