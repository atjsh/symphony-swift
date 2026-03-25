import Foundation
import Network
import SymphonyShared

final class SymphonyHTTPServer: @unchecked Sendable {
    private let listener: NWListener
    private let api: SymphonyHTTPAPI
    private let queue = DispatchQueue(label: "dev.atjsh.symphony.http-server")

    init(port: Int, api: SymphonyHTTPAPI) throws {
        let requestedPort = port
        guard let rawPort = UInt16(exactly: requestedPort),
              let port = NWEndpoint.Port(rawValue: rawPort) else {
            throw SymphonyRuntimeError.sqlite("Invalid listener port \(requestedPort).")
        }
        self.listener = try NWListener(using: .tcp, on: port)
        self.api = api
    }

    func start() throws {
        let started = DispatchSemaphore(value: 0)
        let startup = StartupState()

        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                started.signal()
            case .failed(let error):
                startup.error = error
                started.signal()
            default:
                break
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.start(queue: queue)
        started.wait()

        if let startupError = startup.error {
            throw startupError
        }
    }

    func stop() {
        listener.cancel()
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, accumulated: Data())
    }

    private func receive(on connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            let action = Self.receiveAction(
                isServerAvailable: true,
                data: data,
                isComplete: isComplete,
                error: error,
                accumulated: accumulated,
                responder: self.response(for:)
            )
            Self.applyReceiveAction(
                action,
                cancel: { connection.cancel() },
                send: { response in
                    connection.send(content: response, completion: .contentProcessed { _ in
                        connection.cancel()
                    })
                },
                receive: { nextAccumulated in
                    self.receive(on: connection, accumulated: nextAccumulated)
                }
            )
        }
    }

    private func response(for requestData: Data) -> Data {
        try! SymphonyHTTPWire.response(for: requestData, api: api)
    }

    static func receiveAction(
        isServerAvailable: Bool,
        data: Data?,
        isComplete: Bool,
        error: NWError?,
        accumulated: Data,
        responder: (Data) -> Data
    ) -> SymphonyHTTPReceiveAction {
        guard isServerAvailable else {
            return .cancel
        }

        if let error {
            _ = error
            return .cancel
        }

        let nextAccumulated = accumulated + (data ?? Data())
        let delimiter = Data("\r\n\r\n".utf8)

        if let range = nextAccumulated.range(of: delimiter) {
            let headerData = nextAccumulated[..<range.upperBound]
            return .send(responder(Data(headerData)))
        }

        if isComplete {
            return .cancel
        }

        return .continueReceiving(nextAccumulated)
    }

    static func applyReceiveAction(
        _ action: SymphonyHTTPReceiveAction,
        cancel: () -> Void,
        send: (Data) -> Void,
        receive: (Data) -> Void
    ) {
        switch action {
        case .cancel:
            cancel()
        case .send(let response):
            send(response)
        case .continueReceiving(let accumulated):
            receive(accumulated)
        }
    }
}

private final class StartupState: @unchecked Sendable {
    var error: Error?
}

enum SymphonyHTTPWire {
    static func response(for requestData: Data, api: SymphonyHTTPAPI) throws -> Data {
        let response: SymphonyHTTPResponse
        do {
            let request = try parseRequest(from: requestData)
            response = try api.respond(to: request)
        } catch {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let body = try! encoder.encode(
                ErrorEnvelope(
                    error: ErrorPayload(
                        code: "bad_request",
                        message: "The HTTP request could not be parsed."
                    )
                )
            )
            return serialize(
                SymphonyHTTPResponse(
                    statusCode: 400,
                    headers: ["Content-Type": "application/json; charset=utf-8"],
                    body: body
                )
            )
        }

        return serialize(response)
    }

    static func parseRequest(from data: Data) throws -> SymphonyAPIRequest {
        guard let text = String(data: data, encoding: .utf8) else {
            throw SymphonyRuntimeError.encoding("Failed to decode HTTP request bytes.")
        }
        guard !text.isEmpty else {
            throw SymphonyRuntimeError.encoding("Missing HTTP request line.")
        }

        let sections = text.components(separatedBy: "\r\n")
        let requestLine = sections[0]

        let requestParts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard requestParts.count >= 2 else {
            throw SymphonyRuntimeError.encoding("Malformed HTTP request line.")
        }

        var headers = [String: String]()
        for line in sections.dropFirst() {
            if line.isEmpty {
                break
            }
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else {
                continue
            }
            headers[String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)] = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return SymphonyAPIRequest(
            method: String(requestParts[0]),
            path: String(requestParts[1]),
            headers: headers
        )
    }

    static func serialize(_ response: SymphonyHTTPResponse) -> Data {
        var headers = response.headers
        headers["Content-Length"] = String(response.body.count)
        headers["Connection"] = "close"

        var lines = ["HTTP/1.1 \(response.statusCode) \(statusText(for: response.statusCode))"]
        lines.append(contentsOf: headers.sorted(by: { $0.key < $1.key }).map { "\($0.key): \($0.value)" })
        lines.append("")
        lines.append("")

        var data = Data(lines.joined(separator: "\r\n").utf8)
        data.append(response.body)
        return data
    }

    static func statusText(for statusCode: Int) -> String {
        switch statusCode {
        case 200:
            return "OK"
        case 202:
            return "Accepted"
        case 400:
            return "Bad Request"
        case 404:
            return "Not Found"
        case 405:
            return "Method Not Allowed"
        default:
            return "Internal Server Error"
        }
    }
}

enum SymphonyHTTPReceiveAction {
    case cancel
    case send(Data)
    case continueReceiving(Data)
}
