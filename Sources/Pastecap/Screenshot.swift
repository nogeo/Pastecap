import AppKit
import CoreGraphics
import ScreenCaptureKit

// MARK: - Geometry

enum ScreenshotGeometry {
    static func displayRect(for selection: CGRect, screenFrame: CGRect, scale: CGFloat) -> CGRect {
        CGRect(
            x: (selection.minX - screenFrame.minX) * scale,
            y: (screenFrame.maxY - selection.maxY) * scale,
            width: selection.width * scale,
            height: selection.height * scale
        ).integral
    }

    static func toolbarFrame(selection: CGRect, visibleFrame: CGRect, size: NSSize) -> CGRect {
        let x = min(max(selection.maxX - size.width, visibleFrame.minX + 8), visibleFrame.maxX - size.width - 8)
        let yAbove = selection.maxY + 8
        let y = yAbove + size.height <= visibleFrame.maxY ? yAbove : max(visibleFrame.minY + 8, selection.minY - size.height - 8)
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    static func clampedSelection(_ rect: CGRect, in screenFrame: CGRect) -> CGRect {
        guard rect.width <= screenFrame.width, rect.height <= screenFrame.height else { return screenFrame }
        let x = min(max(rect.minX, screenFrame.minX), screenFrame.maxX - rect.width)
        let y = min(max(rect.minY, screenFrame.minY), screenFrame.maxY - rect.height)
        return CGRect(x: x, y: y, width: rect.width, height: rect.height)
    }

    static func selectionRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
    }
}

struct ScreenSnapshot {
    let displayID: CGDirectDisplayID
    let screenFrame: CGRect
    let image: CGImage
}

// MARK: - Permission

enum ScreenCaptureAuthorization {
    static var isGranted: Bool { CGPreflightScreenCaptureAccess() }

    static func shouldPrompt(afterCaptureFailure: Bool, granted: Bool) -> Bool {
        afterCaptureFailure && !granted
    }

    /// Registers the app in System Settings › Screen Recording and may show the system prompt.
    /// After this call the user only needs to turn the switch on.
    @discardableResult
    static func requestAccess() -> Bool {
        if isGranted { return true }
        return CGRequestScreenCaptureAccess()
    }

    static func openPrivacySettings() {
        let panes = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        ]
        for pane in panes {
            if let url = URL(string: pane), NSWorkspace.shared.open(url) { return }
        }
    }
}

// MARK: - Save destination

enum ScreenshotDestination {
    static func resolveSaveDirectory(defaults: UserDefaults = .standard) -> URL {
        let fallback = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Pictures", isDirectory: true)
            .appendingPathComponent("Pastecap", isDirectory: true)
        guard let stored = defaults.string(forKey: "saveDirectory"), !stored.isEmpty else { return fallback }
        let expanded = (stored as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/") else { return fallback }
        return URL(fileURLWithPath: expanded, isDirectory: true)
    }
}

// MARK: - Annotations

enum AnnotationTool: Int, CaseIterable {
    case rectangle, ellipse, arrow, pen, mosaic, text

    var symbolName: String {
        switch self {
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .arrow: return "arrow.up.right"
        case .pen: return "pencil"
        case .mosaic: return "square.grid.3x3.fill"
        case .text: return "textformat"
        }
    }

    var toolTip: String {
        switch self {
        case .rectangle: return "矩形"
        case .ellipse: return "椭圆"
        case .arrow: return "箭头"
        case .pen: return "画笔"
        case .mosaic: return "马赛克"
        case .text: return "文字"
        }
    }
}

enum AnnotationThickness: Int, CaseIterable {
    case thin, medium, thick

    var strokeWidth: CGFloat {
        switch self {
        case .thin: return 2
        case .medium: return 4
        case .thick: return 7
        }
    }

    var fontSize: CGFloat {
        switch self {
        case .thin: return 14
        case .medium: return 18
        case .thick: return 26
        }
    }

    var mosaicBlock: CGFloat {
        switch self {
        case .thin: return 10
        case .medium: return 18
        case .thick: return 30
        }
    }
}

struct AnnotationStyle {
    let color: NSColor
    let thickness: AnnotationThickness

    static let palette: [NSColor] = [.systemRed, .systemOrange, .systemYellow, .systemGreen, .systemBlue, .black, .white]
}

enum ScreenshotAnnotation {
    case stroke(NSBezierPath, AnnotationStyle)
    case rectangle(CGRect, AnnotationStyle)
    case ellipse(CGRect, AnnotationStyle)
    case arrow(CGPoint, CGPoint, AnnotationStyle)
    case text(String, CGPoint, AnnotationStyle)
    case mosaic(CGRect, CGFloat)
}

enum ScreenshotRenderer {
    static func arrowPath(from start: CGPoint, to end: CGPoint, strokeWidth: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        path.lineWidth = strokeWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: start)
        path.line(to: end)
        let angle = atan2(end.y - start.y, end.x - start.x)
        let length = max(10, strokeWidth * 3)
        for offset in [CGFloat.pi * 0.82, -CGFloat.pi * 0.82] {
            path.move(to: end)
            path.line(to: CGPoint(x: end.x + cos(angle + offset) * length, y: end.y + sin(angle + offset) * length))
        }
        return path
    }

    /// Draws one annotation translated by `offset`. `pixelated` maps a mosaic block
    /// size to a pixelated copy covering the same area as the snapshot the annotations
    /// were drawn on, so mosaics stay aligned.
    static func draw(_ annotation: ScreenshotAnnotation, offset: CGPoint, pixelated: (CGFloat) -> NSImage?) {
        switch annotation {
        case .stroke(let path, let style):
            style.color.setStroke()
            path.lineWidth = style.thickness.strokeWidth
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
        case .rectangle(let rect, let style):
            let path = NSBezierPath(rect: rect.offsetBy(dx: offset.x, dy: offset.y))
            path.lineWidth = style.thickness.strokeWidth
            path.lineJoinStyle = .round
            style.color.setStroke()
            path.stroke()
        case .ellipse(let rect, let style):
            let path = NSBezierPath(ovalIn: rect.offsetBy(dx: offset.x, dy: offset.y))
            path.lineWidth = style.thickness.strokeWidth
            style.color.setStroke()
            path.stroke()
        case .arrow(let start, let end, let style):
            style.color.setStroke()
            arrowPath(from: CGPoint(x: start.x + offset.x, y: start.y + offset.y),
                      to: CGPoint(x: end.x + offset.x, y: end.y + offset.y),
                      strokeWidth: style.thickness.strokeWidth).stroke()
        case .text(let text, let point, let style):
            text.draw(
                at: CGPoint(x: point.x + offset.x, y: point.y + offset.y),
                withAttributes: [
                    .font: NSFont.systemFont(ofSize: style.thickness.fontSize, weight: .semibold),
                    .foregroundColor: style.color
                ]
            )
        case .mosaic(let rect, let block):
            guard let pixelated = pixelated(block) else { return }
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: rect.offsetBy(dx: offset.x, dy: offset.y)).addClip()
            NSGraphicsContext.current?.imageInterpolation = .none
            pixelated.draw(in: CGRect(origin: offset, size: pixelated.size))
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    static func pixelate(_ image: NSImage, block: CGFloat = 18) -> NSImage {
        let pixelSize = NSSize(width: max(1, image.size.width / block), height: max(1, image.size.height / block))
        let small = NSImage(size: pixelSize)
        small.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .low
        image.draw(in: CGRect(origin: .zero, size: pixelSize))
        small.unlockFocus()

        let result = NSImage(size: image.size)
        result.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .none
        small.draw(in: CGRect(origin: .zero, size: image.size))
        result.unlockFocus()
        return result
    }

    static func render(snapshot: CGImage, viewSize: CGSize, selection: CGRect, annotations: [ScreenshotAnnotation]) -> NSImage? {
        let scale = CGFloat(snapshot.width) / max(viewSize.width, 1)
        let pixelRect = ScreenshotGeometry.displayRect(for: selection, screenFrame: CGRect(origin: .zero, size: viewSize), scale: scale)
        guard let crop = snapshot.cropping(to: pixelRect) else { return nil }

        // lockFocus 只产出 1x 位图，Retina 下会丢一半像素；这里按快照原生分辨率建位图
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: max(1, crop.width),
            pixelsHigh: max(1, crop.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        rep.size = selection.size
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }

        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = context
        let canvas = CGRect(origin: .zero, size: selection.size)
        NSImage(cgImage: crop, size: canvas.size).draw(in: canvas)
        if !annotations.isEmpty {
            let base = NSImage(cgImage: snapshot, size: viewSize)
            var pixelatedCache: [CGFloat: NSImage] = [:]
            let pixelated: (CGFloat) -> NSImage? = { block in
                if let cached = pixelatedCache[block] { return cached }
                let built = pixelate(base, block: block)
                pixelatedCache[block] = built
                return built
            }
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: canvas).addClip()
            let offset = CGPoint(x: -selection.minX, y: -selection.minY)
            annotations.forEach { draw($0, offset: offset, pixelated: pixelated) }
            NSGraphicsContext.restoreGraphicsState()
        }
        NSGraphicsContext.current = previous

        let image = NSImage(size: canvas.size)
        image.addRepresentation(rep)
        return image
    }
}

// MARK: - Controller

final class ScreenshotController: NSObject {
    private let store: ClipboardStore
    private var captureWindows: [CaptureWindow] = []
    private var escapeMonitor: Any?
    private var isPresentingDialog = false
    private var cursorIsPushed = false
    private var isPreparing = false
    private var snapshots: [CGDirectDisplayID: ScreenSnapshot] = [:]

    init(store: ClipboardStore) {
        self.store = store
        super.init()
    }

    func start() {
        guard captureWindows.isEmpty, !isPreparing, !isPresentingDialog else { return }
        if !ScreenCaptureAuthorization.isGranted {
            guard ScreenCaptureAuthorization.requestAccess() else {
                presentPermissionAlert()
                return
            }
        }
        isPreparing = true

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.prepareSelection()
            } catch {
                self.isPreparing = false
                self.finishSession()
                self.reportCaptureFailure(error)
            }
        }
    }

    private func reportCaptureFailure(_ error: Error) {
        if ScreenCaptureAuthorization.shouldPrompt(afterCaptureFailure: true, granted: ScreenCaptureAuthorization.isGranted) {
            presentPermissionAlert()
        } else {
            presentFailureAlert(error)
        }
    }

    private func presentPermissionAlert() {
        guard !isPresentingDialog else { return }
        isPresentingDialog = true
        defer { isPresentingDialog = false }

        ScreenCaptureAuthorization.requestAccess()

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "打开屏幕录制开关"
        alert.informativeText = "Pastecap 已出现在系统设置的屏幕录制列表中。\n\n请打开开关，然后重新打开 Pastecap。"
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "取消")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            ScreenCaptureAuthorization.openPrivacySettings()
        }
    }

    private func presentFailureAlert(_ error: Error) {
        guard !isPresentingDialog else { return }
        isPresentingDialog = true
        defer { isPresentingDialog = false }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "截图失败"
        alert.informativeText = "\(error.localizedDescription)\n\n如果问题持续存在，请重启 Pastecap 后重试。"
        alert.addButton(withTitle: "好")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @MainActor
    private func prepareSelection() async throws {
        let snapshots = try await captureVisibleScreens()
        guard !snapshots.isEmpty else { throw ScreenshotCaptureError.noDisplays }
        self.snapshots = snapshots
        isPreparing = false
        beginSelection()
    }

    private func beginSelection() {
        installEscapeMonitor()
        NSApp.activate(ignoringOtherApps: true)
        captureWindows = NSScreen.screens.compactMap { screen in
            guard let displayID = displayID(for: screen), let snapshot = snapshots[displayID] else { return nil }
            return CaptureWindow(screen: screen, snapshot: snapshot.image, controller: self)
        }
        guard !captureWindows.isEmpty else {
            snapshots.removeAll()
            finishSession()
            return
        }
        captureWindows.forEach { $0.orderFrontRegardless() }
        captureWindows.first?.makeKey()
        NSCursor.crosshair.push()
        cursorIsPushed = true
    }

    func complete(_ result: NSImage?) {
        if let result { store.addImage(result) }
        closeCaptureWindows()
        finishSession()
    }

    func cancel() {
        isPreparing = false
        snapshots.removeAll()
        closeCaptureWindows()
        finishSession()
    }

    private func closeCaptureWindows() {
        captureWindows.forEach { $0.orderOut(nil) }
        captureWindows.removeAll()
        if cursorIsPushed {
            NSCursor.pop()
            cursorIsPushed = false
        }
    }

    private func installEscapeMonitor() {
        guard escapeMonitor == nil else { return }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53, NSApp.modalWindow == nil else { return event }
            if let editor = NSApp.keyWindow?.firstResponder as? NSTextView, editor.isFieldEditor {
                return event
            }
            self?.cancel()
            return nil
        }
    }

    private func finishSession() {
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }
    }

    @MainActor
    private func captureVisibleScreens() async throws -> [CGDirectDisplayID: ScreenSnapshot] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        var result: [CGDirectDisplayID: ScreenSnapshot] = [:]

        for screen in NSScreen.screens {
            guard let displayID = displayID(for: screen),
                  let display = content.displays.first(where: { $0.displayID == displayID }) else { continue }

            let pixelSize = Self.nativePixelSize(of: screen, displayID: displayID)
            let configuration = SCStreamConfiguration()
            configuration.width = Int(pixelSize.width)
            configuration.height = Int(pixelSize.height)
            configuration.showsCursor = false
            configuration.captureResolution = .best
            configuration.ignoreShadowsDisplay = false
            configuration.shouldBeOpaque = true
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            result[displayID] = ScreenSnapshot(displayID: displayID, screenFrame: screen.frame, image: image)
        }
        return result
    }

    private func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(number.uint32Value)
    }

    private static func nativePixelSize(of screen: NSScreen, displayID: CGDirectDisplayID) -> CGSize {
        var candidates: [CGSize] = []
        if let mode = CGDisplayCopyDisplayMode(displayID) {
            candidates.append(CGSize(
                width: CGFloat(mode.pixelWidth),
                height: CGFloat(mode.pixelHeight)
            ))
        }
        candidates.append(CGSize(
            width: screen.frame.width * screen.backingScaleFactor,
            height: screen.frame.height * screen.backingScaleFactor
        ))
        candidates.append(CGSize(
            width: CGFloat(CGDisplayPixelsWide(displayID)),
            height: CGFloat(CGDisplayPixelsHigh(displayID))
        ))
        return candidates.max { $0.width * $0.height < $1.width * $1.height }
            ?? CGSize(width: CGFloat(CGDisplayPixelsWide(displayID)), height: CGFloat(CGDisplayPixelsHigh(displayID)))
    }

}

private enum ScreenshotCaptureError: LocalizedError {
    case noDisplays

    var errorDescription: String? {
        switch self {
        case .noDisplays: return "未找到可用的显示器"
        }
    }
}

// MARK: - Capture window

final class CaptureWindow: NSWindow {
    private weak var controller: ScreenshotController?

    init(screen: NSScreen, snapshot: CGImage, controller: ScreenshotController) {
        self.controller = controller
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        level = .screenSaver
        backgroundColor = .clear
        isOpaque = false
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = CaptureView(snapshot: snapshot, viewSize: screen.frame.size, controller: controller)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func becomeKey() {
        super.becomeKey()
        makeFirstResponder(contentView)
    }

    override func cancelOperation(_ sender: Any?) {
        controller?.cancel()
    }
}

// MARK: - Unified capture/annotate view (WeChat-style single overlay)

final class CaptureView: NSView {
    enum Phase { case idle, dragging, editing }
    enum Interaction { case none, newSelection, moveSelection, resize, annotate }
    enum Handle: Int { case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left }

    private weak var controller: ScreenshotController?
    private let snapshotCG: CGImage
    private let snapshot: NSImage
    private var phase: Phase = .idle
    private var interaction: Interaction = .none
    private var activeHandle: Handle?
    private var resizeStartRect = CGRect.zero
    private var dragStart = CGPoint.zero
    private var moveStartMouse = CGPoint.zero
    private var moveStartOrigin = CGPoint.zero
    private var selection = CGRect.zero
    private var annotations: [ScreenshotAnnotation] = []
    private var activeTool: AnnotationTool?
    private var currentAnnotation: ScreenshotAnnotation?
    private var annotateStart = CGPoint.zero
    private var lastMousePoint = CGPoint.zero
    private var pixelatedCache: [CGFloat: NSImage] = [:]
    private lazy var samplingRep: NSBitmapImageRep? = NSBitmapImageRep(cgImage: snapshotCG)
    private var toolButtons: [NSButton] = []
    private lazy var toolbar: NSView = makeToolbar()
    private var toolbarSize: NSSize {
        NSSize(width: 366, height: activeTool == nil ? 44 : 72)
    }
    private var strokeColorIndex: Int
    private var strokeColor: NSColor { AnnotationStyle.palette[strokeColorIndex] }
    private var thickness: AnnotationThickness
    private var currentStyle: AnnotationStyle { AnnotationStyle(color: strokeColor, thickness: thickness) }
    private var colorButtons: [NSButton] = []
    private var thicknessButtons: [NSButton] = []
    private weak var colorDivider: NSView?
    private lazy var optionsRow: NSView = makeOptionsRow()
    private var textField: NSTextField?
    private var textOrigin = CGPoint.zero

    init(snapshot: CGImage, viewSize: CGSize, controller: ScreenshotController) {
        self.snapshotCG = snapshot
        self.snapshot = NSImage(cgImage: snapshot, size: viewSize)
        self.controller = controller
        let defaults = UserDefaults.standard
        let colorIndex = defaults.integer(forKey: "annotationColorIndex")
        self.strokeColorIndex = min(max(colorIndex, 0), AnnotationStyle.palette.count - 1)
        if let raw = defaults.object(forKey: "annotationThickness") as? Int, let level = AnnotationThickness(rawValue: raw) {
            self.thickness = level
        } else {
            self.thickness = .medium
        }
        super.init(frame: CGRect(origin: .zero, size: viewSize))
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways], owner: self, userInfo: nil))
    }

    required init?(coder: NSCoder) { nil }
    override var acceptsFirstResponder: Bool { true }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if textField != nil { commitTextEditing() }
        if cancelRect.contains(point) {
            controller?.cancel()
            return
        }
        switch phase {
        case .idle, .dragging:
            beginNewSelection(at: point)
        case .editing:
            if let handle = hitHandle(point) {
                activeHandle = handle
                resizeStartRect = selection
                interaction = .resize
                updateCursor(point)
            } else if selection.contains(point), let tool = activeTool {
                beginAnnotation(tool: tool, at: point)
                updateCursor(point)
            } else if selection.contains(point) {
                interaction = .moveSelection
                moveStartMouse = NSEvent.mouseLocation
                moveStartOrigin = selection.origin
                NSCursor.closedHand.set()
            } else {
                beginNewSelection(at: point)
            }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        lastMousePoint = point
        switch interaction {
        case .newSelection:
            selection = ScreenshotGeometry.selectionRect(from: dragStart, to: point).intersection(bounds)
        case .moveSelection:
            let mouse = NSEvent.mouseLocation
            let origin = CGPoint(
                x: moveStartOrigin.x + mouse.x - moveStartMouse.x,
                y: moveStartOrigin.y + mouse.y - moveStartMouse.y
            )
            selection = ScreenshotGeometry.clampedSelection(CGRect(origin: origin, size: selection.size), in: bounds)
            updateToolbarFrame()
        case .resize:
            guard let activeHandle else { return }
            let clamped = CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX), y: min(max(point.y, bounds.minY), bounds.maxY))
            let resized = resizedSelection(from: resizeStartRect, handle: activeHandle, to: clamped).intersection(bounds)
            if !resized.isNull, resized.width >= 2, resized.height >= 2 { selection = resized }
            updateToolbarFrame()
        case .annotate:
            updateAnnotation(to: point)
        case .none:
            break
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        switch interaction {
        case .newSelection:
            if selection.width >= 2, selection.height >= 2 {
                phase = .editing
                showToolbar()
                window?.makeKey()
            } else {
                phase = .idle
                selection = .zero
            }
        case .annotate:
            if let annotation = currentAnnotation, isValid(annotation) {
                annotations.append(annotation)
            }
            currentAnnotation = nil
        default:
            break
        }
        interaction = .none
        activeHandle = nil
        needsDisplay = true
        updateCursor(point)
    }

    override func mouseMoved(with event: NSEvent) {
        lastMousePoint = convert(event.locationInWindow, from: nil)
        updateCursor(lastMousePoint)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: confirmCopy()
        case 53: controller?.cancel()
        default: super.keyDown(with: event)
        }
    }

    // MARK: Interaction helpers

    private func beginNewSelection(at point: CGPoint) {
        annotations.removeAll()
        currentAnnotation = nil
        selection = .zero
        hideToolbar()
        phase = .dragging
        interaction = .newSelection
        dragStart = point
        needsDisplay = true
    }

    private func beginAnnotation(tool: AnnotationTool, at point: CGPoint) {
        annotateStart = point
        switch tool {
        case .text:
            beginTextEditing(at: point)
        case .mosaic:
            currentAnnotation = .mosaic(.zero, thickness.mosaicBlock)
            interaction = .annotate
        case .pen:
            let path = NSBezierPath()
            path.move(to: point)
            currentAnnotation = .stroke(path, currentStyle)
            interaction = .annotate
        case .rectangle:
            currentAnnotation = .rectangle(.zero, currentStyle)
            interaction = .annotate
        case .ellipse:
            currentAnnotation = .ellipse(.zero, currentStyle)
            interaction = .annotate
        case .arrow:
            currentAnnotation = .arrow(point, point, currentStyle)
            interaction = .annotate
        }
    }

    private func updateAnnotation(to point: CGPoint) {
        switch currentAnnotation {
        case .stroke(let path, _):
            path.line(to: point)
        case .rectangle(_, let style):
            currentAnnotation = .rectangle(ScreenshotGeometry.selectionRect(from: annotateStart, to: point), style)
        case .ellipse(_, let style):
            currentAnnotation = .ellipse(ScreenshotGeometry.selectionRect(from: annotateStart, to: point), style)
        case .arrow(let start, _, let style):
            currentAnnotation = .arrow(start, point, style)
        case .mosaic(_, let block):
            currentAnnotation = .mosaic(ScreenshotGeometry.selectionRect(from: annotateStart, to: point), block)
        case .text, nil:
            break
        }
    }

    private func isValid(_ annotation: ScreenshotAnnotation) -> Bool {
        switch annotation {
        case .stroke(let path, _): return !path.isEmpty
        case .rectangle(let rect, _), .ellipse(let rect, _), .mosaic(let rect, _): return rect.width >= 2 && rect.height >= 2
        case .arrow(let start, let end, _): return hypot(end.x - start.x, end.y - start.y) >= 4
        case .text: return true
        }
    }

    private func resizedSelection(from start: CGRect, handle: Handle, to point: CGPoint) -> CGRect {
        let minX = min(point.x, start.maxX - 2)
        let minY = min(point.y, start.maxY - 2)
        let maxX = max(point.x, start.minX + 2)
        let maxY = max(point.y, start.minY + 2)
        switch handle {
        case .topLeft: return CGRect(x: minX, y: minY, width: start.maxX - minX, height: start.maxY - minY)
        case .top: return CGRect(x: start.minX, y: minY, width: start.width, height: start.maxY - minY)
        case .topRight: return CGRect(x: start.minX, y: minY, width: maxX - start.minX, height: start.maxY - minY)
        case .right: return CGRect(x: start.minX, y: start.minY, width: maxX - start.minX, height: start.height)
        case .bottomRight: return CGRect(x: start.minX, y: start.minY, width: maxX - start.minX, height: maxY - start.minY)
        case .bottom: return CGRect(x: start.minX, y: start.minY, width: start.width, height: maxY - start.minY)
        case .bottomLeft: return CGRect(x: minX, y: start.minY, width: start.maxX - minX, height: maxY - start.minY)
        case .left: return CGRect(x: minX, y: start.minY, width: start.maxX - minX, height: start.height)
        }
    }

    private var handlePoints: [(Handle, CGPoint)] {
        [
            (.topLeft, CGPoint(x: selection.minX, y: selection.maxY)),
            (.top, CGPoint(x: selection.midX, y: selection.maxY)),
            (.topRight, CGPoint(x: selection.maxX, y: selection.maxY)),
            (.right, CGPoint(x: selection.maxX, y: selection.midY)),
            (.bottomRight, CGPoint(x: selection.maxX, y: selection.minY)),
            (.bottom, CGPoint(x: selection.midX, y: selection.minY)),
            (.bottomLeft, CGPoint(x: selection.minX, y: selection.minY)),
            (.left, CGPoint(x: selection.minX, y: selection.midY))
        ]
    }

    private func hitHandle(_ point: CGPoint) -> Handle? {
        for (handle, center) in handlePoints where hypot(point.x - center.x, point.y - center.y) <= 10 {
            return handle
        }
        return nil
    }

    private func updateCursor(_ point: CGPoint) {
        switch phase {
        case .idle, .dragging:
            NSCursor.crosshair.set()
        case .editing:
            if let handle = hitHandle(point) {
                switch handle {
                case .top, .bottom: NSCursor.resizeUpDown.set()
                case .left, .right: NSCursor.resizeLeftRight.set()
                default: NSCursor.crosshair.set()
                }
            } else if selection.contains(point) {
                if activeTool == nil { NSCursor.openHand.set() } else { NSCursor.crosshair.set() }
            } else {
                NSCursor.crosshair.set()
            }
        }
    }

    // MARK: Completion

    private func confirmCopy() {
        guard phase == .editing, let result = renderedResult() else { return }
        let board = NSPasteboard.general
        board.clearContents()
        board.writeObjects([result])
        board.setData(Data(), forType: ClipboardStore.internalPasteboardType)
        controller?.complete(result)
    }

    private func confirmSave() {
        guard phase == .editing, let result = renderedResult(), save(result) else {
            NSSound.beep()
            return
        }
        controller?.complete(result)
    }

    private func renderedResult() -> NSImage? {
        ScreenshotRenderer.render(snapshot: snapshotCG, viewSize: bounds.size, selection: selection, annotations: annotations)
    }

    private func save(_ image: NSImage) -> Bool {
        let folder = ScreenshotDestination.resolveSaveDirectory()
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            guard let data = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: data),
                  let png = bitmap.representation(using: .png, properties: [:]) else { return false }
            try png.write(to: folder.appendingPathComponent("Screenshot-\(Int(Date().timeIntervalSince1970)).png"), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    // MARK: Inline text editing

    private func beginTextEditing(at point: CGPoint) {
        commitTextEditing()
        textOrigin = point
        let width = min(240, max(60, bounds.maxX - point.x - 8))
        let fieldHeight = thickness.fontSize + 10
        let field = NSTextField(frame: CGRect(x: point.x, y: point.y - 4, width: width, height: fieldHeight))
        field.font = NSFont.systemFont(ofSize: thickness.fontSize, weight: .semibold)
        field.textColor = strokeColor
        field.backgroundColor = NSColor.black.withAlphaComponent(0.35)
        field.drawsBackground = true
        field.isBordered = false
        field.focusRingType = .none
        field.placeholderString = "输入文字"
        field.target = self
        field.action = #selector(commitTextEditing)
        field.delegate = self
        addSubview(field)
        textField = field
        window?.makeFirstResponder(field)
    }

    @objc private func commitTextEditing() {
        guard let field = textField else { return }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        textField = nil
        field.removeFromSuperview()
        window?.makeFirstResponder(self)
        guard !text.isEmpty else { return }
        annotations.append(.text(text, textOrigin, currentStyle))
        needsDisplay = true
    }

    private func cancelTextEditing() {
        guard let field = textField else { return }
        textField = nil
        field.removeFromSuperview()
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    // MARK: Toolbar

    @objc private func toolbarAction(_ sender: NSButton) {
        switch sender.tag {
        case 0...5:
            let tool = AnnotationTool(rawValue: sender.tag) ?? .rectangle
            activeTool = activeTool == tool ? nil : tool
            refreshToolButtons()
            refreshAnnotationOptions()
            updateToolbarFrame()
        case 10:
            if !annotations.isEmpty { annotations.removeLast() }
            needsDisplay = true
        case 11:
            controller?.cancel()
        case 12:
            confirmSave()
        case 13:
            confirmCopy()
        default:
            break
        }
    }

    private func makeToolbar() -> NSView {
        let container = NSVisualEffectView()
        container.material = .popover
        container.blendingMode = .behindWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 8

        let symbols = [
            AnnotationTool.rectangle.symbolName,
            AnnotationTool.ellipse.symbolName,
            AnnotationTool.arrow.symbolName,
            AnnotationTool.pen.symbolName,
            AnnotationTool.mosaic.symbolName,
            AnnotationTool.text.symbolName,
            "arrow.uturn.backward",
            "xmark",
            "square.and.arrow.down",
            "checkmark.circle.fill"
        ]
        let tips = ["矩形", "椭圆", "箭头", "画笔", "马赛克", "文字", "撤销", "取消", "保存到文件", "复制并完成"]
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 3
        stack.edgeInsets = NSEdgeInsets(top: 5, left: 7, bottom: 5, right: 7)
        for (index, symbol) in symbols.enumerated() {
            let icon = NSImage(systemSymbolName: symbol, accessibilityDescription: tips[index]) ?? NSImage(size: NSSize(width: 16, height: 16))
            let button = NSButton(image: icon, target: self, action: #selector(toolbarAction(_:)))
            button.tag = index < 6 ? index : index + 4
            button.toolTip = tips[index]
            button.bezelStyle = .texturedRounded
            button.contentTintColor = index == 7 ? .systemRed : (index >= 8 ? .systemBlue : .labelColor)
            button.widthAnchor.constraint(equalToConstant: 32).isActive = true
            button.heightAnchor.constraint(equalToConstant: 32).isActive = true
            if index < 6 {
                button.setButtonType(.toggle)
                button.isBordered = false
                button.wantsLayer = true
                button.layer?.cornerRadius = 6
                toolButtons.append(button)
            } else {
                button.isBordered = false
            }
            stack.addArrangedSubview(button)
        }
        refreshToolButtons()
        stack.translatesAutoresizingMaskIntoConstraints = false
        optionsRow.isHidden = true
        let rows = NSStackView()
        rows.orientation = .vertical
        rows.spacing = 2
        rows.alignment = .centerX
        rows.addArrangedSubview(stack)
        rows.addArrangedSubview(optionsRow)
        container.addSubview(rows)
        rows.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            rows.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            rows.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            rows.topAnchor.constraint(equalTo: container.topAnchor),
            rows.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        refreshAnnotationOptions()
        return container
    }

    private func makeOptionsRow() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 6
        row.edgeInsets = NSEdgeInsets(top: 0, left: 7, bottom: 0, right: 7)

        let colorTips = ["红色", "橙色", "黄色", "绿色", "蓝色", "黑色", "白色"]
        for (index, _) in AnnotationStyle.palette.enumerated() {
            let button = NSButton(title: "", target: self, action: #selector(colorAction(_:)))
            button.tag = index
            button.toolTip = colorTips.indices.contains(index) ? colorTips[index] : "颜色"
            button.isBordered = false
            button.widthAnchor.constraint(equalToConstant: 26).isActive = true
            button.heightAnchor.constraint(equalToConstant: 26).isActive = true
            colorButtons.append(button)
            row.addArrangedSubview(button)
        }

        let divider = NSView()
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.15).cgColor
        divider.widthAnchor.constraint(equalToConstant: 1).isActive = true
        divider.heightAnchor.constraint(equalToConstant: 18).isActive = true
        colorDivider = divider
        row.addArrangedSubview(divider)

        let thicknessTips = ["细", "中", "粗"]
        for level in AnnotationThickness.allCases {
            let button = NSButton(title: "", target: self, action: #selector(thicknessAction(_:)))
            button.tag = level.rawValue
            button.toolTip = thicknessTips.indices.contains(level.rawValue) ? thicknessTips[level.rawValue] : "粗细"
            button.isBordered = false
            button.widthAnchor.constraint(equalToConstant: 26).isActive = true
            button.heightAnchor.constraint(equalToConstant: 26).isActive = true
            thicknessButtons.append(button)
            row.addArrangedSubview(button)
        }
        return row
    }

    @objc private func colorAction(_ sender: NSButton) {
        strokeColorIndex = min(max(sender.tag, 0), AnnotationStyle.palette.count - 1)
        UserDefaults.standard.set(strokeColorIndex, forKey: "annotationColorIndex")
        refreshAnnotationOptions()
        updateTextEditingStyle()
    }

    @objc private func thicknessAction(_ sender: NSButton) {
        guard let level = AnnotationThickness(rawValue: sender.tag) else { return }
        thickness = level
        UserDefaults.standard.set(level.rawValue, forKey: "annotationThickness")
        refreshAnnotationOptions()
        updateTextEditingStyle()
    }

    private func updateTextEditingStyle() {
        guard let field = textField else { return }
        field.textColor = strokeColor
        field.font = NSFont.systemFont(ofSize: thickness.fontSize, weight: .semibold)
    }

    private func refreshAnnotationOptions() {
        optionsRow.isHidden = activeTool == nil
        let showsColors = activeTool != .mosaic
        colorButtons.forEach { $0.isHidden = !showsColors }
        colorDivider?.isHidden = !showsColors
        for (index, button) in colorButtons.enumerated() {
            button.image = swatchImage(for: AnnotationStyle.palette[index], selected: index == strokeColorIndex)
        }
        for level in AnnotationThickness.allCases {
            guard level.rawValue < thicknessButtons.count else { continue }
            thicknessButtons[level.rawValue].image = thicknessImage(for: level, color: strokeColor, selected: level == thickness)
        }
    }

    private func selectionRingColor(for color: NSColor) -> NSColor {
        let brightness = color.usingColorSpace(.deviceRGB)?.brightnessComponent ?? 0
        return brightness > 0.7 ? NSColor.black.withAlphaComponent(0.6) : .white
    }

    private func swatchImage(for color: NSColor, selected: Bool) -> NSImage {
        let side: CGFloat = 26
        let image = NSImage(size: NSSize(width: side, height: side))
        image.lockFocus()
        let diameter: CGFloat = selected ? 20 : 16
        let dot = NSBezierPath(ovalIn: CGRect(x: (side - diameter) / 2, y: (side - diameter) / 2, width: diameter, height: diameter))
        color.setFill()
        NSColor.black.withAlphaComponent(0.18).setStroke()
        dot.lineWidth = 1
        dot.fill()
        dot.stroke()
        if selected {
            selectionRingColor(for: color).setStroke()
            let ring = NSBezierPath(ovalIn: CGRect(x: 1.5, y: 1.5, width: side - 3, height: side - 3))
            ring.lineWidth = 1.5
            ring.stroke()
        }
        image.unlockFocus()
        return image
    }

    private func thicknessImage(for level: AnnotationThickness, color: NSColor, selected: Bool) -> NSImage {
        let side: CGFloat = 26
        let image = NSImage(size: NSSize(width: side, height: side))
        image.lockFocus()
        let diameters: [CGFloat] = [6, 10, 16]
        let diameter = diameters[level.rawValue]
        let dot = NSBezierPath(ovalIn: CGRect(x: (side - diameter) / 2, y: (side - diameter) / 2, width: diameter, height: diameter))
        color.setFill()
        dot.fill()
        if selected {
            selectionRingColor(for: color).setStroke()
            let ring = NSBezierPath(ovalIn: CGRect(x: 1.5, y: 1.5, width: side - 3, height: side - 3))
            ring.lineWidth = 1.5
            ring.stroke()
        }
        image.unlockFocus()
        return image
    }

    private func refreshToolButtons() {
        for button in toolButtons {
            let isSelected = AnnotationTool(rawValue: button.tag) == activeTool
            button.state = isSelected ? .on : .off
            button.contentTintColor = isSelected ? .white : .labelColor
            button.layer?.backgroundColor = isSelected ? NSColor.controlAccentColor.cgColor : nil
        }
    }

    private func showToolbar() {
        if toolbar.superview == nil { addSubview(toolbar) }
        refreshAnnotationOptions()
        updateToolbarFrame()
    }

    private func hideToolbar() {
        toolbar.removeFromSuperview()
    }

    private func updateToolbarFrame() {
        guard toolbar.superview != nil else { return }
        toolbar.frame = ScreenshotGeometry.toolbarFrame(selection: selection, visibleFrame: bounds, size: toolbarSize)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        snapshot.draw(in: bounds, from: .zero, operation: .copy, fraction: 1)
        NSColor.black.withAlphaComponent(0.42).setFill()
        bounds.fill()

        if !selection.isNull, !selection.isEmpty {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: selection).addClip()
            snapshot.draw(in: bounds, from: .zero, operation: .copy, fraction: 1)
            annotations.forEach { ScreenshotRenderer.draw($0, offset: .zero, pixelated: { [weak self] block in
                self?.pixelatedImage(block: block)
            }) }
            if let currentAnnotation {
                ScreenshotRenderer.draw(currentAnnotation, offset: .zero, pixelated: { [weak self] block in
                    self?.pixelatedImage(block: block)
                })
            }
            NSGraphicsContext.restoreGraphicsState()

            NSColor.systemBlue.setStroke()
            let border = NSBezierPath(rect: selection)
            border.lineWidth = 1.5
            border.stroke()
            if phase == .editing { drawHandles() }
        }

        if interaction == .newSelection || interaction == .resize {
            drawSizeLabel()
            drawMagnifier(at: lastMousePoint)
        }
        if phase == .idle {
            drawHint("拖动选择截图区域 · 松开后可移动调整 · Esc 取消 · 回车完成")
        }
        drawCancelButton()
    }

    private func pixelatedImage(block: CGFloat) -> NSImage {
        if let cached = pixelatedCache[block] { return cached }
        let built = ScreenshotRenderer.pixelate(snapshot, block: block)
        pixelatedCache[block] = built
        return built
    }

    private func drawHandles() {
        for (_, center) in handlePoints {
            let dot = NSBezierPath(ovalIn: CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8))
            NSColor.white.setFill()
            dot.fill()
            NSColor.systemBlue.setStroke()
            dot.lineWidth = 1
            dot.stroke()
        }
    }

    private var cancelRect: CGRect {
        CGRect(x: bounds.maxX - 112, y: bounds.maxY - 42, width: 96, height: 28)
    }

    private func drawHint(_ text: String) {
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.white]
        let size = text.size(withAttributes: attributes)
        text.draw(at: CGPoint(x: (bounds.width - size.width) / 2, y: bounds.height / 2), withAttributes: attributes)
    }

    private func drawSizeLabel() {
        let text = "\(Int(selection.width)) × \(Int(selection.height))"
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white]
        let textSize = text.size(withAttributes: attributes)
        let labelY = max(4, selection.minY - textSize.height - 10)
        let labelRect = CGRect(x: selection.minX + 8, y: labelY, width: textSize.width + 14, height: textSize.height + 6)
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: labelRect, xRadius: 4, yRadius: 4).fill()
        text.draw(at: CGPoint(x: labelRect.minX + 7, y: labelRect.minY + 3), withAttributes: attributes)
    }

    private func drawMagnifier(at point: CGPoint) {
        let side: CGFloat = 116
        let zoom: CGFloat = 4
        let sourceSide = side / zoom
        var origin = CGPoint(x: point.x + 20, y: point.y + 20)
        if origin.x + side > bounds.maxX - 6 { origin.x = point.x - 20 - side }
        if origin.y + side + 26 > bounds.maxY - 6 { origin.y = point.y - 20 - side - 26 }
        let loupe = CGRect(origin: origin, size: CGSize(width: side, height: side))

        snapshot.draw(
            in: loupe,
            from: CGRect(x: point.x - sourceSide / 2, y: point.y - sourceSide / 2, width: sourceSide, height: sourceSide),
            operation: .copy,
            fraction: 1
        )
        NSColor.white.withAlphaComponent(0.85).setStroke()
        let border = NSBezierPath(roundedRect: loupe, xRadius: 8, yRadius: 8)
        border.lineWidth = 1.5
        border.stroke()

        NSColor.white.withAlphaComponent(0.7).setStroke()
        let cross = NSBezierPath()
        cross.move(to: CGPoint(x: loupe.midX, y: loupe.minY + 4))
        cross.line(to: CGPoint(x: loupe.midX, y: loupe.maxY - 4))
        cross.move(to: CGPoint(x: loupe.minX + 4, y: loupe.midY))
        cross.line(to: CGPoint(x: loupe.maxX - 4, y: loupe.midY))
        cross.lineWidth = 1
        cross.stroke()

        let label = "\(Int(selection.width)) × \(Int(selection.height))\(colorHex(at: point).map { "    \($0)" } ?? "")"
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.white]
        let textSize = label.size(withAttributes: attributes)
        let labelRect = CGRect(x: loupe.minX, y: loupe.minY - textSize.height - 10, width: textSize.width + 14, height: textSize.height + 6)
        NSColor.black.withAlphaComponent(0.8).setFill()
        NSBezierPath(roundedRect: labelRect, xRadius: 4, yRadius: 4).fill()
        label.draw(at: CGPoint(x: labelRect.minX + 7, y: labelRect.minY + 3), withAttributes: attributes)
    }

    private func colorHex(at point: CGPoint) -> String? {
        guard let samplingRep else { return nil }
        let scaleX = CGFloat(snapshotCG.width) / max(bounds.width, 1)
        let scaleY = CGFloat(snapshotCG.height) / max(bounds.height, 1)
        let x = min(max(Int(point.x * scaleX), 0), max(snapshotCG.width - 1, 0))
        let y = min(max(Int((bounds.height - point.y) * scaleY), 0), max(snapshotCG.height - 1, 0))
        guard let color = samplingRep.colorAt(x: x, y: y) else { return nil }
        return String(format: "#%02X%02X%02X", Int(color.redComponent * 255), Int(color.greenComponent * 255), Int(color.blueComponent * 255))
    }

    private func drawCancelButton() {
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: cancelRect, xRadius: 6, yRadius: 6).fill()
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.white]
        let title = "取消截图"
        let size = title.size(withAttributes: attributes)
        title.draw(at: CGPoint(x: cancelRect.midX - size.width / 2, y: cancelRect.midY - size.height / 2), withAttributes: attributes)
    }
}

extension CaptureView: NSTextFieldDelegate {
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(insertNewline(_:)):
            commitTextEditing()
            return true
        case #selector(cancelOperation(_:)):
            cancelTextEditing()
            return true
        default:
            return false
        }
    }
}
