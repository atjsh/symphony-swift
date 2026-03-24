import Foundation

public struct SymphonyBuildError: LocalizedError, CustomStringConvertible, Sendable {
    public let code: String
    public let message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }

    public var errorDescription: String? {
        "[\(code)] \(message)"
    }

    public var description: String {
        errorDescription ?? message
    }
}

public struct SymphonyBuildCommandFailure: LocalizedError, Sendable {
    public let message: String
    public let summaryPath: URL?

    public init(message: String, summaryPath: URL? = nil) {
        self.message = message
        self.summaryPath = summaryPath
    }

    public var errorDescription: String? {
        if let summaryPath {
            return "\(message) Summary: \(summaryPath.path)"
        }
        return message
    }
}
