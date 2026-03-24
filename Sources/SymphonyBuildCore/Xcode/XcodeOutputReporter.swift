import Foundation

final class XcodeOutputReporter: @unchecked Sendable {
    private let mode: XcodeOutputMode
    private let sink: @Sendable (String) -> Void
    private let lock = NSLock()
    private var suppressedLineCount = 0

    init(mode: XcodeOutputMode, sink: @escaping @Sendable (String) -> Void) {
        self.mode = mode
        self.sink = sink
    }

    func makeObservation(label: String) -> ProcessObservation {
        ProcessObservation(
            label: label,
            onStaleSignal: { [sink] message in
                sink(message)
            },
            onLine: { [weak self] stream, line in
                self?.handle(stream: stream, line: line)
            }
        )
    }

    func finish() {
        guard mode == .filtered else {
            return
        }

        let suppressedCount: Int
        lock.lock()
        suppressedCount = suppressedLineCount
        suppressedLineCount = 0
        lock.unlock()

        if suppressedCount > 0 {
            sink(timestamped("[xcodebuild] suppressed \(suppressedCount) low-signal lines"))
        }
    }

    private func handle(stream: ProcessStream, line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        switch mode {
        case .quiet:
            return
        case .full:
            sink(timestamped("[xcodebuild/\(stream.rawValue)] \(trimmed)"))
        case .filtered:
            if isHighSignal(trimmed) {
                sink(timestamped("[xcodebuild] \(trimmed)"))
            } else {
                lock.lock()
                suppressedLineCount += 1
                lock.unlock()
            }
        }
    }

    private func isHighSignal(_ line: String) -> Bool {
        let lowercase = line.lowercased()
        let prefixes = [
            "error:",
            "warning:",
            "note:",
            "testing failed",
            "test suite",
            "failing tests:",
            "command line invocation:",
            "result bundle written",
            "writing result bundle",
            "** build",
            "** test",
        ]

        if prefixes.contains(where: { lowercase.hasPrefix($0) }) {
            return true
        }

        let contains = [
            ": error:",
            ": warning:",
            "failed",
            "succeeded",
            "result bundle",
            "provisioning",
            "signing",
        ]

        return contains.contains(where: { lowercase.contains($0) })
    }

    private func timestamped(_ message: String) -> String {
        "[\(DateFormatting.iso8601(Date()))] \(message)"
    }
}
