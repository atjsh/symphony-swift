import Darwin
import Foundation
import Network
import Testing
@testable import SymphonyRuntime
import SymphonyShared

@Test func httpWireParsesRequestsAndSerializesResponses() throws {
    let api = try makeTransportAPI()
    let requestData = Data("""
    GET /api/v1/health HTTP/1.1\r
    Host: localhost\r
    Accept: application/json\r
    \r
    """.utf8)

    let request = try SymphonyHTTPWire.parseRequest(from: requestData)
    #expect(request.method == "GET")
    #expect(request.path == "/api/v1/health")
    #expect(request.headers["Host"] == "localhost")

    let responseData = try SymphonyHTTPWire.response(for: requestData, api: api)
    let responseText = try #require(String(data: responseData, encoding: .utf8))
    #expect(responseText.contains("HTTP/1.1 200 OK"))
    #expect(responseText.contains("Connection: close"))
    #expect(responseText.contains("Content-Type: application/json; charset=utf-8"))
    #expect(responseText.contains(#""tracker_kind":"github""#))

    let serialized = SymphonyHTTPWire.serialize(
        SymphonyHTTPResponse(
            statusCode: 202,
            headers: ["Content-Type": "application/json"],
            body: Data(#"{"queued":true}"#.utf8)
        )
    )
    let serializedText = try #require(String(data: serialized, encoding: .utf8))
    #expect(serializedText.contains("HTTP/1.1 202 Accepted"))
    #expect(SymphonyHTTPWire.statusText(for: 200) == "OK")
    #expect(SymphonyHTTPWire.statusText(for: 202) == "Accepted")
    #expect(SymphonyHTTPWire.statusText(for: 400) == "Bad Request")
    #expect(SymphonyHTTPWire.statusText(for: 404) == "Not Found")
    #expect(SymphonyHTTPWire.statusText(for: 405) == "Method Not Allowed")
    #expect(SymphonyHTTPWire.statusText(for: 500) == "Internal Server Error")
}

@Test func httpWireReturnsBadRequestForMalformedRequests() throws {
    let api = try makeTransportAPI()
    let malformedRequest = Data("GET_ONLY\r\n\r\n".utf8)
    let malformedResponse = try SymphonyHTTPWire.response(for: malformedRequest, api: api)
    let malformedText = try #require(String(data: malformedResponse, encoding: .utf8))
    #expect(malformedText.contains("HTTP/1.1 400 Bad Request"))
    #expect(malformedText.contains(#""code":"bad_request""#))

    let invalidUTF8 = Data([0xFF, 0xFE, 0xFD])
    let invalidUTF8Response = try SymphonyHTTPWire.response(for: invalidUTF8, api: api)
    let invalidUTF8Text = try #require(String(data: invalidUTF8Response, encoding: .utf8))
    #expect(invalidUTF8Text.contains("HTTP/1.1 400 Bad Request"))

    do {
        _ = try SymphonyHTTPWire.parseRequest(from: Data())
        Issue.record("Expected empty request bytes to fail parsing.")
    } catch let error as SymphonyRuntimeError {
        #expect(String(describing: error).contains("Missing HTTP request line"))
    }
}

@Test func httpServerRejectsInvalidPortsAndPortConflicts() throws {
    let api = try makeTransportAPI()

    do {
        _ = try SymphonyHTTPServer(port: 70_000, api: api)
        Issue.record("Expected invalid listener ports to throw.")
    } catch let error as SymphonyRuntimeError {
        #expect(String(describing: error).contains("Invalid listener port"))
    }

    let port = try availableLoopbackPort()
    let first = try SymphonyHTTPServer(port: port, api: api)
    try first.start()
    defer { first.stop() }

    let second = try SymphonyHTTPServer(port: port, api: api)
    do {
        try second.start()
        Issue.record("Expected conflicting listeners to fail.")
    } catch {
        #expect(String(describing: error).isEmpty == false)
    }
}

@Test func httpServerServesChunkedLoopbackRequests() throws {
    let api = try makeTransportAPI()
    let port = try availableLoopbackPort()
    let server = try SymphonyHTTPServer(port: port, api: api)
    try server.start()
    defer { server.stop() }

    let responseData = try sendRawHTTPRequest(
        port: port,
        chunks: [
            Data("GET /api/v1/health HTTP/1.1\r\nHost: localhost\r\n".utf8),
            Data("Accept: application/json\r\n\r\n".utf8),
        ],
        pauseBetweenChunks: .milliseconds(50)
    )
    let responseText = try #require(String(data: responseData, encoding: .utf8))

    #expect(responseText.contains("HTTP/1.1 200 OK"))
    #expect(responseText.contains(#""tracker_kind":"github""#))
}

@Test func httpServerCancelsIncompleteLoopbackRequestsWhenPeerCloses() throws {
    let api = try makeTransportAPI()
    let port = try availableLoopbackPort()
    let server = try SymphonyHTTPServer(port: port, api: api)
    try server.start()
    defer { server.stop() }

    try sendAndCloseRawHTTPRequest(
        port: port,
        chunks: [Data("GET /api/v1/health HTTP/1.1\r\nHost: localhost\r\n".utf8)]
    )

    let responseData = try sendRawHTTPRequest(
        port: port,
        chunks: [Data("GET /api/v1/health HTTP/1.1\r\nHost: localhost\r\n\r\n".utf8)]
    )
    let responseText = try #require(String(data: responseData, encoding: .utf8))
    #expect(responseText.contains("HTTP/1.1 200 OK"))
}

@Test func httpServerCancelsAcceptedConnectionsAfterServerRelease() throws {
    let api = try makeTransportAPI()
    let port = try availableLoopbackPort()
    var server: SymphonyHTTPServer? = try SymphonyHTTPServer(port: port, api: api)
    try #require(server).start()

    let connection = NWConnection(
        host: NWEndpoint.Host("127.0.0.1"),
        port: NWEndpoint.Port(rawValue: UInt16(port))!,
        using: .tcp
    )
    let queue = DispatchQueue(label: "dev.atjsh.symphony.http-server-tests.release")
    let ready = DispatchSemaphore(value: 0)
    let sent = DispatchSemaphore(value: 0)
    let completed = DispatchSemaphore(value: 0)
    let box = LoopbackResponseBox()
    let sendState = SendState()

    connection.stateUpdateHandler = { state in
        switch state {
        case .ready:
            ready.signal()
        case .failed(let error):
            box.stateError = error
            ready.signal()
            completed.signal()
        default:
            break
        }
    }
    connection.start(queue: queue)

    guard ready.wait(timeout: .now() + 3) == .success else {
        connection.cancel()
        throw POSIXError(.ETIMEDOUT)
    }
    if let stateError = box.stateError {
        connection.cancel()
        throw stateError
    }

    Thread.sleep(forTimeInterval: 0.1)

    let releasedServer = WeakReference(server)
    server = nil
    #expect(releasedServer.value == nil)

    connection.send(
        content: Data("GET /api/v1/health HTTP/1.1\r\nHost: localhost\r\n\r\n".utf8),
        completion: .contentProcessed { error in
            sendState.error = error
            sent.signal()
        }
    )
    guard sent.wait(timeout: .now() + 3) == .success else {
        connection.cancel()
        throw POSIXError(.ETIMEDOUT)
    }
    if let sendError = sendState.error {
        connection.cancel()
        throw sendError
    }

    connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, isComplete, error in
        box.append(data ?? Data())
        if let error {
            box.receiveError = error
        }
        if error != nil || isComplete || (data?.isEmpty ?? true) {
            completed.signal()
            return
        }
        completed.signal()
    }

    guard completed.wait(timeout: .now() + 3) == .success else {
        connection.cancel()
        throw POSIXError(.ETIMEDOUT)
    }
    connection.cancel()

    #expect(box.response.isEmpty)
}

@Test func httpReceiveActionCoversUnavailableErrorCompleteAndContinueBranches() throws {
    let requestTail = Data("Accept: application/json\r\n".utf8)
    let delimiter = Data("\r\n\r\n".utf8)
    let cannedResponse = Data("HTTP/1.1 200 OK\r\n\r\n".utf8)

    switch SymphonyHTTPServer.receiveAction(
        isServerAvailable: false,
        data: nil,
        isComplete: false,
        error: nil,
        accumulated: Data(),
        responder: { _ in cannedResponse }
    ) {
    case .cancel:
        break
    default:
        Issue.record("Expected unavailable server instances to cancel the connection.")
    }

    switch SymphonyHTTPServer.receiveAction(
        isServerAvailable: true,
        data: nil,
        isComplete: false,
        error: .posix(.ECONNRESET),
        accumulated: Data(),
        responder: { _ in cannedResponse }
    ) {
    case .cancel:
        break
    default:
        Issue.record("Expected network errors to cancel the connection.")
    }

    switch SymphonyHTTPServer.receiveAction(
        isServerAvailable: true,
        data: requestTail,
        isComplete: false,
        error: nil,
        accumulated: Data("GET /api/v1/health HTTP/1.1\r\nHost: localhost\r\n".utf8),
        responder: { _ in cannedResponse }
    ) {
    case .continueReceiving(let accumulated):
        #expect(String(decoding: accumulated, as: UTF8.self).contains("Accept: application/json"))
    default:
        Issue.record("Expected partial requests to keep accumulating bytes.")
    }

    switch SymphonyHTTPServer.receiveAction(
        isServerAvailable: true,
        data: delimiter,
        isComplete: false,
        error: nil,
        accumulated: Data("GET /api/v1/health HTTP/1.1\r\nHost: localhost\r\n".utf8),
        responder: { requestData in
            #expect(String(decoding: requestData, as: UTF8.self).contains("GET /api/v1/health"))
            return cannedResponse
        }
    ) {
    case .send(let response):
        #expect(response == cannedResponse)
    default:
        Issue.record("Expected complete requests to produce a response.")
    }

    switch SymphonyHTTPServer.receiveAction(
        isServerAvailable: true,
        data: requestTail,
        isComplete: true,
        error: nil,
        accumulated: Data("GET /api/v1/health HTTP/1.1\r\nHost: localhost\r\n".utf8),
        responder: { _ in cannedResponse }
    ) {
    case .cancel:
        break
    default:
        Issue.record("Expected incomplete but closed connections to cancel.")
    }

    var didCancel = false
    var sentResponse: Data?
    var continuedAccumulated: Data?
    SymphonyHTTPServer.applyReceiveAction(
        .cancel,
        cancel: { didCancel = true },
        send: { sentResponse = $0 },
        receive: { continuedAccumulated = $0 }
    )
    #expect(didCancel)
    #expect(sentResponse == nil)
    #expect(continuedAccumulated == nil)

    didCancel = false
    SymphonyHTTPServer.applyReceiveAction(
        .send(cannedResponse),
        cancel: { didCancel = true },
        send: { sentResponse = $0 },
        receive: { continuedAccumulated = $0 }
    )
    #expect(!didCancel)
    #expect(sentResponse == cannedResponse)
    #expect(continuedAccumulated == nil)

    sentResponse = nil
    continuedAccumulated = nil
    SymphonyHTTPServer.applyReceiveAction(
        .continueReceiving(Data("next".utf8)),
        cancel: { didCancel = true },
        send: { sentResponse = $0 },
        receive: { continuedAccumulated = $0 }
    )
    #expect(!didCancel)
    #expect(continuedAccumulated == Data("next".utf8))

    switch SymphonyHTTPServer.receiveAction(
        isServerAvailable: true,
        data: nil,
        isComplete: false,
        error: nil,
        accumulated: Data("GET /api/v1/health HTTP/1.1\r\nHost: localhost\r\n\r\n".utf8),
        responder: { requestData in
            #expect(String(decoding: requestData, as: UTF8.self).contains("Host: localhost"))
            return cannedResponse
        }
    ) {
    case .send(let response):
        #expect(response == cannedResponse)
    default:
        Issue.record("Expected already-complete accumulated requests to produce a response.")
    }
}

private func makeTransportAPI() throws -> SymphonyHTTPAPI {
    let databaseURL = try makeTransportTemporaryDirectory().appendingPathComponent("transport.sqlite3")
    let store = try SQLiteServerStateStore(databaseURL: databaseURL)
    return SymphonyHTTPAPI(
        store: store,
        version: "1.0.0",
        trackerKind: "github",
        now: { Date(timeIntervalSince1970: 1_711_281_600) },
        refresh: {}
    )
}

private func makeTransportTemporaryDirectory() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private func availableLoopbackPort() throws -> Int {
    let descriptor = socket(AF_INET, SOCK_STREAM, 0)
    guard descriptor >= 0 else {
        throw POSIXError(.EIO)
    }
    defer { close(descriptor) }

    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.stride)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = in_port_t(0).bigEndian
    address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

    let bindResult = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.stride))
        }
    }
    guard bindResult == 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }

    var length = socklen_t(MemoryLayout<sockaddr_in>.stride)
    let nameResult = withUnsafeMutablePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            getsockname(descriptor, $0, &length)
        }
    }
    guard nameResult == 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }

    return Int(UInt16(bigEndian: address.sin_port))
}

private func sendRawHTTPRequest(port: Int, chunks: [Data], pauseBetweenChunks: Duration? = nil) throws -> Data {
    let connection = NWConnection(
        host: NWEndpoint.Host("127.0.0.1"),
        port: NWEndpoint.Port(rawValue: UInt16(port))!,
        using: .tcp
    )
    let queue = DispatchQueue(label: "dev.atjsh.symphony.http-server-tests")

    let ready = DispatchSemaphore(value: 0)
    let completed = DispatchSemaphore(value: 0)
    let box = LoopbackResponseBox()

    connection.stateUpdateHandler = { state in
        switch state {
        case .ready:
            ready.signal()
        case .failed(let error):
            box.stateError = error
            ready.signal()
            completed.signal()
        default:
            break
        }
    }
    connection.start(queue: queue)

    guard ready.wait(timeout: .now() + 3) == .success else {
        connection.cancel()
        throw POSIXError(.ETIMEDOUT)
    }
    if let stateError = box.stateError {
        connection.cancel()
        throw stateError
    }

    for chunk in chunks {
        let sent = DispatchSemaphore(value: 0)
        let sendState = SendState()
        connection.send(content: chunk, completion: .contentProcessed { error in
            sendState.error = error
            sent.signal()
        })
        guard sent.wait(timeout: .now() + 3) == .success else {
            connection.cancel()
            throw POSIXError(.ETIMEDOUT)
        }
        if let sendError = sendState.error {
            connection.cancel()
            throw sendError
        }
        if let pauseBetweenChunks {
            Thread.sleep(forTimeInterval: pauseBetweenChunks.timeInterval)
        }
    }

    @Sendable func receiveNext() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, isComplete, error in
            box.append(data ?? Data())

            if let error {
                box.receiveError = error
                completed.signal()
                return
            }

            if isComplete {
                completed.signal()
                return
            }

            receiveNext()
        }
    }

    receiveNext()
    guard completed.wait(timeout: .now() + 3) == .success else {
        connection.cancel()
        throw POSIXError(.ETIMEDOUT)
    }
    connection.cancel()

    if let receiveError = box.receiveError {
        throw receiveError
    }
    return box.response
}

private func sendAndCloseRawHTTPRequest(port: Int, chunks: [Data]) throws {
    let connection = NWConnection(
        host: NWEndpoint.Host("127.0.0.1"),
        port: NWEndpoint.Port(rawValue: UInt16(port))!,
        using: .tcp
    )
    let queue = DispatchQueue(label: "dev.atjsh.symphony.http-server-tests.close")
    let ready = DispatchSemaphore(value: 0)
    let state = LoopbackCloseState()

    connection.stateUpdateHandler = { newState in
        switch newState {
        case .ready:
            ready.signal()
        case .failed(let error):
            state.error = error
            ready.signal()
        default:
            break
        }
    }
    connection.start(queue: queue)

    guard ready.wait(timeout: .now() + 3) == .success else {
        connection.cancel()
        throw POSIXError(.ETIMEDOUT)
    }
    if let error = state.error {
        connection.cancel()
        throw error
    }

    for chunk in chunks {
        let sent = DispatchSemaphore(value: 0)
        let sendState = SendState()
        connection.send(content: chunk, completion: .contentProcessed { error in
            sendState.error = error
            sent.signal()
        })
        guard sent.wait(timeout: .now() + 3) == .success else {
            connection.cancel()
            throw POSIXError(.ETIMEDOUT)
        }
        if let error = sendState.error {
            connection.cancel()
            throw error
        }
    }

    connection.cancel()
    Thread.sleep(forTimeInterval: 0.1)
}

private final class LoopbackResponseBox: @unchecked Sendable {
    private let lock = NSLock()
    var stateError: Error?
    var receiveError: Error?
    private(set) var response = Data()

    func append(_ data: Data) {
        lock.lock()
        response.append(data)
        lock.unlock()
    }
}

private final class SendState: @unchecked Sendable {
    var error: NWError?
}

private final class LoopbackCloseState: @unchecked Sendable {
    var error: NWError?
}

private final class WeakReference<Object: AnyObject>: @unchecked Sendable {
    weak var value: Object?

    init(_ value: Object?) {
        self.value = value
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let components = components
        return Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
