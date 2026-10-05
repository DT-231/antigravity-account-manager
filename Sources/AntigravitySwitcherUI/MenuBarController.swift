import AppKit
import AntigravitySwitcherCore
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var managerWindow: NSWindow?
    private var modelObserver: AnyCancellable?
    private let profileStore = ProfileStore()
    private let switchState = SwitchStateStore()
    private lazy var switchCoordinator = SwitchCoordinator()
    private lazy var viewModel = ProfileViewModel(switchCoordinator: switchCoordinator)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if let brandIcon = AGAssets.brandIcon {
            NSApp.applicationIconImage = brandIcon
        }
        configureStatusItem()
        configurePopover()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(profileStateDidChange),
            name: .agProfilesDidChange,
            object: nil
        )
        modelObserver = viewModel.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateStatusItem() }
        }
        updateStatusItem()
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }

        // Ảnh menu bar nguồn là JPG có nền caro thật, không phải alpha.
        // Dùng template glyph sạch để macOS tự đổi màu theo menu bar sáng/tối.
        button.image = NSImage(
            systemSymbolName: "arrow.triangle.2.circlepath",
            accessibilityDescription: "Antigravity Switcher"
        )
        button.image?.isTemplate = true
        button.title = " AG"
        button.imagePosition = .imageLeading
        button.target = self
        button.action = #selector(togglePopover)
        button.sendAction(on: [.leftMouseUp])
        button.toolTip = "Mở Antigravity Switcher"
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 360, height: 500)
        popover.contentViewController = NSHostingController(
            rootView: MenuBarPopoverView(
                model: viewModel,
                onSwitch: { [weak self] profile in self?.requestSwitch(to: profile) },
                onOpenManager: { [weak self] in self?.openManager() },
                onQuit: { [weak self] in self?.quit() }
            )
        )
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            updateStatusItem()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    @objc private func profileStateDidChange() {
        updateStatusItem()
    }

    private func updateStatusItem() {
        let profiles = viewModel.profiles.isEmpty
            ? ((try? profileStore.list()) ?? [])
            : viewModel.profiles
        let activeID = viewModel.activeProfileID ?? (try? switchState.activeProfileID())
        guard let activeID,
              let active = profiles.first(where: { $0.id == activeID }) else {
            statusItem.button?.title = " AG"
            return
        }

        let name = compactStatusName(active.name, maximumWidth: 105)
        if let snapshot = viewModel.quotaSnapshot(for: activeID),
           let summary = quotaBadge(snapshot) {
            statusItem.button?.title = " \(name) · \(summary)"
        } else {
            statusItem.button?.title = " \(name)"
        }
    }

    private func quotaBadge(_ snapshot: AntigravityQuotaSnapshot) -> String? {
        let prompt = creditPercent(
            available: snapshot.availablePromptCredits,
            total: snapshot.monthlyPromptCredits
        )
        let flow = creditPercent(
            available: snapshot.availableFlowCredits,
            total: snapshot.monthlyFlowCredits
        )
        guard prompt != nil || flow != nil else { return nil }
        return "P:\(prompt.map(String.init) ?? "—")% F:\(flow.map(String.init) ?? "—")%"
    }

    private func creditPercent(available: Double?, total: Double?) -> Int? {
        guard let available, let total, total > 0 else { return nil }
        return Int(min(max(available / total * 100, 0), 100).rounded())
    }

    private func requestSwitch(to profile: AccountProfile) {
        guard !viewModel.isSwitching, profile.id != viewModel.activeProfileID else { return }
        let confirmation = NSAlert()
        confirmation.alertStyle = .warning
        confirmation.messageText = "Chuyển sang \(profile.name)?"
        confirmation.informativeText = "Antigravity IDE sẽ được đóng và mở lại. Hãy lưu mọi file đang chỉnh sửa trước khi tiếp tục."
        confirmation.addButton(withTitle: "Đã lưu · Chuyển profile")
        confirmation.addButton(withTitle: "Hủy")
        guard confirmation.runModal() == .alertFirstButtonReturn else { return }
        viewModel.switchTo(profile)
    }

    @objc private func openManager() {
        popover.performClose(nil)
        if let managerWindow {
            managerWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(rootView: StyledManagerView(model: viewModel))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Antigravity Switcher"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.delegate = self
        window.setContentSize(NSSize(width: 1080, height: 700))
        window.center()
        window.makeKeyAndOrderFront(nil)
        managerWindow = window
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow,
              closingWindow === managerWindow else { return }
        managerWindow = nil
    }

    private func compactStatusName(_ name: String, maximumWidth: CGFloat) -> String {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.menuBarFont(ofSize: 0)
        ]
        guard (name as NSString).size(withAttributes: attributes).width > maximumWidth else { return name }
        var value = name
        while value.count > 1,
              ((value + "…") as NSString).size(withAttributes: attributes).width > maximumWidth {
            value.removeLast()
        }
        return value + "…"
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
