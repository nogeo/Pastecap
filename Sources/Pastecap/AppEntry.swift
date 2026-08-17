import AppKit
import SwiftUI

@main
struct PastecapApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene { Settings { EmptyView() } }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var history = ClipboardStore()
    private var hotKeySettings = HotKeySettings()
    private var monitor: ClipboardMonitor!
    private var hotKeys: HotKeyManager!
    private var screenshot: ScreenshotController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let statusImage = NSImage(systemSymbolName: "clipboard.fill", accessibilityDescription: "Pastecap")
        statusImage?.isTemplate = true
        statusItem.button?.image = statusImage
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.toolTip = "Pastecap 剪贴板"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)

        monitor = ClipboardMonitor(store: history)
        monitor.start()
        screenshot = ScreenshotController(store: history)
        hotKeys = HotKeyManager(settings: hotKeySettings) { [weak self] action in
            if action == .history { self?.showPopover() } else { self?.startScreenshot() }
        }
        hotKeys.register()

        popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 420, height: 570)
        popover.contentViewController = NSHostingController(rootView: HistoryView(store: history, hotKeySettings: hotKeySettings, onScreenshot: { [weak self] in self?.startScreenshot() }))
    }

    @objc private func togglePopover() { popover.isShown ? popover.performClose(nil) : showPopover() }
    private func showPopover() {
        monitor.check()
        guard let button = statusItem.button else { return }
        if !popover.isShown { popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY) }
        NSApp.activate(ignoringOtherApps: true)
    }
    private func startScreenshot() {
        guard popover.isShown else {
            screenshot.start()
            return
        }
        popover.performClose(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.screenshot.start()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        history.flush()
    }
}
