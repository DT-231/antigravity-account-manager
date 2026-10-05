import AppKit
import Foundation

public enum ProcessControllerError: LocalizedError {
    case appNotRunning
    case quitTimedOut
    case launchFailed(String)
    case readinessTimedOut

    public var errorDescription: String {
        switch self {
        case .appNotRunning: return "Antigravity IDE is not running"
        case .quitTimedOut: return "Antigravity IDE did not quit before timeout"
        case .launchFailed(let message): return "Failed to launch Antigravity IDE: \(message)"
        case .readinessTimedOut: return "Antigravity IDE did not become ready before timeout"
        }
    }
}

private final class LaunchResult: @unchecked Sendable {
    private let lock = NSLock()
    private var storedError: Error?

    func set(error: Error?) {
        lock.lock()
        storedError = error
        lock.unlock()
    }

    func error() -> Error? {
        lock.lock()
        defer { lock.unlock() }
        return storedError
    }
}

public struct ProcessController: Sendable {
    public init() {}

    public func runningApplications(bundleId: String) -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == bundleId }
    }

    @MainActor
    public func activateRunning(bundleId: String) -> Bool {
        guard let application = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == bundleId
        }) else { return false }
        return application.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
    }

    @discardableResult
    public func quit(bundleId: String, timeout: TimeInterval, forceAfterTimeout: Bool = false) throws -> Bool {
        let applications = runningApplications(bundleId: bundleId)
        guard !applications.isEmpty else { return false }
        applications.forEach { _ = $0.terminate() }
        let deadline = Date().addingTimeInterval(timeout)
        while !runningApplications(bundleId: bundleId).isEmpty && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        guard !runningApplications(bundleId: bundleId).isEmpty else { return true }
        guard forceAfterTimeout else { throw ProcessControllerError.quitTimedOut }
        runningApplications(bundleId: bundleId).forEach { _ = $0.forceTerminate() }
        let forceDeadline = Date().addingTimeInterval(5)
        while !runningApplications(bundleId: bundleId).isEmpty && Date() < forceDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        guard runningApplications(bundleId: bundleId).isEmpty else { throw ProcessControllerError.quitTimedOut }
        return true
    }

    public func launch(appPath: String, arguments: [String]) throws {
        let appURL = URL(fileURLWithPath: appPath)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = arguments
        configuration.createsNewApplicationInstance = true
        let semaphore = DispatchSemaphore(value: 0)
        let result = LaunchResult()
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
            result.set(error: error)
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 30)
        if let launchError = result.error() { throw ProcessControllerError.launchFailed(launchError.localizedDescription) }
    }

    public func waitUntilRunning(bundleId: String, timeout: TimeInterval) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while runningApplications(bundleId: bundleId).isEmpty && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        guard !runningApplications(bundleId: bundleId).isEmpty else {
            throw ProcessControllerError.readinessTimedOut
        }
    }

    @discardableResult
    public func quitAsync(
        bundleId: String,
        timeout: TimeInterval,
        forceAfterTimeout: Bool = false
    ) async throws -> Bool {
        let found = await MainActor.run {
            let applications = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == bundleId }
            applications.forEach { _ = $0.terminate() }
            return !applications.isEmpty
        }
        guard found else { return false }

        let deadline = Date().addingTimeInterval(timeout)
        while await isRunningAsync(bundleId: bundleId), Date() < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        guard await isRunningAsync(bundleId: bundleId) else { return true }
        guard forceAfterTimeout else { throw ProcessControllerError.quitTimedOut }

        await MainActor.run {
            NSWorkspace.shared.runningApplications
                .filter { $0.bundleIdentifier == bundleId }
                .forEach { _ = $0.forceTerminate() }
        }
        let forceDeadline = Date().addingTimeInterval(5)
        while await isRunningAsync(bundleId: bundleId), Date() < forceDeadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        guard !(await isRunningAsync(bundleId: bundleId)) else { throw ProcessControllerError.quitTimedOut }
        return true
    }

    @MainActor
    public func launchAsync(appPath: String, arguments: [String]) async throws {
        let appURL = URL(fileURLWithPath: appPath)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.arguments = arguments
            configuration.createsNewApplicationInstance = true
            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
                if let error {
                    continuation.resume(throwing: ProcessControllerError.launchFailed(error.localizedDescription))
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    public func waitUntilRunningAsync(bundleId: String, timeout: TimeInterval) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !(await isRunningAsync(bundleId: bundleId)), Date() < deadline {
            try await Task.sleep(for: .milliseconds(200))
        }
        guard await isRunningAsync(bundleId: bundleId) else {
            throw ProcessControllerError.readinessTimedOut
        }
    }

    private func isRunningAsync(bundleId: String) async -> Bool {
        await MainActor.run {
            NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleId }
        }
    }
}
