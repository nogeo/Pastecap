import SwiftUI
import AppKit
import ServiceManagement

enum HistoryCategoryFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case text = "文本"
    case image = "图片"

    var id: String { rawValue }
    var iconName: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .text: return "text.alignleft"
        case .image: return "photo"
        }
    }
}

/// 剪贴板列表键盘导航的纯索引计算，便于单元测试
enum HistoryKeyboardNav {
    /// 从 currentIndex 向 delta（±1）移动，钳制在 0..<count；空列表返回 nil
    static func selectedIndex(afterMovingFrom currentIndex: Int?, count: Int, delta: Int) -> Int? {
        guard count > 0 else { return nil }
        return min(max((currentIndex ?? -1) + delta, 0), count - 1)
    }

    /// 删除 index 处的条目后，高亮应落在新列表的位置（尽量保持视觉位置不动）
    static func selectionAfterRemoval(index: Int, remainingCount: Int) -> Int? {
        guard remainingCount > 0 else { return nil }
        return min(index, remainingCount - 1)
    }

    /// 仅 ⌘Q，不含 Option / Control / Shift
    static func isQuitShortcut(character: String, command: Bool, option: Bool = false, control: Bool = false, shift: Bool = false) -> Bool {
        command && !option && !control && !shift && character.lowercased() == "q"
    }

    static func isQuitShortcut(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        return flags == .command && event.charactersIgnoringModifiers?.lowercased() == "q"
    }
}

struct HistoryView: View {
    @ObservedObject var store: ClipboardStore
    @ObservedObject var hotKeySettings: HotKeySettings
    let onScreenshot: () -> Void
    let onCopied: () -> Void
    let onCancel: () -> Void
    @State private var search = ""
    @State private var selectedFilter: HistoryCategoryFilter = .all
    @State private var showingSettings = false
    @State private var confirmingClear = false
    @State private var copiedItemID: UUID?
    @State private var selectedID: UUID?
    @FocusState private var searchFocused: Bool

    private var filtered: [ClipboardItem] {
        let base: [ClipboardItem]
        switch selectedFilter {
        case .all:
            base = store.items
        case .text:
            base = store.items.filter { $0.kind == .text }
        case .image:
            base = store.items.filter { $0.kind == .image }
        }

        guard !search.isEmpty else { return base }
        return base.filter { item in
            if item.kind == .image {
                return (item.displayName ?? item.fileName ?? "").localizedCaseInsensitiveContains(search)
            }
            return (item.text ?? "").localizedCaseInsensitiveContains(search)
        }
    }

    private var countForFilter: (HistoryCategoryFilter) -> Int {
        { filter in
            switch filter {
            case .all: return store.items.count
            case .text: return store.items.filter { $0.kind == .text }.count
            case .image: return store.items.filter { $0.kind == .image }.count
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: 48)
                .fixedSize(horizontal: false, vertical: true)

            searchAndFilterBar

            content
                .frame(maxHeight: .infinity)

            Divider()
                .opacity(0.6)

            footer
                .frame(height: 34)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 360, height: 480)
        .background(.regularMaterial)
        .sheet(isPresented: $showingSettings) { SettingsView(store: store, hotKeySettings: hotKeySettings) }
        .confirmationDialog("清空全部剪贴板记录？", isPresented: $confirmingClear) {
            Button("清空全部记录", role: .destructive) { store.clear() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作无法撤销。")
        }
        .onAppear { prepareForKeyboardUse() }
        // 每次弹出窗口都重置为「搜索框聚焦 + 高亮第一条」，直接打字即可筛选
        .onReceive(NotificationCenter.default.publisher(for: NSPopover.didShowNotification)) { _ in
            prepareForKeyboardUse()
        }
        .onExitCommand { onCancel() }
        .onChange(of: search) { _, _ in selectedID = filtered.first?.id }
        .onChange(of: selectedFilter) { _, _ in selectedID = filtered.first?.id }
        .onKeyPress { press in handleKeyPress(press) }
    }

    private func prepareForKeyboardUse() {
        search = ""
        selectedID = filtered.first?.id
        searchFocused = true
    }

    private func handleKeyPress(_ press: KeyPress) -> KeyPress.Result {
        switch press.key {
        case .upArrow:
            if moveSelection(-1) { return .handled }
        case .downArrow:
            if moveSelection(1) { return .handled }
        default:
            break
        }
        // ⌦（forward delete）删除高亮项；⌫ 保持原语义用于编辑搜索词
        if press.characters == "\u{F728}" {
            removeSelected()
            return .handled
        }
        if press.modifiers.contains(.command),
           let digit = press.characters.first?.wholeNumberValue, (1...9).contains(digit) {
            if copyItemAt(index: digit - 1) { return .handled }
        }
        if HistoryKeyboardNav.isQuitShortcut(
            character: press.characters,
            command: press.modifiers.contains(.command),
            option: press.modifiers.contains(.option),
            control: press.modifiers.contains(.control),
            shift: press.modifiers.contains(.shift)
        ) {
            NSApp.terminate(nil)
            return .handled
        }
        return .ignored
    }

    @discardableResult
    private func moveSelection(_ delta: Int) -> Bool {
        guard !filtered.isEmpty else { return false }
        let current = filtered.firstIndex(where: { $0.id == selectedID })
        guard let next = HistoryKeyboardNav.selectedIndex(afterMovingFrom: current, count: filtered.count, delta: delta) else { return false }
        selectedID = filtered[next].id
        return true
    }

    private func copySelected() {
        if let id = selectedID, let item = filtered.first(where: { $0.id == id }) {
            copyWithFeedback(item)
        } else if let first = filtered.first {
            copyWithFeedback(first)
        }
    }

    @discardableResult
    private func removeSelected() -> Bool {
        guard let id = selectedID, let index = filtered.firstIndex(where: { $0.id == id }) else { return false }
        let remaining = filtered.filter { $0.id != id }
        store.remove(filtered[index])
        if let next = HistoryKeyboardNav.selectionAfterRemoval(index: index, remainingCount: remaining.count) {
            selectedID = remaining[next].id
        } else {
            selectedID = nil
        }
        return true
    }

    @discardableResult
    private func copyItemAt(index: Int) -> Bool {
        guard filtered.indices.contains(index) else { return false }
        copyWithFeedback(filtered[index])
        return true
    }

    private var appIcon: NSImage {
        NSImage(named: "AppIcon") ?? NSApp.applicationIconImage
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: appIcon)
                .resizable()
                .frame(width: 30, height: 30)
                .cornerRadius(7)

            VStack(alignment: .leading, spacing: 1) {
                Text("Pastecap")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Text("历史记录 · 快速粘贴")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onScreenshot) {
                HStack(spacing: 4) {
                    Image(systemName: "viewfinder")
                        .font(.system(size: 11, weight: .bold))
                    Text("截图")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color.accentColor, in: Capsule())
                .shadow(color: Color.accentColor.opacity(0.25), radius: 3, y: 1)
            }
            .buttonStyle(.plain)
            .help("区域截图  \(hotKeySettings.screenshot.displayName)")

            Button { showingSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.8), in: Circle())
            }
            .buttonStyle(.plain)
            .help("设置")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var searchAndFilterBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("搜索剪贴板…", text: $search)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($searchFocused)
                    // 回车即复制当前高亮项（搜索框始终持有焦点，保证快捷键可达）
                    .onSubmit { copySelected() }
                if !search.isEmpty {
                    Button { search = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.8), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 0.5)
            }

            // 分类胶囊切换栏
            HStack(spacing: 6) {
                ForEach(HistoryCategoryFilter.allCases) { filter in
                    let isSelected = selectedFilter == filter
                    let count = countForFilter(filter)
                    Button {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            selectedFilter = filter
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: filter.iconName)
                                .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                            Text(filter.rawValue)
                                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                            Text("\(count)")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(isSelected ? Color.accentColor.opacity(0.2) : Color(nsColor: .quaternaryLabelColor).opacity(0.3), in: Capsule())
                        }
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .background(
                            isSelected ?
                                Color(nsColor: .controlBackgroundColor) :
                                Color.clear,
                            in: Capsule()
                        )
                        .overlay {
                            if isSelected {
                                Capsule()
                                    .stroke(Color.accentColor.opacity(0.3), lineWidth: 0.5)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    private var content: some View {
        Group {
            if filtered.isEmpty {
                ContentUnavailableView(
                    search.isEmpty ? (selectedFilter == .all ? "没有记录" : "暂无\(selectedFilter.rawValue)记录") : "无匹配结果",
                    systemImage: search.isEmpty ? "clipboard" : "magnifyingglass",
                    description: Text(search.isEmpty ? "复制文本或截图后会自动保存在这里" : "尝试更换搜索关键词")
                )
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 5) {
                            ForEach(filtered) { item in
                                HistoryCardRow(
                                    item: item,
                                    isSelected: selectedID == item.id,
                                    isCopied: copiedItemID == item.id,
                                    thumbnail: item.kind == .image ? store.thumbnail(for: item, size: CGSize(width: 52, height: 42)) : nil,
                                    onCopy: { copyWithFeedback(item) },
                                    onRemove: { store.remove(item) }
                                )
                                .id(item.id)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                    }
                    .scrollContentBackground(.hidden)
                    .onChange(of: store.items.first?.id) { _, _ in
                        guard let firstID = filtered.first?.id else { return }
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(firstID, anchor: .top) }
                    }
                    // 键盘移动高亮时保持可见（不强制对齐，最小滚动量）
                    .onChange(of: selectedID) { _, newID in
                        guard let newID else { return }
                        proxy.scrollTo(newID)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            HStack(spacing: 4) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 11))
                Text("共 \(store.items.count) 条历史")
                    .font(.system(size: 11))
            }
            .foregroundStyle(.secondary)

            Spacer()

            Text("↑↓ 选择 · ↵ 复制 · ⌦ 删除")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)

            Divider()
                .frame(height: 12)
                .padding(.horizontal, 6)

            Button("清空记录", role: .destructive) { confirmingClear = true }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(store.items.isEmpty)

            Divider()
                .frame(height: 12)
                .padding(.horizontal, 2)

            Button { NSApp.terminate(nil) } label: {
                Image(systemName: "power")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .keyboardShortcut("q", modifiers: .command)
            .help("退出 Pastecap")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func copyWithFeedback(_ item: ClipboardItem) {
        store.copy(item)
        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
            copiedItemID = item.id
        }
        // 留出「已复制」反馈可见的时间，再收起窗口方便直接粘贴
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            onCopied()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            guard copiedItemID == item.id else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                copiedItemID = nil
            }
        }
    }
}

// MARK: - Modern History Card Row

struct HistoryCardRow: View, Equatable {
    let item: ClipboardItem
    let isSelected: Bool
    let isCopied: Bool
    let thumbnail: NSImage?
    let onCopy: () -> Void
    let onRemove: () -> Void

    @State private var isHovered = false

    static func == (lhs: HistoryCardRow, rhs: HistoryCardRow) -> Bool {
        lhs.item == rhs.item && lhs.isSelected == rhs.isSelected && lhs.isCopied == rhs.isCopied && (lhs.thumbnail != nil) == (rhs.thumbnail != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // 顶部元信息与快捷操作栏
            metaHeader

            // 核心内容区
            if item.kind == .image {
                imageContent
            } else {
                textContent
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(cardBackground)
        .overlay(cardBorder)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { isHovered = $0 }
        .onTapGesture { onCopy() }
        .contextMenu {
            Button("复制") { onCopy() }
            Button("删除", role: .destructive) { onRemove() }
        }
    }

    // MARK: - Meta Header

    private var metaHeader: some View {
        HStack(spacing: 6) {
            tagBadge

            Text(item.relativeTimeString)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(.tertiary)

            Spacer()

            // 悬停/已复制操作徽章
            actionBadge
        }
    }

    @ViewBuilder
    private var tagBadge: some View {
        if item.kind == .image {
            HStack(spacing: 3) {
                Image(systemName: "photo.fill")
                    .font(.system(size: 9))
                Text("图片")
                    .font(.system(size: 9.5, weight: .medium))
            }
            .foregroundStyle(.purple)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(Color.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        } else if let hexColor = item.hexColor {
            HStack(spacing: 4) {
                Circle()
                    .fill(Color(nsColor: hexColor))
                    .frame(width: 8, height: 8)
                    .overlay(Circle().stroke(Color.black.opacity(0.2), lineWidth: 0.5))
                Text("颜色")
                    .font(.system(size: 9.5, weight: .medium))
            }
            .foregroundStyle(.orange)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        } else if item.isURL {
            HStack(spacing: 3) {
                Image(systemName: "link")
                    .font(.system(size: 9))
                Text("链接")
                    .font(.system(size: 9.5, weight: .medium))
            }
            .foregroundStyle(.blue)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        } else if item.isMultiline {
            HStack(spacing: 3) {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 9))
                Text("\(item.lineCount)行 · \(item.characterCount)字")
                    .font(.system(size: 9.5, weight: .medium))
            }
            .foregroundStyle(.teal)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(Color.teal.opacity(0.12), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        } else {
            HStack(spacing: 3) {
                Image(systemName: "text.quote")
                    .font(.system(size: 9))
                Text("\(item.characterCount)字")
                    .font(.system(size: 9.5, weight: .medium))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(Color(nsColor: .quaternaryLabelColor).opacity(0.3), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
    }

    @ViewBuilder
    private var actionBadge: some View {
        if isCopied {
            HStack(spacing: 3) {
                Image(systemName: "checkmark")
                    .font(.system(size: 9.5, weight: .bold))
                Text("已复制")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.green, in: Capsule())
            .frame(height: 18)
        } else {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 10))
                .foregroundStyle(isHovered ? Color.accentColor : Color.secondary.opacity(0.4))
                .frame(width: 18, height: 18)
        }
    }

    // MARK: - Content Views

    private var textContent: some View {
        Text(item.previewSnippet)
            .font(item.isURL ? .system(size: 12.5, design: .monospaced) : .system(size: 12.5, design: .default))
            .lineSpacing(2.5)
            .lineLimit(3)
            .truncationMode(.tail)
            .foregroundStyle(Color(nsColor: .labelColor))
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.disabled)
    }

    private var imageContent: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .underPageBackgroundColor).opacity(0.8))
                    .frame(width: 52, height: 42)

                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 52, height: 42)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 0.5)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName ?? item.fileName ?? "屏幕截图")
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(Color(nsColor: .labelColor))

                if let byteCount = item.byteCount {
                    Text("PNG · \(ClipboardItem.compactByteCount(byteCount))")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
    }

    // MARK: - Card Styling

    private var cardBackground: some View {
        ZStack {
            if isCopied {
                Color.green.opacity(0.08)
            } else if isSelected {
                Color.accentColor.opacity(0.09)
            } else if isHovered {
                Color.accentColor.opacity(0.05)
            } else {
                Color(nsColor: .controlBackgroundColor).opacity(0.65)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .animation(.easeInOut(duration: 0.15), value: isCopied)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(
                isCopied ? Color.green.opacity(0.4) :
                (isSelected ? Color.accentColor.opacity(0.55) :
                (isHovered ? Color.accentColor.opacity(0.3) : Color(nsColor: .separatorColor).opacity(0.3))),
                lineWidth: (isCopied || isSelected) ? 1 : 0.5
            )
            .animation(.easeInOut(duration: 0.15), value: isHovered)
            .animation(.easeInOut(duration: 0.15), value: isCopied)
            .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - Modern Settings View

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
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        return "v\(version)"
    }

    var body: some View {
        VStack(spacing: 0) {
            // 设置顶部导航栏
            settingsHeader

            Divider()
                .opacity(0.5)

            // 设置卡片内容区
            ScrollView {
                VStack(spacing: 12) {
                    generalSection
                    shortcutSection
                    storageSection
                    aboutSection
                }
                .padding(16)
            }
        }
        .frame(width: 360, height: 480)
        .background(.regularMaterial)
        .onAppear { refreshCacheSize() }
        .confirmationDialog("清理 Pastecap 缓存？", isPresented: $confirmingCacheClear) {
            Button("清理全部历史和图片", role: .destructive) {
                store.clear()
                refreshCacheSize()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("所有剪贴板历史和缓存图片将被删除，此操作无法撤销。")
        }
    }

    // MARK: - Settings Header

    private var settingsHeader: some View {
        HStack {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.14))
                        .frame(width: 26, height: 26)
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.accentColor)
                }
                Text("偏好设置")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
            }

            Spacer()

            Button("完成") { dismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Sections

    private var generalSection: some View {
        SettingsCard(title: "通用", icon: "slider.horizontal.3", color: .blue) {
            VStack(spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("登录时自动打开")
                            .font(.system(size: 12.5, weight: .medium))
                        Text(runsFromAppBundle ? "开机后在后台安静运行" : "从 Pastecap.app 运行后可开启")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(get: { launch }, set: { value in launch = value; updateLoginItem(value) }))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .disabled(!runsFromAppBundle)
                }

                if let loginItemMessage {
                    HStack(spacing: 5) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                        Text(loginItemMessage)
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Divider().opacity(0.5)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("历史记录上限")
                            .font(.system(size: 12.5, weight: .medium))
                        Text("超出上限将自动移除最早的记录")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Stepper(value: $store.maxItems, in: 20...1000, step: 20) {
                        Text("\(store.maxItems) 条")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.accentColor)
                            .frame(minWidth: 50, alignment: .trailing)
                    }
                }
            }
        }
    }

    private var shortcutSection: some View {
        SettingsCard(title: "快捷键", icon: "command", color: .purple) {
            VStack(spacing: 10) {
                HStack {
                    Text("打开剪贴板")
                        .font(.system(size: 12.5, weight: .medium))
                    Spacer()
                    HotKeyRecorder(shortcut: $hotKeySettings.history)
                }

                Divider().opacity(0.5)

                HStack {
                    Text("区域截图")
                        .font(.system(size: 12.5, weight: .medium))
                    Spacer()
                    HotKeyRecorder(shortcut: $hotKeySettings.screenshot)
                }

                if let message = hotKeySettings.registrationMessage {
                    HStack(spacing: 5) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                        Text(message)
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Divider().opacity(0.5)

                HStack {
                    Spacer()
                    Button("恢复默认快捷键") { hotKeySettings.reset() }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var storageSection: some View {
        SettingsCard(title: "存储", icon: "internaldrive", color: .teal) {
            VStack(spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("截图保存位置")
                            .font(.system(size: 12.5, weight: .medium))
                        Text(saveDirectory)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button("更改…") { chooseSaveDirectory() }
                        .controlSize(.small)
                }

                Divider().opacity(0.5)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("当前缓存占用")
                            .font(.system(size: 12.5, weight: .medium))
                        Text(ByteCountFormatter.string(fromByteCount: cacheSize, countStyle: .file))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("清理缓存", role: .destructive) { confirmingCacheClear = true }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(cacheSize == 0)
                }
            }
        }
    }

    private var aboutSection: some View {
        SettingsCard(title: "关于", icon: "info.circle", color: .indigo) {
            VStack(spacing: 8) {
                HStack {
                    Text("Pastecap")
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    Spacer()
                    Text(versionText)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Text("剪贴板和截图数据均保存在本机本地，绝不联网上传。密码管理器等标记为机密的内容自动被过滤保护。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
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

// MARK: - Settings Card Wrapper

private struct SettingsCard<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            content()
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.65))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.3), lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - HotKeyRecorder

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
