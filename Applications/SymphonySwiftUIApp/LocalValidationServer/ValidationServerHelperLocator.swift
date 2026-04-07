#if os(macOS)
  import Foundation

  /// Protocol for locating the bundled validation server helper binary.
  protocol ValidationServerHelperLocating {
    func helperURL() throws -> URL
  }

  struct BundledValidationServerHelperLocator: ValidationServerHelperLocating {
    let bundle: Bundle
    let fileManager: FileManager

    init(bundle: Bundle = .main, fileManager: FileManager = .default) {
      self.bundle = bundle
      self.fileManager = fileManager
    }

    func helperURL() throws -> URL {
      let candidates = [
        bundle.bundleURL.appendingPathComponent("Contents/Resources/SymphonyValidationServerHelper"),
        bundle.bundleURL.appendingPathComponent("Contents/Helpers/SymphonyValidationServerHelper"),
        bundle.bundleURL.appendingPathComponent("Contents/MacOS/SymphonyValidationServerHelper"),
        bundle.bundleURL.deletingLastPathComponent()
          .appendingPathComponent("SymphonyValidationServerHelper"),
      ]

      for candidate in candidates where fileManager.isExecutableFile(atPath: candidate.path) {
        return candidate
      }

      throw ValidationServerLaunchError.helperUnavailable(candidates[0].path)
    }
  }

  struct StubValidationServerHelperLocator: ValidationServerHelperLocating {
    var url: URL

    func helperURL() throws -> URL {
      url
    }
  }
#endif
