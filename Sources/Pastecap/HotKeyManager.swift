import AppKit
import Carbon.HIToolbox

enum HotKeyAction { case history, screenshot }

struct HotKeyShortcut: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32

    static let historyDefault = HotKeyShortcut(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | shiftKey))
    static let screenshotDefault = HotKeyShortcut(keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(optionKey | cmdKey))

    static let legacyHistoryDefault = HotKeyShortcut(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(optionKey | cmdKey))
    static let legacyScreenshotDefault = HotKeyShortcut(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(controlKey | optionKey))

    var displayName: String {
        var result = ""
        if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        result += Self.keyName(for: keyCode)
        return result
    }

    static func from(event: NSEvent) -> HotKeyShortcut? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var carbonModifiers: UInt32 = 0
        if flags.contains(.control) { carbonModifiers |= UInt32(controlKey) }
        if flags.contains(.option) { carbonModifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }
        if flags.contains(.command) { carbonModifiers |= UInt32(cmdKey) }
        guard carbonModifiers != 0, event.keyCode != UInt16(kVK_Escape) else { return nil }
        return HotKeyShortcut(keyCode: UInt32(event.keyCode), modifiers: carbonModifiers)
    }

    private static func keyName(for keyCode: UInt32) -> String {
        let names: [UInt32: String] = [
            UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
            UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
            UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
            UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
            UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
            UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
            UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
            UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
            UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
            UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
            UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
            UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
            UInt32(kVK_ANSI_9): "9", UInt32(kVK_Space): "Space"
        ]
        return names[keyCode] ?? "Key \(keyCode)"
    }
}

final class HotKeySettings: ObservableObject {
    @Published var history: HotKeyShortcut { didSet { persist(); onChange?() } }
    @Published var screenshot: HotKeyShortcut { didSet { persist(); onChange?() } }
    @Published var registrationMessage: String?
    var onChange: (() -> Void)?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var loadedHistory = Self.load("historyHotKey", defaults: defaults) ?? .historyDefault
        if loadedHistory == HotKeyShortcut.legacyHistoryDefault { loadedHistory = .historyDefault }
        var loadedScreenshot = Self.load("screenshotHotKey", defaults: defaults) ?? .screenshotDefault
        if loadedScreenshot == HotKeyShortcut.legacyScreenshotDefault { loadedScreenshot = .screenshotDefault }
        history = loadedHistory
        screenshot = loadedScreenshot
        persist()
    }

    func reset() {
        history = .historyDefault
        screenshot = .screenshotDefault
    }

    private func persist() {
        if let historyData = try? JSONEncoder().encode(history) { defaults.set(historyData, forKey: "historyHotKey") }
        if let screenshotData = try? JSONEncoder().encode(screenshot) { defaults.set(screenshotData, forKey: "screenshotHotKey") }
    }

    private static func load(_ key: String, defaults: UserDefaults) -> HotKeyShortcut? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(HotKeyShortcut.self, from: data)
    }
}

final class HotKeyManager {
    private var refs: [EventHotKeyRef] = []
    private var eventHandlerRef: EventHandlerRef?
    private let settings: HotKeySettings
    private let handler: (HotKeyAction) -> Void

    init(settings: HotKeySettings, handler: @escaping (HotKeyAction) -> Void) {
        self.settings = settings
        self.handler = handler
        settings.onChange = { [weak self] in self?.register() }
    }

    func register() {
        installHandlerIfNeeded()
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()

        var failures: [String] = []
        if !register(settings.history, id: 1) { failures.append("剪贴板快捷键被占用") }
        if settings.screenshot == settings.history {
            failures.append("两个功能不能使用相同快捷键")
        } else if !register(settings.screenshot, id: 2) {
            failures.append("截图快捷键被占用")
        }
        settings.registrationMessage = failures.isEmpty ? nil : failures.joined(separator: "；")
    }

    deinit {
        refs.forEach { UnregisterEventHotKey($0) }
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
    }

    private func installHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }
        let eventHandler: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return noErr }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            if id.id == 1 { manager.handler(.history) }
            else if id.id == 2 { manager.handler(.screenshot) }
            return noErr
        }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), eventHandler, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &eventHandlerRef)
    }

    private func register(_ shortcut: HotKeyShortcut, id: UInt32) -> Bool {
        var ref: EventHotKeyRef?
        let hotID = EventHotKeyID(signature: OSType(0x50636170), id: id)
        guard RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, hotID, GetApplicationEventTarget(), 0, &ref) == noErr,
              let ref else { return false }
        refs.append(ref)
        return true
    }
}
