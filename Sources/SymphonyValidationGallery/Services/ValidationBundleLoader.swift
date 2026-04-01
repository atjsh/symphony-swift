import Foundation
import SymphonyXcodeValidation

public actor ValidationBundleLoader: ValidationBundleLoading {
  private let fileManager: FileManager

  public init(fileManager: FileManager = .default) {
    self.fileManager = fileManager
  }

  public func load(from source: ValidationBundleSource) async throws -> ValidationBundleSnapshot {
    let bundleRootURL = source.bundleRootURL.standardizedFileURL
    let manifestURL = source.manifestURL.standardizedFileURL
    let summaryURL = bundleRootURL.appendingPathComponent("summary.json").standardizedFileURL
    let auditSummaryURL = bundleRootURL.appendingPathComponent("audit-summary.json").standardizedFileURL

    let summary = try decodeRequired(
      ValidationSummary.self,
      at: summaryURL,
      named: "summary.json"
    )
    let manifest = try decodeRequired(
      [MediaArtifact].self,
      at: manifestURL,
      named: "manifest.json"
    )
    let auditRecords = try decodeRequired(
      [AuditIssueRecord].self,
      at: auditSummaryURL,
      named: "audit-summary.json"
    )

    var warnings = [ValidationBundleWarning]()
    let artifacts = manifest.map { record in
      let resolvedURL = resolvePath(record.file, relativeTo: bundleRootURL)
      let isAvailable = fileManager.fileExists(atPath: resolvedURL.path)
      if isAvailable == false {
        warnings.append(
          ValidationBundleWarning(
            kind: .missingMedia,
            message: "Missing media artifact at \(resolvedURL.path)"
          )
        )
      }
      return ValidationGalleryArtifact(record: record, fileURL: resolvedURL, isAvailable: isAvailable)
    }
    let normalizedArtifacts = deduplicatedArtifactsKeepingLast(artifacts)

    let auditIssues = auditRecords.map { record in
      let resolvedURL = resolvePath(record.file, relativeTo: bundleRootURL)
      let isAvailable = fileManager.fileExists(atPath: resolvedURL.path)
      if isAvailable == false {
        warnings.append(
          ValidationBundleWarning(
            kind: .missingAuditAttachment,
            message: "Missing audit attachment at \(resolvedURL.path)"
          )
        )
      }
      return ValidationGalleryAuditIssue(record: record, fileURL: resolvedURL, isAvailable: isAvailable)
    }
    warnings = deduplicatedWarnings(warnings)

    let sections = ValidationGalleryOrganizer.makePlatformSections(from: normalizedArtifacts)
    return ValidationBundleSnapshot(
      source: source,
      sourceLabel: bundleRootURL.path,
      bundleRootURL: bundleRootURL,
      manifestURL: manifestURL,
      summary: summary,
      artifacts: normalizedArtifacts,
      auditIssues: auditIssues,
      warnings: warnings,
      platformSections: sections
    )
  }

  private func decodeRequired<Decoded: Decodable>(
    _ type: Decoded.Type,
    at url: URL,
    named fileName: String
  ) throws -> Decoded {
    guard fileManager.fileExists(atPath: url.path) else {
      throw ValidationGalleryError.missingRequiredFile(fileName)
    }

    do {
      let data = try Data(contentsOf: url)
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      return try decoder.decode(Decoded.self, from: data)
    } catch let error as ValidationGalleryError {
      throw error
    } catch {
      throw ValidationGalleryError.malformedJSON(
        fileName: fileName,
        reason: error.localizedDescription
      )
    }
  }

  private func resolvePath(_ rawPath: String, relativeTo bundleRootURL: URL) -> URL {
    if let fileURL = URL(string: rawPath), fileURL.isFileURL {
      return fileURL.standardizedFileURL
    }

    let expandedPath = NSString(string: rawPath).expandingTildeInPath
    if expandedPath.hasPrefix("/") {
      return URL(fileURLWithPath: expandedPath).standardizedFileURL
    }

    let cleaned = rawPath
      .replacingOccurrences(of: "\\", with: "/")
      .replacingOccurrences(of: "./", with: "", options: .anchored)
    return bundleRootURL.appendingPathComponent(cleaned).standardizedFileURL
  }

  private func deduplicatedArtifactsKeepingLast(
    _ artifacts: [ValidationGalleryArtifact]
  ) -> [ValidationGalleryArtifact] {
    var lastIndexByKey = [ValidationCanonicalMediaKey: Int]()
    for (index, artifact) in artifacts.enumerated() {
      lastIndexByKey[
        ValidationCanonicalMediaKey(
          artifact: artifact.record,
          filePath: artifact.fileURL.standardizedFileURL.path
        )
      ] = index
    }

    return artifacts.enumerated().compactMap { index, artifact in
      let key = ValidationCanonicalMediaKey(
        artifact: artifact.record,
        filePath: artifact.fileURL.standardizedFileURL.path
      )
      guard lastIndexByKey[key] == index else {
        return nil
      }

      return artifact
    }
  }

  private func deduplicatedWarnings(
    _ warnings: [ValidationBundleWarning]
  ) -> [ValidationBundleWarning] {
    var seenWarningIDs = Set<String>()
    return warnings.filter { warning in
      seenWarningIDs.insert(warning.id).inserted
    }
  }
}
