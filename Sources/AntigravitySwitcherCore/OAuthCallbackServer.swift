import Foundation
import Network

public final class OAuthCallbackServer: @unchecked Sendable {
    private let listener: NWListener
    private let port: UInt16
    private let queue = DispatchQueue(label: "com.antigravityswitcher.oauth-callback")
    private let lock = NSLock()
    private var continuation: CheckedContinuation<OAuthCallback, Error>?
    private var timeoutWork: DispatchWorkItem?

    public init(port: UInt16 = 1455) throws {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else { throw OAuthError.callbackServerFailed("invalid port") }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: endpointPort)
        self.listener = try NWListener(using: parameters, on: endpointPort)
        self.port = port
    }

    public func waitForCallback(timeout: TimeInterval = 300) async throws -> OAuthCallback {
        OAuthDiagnostics.info("Callback listener started on configured loopback port")
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.start(queue: queue)
        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            self.continuation = continuation
            let work = DispatchWorkItem { [weak self] in self?.finish(.failure(OAuthError.timeout)) }
            timeoutWork = work
            lock.unlock()
            queue.asyncAfter(deadline: .now() + timeout, execute: work)
        }
    }

    public func cancel() { finish(.failure(OAuthError.cancelled)) }

    private func accept(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            if case .ready = state {
                guard let endpoint = connection.currentPath?.remoteEndpoint, Self.isLoopback(endpoint) else {
                    OAuthDiagnostics.error("Rejected non-loopback callback connection")
                    connection.cancel()
                    return
                }
                connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
                    self?.handle(data: data, connection: connection)
                }
            }
        }
        connection.start(queue: queue)
    }

    private static func isLoopback(_ endpoint: NWEndpoint) -> Bool {
        guard case let .hostPort(host, _) = endpoint else { return false }
        return host.debugDescription == "127.0.0.1" || host.debugDescription == "::1"
    }

    private func handle(data: Data?, connection: NWConnection) {
        guard let data, data.count <= 8192, let request = String(data: data, encoding: .utf8),
              let firstLine = request.components(separatedBy: "\r\n").first else {
            OAuthDiagnostics.error("Rejected malformed or oversized callback request")
            connection.cancel(); finish(.failure(OAuthError.callbackInvalid)); return
        }
        let parts = firstLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count == 3, let url = URL(string: "http://127.0.0.1\(parts[1])"),
              let host = request.split(separator: "\r\n").first(where: { $0.lowercased().hasPrefix("host:") })?.split(separator: ":", maxSplits: 1).last.map(String.init),
              request.components(separatedBy: "\r\n\r\n").dropFirst().joined().isEmpty else {
            OAuthDiagnostics.error("Rejected callback request: invalid method, host, path, or body")
            connection.cancel(); finish(.failure(OAuthError.callbackInvalid)); return
        }
        let path = url.path
        let query = url.query ?? ""
        do {
            let callback = try OAuthCallbackParser.parse(
                method: parts[0],
                host: host.trimmingCharacters(in: .whitespaces),
                path: path,
                query: query,
                expectedPort: port
            )
            let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nConnection: close\r\n\r\nYou may close this window."
            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
            finish(.success(callback))
        } catch {
            OAuthDiagnostics.error("Rejected invalid OAuth callback: \(error.localizedDescription)")
            connection.cancel(); finish(.failure(error))
        }
    }

    private func finish(_ result: Result<OAuthCallback, Error>) {
        lock.lock()
        guard let continuation else { lock.unlock(); return }
        self.continuation = nil
        timeoutWork?.cancel(); timeoutWork = nil
        lock.unlock()
        listener.cancel()
        continuation.resume(with: result)
    }
}
