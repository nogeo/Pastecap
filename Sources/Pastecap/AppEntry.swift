import AppKit
import SwiftUI

@main
struct PastecapApp {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.setActivationPolicy(.accessory)
        application.delegate = delegate
        // NSApplication 的 delegate 为弱引用，需覆盖整个事件循环的生命周期。
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    let history = ClipboardStore()
    let hotKeySettings = HotKeySettings()
    private var monitor: ClipboardMonitor!
    private var hotKeys: HotKeyManager!
    private var screenshot: ScreenshotController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installMainMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let statusImage = Self.makeStatusItemIcon()
        statusItem.button?.image = statusImage
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.toolTip = "Pastecap 剪贴板与截图"
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
        popover.contentSize = NSSize(width: 360, height: 480)
        popover.contentViewController = NSHostingController(rootView: HistoryView(
            store: history,
            hotKeySettings: hotKeySettings,
            onScreenshot: { [weak self] in self?.startScreenshot() },
            onCopied: { [weak self] in self?.closeAfterCopy() },
            onCancel: { [weak self] in self?.popover.performClose(nil) }
        ))
        installQuitMonitor()
    }

    /// LSUIElement 没有菜单栏，系统 ⌘Q 到不了 Quit；本地拦截后主动退出。
    private func installQuitMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard HistoryKeyboardNav.isQuitShortcut(event) else { return event }
            NSApp.terminate(nil)
            return nil
        }
    }

    private func installMainMenu() {
        let appName = "Pastecap"
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(
            title: "退出 \(appName)",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
        appItem.submenu = appMenu
        NSApp.mainMenu = mainMenu
    }

    /// 点击列表项复制后收起窗口，并把焦点还给之前的应用，方便直接 ⌘V 粘贴
    private func closeAfterCopy() {
        guard popover.isShown else { return }
        popover.performClose(nil)
        NSApp.deactivate()
    }

    /// 菜单栏应用没有常规窗口：拒绝系统在激活/启动时自动打开的窗口，
    /// 避免弹出空白的 Settings 窗口（如安装后从 Finder 打开时）。
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { false }
    func applicationShouldSaveSecureApplicationState(_ app: NSApplication) -> Bool { false }
    func applicationShouldRestoreSecureApplicationState(_ app: NSApplication) -> Bool { false }

    @objc private func togglePopover() { popover.isShown ? popover.performClose(nil) : showPopover() }
    private func showPopover() {
        guard let button = statusItem.button else { return }
        if !popover.isShown { popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY) }
        NSApp.activate(ignoringOtherApps: true)
        // Let the popover presentation run before requesting new pasteboard data.
        DispatchQueue.main.async { [weak self] in self?.monitor.check() }
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

    /// 矢量动态绘制 MenuBar 专用图标（18x18 Template 图标：层叠文档 + 右上角剪刀）
    private static func makeStatusItemIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let img = NSImage(size: size, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.setAllowsAntialiasing(true)
            context.setShouldAntialias(true)

            // 1. 底层文档 (Back Document - 偏移在左上方)
            let backPath = NSBezierPath(roundedRect: NSRect(x: 1.5, y: 4.5, width: 9.5, height: 12.0), xRadius: 1.5, yRadius: 1.5)
            backPath.lineWidth = 1.2
            NSColor.black.withAlphaComponent(0.65).setStroke()
            backPath.stroke()

            // 2. 表层主文档 (Front Document - 主体偏左下，留出右上空间给剪刀)
            let frontRect = NSRect(x: 4.0, y: 1.5, width: 10.0, height: 12.5)
            let frontPath = NSBezierPath(roundedRect: frontRect, xRadius: 1.8, yRadius: 1.8)

            // 清理底层重叠部分并描边
            context.saveGState()
            context.setBlendMode(.clear)
            frontPath.fill()
            context.restoreGState()

            frontPath.lineWidth = 1.3
            NSColor.black.setStroke()
            frontPath.stroke()

            // 表层文档内部文本短线 (2 条微细横线)
            let linePath = NSBezierPath()
            linePath.move(to: NSPoint(x: 6.5, y: 10.2))
            linePath.line(to: NSPoint(x: 11.5, y: 10.2))
            linePath.move(to: NSPoint(x: 6.5, y: 7.4))
            linePath.line(to: NSPoint(x: 10.0, y: 7.4))
            linePath.lineWidth = 1.1
            linePath.lineCapStyle = .round
            NSColor.black.withAlphaComponent(0.85).setStroke()
            linePath.stroke()

            // 3. 剪刀图标 (Scissors - 精致裁剪姿态位居右上角)
            context.saveGState()
            // 剪刀手柄两环 (双圆环)
            let upperLoop = NSBezierPath(ovalIn: NSRect(x: 13.8, y: 13.6, width: 3.2, height: 3.2))
            upperLoop.lineWidth = 1.1
            upperLoop.stroke()

            let lowerLoop = NSBezierPath(ovalIn: NSRect(x: 14.6, y: 8.8, width: 3.2, height: 3.2))
            lowerLoop.lineWidth = 1.1
            lowerLoop.stroke()

            // 交叉刀刃 (两条斜切线)
            let blades = NSBezierPath()
            // 刀刃 1：右上连到左下
            blades.move(to: NSPoint(x: 14.4, y: 14.2))
            blades.line(to: NSPoint(x: 9.8, y: 9.8))
            // 刀刃 2：右下连到左上
            blades.move(to: NSPoint(x: 15.0, y: 11.0))
            blades.line(to: NSPoint(x: 9.8, y: 13.8))
            blades.lineWidth = 1.15
            blades.lineCapStyle = .round
            blades.stroke()

            // 剪刀中心小转轴铆钉
            let pivot = NSBezierPath(ovalIn: NSRect(x: 12.2, y: 11.4, width: 1.6, height: 1.6))
            NSColor.black.setFill()
            pivot.fill()

            context.restoreGState()

            return true
        }
        img.isTemplate = true
        return img
    }
}
