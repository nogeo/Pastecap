import AppKit
import CryptoKit
import Foundation
import ImageIO
import ObjectiveC
import UniformTypeIdentifiers

enum ClipboardKind: String, Codable { case text, image }
struct ClipboardItem: Identifiable, Codable, Equatable {
    let id: UUID
    let kind: ClipboardKind
    let text: String?
    let fileName: String?
    let displayName: String?
    let createdAt: Date
    let fingerprint: String
    let byteCount: Int64?

    var listTitle: String {
        if kind == .image {
            let size = byteCount.map(Self.compactByteCount)
            let name = displayName ?? fileName
            switch (size, name) {
            case let (size?, name?): return "图片（\(size) \(name)）"
            case let (size?, nil): return "图片（\(size)）"
            case let (nil, name?): return "图片（\(name)）"
            default: return "图片"
            }
        }
        return text ?? ""
    }

    static func compactByteCount(_ bytes: Int64) -> String {
        if bytes < 1024 { return "\(bytes)B" }
        let units = ["K", "M", "G", "T"]
        var value = Double(bytes)
        var unit = "B"
        for next in units {
            guard value >= 1024 else { break }
            value /= 1024
            unit = next
        }
        if value < 10 {
            var text = String(format: "%.1f", value)
            if text.hasSuffix(".0") { text.removeLast(2) }
            return text + unit
        }
        return "\(Int(value.rounded()))" + unit
    }

    private static let presentationCache: NSCache<NSUUID, ClipboardTextPresentation> = {
        let cache = NSCache<NSUUID, ClipboardTextPresentation>()
        cache.countLimit = 1000
        cache.totalCostLimit = 16 * 1024 * 1024
        return cache
    }()

    private var presentation: ClipboardTextPresentation {
        let key = id as NSUUID
        if let cached = Self.presentationCache.object(forKey: key), cached.sourceText == text { return cached }
        let value = ClipboardTextPresentation(text: text)
        Self.presentationCache.setObject(value, forKey: key, cost: text?.utf8.count ?? 0)
        return value
    }

    var isURL: Bool { presentation.isURL }
    var hexColor: NSColor? { presentation.hexColor }
    var isMultiline: Bool { presentation.isMultiline }
    var lineCount: Int { presentation.lineCount }
    var characterCount: Int { presentation.characterCount }
    var previewSnippet: String { presentation.previewSnippet }

    private static let yesterdayFormatter = makeDateFormatter("昨天 HH:mm")
    private static let dateFormatter = makeDateFormatter("MM-dd HH:mm")

    private static func makeDateFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        formatter.timeZone = .autoupdatingCurrent
        return formatter
    }

    var relativeTimeString: String {
        let now = Date()
        let diff = now.timeIntervalSince(createdAt)
        if diff < 60 { return "刚刚" }
        if diff < 3600 { return "\(Int(diff / 60))分钟前" }
        if diff < 86400 { return "\(Int(diff / 3600))小时前" }
        if Calendar.current.isDateInYesterday(createdAt) {
            return Self.yesterdayFormatter.string(from: createdAt)
        }
        return Self.dateFormatter.string(from: createdAt)
    }
}

/// Immutable display metadata is reused across selection, hover, and list updates.
private final class ClipboardTextPresentation {
    let sourceText: String?
    let isURL: Bool
    let hexColor: NSColor?
    let isMultiline: Bool
    let lineCount: Int
    let characterCount: Int
    let previewSnippet: String
    init(text: String?) {
        sourceText = text
        let source = ClipboardTextSource(text: text)
        isURL = source.isURL
        hexColor = source.hexColor
        isMultiline = source.isMultiline
        lineCount = source.lineCount
        characterCount = source.characterCount
        previewSnippet = source.previewSnippet
    }
}

private struct ClipboardTextSource {
    let text: String?
    var isURL: Bool {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return false }
        guard text.hasPrefix("http://") || text.hasPrefix("https://") else { return false }
        return URL(string: text)?.host != nil
    }

    var hexColor: NSColor? {
        guard let raw = text?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        var str = raw
        if str.hasPrefix("#") { str.removeFirst() }
        let len = str.count
        guard len == 3 || len == 6 || len == 8 else { return nil }
        guard let intVal = UInt64(str, radix: 16) else { return nil }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        if len == 3 {
            r = CGFloat((intVal >> 8) & 0xF) / 15.0
            g = CGFloat((intVal >> 4) & 0xF) / 15.0
            b = CGFloat(intVal & 0xF) / 15.0
        } else if len == 6 {
            r = CGFloat((intVal >> 16) & 0xFF) / 255.0
            g = CGFloat((intVal >> 8) & 0xFF) / 255.0
            b = CGFloat(intVal & 0xFF) / 255.0
        } else if len == 8 {
            r = CGFloat((intVal >> 24) & 0xFF) / 255.0
            g = CGFloat((intVal >> 16) & 0xFF) / 255.0
            b = CGFloat((intVal >> 8) & 0xFF) / 255.0
            a = CGFloat(intVal & 0xFF) / 255.0
        }
        return NSColor(calibratedRed: r, green: g, blue: b, alpha: a)
    }

    var isMultiline: Bool {
        guard let text else { return false }
        return text.contains("\n") || text.contains("\r")
    }

    var lineCount: Int {
        guard let text else { return 0 }
        let lines = text.split(whereSeparator: \.isNewline)
        return max(1, lines.count)
    }

    var characterCount: Int {
        text?.count ?? 0
    }

    var previewSnippet: String {
        guard let text else { return "" }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = trimmed.prefix(500)
        return prefix.endIndex < trimmed.endIndex ? String(prefix) + "…" : String(prefix)
    }

}

enum PasteboardPolicy {
    static let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    static let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    static let autoGenerated = NSPasteboard.PasteboardType("org.nspasteboard.AutoGeneratedType")
    static let onePassword = NSPasteboard.PasteboardType("com.agilebits.onepassword")

    static func shouldIgnore(_ board: NSPasteboard) -> Bool {
        let types = Set(board.types ?? [])
        return types.contains(concealed)
            || types.contains(transient)
            || types.contains(autoGenerated)
            || types.contains(onePassword)
    }
}

/// 截图和剪贴板图片统一写成 PNG：不透明图去掉无用 Alpha，直接走 ImageIO，避免 TIFF 中转。
enum ImagePNG {
    enum AlphaPolicy {
        /// 全不透明则去掉 Alpha；有透明像素则保留。
        case stripIfOpaque
        /// 屏幕截图本身不透明，跳过逐像素扫描。
        case stripAlways
    }

    static func data(from image: NSImage, alpha: AlphaPolicy = .stripIfOpaque) -> Data? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return data(from: cgImage, alpha: alpha)
    }

    static func data(from image: CGImage, alpha: AlphaPolicy = .stripIfOpaque) -> Data? {
        encode(prepared(image, alpha: alpha))
    }

    /// 立刻在剪贴板上声明 PNG，压缩放到后台。返回的闭包与这次编码共用同一份数据。
    @discardableResult
    static func copy(_ image: NSImage, to board: NSPasteboard, alpha: AlphaPolicy = .stripIfOpaque) -> () -> Data? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return { nil } }
        let source = Source(image: cgImage, alpha: alpha)
        let item = NSPasteboardItem()
        item.setDataProvider(source, forTypes: [.png])
        board.writeObjects([item])
        source.startEncoding()
        return { source.data() }
    }

    private static func encode(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    private static func prepared(_ image: CGImage, alpha: AlphaPolicy) -> CGImage {
        switch image.alphaInfo {
        case .none, .noneSkipLast, .noneSkipFirst:
            return image
        default:
            break
        }
        switch alpha {
        case .stripAlways:
            return flattenRGB(image) ?? image
        case .stripIfOpaque:
            return opaqueRGBIfPossible(image)
        }
    }

    private static func flattenRGB(_ image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height
        guard let context = rgbContext(width: width, height: height, space: colorSpace(for: image), alpha: .noneSkipLast) else { return nil }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    private static func opaqueRGBIfPossible(_ image: CGImage) -> CGImage {
        let width = image.width
        let height = image.height
        let space = colorSpace(for: image)
        guard let context = rgbContext(width: width, height: height, space: space, alpha: .premultipliedLast) else { return image }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let pixels = context.data else { return context.makeImage() ?? image }

        let bytesPerRow = context.bytesPerRow
        let pointer = pixels.bindMemory(to: UInt8.self, capacity: bytesPerRow * height)
        var opaque = true
        rowLoop: for y in 0..<height {
            let row = pointer + y * bytesPerRow
            for x in 0..<width where row[x * 4 + 3] != 255 {
                opaque = false
                break rowLoop
            }
        }
        guard opaque else { return context.makeImage() ?? image }

        let copy = Data(bytes: pixels, count: bytesPerRow * height)
        guard let provider = CGDataProvider(data: copy as CFData) else { return context.makeImage() ?? image }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) ?? image
    }

    private static func colorSpace(for image: CGImage) -> CGColorSpace {
        image.colorSpace.flatMap { $0.numberOfComponents >= 3 ? $0 : nil }
            ?? CGColorSpace(name: CGColorSpace.sRGB)
            ?? CGColorSpaceCreateDeviceRGB()
    }

    private static func rgbContext(width: Int, height: Int, space: CGColorSpace, alpha: CGImageAlphaInfo) -> CGContext? {
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: alpha.rawValue
        )
    }

    private final class Source: NSObject, NSPasteboardItemDataProvider {
        private let image: CGImage
        private let alpha: AlphaPolicy
        private let queue = DispatchQueue(label: "com.wwm.Pastecap.png-encode", qos: .userInitiated)
        private var cached: Data?

        init(image: CGImage, alpha: AlphaPolicy) {
            self.image = image
            self.alpha = alpha
        }

        func startEncoding() {
            queue.async { [weak self] in
                _ = self?.encodeIfNeeded()
            }
        }

        func data() -> Data? {
            queue.sync { encodeIfNeeded() }
        }

        private func encodeIfNeeded() -> Data? {
            if let cached { return cached }
            let encoded = ImagePNG.data(from: image, alpha: alpha)
            cached = encoded
            return encoded
        }

        func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
            guard type == .png, let png = data() else { return }
            item.setData(png, forType: .png)
        }
    }
}

final class ClipboardStore: ObservableObject {
    static let internalPasteboardType = NSPasteboard.PasteboardType("com.wwm.Pastecap.internal-copy")
    @Published private(set) var items: [ClipboardItem] = []
    @Published var maxItems: Int {
        didSet {
            defaults.set(maxItems, forKey: "maxItems")
            trim()
            scheduleSave()
        }
    }
    private let directory: URL
    private let indexURL: URL
    private let defaults: UserDefaults
    private let ioQueue = DispatchQueue(label: "com.wwm.Pastecap.store-io", qos: .utility)
    private let saveQueue = DispatchQueue(label: "com.wwm.Pastecap.history-save", qos: .utility)
    private var saveWorkItem: DispatchWorkItem?
    private var pendingImageOps = 0
    private let thumbnailQueue = DispatchQueue(label: "com.wwm.Pastecap.thumbnails", qos: .userInitiated)
    private let thumbnailCache = NSCache<NSString, NSImage>()
    private var thumbnailKeys: [String: Set<String>] = [:]

    static func supportDirectory(
        in base: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    ) -> URL {
        base.appendingPathComponent("Pastecap", isDirectory: true)
    }

    init(directory customDirectory: URL? = nil, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let base = customDirectory ?? Self.supportDirectory()
        directory = base
        indexURL = directory.appendingPathComponent("history.json")
        let savedLimit = defaults.integer(forKey: "maxItems")
        maxItems = savedLimit > 0 ? savedLimit : 20
        thumbnailCache.countLimit = 80
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var originalItems: [ClipboardItem] = []
        if let data = try? Data(contentsOf: indexURL),
           let decoded = try? JSONDecoder().decode([ClipboardItem].self, from: data) {
            originalItems = decoded
            var fingerprints = Set<String>()
            items = decoded.compactMap(migratedItem).filter { fingerprints.insert($0.fingerprint).inserted }
        }
        trim()
        if items != originalItems { scheduleSave() }
    }

    deinit {
        let hasPendingSave = saveWorkItem != nil
        saveWorkItem?.cancel()
        let snapshot = items
        let destination = indexURL
        saveQueue.sync {
            if hasPendingSave { Self.writeHistory(snapshot, to: destination) }
        }
    }

    func addText(_ value: String) {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        add(ClipboardItem(id: UUID(), kind: .text, text: value, fileName: nil, displayName: nil, createdAt: Date(), fingerprint: fingerprint(prefix: "text", data: Data(value.utf8)), byteCount: nil))
    }

    func addImage(_ image: NSImage, preferredName: String? = nil) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        addPNG({ ImagePNG.data(from: cgImage) }, preferredName: preferredName)
    }

    func addPNG(_ provider: @escaping () -> Data?, preferredName: String? = nil) {
        pendingImageOps += 1
        ioQueue.async { [weak self] in
            guard let self else { return }
            guard let png = provider() else {
                DispatchQueue.main.async { self.finishImageOp() }
                return
            }
            let fingerprint = self.fingerprint(prefix: "image", data: png)
            DispatchQueue.main.async {
                if self.items.contains(where: { $0.fingerprint == fingerprint }) {
                    self.finishImageOp()
                    return
                }
                let name = "\(UUID().uuidString).png"
                let shownName = Self.imageDisplayName(preferredName)
                let url = self.directory.appendingPathComponent(name)
                self.ioQueue.async {
                    try? png.write(to: url, options: .atomic)
                    DispatchQueue.main.async {
                        if self.items.contains(where: { $0.fingerprint == fingerprint }) {
                            try? FileManager.default.removeItem(at: url)
                            self.finishImageOp()
                            return
                        }
                        self.finishImageOp {
                            self.add(ClipboardItem(
                                id: UUID(),
                                kind: .image,
                                text: nil,
                                fileName: name,
                                displayName: shownName,
                                createdAt: Date(),
                                fingerprint: fingerprint,
                                byteCount: Int64(png.count)
                            ))
                        }
                    }
                }
            }
        }
    }

    func image(for item: ClipboardItem) -> NSImage? {
        guard let name = item.fileName else { return nil }
        return NSImage(contentsOf: directory.appendingPathComponent(name))
    }

    /// Keep file reads and image decoding off the UI thread, including the first display.
    @MainActor
    func thumbnail(for item: ClipboardItem, size: CGSize = CGSize(width: 54, height: 44), scale: CGFloat = 2) async -> NSImage? {
        guard item.kind == .image, let name = item.fileName,
              size.width > 0, size.height > 0, scale > 0,
              !Task.isCancelled else { return nil }
        let key = "\(name)-\(size.width)x\(size.height)@\(scale)" as NSString
        if let cached = thumbnailCache.object(forKey: key) { return cached }
        let url = directory.appendingPathComponent(name)
        let maxPixels = max(1, Int(ceil(max(size.width, size.height) * scale)))
        let decoded: CGImage? = await withCheckedContinuation { continuation in
            thumbnailQueue.async {
                let image = autoreleasepool {
                    Self.makeThumbnail(at: url, maxPixels: maxPixels)
                }
                continuation.resume(returning: image)
            }
        }
        // A row may have disappeared or been deleted while decoding was in flight.
        guard !Task.isCancelled, items.contains(where: { $0.id == item.id }),
              let decoded else { return nil }
        if let cached = thumbnailCache.object(forKey: key) { return cached }
        let thumb = NSImage(cgImage: decoded, size: NSSize(
            width: CGFloat(decoded.width) / scale, height: CGFloat(decoded.height) / scale
        ))
        thumbnailCache.setObject(thumb, forKey: key)
        thumbnailKeys[name, default: []].insert(key as String)
        return thumb
    }

    func copy(_ item: ClipboardItem, to board: NSPasteboard = .general) {
        board.clearContents()
        if item.kind == .text, let text = item.text {
            board.setString(text, forType: .string)
        }
        if item.kind == .image, let name = item.fileName,
           let png = try? Data(contentsOf: directory.appendingPathComponent(name)) {
            let pasteItem = NSPasteboardItem()
            pasteItem.setData(png, forType: .png)
            board.writeObjects([pasteItem])
        }
        board.setData(Data(), forType: Self.internalPasteboardType)
    }

    func remove(_ item: ClipboardItem) {
        items.removeAll { $0.id == item.id }
        invalidateThumbnail(for: item)
        deleteFile(item)
        scheduleSave()
    }

    func clear() {
        items.forEach {
            invalidateThumbnail(for: $0)
            deleteFile($0)
        }
        items.removeAll()
        thumbnailCache.removeAllObjects()
        thumbnailKeys.removeAll()
        scheduleSave()
    }

    func cacheSizeBytes() -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else { return 0 }
        return enumerator.compactMap { $0 as? URL }.reduce(0) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return total + Int64(size)
        }
    }

    /// Waits for in-flight image encodes and writes history to disk immediately.
    func flush(timeout: TimeInterval = 5) {
        let deadline = Date().addingTimeInterval(timeout)
        while pendingImageOps > 0, Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        saveNow()
        saveQueue.sync {}
    }

    private func finishImageOp(_ body: () -> Void = {}) {
        body()
        pendingImageOps = max(0, pendingImageOps - 1)
    }

    private func add(_ item: ClipboardItem) {
        let removed = items.filter { $0.fingerprint == item.fingerprint }
        removed.forEach(invalidateThumbnail)
        items.removeAll { $0.fingerprint == item.fingerprint }
        items.insert(item, at: 0)
        trim()
        scheduleSave()
    }

    private func trim() {
        while items.count > maxItems {
            let removed = items.removeLast()
            invalidateThumbnail(for: removed)
            deleteFile(removed)
        }
    }

    private func deleteFile(_ item: ClipboardItem) {
        if let name = item.fileName {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    private func invalidateThumbnail(for item: ClipboardItem) {
        guard let name = item.fileName else { return }
        for key in thumbnailKeys.removeValue(forKey: name) ?? [] {
            thumbnailCache.removeObject(forKey: key as NSString)
        }
    }

    private func migratedItem(_ item: ClipboardItem) -> ClipboardItem? {
        if item.kind == .text, let text = item.text {
            if item.fingerprint.hasPrefix("text:") {
                return item
            }
            return ClipboardItem(id: item.id, kind: .text, text: text, fileName: nil, displayName: nil, createdAt: item.createdAt, fingerprint: fingerprint(prefix: "text", data: Data(text.utf8)), byteCount: nil)
        }
        guard let fileName = item.fileName else { return nil }
        let url = directory.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let byteCount = item.byteCount ?? Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        let displayName = item.displayName ?? fileName
        if item.fingerprint.hasPrefix("image:") {
            if item.byteCount == byteCount, item.displayName != nil { return item }
            return ClipboardItem(id: item.id, kind: .image, text: nil, fileName: fileName, displayName: displayName, createdAt: item.createdAt, fingerprint: item.fingerprint, byteCount: byteCount)
        }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return ClipboardItem(id: item.id, kind: .image, text: nil, fileName: fileName, displayName: displayName, createdAt: item.createdAt, fingerprint: fingerprint(prefix: "image", data: data), byteCount: byteCount)
    }

    private static func imageDisplayName(_ preferred: String?) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        var stem = formatter.string(from: Date())
        if let preferred, !preferred.isEmpty {
            let base = URL(fileURLWithPath: preferred).deletingPathExtension().lastPathComponent
                .replacingOccurrences(of: ":", with: "-")
                .replacingOccurrences(of: "/", with: "-")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !base.isEmpty { stem = base }
        }
        return "\(stem).png"
    }

    private func fingerprint(prefix: String, data: Data) -> String {
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return "\(prefix):\(digest)"
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private func saveNow() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        let snapshot = items
        let destination = indexURL
        saveQueue.async { Self.writeHistory(snapshot, to: destination) }
    }

    private static func writeHistory(_ snapshot: [ClipboardItem], to destination: URL) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: destination, options: .atomic)
    }

    private static func makeThumbnail(at url: URL, maxPixels: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary)
    }
}

/// macOS 没有公开的剪贴板变更通知。复制发生时，pboard 会向本进程发缓存失效；
/// 拦截 `_CFPasteboardCache.setChangeCount:` 即可实时回调（Chromium 同款做法）。
private enum PasteboardChangeHook {
    static var onChange: (() -> Void)?
    private static var installed = false

    @discardableResult
    static func install() -> Bool {
        if installed { return true }
        guard let cls = NSClassFromString("_CFPasteboardCache") else { return false }
        let selector = NSSelectorFromString("setChangeCount:")
        guard let method = class_getInstanceMethod(cls, selector) else { return false }

        typealias Setter = @convention(c) (AnyObject, Selector, Int32) -> Void
        let original = unsafeBitCast(method_getImplementation(method), to: Setter.self)
        let block: @convention(block) (AnyObject, Int32) -> Void = { object, count in
            original(object, selector, count)
            DispatchQueue.main.async {
                _ = NSPasteboard.general.changeCount
                onChange?()
            }
        }
        method_setImplementation(method, imp_implementationWithBlock(block))
        installed = true
        _ = NSPasteboard.general.changeCount
        return true
    }
}

final class ClipboardMonitor {
    private let store: ClipboardStore
    private let pasteboard: NSPasteboard
    private var changeCount: Int
    private var timer: Timer?
    private var running = false

    init(store: ClipboardStore, pasteboard: NSPasteboard = .general) {
        self.store = store
        self.pasteboard = pasteboard
        changeCount = pasteboard.changeCount
    }

    deinit {
        stop()
    }

    func start() {
        guard !running else { return }
        running = true
        PasteboardChangeHook.onChange = { [weak self] in self?.check() }
        if PasteboardChangeHook.install() { return }
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.check() }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        running = false
        if PasteboardChangeHook.onChange != nil {
            PasteboardChangeHook.onChange = nil
        }
        timer?.invalidate()
        timer = nil
    }

    func check() {
        let board = pasteboard
        guard board.changeCount != changeCount else { return }
        changeCount = board.changeCount
        if board.data(forType: ClipboardStore.internalPasteboardType) != nil { return }
        if PasteboardPolicy.shouldIgnore(board) { return }
        if let text = board.string(forType: .string) { store.addText(text) }
        else if let image = NSImage(pasteboard: board) {
            store.addImage(image, preferredName: Self.suggestedImageName(from: board))
        }
    }

    private static func suggestedImageName(from board: NSPasteboard) -> String? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if let urls = board.readObjects(forClasses: [NSURL.self], options: options) as? [URL],
           let name = urls.first?.lastPathComponent,
           !name.isEmpty {
            return name
        }
        if let string = board.string(forType: .fileURL) {
            let url = URL(string: string) ?? URL(fileURLWithPath: string)
            if !url.lastPathComponent.isEmpty { return url.lastPathComponent }
        }
        return nil
    }
}
