import AppKit
import Carbon.HIToolbox
import Foundation

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

private var passed = 0

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw TestFailure(description: message) }
    passed += 1
}

private struct TestContext {
    let directory: URL
    let defaults: UserDefaults
    let suiteName: String

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("PastecapTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "PastecapTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName) ?? .standard
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
    }
}

private func testTextDeduplicationAndOrdering() throws {
    let context = try TestContext()
    defer { context.cleanup() }
    let store = ClipboardStore(directory: context.directory, defaults: context.defaults)
    store.addText("first")
    store.addText("second")
    store.addText("first")
    store.flush()
    try expect(store.items.map(\.text) == ["first", "second"], "text ordering or deduplication failed")
    try expect(Set(store.items.map(\.fingerprint)).count == 2, "text fingerprints are not stable")
}

private func testHistoryPersistence() throws {
    let context = try TestContext()
    defer { context.cleanup() }
    let firstStore = ClipboardStore(directory: context.directory, defaults: context.defaults)
    firstStore.addText("persistent")
    firstStore.flush()
    let fingerprint = firstStore.items[0].fingerprint
    let restoredStore = ClipboardStore(directory: context.directory, defaults: context.defaults)
    try expect(restoredStore.items.count == 1, "history did not survive restart")
    try expect(restoredStore.items[0].fingerprint == fingerprint, "fingerprint changed after restart")
    restoredStore.addText("persistent")
    restoredStore.flush()
    try expect(restoredStore.items.count == 1, "restored item did not deduplicate")
}

private func testLimitAndSettingsPersistence() throws {
    let context = try TestContext()
    defer { context.cleanup() }
    let store = ClipboardStore(directory: context.directory, defaults: context.defaults)
    store.maxItems = 20
    for index in 0..<25 { store.addText("item-\(index)") }
    store.flush()
    try expect(store.items.count == 20, "history limit did not trim")
    try expect(store.items.first?.text == "item-24", "history limit removed the wrong side")
    try expect(context.defaults.integer(forKey: "maxItems") == 20, "history limit did not persist")
}

private func testImagePersistenceAndDeduplication() throws {
    let context = try TestContext()
    defer { context.cleanup() }
    let store = ClipboardStore(directory: context.directory, defaults: context.defaults)
    let image = NSImage(size: NSSize(width: 8, height: 8))
    image.lockFocus()
    NSColor.systemRed.setFill()
    NSRect(x: 0, y: 0, width: 8, height: 8).fill()
    image.unlockFocus()
    store.addImage(image)
    store.addImage(image)
    store.flush()
    try expect(store.items.count == 1, "identical image was duplicated")
    try expect(store.image(for: store.items[0]) != nil, "stored image could not be loaded")
    try expect(store.thumbnail(for: store.items[0]) != nil, "thumbnail could not be generated")
    store.flush()
    try expect(ClipboardStore(directory: context.directory, defaults: context.defaults).items.count == 1, "image did not survive restart")
    try expect(store.cacheSizeBytes() > 0, "cache size did not include persisted files")
    store.clear()
    store.flush()
    try expect(store.items.isEmpty, "cache clear did not remove history")
    try expect(store.cacheSizeBytes() < 100, "cache clear did not remove image files")
}

private func testInternalCopySuppression() throws {
    let context = try TestContext()
    defer { context.cleanup() }
    let store = ClipboardStore(directory: context.directory, defaults: context.defaults)
    store.addText("internal")
    let board = NSPasteboard(name: NSPasteboard.Name("PastecapTests-\(UUID().uuidString)"))
    let monitor = ClipboardMonitor(store: store, pasteboard: board)
    store.copy(store.items[0], to: board)
    monitor.check()
    try expect(store.items.count == 1, "internal copy generated another history item")
    board.clearContents()
    board.setString("external", forType: .string)
    monitor.check()
    let observedItems = store.items.compactMap(\.text)
    let observedTypes = board.types?.map(\.rawValue) ?? []
    try expect(
        observedItems == ["external", "internal"],
        "external copy after internal copy was swallowed (items: \(observedItems), types: \(observedTypes))"
    )
}

private func testSensitivePasteboardIgnored() throws {
    let context = try TestContext()
    defer { context.cleanup() }
    let store = ClipboardStore(directory: context.directory, defaults: context.defaults)
    store.addText("keep")
    let board = NSPasteboard(name: NSPasteboard.Name("PastecapTests-\(UUID().uuidString)"))
    let monitor = ClipboardMonitor(store: store, pasteboard: board)

    board.clearContents()
    board.setString("secret", forType: .string)
    board.setData(Data(), forType: PasteboardPolicy.concealed)
    monitor.check()
    try expect(store.items.map(\.text) == ["keep"], "concealed pasteboard was recorded")

    board.clearContents()
    board.setString("temp", forType: .string)
    board.setData(Data(), forType: PasteboardPolicy.transient)
    monitor.check()
    try expect(store.items.map(\.text) == ["keep"], "transient pasteboard was recorded")

    board.clearContents()
    board.setString("ok", forType: .string)
    monitor.check()
    try expect(
        store.items.compactMap(\.text) == ["ok", "keep"],
        "normal paste after sensitive types was not recorded"
    )
}

private func testScreenshotGeometry() throws {
    let displayRect = ScreenshotGeometry.displayRect(
        for: CGRect(x: 100, y: 200, width: 300, height: 150),
        screenFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
        scale: 2
    )
    try expect(displayRect == CGRect(x: 200, y: 1534, width: 600, height: 300), "Retina display coordinate conversion is wrong")
    let visible = CGRect(x: 0, y: 0, width: 1000, height: 700)
    let size = NSSize(width: 354, height: 44)
    let normal = ScreenshotGeometry.toolbarFrame(selection: CGRect(x: 100, y: 100, width: 500, height: 300), visibleFrame: visible, size: size)
    try expect(normal.minY == 408, "toolbar was not placed above selection")
    let nearTop = ScreenshotGeometry.toolbarFrame(selection: CGRect(x: 100, y: 620, width: 500, height: 60), visibleFrame: visible, size: size)
    try expect(nearTop.minY == 568, "toolbar did not fall back below selection")
    try expect(nearTop.minX >= visible.minX + 8 && nearTop.maxX <= visible.maxX - 8, "toolbar escaped visible screen bounds")

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: 8,
        height: 8,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { throw TestFailure(description: "could not create crop test context") }
    context.setFillColor(NSColor.systemRed.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: 8, height: 4))
    context.setFillColor(NSColor.systemBlue.cgColor)
    context.fill(CGRect(x: 0, y: 4, width: 8, height: 4))
    guard let frozenScreen = context.makeImage() else { throw TestFailure(description: "could not create frozen screen") }
    let topHalf = ScreenshotGeometry.displayRect(
        for: CGRect(x: 0, y: 2, width: 4, height: 2),
        screenFrame: CGRect(x: 0, y: 0, width: 4, height: 4),
        scale: 2
    )
    try expect(topHalf == CGRect(x: 0, y: 0, width: 8, height: 4), "top-half selection mapped to the wrong snapshot pixels")
    try expect(frozenScreen.cropping(to: topHalf)?.height == 4, "frozen snapshot crop failed")
}

private func testSelectionClamping() throws {
    let screen = CGRect(x: 0, y: 0, width: 1000, height: 700)
    let size = CGSize(width: 200, height: 100)
    try expect(
        ScreenshotGeometry.clampedSelection(CGRect(x: -50, y: -20, width: size.width, height: size.height), in: screen)
            == CGRect(x: 0, y: 0, width: 200, height: 100),
        "selection was not clamped to the screen origin"
    )
    try expect(
        ScreenshotGeometry.clampedSelection(CGRect(x: 950, y: 680, width: size.width, height: size.height), in: screen)
            == CGRect(x: 800, y: 600, width: 200, height: 100),
        "selection was not clamped to the screen max edges"
    )
    try expect(
        ScreenshotGeometry.clampedSelection(CGRect(x: 300, y: 300, width: size.width, height: size.height), in: screen)
            == CGRect(x: 300, y: 300, width: 200, height: 100),
        "fully visible selection should not move"
    )
    try expect(
        ScreenshotGeometry.clampedSelection(CGRect(x: 300, y: 300, width: 1200, height: 800), in: screen) == screen,
        "oversized selection should become the whole screen"
    )
}

private func testScreenCaptureAuthorization() throws {
    try expect(
        !ScreenCaptureAuthorization.shouldPrompt(afterCaptureFailure: false, granted: false),
        "a successful screen capture must not prompt for permission"
    )
    try expect(
        ScreenCaptureAuthorization.shouldPrompt(afterCaptureFailure: true, granted: false),
        "a failed capture without permission should prompt for permission"
    )
    try expect(
        !ScreenCaptureAuthorization.shouldPrompt(afterCaptureFailure: true, granted: true),
        "a failed capture with permission must show a generic failure instead of the permission prompt"
    )
}

private func testSaveDirectoryResolution() throws {
    let context = try TestContext()
    defer { context.cleanup() }
    try expect(
        ScreenshotDestination.resolveSaveDirectory(defaults: context.defaults).path.hasSuffix("Pictures/Pastecap"),
        "unset save directory did not fall back to ~/Pictures/Pastecap"
    )
    context.defaults.set("~/Screenshots", forKey: "saveDirectory")
    try expect(
        ScreenshotDestination.resolveSaveDirectory(defaults: context.defaults).path == NSHomeDirectory() + "/Screenshots",
        "tilde in save directory was not expanded"
    )
    context.defaults.set("/tmp", forKey: "saveDirectory")
    try expect(
        ScreenshotDestination.resolveSaveDirectory(defaults: context.defaults).path == "/tmp",
        "absolute save directory was not honored"
    )
    context.defaults.set("relative/path", forKey: "saveDirectory")
    try expect(
        ScreenshotDestination.resolveSaveDirectory(defaults: context.defaults).path.hasSuffix("Pictures/Pastecap"),
        "relative save directory did not fall back"
    )
}

private func testHotKeySettings() throws {
    let context = try TestContext()
    defer { context.cleanup() }
    let settings = HotKeySettings(defaults: context.defaults)
    try expect(settings.history == .historyDefault, "history shortcut default is wrong")
    try expect(settings.screenshot == .screenshotDefault, "screenshot shortcut default is wrong")
    try expect(settings.history.displayName == "⇧⌘V", "history shortcut display is wrong")
    try expect(settings.screenshot.displayName == "⌥⌘A", "screenshot shortcut display is wrong")
    settings.history = HotKeyShortcut(keyCode: 8, modifiers: UInt32(controlKey | shiftKey))
    let restored = HotKeySettings(defaults: context.defaults)
    try expect(restored.history.displayName == "⌃⇧C", "custom shortcut did not persist")
    restored.reset()
    try expect(restored.history == .historyDefault && restored.screenshot == .screenshotDefault, "shortcut reset failed")
}

private func testAnnotationRendering() throws {
    _ = NSApplication.shared
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: 8,
        height: 8,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { throw TestFailure(description: "could not create render test context") }
    context.setFillColor(NSColor.systemBlue.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
    guard let snapshot = context.makeImage() else { throw TestFailure(description: "could not create render test snapshot") }

    let viewSize = CGSize(width: 8, height: 8)
    let selection = CGRect(x: 2, y: 2, width: 4, height: 4)
    let style = AnnotationStyle(color: .systemRed, thickness: .medium)
    let pen = NSBezierPath()
    pen.lineWidth = 2
    pen.move(to: CGPoint(x: 2, y: 2))
    pen.line(to: CGPoint(x: 6, y: 6))
    let annotations: [ScreenshotAnnotation] = [
        .stroke(pen, style),
        .rectangle(CGRect(x: 2, y: 2, width: 4, height: 4), style),
        .ellipse(CGRect(x: 2, y: 2, width: 4, height: 4), style),
        .arrow(CGPoint(x: 2, y: 2), CGPoint(x: 6, y: 6), style),
        .mosaic(CGRect(x: 2, y: 2, width: 4, height: 4), 18),
        .text("x", CGPoint(x: 3, y: 3), style)
    ]
    for subset in [annotations.dropLast(3), annotations.dropFirst(3), annotations[...]] {
        guard let rendered = ScreenshotRenderer.render(
            snapshot: snapshot,
            viewSize: viewSize,
            selection: selection,
            annotations: Array(subset)
        ) else { throw TestFailure(description: "annotation render failed for \(subset.count) annotations") }
        try expect(rendered.size == selection.size, "rendered size \(rendered.size) does not match selection \(selection.size)")
    }
    try expect(
        ScreenshotRenderer.render(snapshot: snapshot, viewSize: viewSize, selection: selection, annotations: []) != nil,
        "render without annotations failed"
    )

    func renderPen(_ style: AnnotationStyle, path: NSBezierPath) throws -> NSImage {
        guard let rendered = ScreenshotRenderer.render(
            snapshot: snapshot,
            viewSize: viewSize,
            selection: selection,
            annotations: [.stroke(path, style)]
        ) else { throw TestFailure(description: "pen render failed") }
        return rendered
    }
    func centerColor(of image: NSImage) throws -> NSColor {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else {
            throw TestFailure(description: "could not sample rendered pen stroke")
        }
        guard let color = rep.colorAt(x: 2, y: 2) else { throw TestFailure(description: "no color at pen stroke center") }
        return color
    }
    let red = try centerColor(of: renderPen(AnnotationStyle(color: .systemRed, thickness: .thick), path: pen))
    try expect(red.redComponent > 0.5 && red.blueComponent < 0.5, "pen stroke did not render in the configured color (got \(red))")
    let blue = try centerColor(of: renderPen(AnnotationStyle(color: .systemBlue, thickness: .thick), path: pen))
    try expect(blue.blueComponent > 0.5 && blue.redComponent < 0.5, "pen stroke did not render in the configured color (got \(blue))")

    let column = NSBezierPath()
    column.move(to: CGPoint(x: 4, y: 2))
    column.line(to: CGPoint(x: 4, y: 6))
    func inkCoverage(_ style: AnnotationStyle) throws -> Int {
        guard let tiff = try renderPen(style, path: column).tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else {
            throw TestFailure(description: "could not sample thickness render")
        }
        return (0..<4).reduce(0) { count, x in
            count + (0..<4).reduce(0) { row, y in
                row + ((rep.colorAt(x: x, y: y)?.redComponent ?? 0) > 0.5 ? 1 : 0)
            }
        }
    }
    let thickInk = try inkCoverage(AnnotationStyle(color: .systemRed, thickness: .thick))
    let thinInk = try inkCoverage(AnnotationStyle(color: .systemRed, thickness: .thin))
    try expect(thickInk > thinInk, "thickness setting did not change the rendered stroke width")
}

private func testSupportDirectoryName() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("PastecapSupport-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let directory = ClipboardStore.supportDirectory(in: root)
    try expect(directory.lastPathComponent == "Pastecap", "support directory is not named Pastecap")
}

do {
    try testTextDeduplicationAndOrdering()
    try testHistoryPersistence()
    try testLimitAndSettingsPersistence()
    try testImagePersistenceAndDeduplication()
    try testInternalCopySuppression()
    try testSensitivePasteboardIgnored()
    try testScreenshotGeometry()
    try testSelectionClamping()
    try testScreenCaptureAuthorization()
    try testSaveDirectoryResolution()
    try testHotKeySettings()
    try testAnnotationRendering()
    try testSupportDirectoryName()
    print("PASS: \(passed) assertions")
} catch {
    fputs("FAIL: \(error)\n", stderr)
    exit(1)
}
