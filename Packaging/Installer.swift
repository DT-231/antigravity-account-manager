import AppKit
import Foundation

private let installedBundleIdentifier = "com.antigravityswitcher.local"
private let applicationName = "Antigravity Switcher.app"

@MainActor
final class InstallerDelegate: NSObject, NSApplicationDelegate {
    // A tiny offscreen window is required as the key window so that macOS does
    // not auto-create a blank visible window when activation policy is .regular.
    private var backdropWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let w = NSWindow(
            contentRect: NSRect(x: -1000, y: -1000, width: 1, height: 1),
            styleMask: [],
            backing: .buffered,
            defer: false
        )
        w.isReleasedWhenClosed = false
        w.makeKeyAndOrderFront(nil)
        backdropWindow = w

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        do {
            let sourceURL = Bundle.main.bundleURL
                .deletingLastPathComponent()
                .appendingPathComponent(applicationName, isDirectory: true)
            let targetURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
                .appendingPathComponent(applicationName, isDirectory: true)

            guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                showError(
                    title: "Không thể cài đặt",
                    message: "Không tìm thấy Antigravity Switcher.app bên cạnh trình cài đặt. Hãy giải nén toàn bộ ZIP rồi thử lại."
                )
                return
            }

            guard NSRunningApplication.runningApplications(
                withBundleIdentifier: installedBundleIdentifier
            ).isEmpty else {
                showError(
                    title: "Antigravity Switcher đang chạy",
                    message: "Hãy chọn Thoát trong menu bar của Antigravity Switcher, sau đó chạy lại trình cài đặt."
                )
                return
            }

            if sourceURL.standardizedFileURL == targetURL.standardizedFileURL {
                openAndFinish(targetURL)
                return
            }

            let targetExists = FileManager.default.fileExists(atPath: targetURL.path)
            if targetExists, !confirmReplacement() {
                NSApp.terminate(nil)
                return
            }

            try install(sourceURL: sourceURL, targetURL: targetURL, replacing: targetExists)
            openAndFinish(targetURL)
        } catch {
            showError(
                title: "Cài đặt thất bại",
                message: "Không thể chép ứng dụng vào thư mục Applications. Bạn có thể kéo Antigravity Switcher.app vào Applications bằng Finder rồi chọn Thay thế."
            )
        }
    }

    private func confirmReplacement() -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Thay thế Antigravity Switcher?"
        alert.informativeText = "Đã có ứng dụng trong Applications. Phiên bản cũ sẽ được chuyển vào Thùng rác; profile và dữ liệu tài khoản được giữ nguyên."
        alert.addButton(withTitle: "Thay thế")
        alert.addButton(withTitle: "Hủy")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func install(sourceURL: URL, targetURL: URL, replacing: Bool) throws {
        let fileManager = FileManager.default
        var trashedURL: NSURL?

        if replacing {
            try fileManager.trashItem(at: targetURL, resultingItemURL: &trashedURL)
        }

        do {
            try fileManager.copyItem(at: sourceURL, to: targetURL)
        } catch {
            if let trashedURL = trashedURL as URL?,
               !fileManager.fileExists(atPath: targetURL.path) {
                try? fileManager.moveItem(at: trashedURL, to: targetURL)
            }
            throw error
        }
    }

    private func openAndFinish(_ applicationURL: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(
            at: applicationURL,
            configuration: configuration
        ) { _, error in
            Task { @MainActor in
                if error != nil {
                    self.showError(
                        title: "Đã cài đặt nhưng chưa thể mở",
                        message: "Ứng dụng đã nằm trong Applications. Hãy nhấp phải Antigravity Switcher và chọn Open."
                    )
                } else {
                    NSApp.terminate(nil)
                }
            }
        }
    }

    private func showError(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
        NSApp.terminate(nil)
    }
}

@main
struct InstallerMain {
    @MainActor
    static func main() {
        let delegate = InstallerDelegate()
        let application = NSApplication.shared
        application.delegate = delegate
        application.run()
        withExtendedLifetime(delegate) {}
    }
}
