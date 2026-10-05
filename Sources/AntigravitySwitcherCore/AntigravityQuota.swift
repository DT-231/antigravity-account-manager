import Foundation
import OSLog

public enum AntigravityDiscoveryError: LocalizedError, Equatable, Sendable {
    case antigravityNotRunning
    case languageServerNotFound
    case csrfTokenNotFound
    case noListeningPort
    case rpcPortNotFound
    case getUserStatusFailed
    case invalidResponse
    case commandFailed(String)

    public var errorDescription: String {
        switch self {
        case .antigravityNotRunning: return "Antigravity is not running"
        case .languageServerNotFound: return "Antigravity language server was not found"
        case .csrfTokenNotFound: return "Antigravity CSRF token was not found"
        case .noListeningPort: return "No localhost listening port was found"
        case .rpcPortNotFound: return "Antigravity RPC port was not found"
        case .getUserStatusFailed: return "Antigravity user status could not be read"
        case .invalidResponse: return "Antigravity returned an invalid response"
        case .commandFailed(let command): return "System command failed: \(command)"
        }
    }
}

public struct AntigravityLanguageServer: Equatable, Sendable {
    public let pid: Int
    public let csrfToken: String
    public let arguments: [String: String]
}

public struct AntigravityRuntimeServer: Equatable, Sendable {
    public let pid: Int
    public let rpcPort: Int
    public let csrfToken: String
}

public struct AntigravityModelQuota: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let model: String?
    public let remainingFraction: Double?
    public let resetTime: String?

    public var remainingPercent: Double? {
        remainingFraction.map { $0 * 100 }
    }
}

public struct AntigravityAccountQuota: Equatable, Sendable {
    public let name: String?
    public let email: String?
    public let planName: String?
    public let planTier: String?
    public let monthlyPromptCredits: Double?
    public let monthlyFlowCredits: Double?
    public let availablePromptCredits: Double?
    public let availableFlowCredits: Double?
    public let models: [AntigravityModelQuota]
    public let fetchedAt: Date
    public let server: AntigravityRuntimeServer
}

private struct LocalCommand {
    private final class OutputBox: @unchecked Sendable {
        var data = Data()
    }

    static func run(_ path: String, _ arguments: [String], timeout: TimeInterval = 5) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { throw AntigravityDiscoveryError.commandFailed(error.localizedDescription) }
        let readGroup = DispatchGroup()
        let outputBox = OutputBox()
        readGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            outputBox.data = output.fileHandleForReading.readDataToEndOfFile()
            readGroup.leave()
        }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            readGroup.wait()
            throw AntigravityDiscoveryError.commandFailed("\(path) timed out")
        }
        readGroup.wait()
        guard process.terminationStatus == 0 else {
            throw AntigravityDiscoveryError.commandFailed("\(path) exited with \(process.terminationStatus)")
        }
        return String(decoding: outputBox.data, as: UTF8.self)
    }
}

public struct AntigravityProcessDiscovery: Sendable {
    public init() {}

    public func findLanguageServers() throws -> [AntigravityLanguageServer] {
        let output = try LocalCommand.run("/bin/ps", ["-axo", "pid=,command="])
        quotaDiagnostic("ps returned \(output.split(whereSeparator: \.isNewline).count) line(s)")
        var result: [AntigravityLanguageServer] = []
        for line in output.split(whereSeparator: \ .isNewline) {
            let text = String(line).trimmingCharacters(in: .whitespaces)
            let parts = text.split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard parts.count == 2, let pid = Int(parts[0]),
                  parts[1].localizedCaseInsensitiveContains("language_server") else { continue }
            let args = Self.parseArguments(parts[1])
            guard let csrf = args["csrf_token"], !csrf.isEmpty else {
                quotaDiagnostic("language server PID \(pid) has no CSRF argument")
                continue
            }
            quotaDiagnostic("language server PID \(pid) detected")
            result.append(AntigravityLanguageServer(pid: pid, csrfToken: csrf, arguments: args))
        }
        if result.isEmpty { quotaDiagnostic("no language server with CSRF was parsed") }
        guard !result.isEmpty else { throw AntigravityDiscoveryError.languageServerNotFound }
        return result
    }

    public func listeningPorts(for pid: Int) throws -> [Int] {
        let output = try LocalCommand.run("/usr/sbin/lsof", ["-nP", "-a", "-p", String(pid), "-iTCP", "-sTCP:LISTEN"])
        let pattern = try! NSRegularExpression(pattern: "(?:127\\.0\\.0\\.1|localhost|\\*|\\[::1\\]):([0-9]+)")
        var ports = Set<Int>()
        for match in pattern.matches(in: output, range: NSRange(output.startIndex..., in: output)) {
            if let range = Range(match.range(at: 1), in: output), let port = Int(output[range]) { ports.insert(port) }
        }
        guard !ports.isEmpty else { throw AntigravityDiscoveryError.noListeningPort }
        return ports.sorted()
    }

    static func parseArguments(_ command: String) -> [String: String] {
        let tokens = command.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        var result: [String: String] = [:]
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            guard token.hasPrefix("--") else { index += 1; continue }
            let pair = token.dropFirst(2).split(separator: "=", maxSplits: 1).map(String.init)
            if pair.count == 2 { result[pair[0]] = pair[1] }
            else if index + 1 < tokens.count, !tokens[index + 1].hasPrefix("--") {
                result[pair[0]] = tokens[index + 1]; index += 1
            }
            index += 1
        }
        return result
    }
}

private func quotaDiagnostic(_ message: String) {
    Logger(subsystem: "com.antigravityswitcher", category: "quota")
        .debug("\(message, privacy: .public)")
#if DEBUG
    let line = "[antigravity] \(message)\n"
    FileHandle.standardError.write(Data(line.utf8))
#endif
}

private final class LocalhostTrustDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // The Antigravity language server uses an ephemeral self-signed TLS
        // certificate. Trust is relaxed only for loopback hosts; every other
        // challenge is rejected and no request is sent outside localhost.
        let host = challenge.protectionSpace.host
        guard (host == "127.0.0.1" || host == "localhost" || host == "::1"),
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.cancelAuthenticationChallenge, nil); return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}

private struct AntigravityRPCClient: Sendable {
    let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 10
        session = URLSession(configuration: configuration, delegate: LocalhostTrustDelegate(), delegateQueue: nil)
    }

    func post(port: Int, csrfToken: String, path: String, body: [String: Any]) async throws -> Any {
        guard let url = URL(string: "https://127.0.0.1:\(port)\(path)") else { throw AntigravityDiscoveryError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.setValue(csrfToken, forHTTPHeaderField: "X-Codeium-Csrf-Token")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response): (Data, URLResponse)
        do { (data, response) = try await session.data(for: request) }
        catch { throw AntigravityDiscoveryError.getUserStatusFailed }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AntigravityDiscoveryError.getUserStatusFailed
        }
        return try JSONSerialization.jsonObject(with: data)
    }
}

public enum AntigravityQuotaParser {
    public static func parse(_ response: Any, server: AntigravityRuntimeServer) throws -> AntigravityAccountQuota {
        guard let root = response as? [String: Any] else { throw AntigravityDiscoveryError.invalidResponse }
        let status = (root["userStatus"] as? [String: Any]) ?? root
        let planInfo = ((status["planStatus"] as? [String: Any])?["planInfo"] as? [String: Any]) ?? [:]
        let cascade = (status["cascadeModelConfigData"] as? [String: Any]) ?? [:]
        let configs = (cascade["clientModelConfigs"] as? [[String: Any]]) ?? []
        let models = configs.enumerated().map { index, config in
            let alias = config["modelOrAlias"] as? [String: Any]
            let quota = config["quotaInfo"] as? [String: Any]
            let id = string(config["modelId"]) ?? string(alias?["model"]) ?? "model-\(index)"
            return AntigravityModelQuota(id: id, label: string(config["label"]) ?? id,
                model: string(alias?["model"]), remainingFraction: number(quota?["remainingFraction"]),
                resetTime: string(quota?["resetTime"]))
        }
        return AntigravityAccountQuota(name: string(status["name"]), email: string(status["email"]),
            planName: string(planInfo["planName"]), planTier: string(planInfo["teamsTier"]),
            monthlyPromptCredits: number(planInfo["monthlyPromptCredits"]), monthlyFlowCredits: number(planInfo["monthlyFlowCredits"]),
            availablePromptCredits: number(status["availablePromptCredits"]), availableFlowCredits: number(status["availableFlowCredits"]),
            models: models, fetchedAt: Date(), server: server)
    }

    private static func string(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }
}

public actor AntigravityQuotaService {
    private let discovery: AntigravityProcessDiscovery
    private let client: AntigravityRPCClient
    private var cachedRuntimeServer: AntigravityRuntimeServer?

    public init() {
        discovery = AntigravityProcessDiscovery(); client = AntigravityRPCClient()
    }

    public func invalidateRuntimeServer() {
        cachedRuntimeServer = nil
    }

    public func discoverRuntimeServer() async throws -> AntigravityRuntimeServer {
        diagnostic("discovering language servers")
        let servers = try discovery.findLanguageServers()
        diagnostic("found \(servers.count) language server process(es)")
        for server in servers {
            guard let ports = try? discovery.listeningPorts(for: server.pid) else { continue }
            diagnostic("PID \(server.pid): \(ports.count) candidate port(s)")
            for port in ports {
                diagnostic("probing PID \(server.pid) port \(port)")
                if (try? await client.post(port: port, csrfToken: server.csrfToken,
                    path: "/exa.language_server_pb.LanguageServerService/GetUnleashData", body: [:])) != nil {
                    let runtime = AntigravityRuntimeServer(pid: server.pid, rpcPort: port, csrfToken: server.csrfToken)
                    cachedRuntimeServer = runtime
                    diagnostic("RPC port discovered: \(port)")
                    return runtime
                }
            }
        }
        diagnostic("no RPC port responded")
        throw AntigravityDiscoveryError.rpcPortNotFound
    }

    public func fetchCurrentQuota() async throws -> AntigravityAccountQuota {
        let body: [String: Any] = ["metadata": ["ideName": "antigravity", "extensionName": "antigravity", "ideVersion": "unknown", "locale": "en"]]
        if let cached = cachedRuntimeServer {
            do {
                let response = try await client.post(port: cached.rpcPort, csrfToken: cached.csrfToken,
                    path: "/exa.language_server_pb.LanguageServerService/GetUserStatus", body: body)
                return try AntigravityQuotaParser.parse(response, server: cached)
            } catch {
                diagnostic("cached runtime failed; rediscovering")
                cachedRuntimeServer = nil
            }
        }
        let runtime = try await discoverRuntimeServer()
        let response = try await client.post(port: runtime.rpcPort, csrfToken: runtime.csrfToken,
            path: "/exa.language_server_pb.LanguageServerService/GetUserStatus", body: body)
        diagnostic("GetUserStatus succeeded")
        return try AntigravityQuotaParser.parse(response, server: runtime)
    }

    /// Probes every live language server and prefers the session whose email
    /// matches the account being provisioned. If other authenticated sessions
    /// exist but none match, one is returned so the caller can show an explicit
    /// account-mismatch error instead of a generic discovery failure.
    public func fetchQuota(matchingEmail expectedEmail: String) async throws -> AntigravityAccountQuota {
        let expected = expectedEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let body: [String: Any] = ["metadata": [
            "ideName": "antigravity",
            "extensionName": "antigravity",
            "ideVersion": "unknown",
            "locale": "en"
        ]]
        cachedRuntimeServer = nil
        let servers = try discovery.findLanguageServers()
        var firstAuthenticatedSession: AntigravityAccountQuota?

        for server in servers {
            guard let ports = try? discovery.listeningPorts(for: server.pid) else { continue }
            for port in ports {
                guard (try? await client.post(
                    port: port,
                    csrfToken: server.csrfToken,
                    path: "/exa.language_server_pb.LanguageServerService/GetUnleashData",
                    body: [:]
                )) != nil else { continue }

                let runtime = AntigravityRuntimeServer(
                    pid: server.pid,
                    rpcPort: port,
                    csrfToken: server.csrfToken
                )
                guard let response = try? await client.post(
                    port: port,
                    csrfToken: server.csrfToken,
                    path: "/exa.language_server_pb.LanguageServerService/GetUserStatus",
                    body: body
                ), let quota = try? AntigravityQuotaParser.parse(response, server: runtime) else {
                    continue
                }

                if firstAuthenticatedSession == nil { firstAuthenticatedSession = quota }
                let actual = quota.email?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                if actual == expected {
                    cachedRuntimeServer = runtime
                    diagnostic("matching authenticated language server discovered")
                    return quota
                }
            }
        }

        if let firstAuthenticatedSession { return firstAuthenticatedSession }
        throw AntigravityDiscoveryError.getUserStatusFailed
    }

    private func diagnostic(_ message: String) {
        quotaDiagnostic(message)
    }
}
