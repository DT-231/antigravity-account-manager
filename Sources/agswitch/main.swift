import Foundation
import AntigravitySwitcherCore

func printUsage() {
    print("Usage:")
    print("  agswitch doctor [--json]")
    print("  agswitch selftest [--json]")
    print("  agswitch profile list")
    print("  agswitch profile add --id ID --name NAME --path PATH [--dry-run]")
    print("  agswitch profile rename --id ID --name NAME [--dry-run]")
    print("  agswitch profile remove --id ID [--delete-data] [--yes] [--dry-run]")
    print("  agswitch switch --to ID [--dry-run]")
    print("  agswitch quota")
}

func displayNumber(_ value: Double?) -> String {
    guard let value else { return "unknown" }
    return String(value)
}

func value(after flag: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
    return arguments[index + 1]
}

func runQuotaCommand(_ semaphore: DispatchSemaphore) async {
    do {
        let quota = try await AntigravityQuotaService().fetchCurrentQuota()
        print("Antigravity detected")
        print("Account:")
        print("  Name: \(quota.name ?? "unknown")")
        print("  Email: \(quota.email ?? "unknown")")
        print("Plan:")
        print("  \(quota.planName ?? "unknown")")
        print("  Tier: \(quota.planTier ?? "unknown")")
        print("Credits:")
        print("  Monthly prompt: \(displayNumber(quota.monthlyPromptCredits))")
        print("  Monthly flow: \(displayNumber(quota.monthlyFlowCredits))")
        print("  Available prompt: \(displayNumber(quota.availablePromptCredits))")
        print("  Available flow: \(displayNumber(quota.availableFlowCredits))")
        print("Models:")
        for model in quota.models {
            let percent = model.remainingPercent.map { String(format: "%.1f%%", $0) } ?? "unknown"
            print("  \(model.label): \(percent)\(model.resetTime.map { " (reset \($0))" } ?? "")")
        }
        print("RPC:")
        print("  PID: \(quota.server.pid)")
        print("  Port: \(quota.server.rpcPort)")
        print("Fetched: \(quota.fetchedAt)")
    } catch {
        print("quota: \(String(describing: error))")
    }
    semaphore.signal()
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else {
    printUsage()
    exit(0)
}

do {
    switch command {
    case "doctor":
        let manifest = try ManifestLoader().loadDefault()
        let resolver = PathResolver()
        let appPath = resolver.firstExistingPath(from: manifest.app.pathCandidates)
        let ideVersion = resolver.shortVersion(at: appPath) ?? "unknown"
        let profileStore = ProfileStore()
        let stateStore = SwitchStateStore()
        let profiles = (try? profileStore.list()) ?? []
        let activeProfileID = try? stateStore.activeProfileID()
        let pendingTargetProfileID = try? stateStore.pendingSwitch()?.targetProfileID
        let report = Doctor().report(
            manifest: manifest,
            ideVersion: ideVersion,
            resolver: resolver,
            profiles: profiles,
            activeProfileID: activeProfileID ?? nil,
            pendingTargetProfileID: pendingTargetProfileID ?? nil
        )
        if arguments.contains("--json") {
            let data = try JSONEncoder().encode(report)
            print(String(decoding: data, as: UTF8.self))
        } else {
            print("adapter: \(report.adapterId)")
            print("strategy: \(report.strategy.rawValue)")
            print("app: \(report.appPath ?? "not found")")
            print("database: \(report.databasePath ?? "not found")")
            print("IDE version: \(report.ideVersion) (\(report.versionStatus.rawValue))")
            print("required identity keys: \(report.requiredIdentityKeyCount)")
            print("profiles: \(report.profiles.count)")
            if let active = report.activeProfileID { print("active profile: \(active)") }
            if let pending = report.pendingTargetProfileID { print("pending switch: \(pending)") }
        }
    case "selftest":
        let manifest = try ManifestLoader().loadDefault()
        let resolver = PathResolver()
        let appPath = resolver.firstExistingPath(from: manifest.app.pathCandidates)
        let ideVersion = resolver.shortVersion(at: appPath) ?? "unknown"
        let profileStore = ProfileStore()
        let stateStore = SwitchStateStore()
        let report = ProfileSelfTester().run(
            manifest: manifest,
            ideVersion: ideVersion,
            profiles: (try? profileStore.list()) ?? [],
            activeProfileID: try stateStore.activeProfileID(),
            pendingSwitch: try stateStore.pendingSwitch(),
            resolver: resolver
        )
        if arguments.contains("--json") {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(report)
            print(String(decoding: data, as: UTF8.self))
        } else {
            print(report.passed ? "selftest: passed" : "selftest: issues detected")
            for check in report.checks {
                let marker: String
                switch check.status {
                case .passed: marker = "PASS"
                case .warning: marker = "WARN"
                case .failed: marker = "FAIL"
                }
                print("[\(marker)] \(check.title): \(check.detail)")
            }
        }
    case "profile":
        let store = ProfileStore()
        switch arguments.dropFirst().first {
        case "list":
            for profile in try store.list() {
                print("\(profile.id)\t\(profile.name)\t\(profile.userDataDir)")
            }
        case "add":
            guard let id = value(after: "--id", in: arguments),
                  let name = value(after: "--name", in: arguments),
                  let path = value(after: "--path", in: arguments) else {
                throw ProfileStoreError.invalidProfile("profile add requires --id, --name and --path")
            }
            let profile = AccountProfile(id: id, name: name, userDataDir: path)
            if arguments.contains("--dry-run") {
                print("dry-run: would add profile \(id) -> \(path)")
            } else {
                try store.add(profile)
                print("added profile: \(id)")
            }
        case "rename":
            guard let id = value(after: "--id", in: arguments),
                  let name = value(after: "--name", in: arguments) else {
                throw ProfileStoreError.invalidProfile("profile rename requires --id and --name")
            }
            _ = try store.profile(id: id)
            if arguments.contains("--dry-run") {
                print("dry-run: would rename profile \(id) to \(name)")
            } else {
                try store.rename(id: id, name: name)
                print("renamed profile: \(id)")
            }
        case "remove":
            guard let index = arguments.firstIndex(of: "--id"), arguments.indices.contains(index + 1) else {
                throw ProfileStoreError.invalidProfile("profile remove requires --id")
            }
            let id = arguments[index + 1]
            let profile = try store.profile(id: id)
            let deleteData = arguments.contains("--delete-data")
            let state = SwitchStateStore()
            if try state.activeProfileID() == id {
                throw ProfileStoreError.activeProfile(id)
            }
            if arguments.contains("--dry-run") {
                if deleteData {
                    print("dry-run: would remove profile \(id) and move data at \(profile.userDataDir) to Trash")
                } else {
                    print("dry-run: would remove registry entry for profile \(id); directory would remain")
                }
            } else {
                if deleteData && !arguments.contains("--yes") {
                    throw ProfileStoreError.invalidProfile("--delete-data requires --yes; use --dry-run first")
                }
                if deleteData { try store.removeData(for: profile) }
                try store.remove(id: id)
                print(deleteData ? "removed profile and moved data to Trash: \(id)" : "removed profile registry entry: \(id)")
            }
        default:
            printUsage()
            exit(2)
        }
    case "switch":
        guard let toIndex = arguments.firstIndex(of: "--to"), arguments.indices.contains(toIndex + 1) else {
            throw ProfileStoreError.invalidProfile("switch requires --to ID")
        }
        let id = arguments[toIndex + 1]
        let profile = try ProfileStore().profile(id: id)
        let plan = try SwitchCoordinator.validatedPlan(for: profile)
        print("target: \(profile.id) (\(profile.name))")
        print("app: \(plan.appPath)")
        print("args: \(plan.arguments.joined(separator: " "))")
        if arguments.contains("--dry-run") {
            print("dry-run: no process started")
        } else {
            _ = try SwitchCoordinator.switchSynchronously(to: profile)
            print("switch: launched \(profile.id)")
        }
    case "quota":
        let semaphore = DispatchSemaphore(value: 0)
        print("quota: starting dynamic discovery")
        let task: Task<Void, Never> = Task.detached {
            await runQuotaCommand(semaphore)
        }
        _ = task
        semaphore.wait()
    default:
        printUsage()
        exit(2)
    }
} catch {
    fputs("agswitch: \(error.localizedDescription)\n", stderr)
    exit(1)
}
