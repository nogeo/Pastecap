import SwiftUI
import AppKit
import ServiceManagement

struct HistoryView: View {
    @ObservedObject var store: ClipboardStore
    @ObservedObject var hotKeySettings: HotKeySettings
    let onScreenshot: () -> Void
    @State private var search = ""
    @State private var showingSettings = false
    @State private var confirmingClear = false
    @State private var copiedItemID: UUID?
    @StateObject private var copiedRowFrame = CopiedRowFrame()

    private var filtered: [ClipboardItem] {
        guard !search.isEmpty else { return store.items }
        return store.items.filter { item in
            item.kind == .image || (item.text ?? "").localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: 58)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            searchField
            content
                .frame(maxHeight: .infinity)
                .overlay { copiedTooltip }
            Divider()
            footer
                .frame(height: 38)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 420, height: 570)
        .background(.regularMaterial)
        .sheet(isPresented: $showingSettings) { SettingsView(store: store, hotKeySettings: hotKeySettings) }
        .confirmationDialog("清空全部剪贴板记录？", isPresented: $confirmingClear) {
            Button("清空全部记录", role: .destructive) { store.clear() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作无法撤销。")
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text("剪贴板")
                    .font(.system(.headline, design: .rounded))
                Text("最近复制的内容")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onScreenshot) {
                Image(systemName: "viewfinder")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Color.accentColor, in: Circle())
            }
            .buttonStyle(.plain)
            .help("区域截图  \(hotKeySettings.screenshot.displayName)")
            Button { showingSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 28, height: 28)
                    .background(Color(nsColor: .controlBackgroundColor), in: Circle())
            }
            .buttonStyle(.plain)
            .help("设置")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索剪贴板", text: $search)
                .textFieldStyle(.plain)
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var content: some View {
        Group {
            if filtered.isEmpty {
                ContentUnavailableView("没有记录", systemImage: search.isEmpty ? "clipboard" : "magnifyingglass", description: Text(search.isEmpty ? "复制文本或图片后会显示在这里" : "没有匹配的剪贴板内容"))
            } else {
                VStack(spacing: 0) {
                    sectionHeaderBar
                    ScrollViewReader { proxy in
                        List {
                            ForEach(filtered) { item in
                                HistoryRow(
                                    item: item,
                                    isCopied: copiedItemID == item.id,
                                    thumbnail: item.kind == .image ? store.thumbnail(for: item) : nil,
                                    copiedRowFrame: copiedRowFrame,
                                    onCopy: { copyWithFeedback(item) },
                                    onRemove: { store.remove(item) }
                                )
                                    .id(item.id)
                                    .listRowInsets(EdgeInsets(top: 5, leading: 14, bottom: 5, trailing: 14))
                                    .listRowSeparator(.visible)
                            }
                            .onDelete { offsets in
                                offsets.map { filtered[$0] }.forEach(store.remove)
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .onChange(of: store.items.first?.id) { _, _ in
                            guard let firstID = filtered.first?.id else { return }
                            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(firstID, anchor: .top) }
                        }
                    }
                }
            }
        }
    }

    private var sectionHeaderBar: some View {
        HStack {
            Text(search.isEmpty ? "全部记录" : "搜索结果")
                .textCase(nil)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    /// antd Tooltip 风格的“已复制”气泡，浮在所点行上方；行靠近顶部时翻转到下方。
    /// 位置用全局坐标经共享对象传递——List 的行宿主不传播 PreferenceKey。
    @ViewBuilder private var copiedTooltip: some View {
        GeometryReader { geo in
            if let frame = copiedRowFrame.frame {
                let base = geo.frame(in: .global)
                let localMinY = frame.minY - base.minY
                let above = localMinY > 52
                CopiedTooltip(arrowDown: above)
                    .position(x: frame.midX - base.minX,
                              y: above ? localMinY - 24 : frame.maxY - base.minY + 24)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    .allowsHitTesting(false)
                    .animation(.easeInOut(duration: 0.18), value: copiedRowFrame.frame)
            }
        }
    }

    private var footer: some View {
        HStack {
            Label("\(store.items.count) 条", systemImage: "clock")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("清空记录", role: .destructive) { confirmingClear = true }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(store.items.isEmpty)
            Button { NSApp.terminate(nil) } label: {
                Image(systemName: "power")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help("退出 Pastecap")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private func copyWithFeedback(_ item: ClipboardItem) {
        store.copy(item)
        copiedItemID = item.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            guard copiedItemID == item.id else { return }
            copiedItemID = nil
            copiedRowFrame.frame = nil
        }
    }
}

struct HistoryRow: View, Equatable {
    let item: ClipboardItem
    let isCopied: Bool
    let thumbnail: NSImage?
    let copiedRowFrame: CopiedRowFrame
    let onCopy: () -> Void
    let onRemove: () -> Void
    @State private var copyPulse = 0

    static func == (lhs: HistoryRow, rhs: HistoryRow) -> Bool {
        lhs.item == rhs.item && lhs.isCopied == rhs.isCopied && (lhs.thumbnail != nil) == (rhs.thumbnail != nil)
    }

    var body: some View {
        HStack(spacing: 11) {
            preview
            VStack(alignment: .leading, spacing: 3) {
                Text(item.kind == .image ? "图片" : (item.text ?? ""))
                    .font(.system(.body, design: .rounded))
                    .lineLimit(2)
                    .truncationMode(.tail)
                Text(item.createdAt.formatted(date: .numeric, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 5)
            Image(systemName: isCopied ? "checkmark.circle.fill" : "doc.on.doc")
                .font(.caption.weight(.semibold))
                .foregroundStyle(isCopied ? Color.green : Color.secondary)
                .frame(width: 18, height: 18)
                .help(isCopied ? "已复制" : "点击复制")
                .symbolEffect(.bounce, value: isCopied)
        }
        .contentShape(Rectangle())
        .background(
            GeometryReader { geo in
                Color.clear
                    .onChange(of: isCopied) { _, newValue in
                        guard newValue else { return }
                        copiedRowFrame.frame = geo.frame(in: .global)
                    }
                    .onChange(of: geo.frame(in: .global)) { _, newFrame in
                        guard isCopied else { return }
                        copiedRowFrame.frame = newFrame
                    }
            }
        )
        .listRowBackground(
            KeyframeAnimator(initialValue: 0.0, trigger: copyPulse) { glow in
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(glow))
                    .padding(.vertical, 1)
            } keyframes: { _ in
                KeyframeTrack(\.self) {
                    CubicKeyframe(0.22, duration: 0.42)
                    CubicKeyframe(0.22, duration: 0.12)
                    CubicKeyframe(0.0, duration: 0.66)
                }
            }
        )
        .onTapGesture { copyWithFeedback() }
        .contextMenu {
            Button("复制") { copyWithFeedback() }
            Button("删除", role: .destructive) { onRemove() }
        }
    }

    private func copyWithFeedback() {
        copyPulse += 1
        onCopy()
    }

    private var preview: some View {
        Group {
            if item.kind == .image, let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 54, height: 44)
                    .background(Color(nsColor: .underPageBackgroundColor))
            } else {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 54, height: 44)
                    .background(Color(nsColor: .underPageBackgroundColor))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

/// 在全局坐标系中记录被复制行的位置；List 的行宿主不传播 PreferenceKey，改用共享对象传递
final class CopiedRowFrame: ObservableObject {
    @Published var frame: CGRect?
}

/// 深色气泡 + 小箭头，视觉对齐 antd Tooltip
private struct CopiedTooltip: View {
    var arrowDown: Bool

    var body: some View {
        VStack(spacing: 0) {
            if !arrowDown { arrow }
            Text("已复制")
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 6))
            if arrowDown { arrow }
        }
        .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
        .fixedSize()
    }

    private var arrow: some View {
        TooltipArrow(pointingDown: arrowDown)
            .fill(Color.black.opacity(0.85))
            .frame(width: 10, height: 5)
    }
}

private struct TooltipArrow: Shape {
    var pointingDown: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if pointingDown {
            path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        } else {
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        }
        path.closeSubpath()
        return path
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: ClipboardStore
    @ObservedObject var hotKeySettings: HotKeySettings
    @AppStorage("launchAtLogin") private var launch = false
    @AppStorage("saveDirectory") private var saveDirectory = "~/Pictures/Pastecap"
    @State private var cacheSize: Int64 = 0
    @State private var confirmingCacheClear = false
    @State private var loginItemMessage: String?

    private var runsFromAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension.lowercased() == "app"
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "版本 \(version) (\(build))"
    }

    var body: some View {
        Form {
            Section("通用") {
                Toggle("登录时打开 Pastecap", isOn: Binding(get: { launch }, set: { value in launch = value; updateLoginItem(value) }))
                    .disabled(!runsFromAppBundle)
                if let loginItemMessage {
                    Label(loginItemMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if !runsFromAppBundle {
                    Text("从 Pastecap.app 启动后才能设置开机启动")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Stepper(value: $store.maxItems, in: 20...1000, step: 20) {
                    HStack { Text("历史记录上限"); Spacer(); Text("\(store.maxItems) 条").foregroundStyle(.secondary) }
                }
            }
            Section("快捷键") {
                LabeledContent("打开剪贴板") {
                    HotKeyRecorder(shortcut: $hotKeySettings.history)
                }
                LabeledContent("区域截图") {
                    HotKeyRecorder(shortcut: $hotKeySettings.screenshot)
                }
                if let message = hotKeySettings.registrationMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                HStack {
                    Spacer()
                    Button("恢复默认") { hotKeySettings.reset() }
                        .controlSize(.small)
                }
            }
            Section("存储") {
                LabeledContent("保存位置") {
                    HStack(spacing: 6) {
                        Text(saveDirectory)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("更改…") { chooseSaveDirectory() }
                            .controlSize(.small)
                    }
                }
                LabeledContent("缓存大小") { Text(ByteCountFormatter.string(fromByteCount: cacheSize, countStyle: .file)).foregroundStyle(.secondary) }
                HStack {
                    Spacer()
                    Button("清理缓存", role: .destructive) { confirmingCacheClear = true }
                        .disabled(cacheSize == 0)
                }
            }
            Section("关于") {
                LabeledContent("Pastecap") { Text(versionText).foregroundStyle(.secondary) }
                Text("剪贴板和截图只保存在本机，不会上传。密码管理器标记为保密的内容不会进入历史。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 520)
        .padding(.top, 8)
        .onAppear { refreshCacheSize() }
        .confirmationDialog("清理 Pastecap 缓存？", isPresented: $confirmingCacheClear) {
            Button("清理剪贴板历史和图片", role: .destructive) {
                store.clear()
                refreshCacheSize()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("所有剪贴板历史和缓存图片将被删除，此操作无法撤销。")
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("完成") { dismiss() }
            }
        }
    }

    private func updateLoginItem(_ enabled: Bool) {
        guard runsFromAppBundle else {
            launch = false
            loginItemMessage = "当前不是从 Pastecap.app 运行，无法设置开机启动"
            return
        }
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginItemMessage = nil
        } catch {
            launch = false
            loginItemMessage = "设置开机启动失败：\(error.localizedDescription)"
        }
    }

    private func chooseSaveDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = ScreenshotDestination.resolveSaveDirectory()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        saveDirectory = (url.path as NSString).abbreviatingWithTildeInPath
    }

    private func refreshCacheSize() {
        cacheSize = store.cacheSizeBytes()
    }
}

struct HotKeyRecorder: NSViewRepresentable {
    @Binding var shortcut: HotKeyShortcut

    func makeNSView(context: Context) -> HotKeyRecorderButton {
        let button = HotKeyRecorderButton()
        button.shortcut = shortcut
        button.onShortcut = { shortcut = $0 }
        return button
    }

    func updateNSView(_ button: HotKeyRecorderButton, context: Context) {
        if !button.isRecording { button.shortcut = shortcut }
    }
}

final class HotKeyRecorderButton: NSButton {
    var onShortcut: ((HotKeyShortcut) -> Void)?
    var shortcut: HotKeyShortcut = .historyDefault { didSet { if !isRecording { title = shortcut.displayName } } }
    private(set) var isRecording = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        controlSize = .small
        target = self
        action = #selector(beginRecording)
        title = shortcut.displayName
    }

    required init?(coder: NSCoder) { nil }
    override var acceptsFirstResponder: Bool { true }

    @objc private func beginRecording() {
        isRecording = true
        title = "请按快捷键"
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            finishRecording()
            return
        }
        guard let newShortcut = HotKeyShortcut.from(event: event) else {
            NSSound.beep()
            return
        }
        shortcut = newShortcut
        onShortcut?(newShortcut)
        finishRecording()
    }

    override func resignFirstResponder() -> Bool {
        finishRecording()
        return super.resignFirstResponder()
    }

    private func finishRecording() {
        isRecording = false
        title = shortcut.displayName
    }
}
