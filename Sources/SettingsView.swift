import AppKit
import SwiftUI
import UserNotifications

// MARK: - 共用外觀

enum Page: Int, CaseIterable {
    case buttons, ring, device, haptics, switching, advanced

    var title: String {
        switch self {
        case .buttons: return Lang.t("按鈕", "Buttons")
        case .ring: return Lang.t("手勢與圓環", "Gestures & Ring")
        case .device: return Lang.t("指標與滾輪", "Pointer & Wheel")
        case .haptics: return Lang.t("觸覺回饋", "Haptics")
        case .switching: return "MX Flow"
        case .advanced: return Lang.t("進階", "Advanced")
        }
    }

    var subtitle: String {
        switch self {
        case .buttons: return Lang.t("為每一顆按鍵選擇要執行的動作", "Choose what each button does")
        case .ring: return Lang.t("自訂 Actions Ring 圓環與拇指四向手勢", "Customize the Actions Ring and thumb gestures")
        case .device: return Lang.t("調整指標速度、精準模式與滾輪", "Tune pointer speed, precision mode and the wheel")
        case .haptics: return Lang.t("設定震動強度，以及哪些操作要讓滑鼠輕震一下", "Set the strength and choose which moments make the mouse tap")
        case .switching: return Lang.t("把游標推到螢幕邊緣，滑鼠就切到另一台電腦", "Push the pointer against a screen edge to move the mouse to another computer")
        case .advanced: return Lang.t("啟動方式、電池提醒、權限與工程模式", "Start-up, battery alerts, permissions and engineering mode")
        }
    }

    var symbol: String {
        switch self {
        case .buttons: return "computermouse"
        case .ring: return "circle.hexagongrid"
        case .device: return "slider.horizontal.3"
        case .haptics: return "hand.tap"
        case .switching: return "rectangle.on.rectangle"
        case .advanced: return "gearshape"
        }
    }
}

struct Card<Content: View>: View {
    var title: String? = nil
    var subtitle: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 14, weight: .semibold))
                    if let subtitle { Text(subtitle).font(.system(size: 11.5)).foregroundStyle(.secondary) }
                }
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.07)))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
    }
}

// 標題＋說明在左、控制項在右的一列。
struct SettingRow<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13))
                if let subtitle {
                    Text(subtitle).font(.system(size: 11.5)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
    }
}

struct NumberBadge: View {
    let text: String
    var active = false

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(active ? Color.white : Color.accentColor)
            .frame(minWidth: 22, minHeight: 22)
            .background(Circle().fill(active ? Color.accentColor : Color.clear))
            .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 1.5))
    }
}

struct Banner: View {
    let symbol: String
    let text: String
    var buttonTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(.orange).font(.system(size: 15))
            Text(text).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if let buttonTitle, let action { Button(buttonTitle, action: action).controlSize(.small) }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.orange.opacity(0.13)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.orange.opacity(0.25)))
    }
}

struct SidebarBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

// MARK: - 主視窗

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var page = Page(rawValue: UserDefaults.standard.integer(forKey: "page")) ?? .buttons   // 啟動參數 -page N 可指定起始頁

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 232).background(SidebarBackground())
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .ignoresSafeArea()
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 46, height: 46)
                VStack(alignment: .leading, spacing: 1) {
                    Text("MX Master 4").font(.system(size: 17, weight: .bold))
                    Text("MX Master Mac").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .padding(.top, 46).padding(.horizontal, 18).padding(.bottom, 22)

            VStack(spacing: 4) {
                ForEach(Page.allCases, id: \.self) { item in
                    Button { page = item } label: {
                        HStack(spacing: 11) {
                            Image(systemName: item.symbol).font(.system(size: 14, weight: .medium)).frame(width: 22)
                            Text(item.title).font(.system(size: 13.5, weight: page == item ? .semibold : .regular))
                            Spacer()
                        }
                        .padding(.horizontal, 12).frame(height: 38)
                        .foregroundStyle(page == item ? Color.white : Color.primary)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(page == item ? Color.accentColor : Color.clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)

            Spacer()
            deviceChip.padding(12)
        }
    }

    // 左下角：連線狀態、電量、啟用開關。
    private var deviceChip: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(statusColor).frame(width: 8, height: 8)
                Text(shortStatus).font(.system(size: 12, weight: .medium))
                Spacer()
            }
            if let snapshot = model.snapshot, snapshot.batteryPercent >= 0 {
                HStack(spacing: 8) {
                    Image(systemName: batterySymbol(snapshot)).font(.system(size: 15))
                        .foregroundStyle(snapshot.batteryPercent <= 15 ? Color.red : Color.green)
                    Text("\(snapshot.batteryPercent)%").font(.system(size: 13, weight: .semibold)).monospacedDigit()
                    Text(snapshot.transport == "BOLT" ? "Logi Bolt" : "Bluetooth")
                        .font(.system(size: 11.5)).foregroundStyle(.secondary)
                    Spacer()
                }
            }
            Divider()
            Toggle(isOn: Binding(get: { model.enabled }, set: { model.setEnabled($0) })) {
                Text(model.enabled ? Lang.t("按鍵對應已啟用", "Mapping enabled") : Lang.t("已暫停", "Paused"))
                    .font(.system(size: 12))
            }
            .toggleStyle(.switch).controlSize(.small)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.05)))
    }

    private func batterySymbol(_ snapshot: DeviceSnapshot) -> String {
        if snapshot.charging { return "battery.100percent.bolt" }
        switch snapshot.batteryPercent {
        case 88...: return "battery.100percent"
        case 63...: return "battery.75percent"
        case 38...: return "battery.50percent"
        case 13...: return "battery.25percent"
        default: return "battery.0percent"
        }
    }

    private var statusColor: Color {
        if !model.enabled { return .orange }
        if case .ready = model.status { return .green }
        return .orange
    }

    private var shortStatus: String {
        if !model.enabled { return Lang.t("已暫停", "Paused") }
        switch model.status {
        case .ready: return Lang.t("滑鼠已就緒", "Mouse ready")
        case .searching: return Lang.t("尋找滑鼠中…", "Searching…")
        case .notFound: return Lang.t("未偵測到滑鼠", "No mouse found")
        case .needsInputMonitoring: return Lang.t("需要權限", "Permission needed")
        case .problem: return Lang.t("連線有問題", "Connection problem")
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(page.title).font(.system(size: 22, weight: .bold))
                Text(page.subtitle).font(.system(size: 12.5)).foregroundStyle(.secondary)
            }
            .padding(.top, 34).padding(.horizontal, 26).padding(.bottom, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    notices
                    switch page {
                    case .buttons: ButtonsPage(model: model)
                    case .ring: RingPage(model: model, page: $page)
                    case .device: DevicePage(model: model, page: $page)
                    case .haptics: HapticsPage(model: model)
                    case .switching: SwitchPage(model: model)
                    case .advanced: AdvancedPage(model: model)
                    }
                }
                .padding(.horizontal, 26).padding(.bottom, 22).padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder private var notices: some View {
        if model.status == .needsInputMonitoring {
            Banner(symbol: "lock.shield.fill",
                   text: Lang.t("需要「輸入監控」權限才能與滑鼠通訊（專用按鍵、電量、裝置設定）。",
                                "Input Monitoring permission is needed to talk to the mouse (special buttons, battery, device settings)."),
                   buttonTitle: Lang.t("開啟設定", "Open Settings")) { model.openInputMonitoringSettings() }
        }
        if !model.trusted {
            Banner(symbol: "lock.shield.fill",
                   text: Lang.t("需要「輔助使用」權限才能送出快捷鍵與攔截按鍵。",
                                "Accessibility permission is needed to send shortcuts and intercept buttons."),
                   buttonTitle: Lang.t("開啟設定", "Open Settings")) {
                model.requestAccessibility()
                model.openAccessibilitySettings()
            }
        }
        if model.optionsPlusRunning {
            Banner(symbol: "exclamationmark.triangle.fill",
                   text: Lang.t("Logi Options+ 正在執行：兩者會互相覆寫按鍵與裝置設定，建議擇一使用。",
                                "Logi Options+ is running: the two overwrite each other's button and device settings. Use only one."))
        }
        if case .problem(let text) = model.status {
            Banner(symbol: "exclamationmark.triangle.fill", text: text)
        }
    }
}

// MARK: - 動作選擇

struct ActionPicker: View {
    @Binding var value: ActionBinding
    @State private var recording = false
    @State private var editingTarget = false
    @State private var target = ""

    var body: some View {
        HStack(spacing: 6) {
            ActionPopUp(value: value, onChoose: choose).frame(maxWidth: .infinity).frame(height: 24)
            if value.action == .customShortcut {
                Button(Lang.t("錄製", "Record")) { recording = true }
            } else if value.action == .launch {
                Button(Lang.t("設定", "Set")) { target = value.param; editingTarget = true }
            }
        }
        .sheet(isPresented: $recording) {
            ShortcutSheet { param, label in
                value = ActionBinding(.customShortcut, param: param, label: label)
            }
        }
        .sheet(isPresented: $editingTarget) {
            LaunchSheet(target: $target) { value = ActionBinding(.launch, param: target) }
        }
    }

    private func choose(_ action: MappedAction) {
        switch action {
        case .customShortcut:
            if value.action != .customShortcut { value = ActionBinding(.customShortcut) }
            recording = true
        case .launch:
            target = value.action == .launch ? value.param : ""
            if value.action != .launch { value = ActionBinding(.launch) }
            editingTarget = true
        default:
            value = ActionBinding(action)
        }
    }
}

// 系統原生的彈出式選單：寬度可以撐滿整列，選項帶圖示並依類別分段。
struct ActionPopUp: NSViewRepresentable {
    let value: ActionBinding
    let onChoose: (MappedAction) -> Void

    final class Coordinator: NSObject {
        var onChoose: ((MappedAction) -> Void)?
        var current = MappedAction.passThrough
        weak var button: NSPopUpButton?

        @objc func picked(_ sender: NSPopUpButton) {
            guard let raw = sender.selectedItem?.representedObject as? String,
                  let action = MappedAction(rawValue: raw) else { return }
            // 自訂類的動作要等對話框確定才算數，先把顯示還原。
            if action == .customShortcut || action == .launch { select(current) }
            onChoose?(action)
        }

        func select(_ action: MappedAction) {
            guard let button, let index = button.itemArray.firstIndex(where: { ($0.representedObject as? String) == action.rawValue })
            else { return }
            button.selectItem(at: index)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.controlSize = .regular
        button.target = context.coordinator
        button.action = #selector(Coordinator.picked(_:))
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        context.coordinator.button = button
        let menu = NSMenu()
        menu.autoenablesItems = false
        for (index, group) in ActionCatalog.groups.enumerated() {
            if index > 0 { menu.addItem(.separator()) }
            menu.addItem(NSMenuItem.sectionHeader(title: group.title))
            for action in group.actions {
                let item = NSMenuItem(title: ActionCatalog.title(action), action: nil, keyEquivalent: "")
                item.representedObject = action.rawValue
                item.image = NSImage(systemSymbolName: ActionCatalog.symbol(action), accessibilityDescription: nil)
                menu.addItem(item)
            }
        }
        button.menu = menu
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.onChoose = onChoose
        context.coordinator.current = value.action
        // 自訂快捷鍵與開啟項目的列，顯示實際設定的內容。
        for item in button.itemArray {
            guard let raw = item.representedObject as? String, let action = MappedAction(rawValue: raw) else { continue }
            item.title = action == value.action ? value.title : ActionCatalog.title(action)
        }
        context.coordinator.select(value.action)
    }
}

struct ShortcutSheet: View {
    let done: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var label = ""
    @State private var param = ""

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "keyboard").font(.system(size: 26)).foregroundStyle(Color.accentColor)
            Text(Lang.t("按下要使用的組合鍵", "Press the key combination")).font(.headline)
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06))
                Text(label.isEmpty ? Lang.t("等待按鍵…", "Waiting…") : label)
                    .font(.system(size: 26, weight: .medium, design: .rounded))
                    .foregroundStyle(label.isEmpty ? .secondary : .primary)
                KeyCatcher { event in
                    label = Shortcut.label(event: event)
                    param = Shortcut.param(event: event)
                }
            }
            .frame(width: 300, height: 76)
            HStack {
                Button(Lang.t("取消", "Cancel")) { dismiss() }
                Button(Lang.t("確定", "OK")) { done(param, label); dismiss() }
                    .disabled(param.isEmpty).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
    }
}

// 接收鍵盤事件的隱形視圖。
struct KeyCatcher: NSViewRepresentable {
    let onKey: (NSEvent) -> Void

    final class Catcher: NSView {
        var onKey: ((NSEvent) -> Void)?
        override var acceptsFirstResponder: Bool { true }
        override func keyDown(with event: NSEvent) { onKey?(event) }
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            // 含 Command 的組合鍵會先走這裡；一樣當成錄到的按鍵。
            guard window?.firstResponder === self, event.type == .keyDown else { return false }
            onKey?(event)
            return true
        }
        override func viewDidMoveToWindow() {
            DispatchQueue.main.async { [weak self] in self?.window?.makeFirstResponder(self) }
        }
    }

    func makeNSView(context: Context) -> Catcher {
        let view = Catcher()
        view.onKey = onKey
        return view
    }

    func updateNSView(_ view: Catcher, context: Context) { view.onKey = onKey }
}

struct LaunchSheet: View {
    @Binding var target: String
    let done: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(Lang.t("要開啟的 App、檔案、資料夾或網址", "App, file, folder or URL to open")).font(.headline)
            HStack {
                TextField("/Applications/Safari.app  ·  https://…", text: $target).frame(width: 360)
                Button(Lang.t("選擇…", "Choose…")) { browse() }
            }
            HStack {
                Spacer()
                Button(Lang.t("取消", "Cancel")) { dismiss() }
                Button(Lang.t("確定", "OK")) { done(); dismiss() }
                    .disabled(target.trimmingCharacters(in: .whitespaces).isEmpty).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
    }

    private func browse() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK, let url = panel.url { target = url.path }
    }
}

// MARK: - 按鈕

struct ButtonsPage: View {
    @ObservedObject var model: AppModel
    @State private var highlight: Int?

    var body: some View {
        Card {
            HStack(alignment: .center, spacing: 22) {
                MouseDiagram(highlight: $highlight).frame(width: 286, height: 360)
                VStack(spacing: 0) {
                    ForEach(Array(MouseInput.allCases.enumerated()), id: \.offset) { index, input in
                        HStack(spacing: 12) {
                            NumberBadge(text: "\(index + 1)", active: highlight == index)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(input.title).font(.system(size: 13))
                                Text(input.hint).font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            .frame(width: 138, alignment: .leading)
                            ActionPicker(value: Binding(get: { model.mapping(input) }, set: { model.setMapping(input, $0) }))
                        }
                        .padding(.vertical, 9).padding(.horizontal, 8)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(highlight == index ? Color.accentColor.opacity(0.10) : Color.clear))
                        .contentShape(Rectangle())
                        .onHover { inside in
                            if inside { highlight = index } else if highlight == index { highlight = nil }
                        }
                        if index < MouseInput.allCases.count - 1 { Divider().padding(.leading, 42) }
                    }
                }
            }
        }
        Text(Lang.t("側鍵與拇指滾輪的對應會套用到所有滑鼠（系統分不出事件來自哪一隻）。示意圖上的位置僅供參考。",
                    "Side-button and thumb-wheel mappings apply to every mouse (the system cannot tell them apart). Positions in the picture are indicative."))
            .font(.system(size: 11.5)).foregroundStyle(.secondary).padding(.horizontal, 4)
    }
}

// MARK: - 手勢與圓環

struct RingPreview: NSViewRepresentable {
    let slots: [ActionBinding]
    let selected: Int
    let bubbles: Bool
    let bubbleScale: CGFloat
    let light: Bool

    func makeNSView(context: Context) -> RingView {
        let view = RingView(frame: .zero)
        view.showNumbers = true
        view.slots = slots
        view.bubbles = bubbles
        view.bubbleScale = bubbleScale
        view.light = light
        return view
    }

    func updateNSView(_ view: RingView, context: Context) {
        view.slots = slots
        view.selected = selected
        view.bubbles = bubbles
        view.bubbleScale = bubbleScale
        view.light = light
    }
}

struct RingPage: View {
    @ObservedObject var model: AppModel
    @Binding var page: Page
    @State private var highlight: Int?
    private let arrows = ["arrow.up", "arrow.right", "arrow.down", "arrow.left"]

    private var directionNames: [String] {
        [Lang.t("向上", "Up"), Lang.t("向右", "Right"), Lang.t("向下", "Down"), Lang.t("向左", "Left")]
    }

    var body: some View {
        Card(title: "Actions Ring", subtitle: Lang.t("按 Actions Ring 鍵叫出八方向圓環，每一格都可以自訂", "Press the Actions Ring button for an eight-way ring; every slice is customizable")) {
            SettingRow(title: Lang.t("顯示八方向圓環", "Show the eight-way ring"),
                       subtitle: Lang.t("按住顯示、移動選擇、放開執行；在中心放開取消", "Hold to show, move to choose, release to run; release at the centre to cancel")) {
                Toggle("", isOn: $model.config.ringMode).toggleStyle(.switch).labelsHidden()
            }
            SettingRow(title: Lang.t("改用點選（不必按住）", "Click to choose (no holding)"),
                       subtitle: Lang.t("按一下顯示，再點選功能；點中心、圓環外、右鍵或再按一次取消", "Press once to show, then click a slice; centre, outside, right-click or another press cancels")) {
                Toggle("", isOn: $model.config.ringClick).toggleStyle(.switch).labelsHidden()
            }
            .disabled(!model.config.ringMode)
            SettingRow(title: Lang.t("滑過選項時震動", "Haptic tick on each slice"),
                       subtitle: model.config.ringHaptic
                        ? Lang.t("已開啟・", "On · ") + HapticWave.title(model.config.ringHapticWave) + Lang.t("；在「觸覺回饋」頁調整", "; adjust on the Haptics page")
                        : Lang.t("已關閉；在「觸覺回饋」頁調整", "Off; adjust on the Haptics page")) {
                Button(Lang.t("觸覺回饋設定…", "Haptics…")) { page = .haptics }
            }
            Divider()
            HStack(alignment: .center, spacing: 20) {
                // 預覽會跟著大小與透明度設定變化；大小 100% 時剛好填滿這個區域。
                RingPreview(slots: model.config.ring, selected: highlight ?? -1, bubbles: model.config.ringStyle == "bubble",
                            bubbleScale: CGFloat(model.config.bubbleScaleFactor), light: model.config.ringColor == "light")
                    .frame(width: 300 * model.config.ringScaleFactor / Config.maxRingScaleFactor,
                           height: 300 * model.config.ringScaleFactor / Config.maxRingScaleFactor)
                    .opacity(model.config.ringOpacity)
                    .frame(width: 300, height: 300)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.04)))
                VStack(spacing: 5) {
                    ForEach(0..<8, id: \.self) { index in
                        HStack(spacing: 10) {
                            NumberBadge(text: "\(index + 1)", active: highlight == index)
                            ActionPicker(value: $model.config.ring[index])
                        }
                        .padding(.vertical, 3).padding(.horizontal, 6)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(highlight == index ? Color.accentColor.opacity(0.10) : Color.clear))
                        .onHover { inside in
                            if inside { highlight = index } else if highlight == index { highlight = nil }
                        }
                    }
                }
            }
            .opacity(model.config.ringMode ? 1 : 0.45)
            Divider()
            SettingRow(title: Lang.t("樣式", "Style"),
                       subtitle: Lang.t("泡泡：只顯示圓形圖示，游標移過去才顯示名稱", "Bubbles: round icons only; the name appears when the pointer is over one")) {
                Picker("", selection: $model.config.ringStyle) {
                    Text(Lang.t("分格圓環", "Ring")).tag("ring")
                    Text(Lang.t("泡泡", "Bubbles")).tag("bubble")
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 220)
            }
            SettingRow(title: Lang.t("顏色", "Color"),
                       subtitle: Lang.t("選到的格子一律用強調色", "The selected slice always uses the accent color")) {
                Picker("", selection: $model.config.ringColor) {
                    Text(Lang.t("深色", "Dark")).tag("dark")
                    Text(Lang.t("白色", "White")).tag("light")
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 220)
            }
            HStack(spacing: 14) {
                Text(Lang.t("整體大小", "Overall size")).font(.system(size: 13)).frame(width: 86, alignment: .leading)
                Slider(value: $model.config.ringSize, in: 0...100)
                Text(verbatim: "\(Int(model.config.ringSize.rounded()))%").font(.system(size: 13, weight: .semibold))
                    .monospacedDigit().frame(width: 50, alignment: .trailing)
            }
            HStack(spacing: 14) {
                Text(Lang.t("泡泡大小", "Bubble size")).font(.system(size: 13)).frame(width: 86, alignment: .leading)
                Slider(value: $model.config.bubbleSize, in: 0...100)
                Text(verbatim: "\(Int(model.config.bubbleSize.rounded()))%").font(.system(size: 13, weight: .semibold))
                    .monospacedDigit().frame(width: 50, alignment: .trailing)
            }
            .disabled(model.config.ringStyle != "bubble").opacity(model.config.ringStyle == "bubble" ? 1 : 0.45)
            HStack(spacing: 14) {
                Text(Lang.t("不透明度", "Opacity")).font(.system(size: 13)).frame(width: 86, alignment: .leading)
                Slider(value: $model.config.ringOpacity, in: 0.4...1.0)
                Text(verbatim: "\(Int((model.config.ringOpacity * 100).rounded()))%").font(.system(size: 13, weight: .semibold))
                    .monospacedDigit().frame(width: 50, alignment: .trailing)
            }
        }

        Card(title: Lang.t("拇指四向手勢", "Thumb gestures"), subtitle: Lang.t("按住拇指手勢鍵並往一個方向滑動", "Hold the gesture button and swipe in a direction")) {
            SettingRow(title: Lang.t("啟用四向手勢", "Enable four-way gestures"),
                       subtitle: Lang.t("關閉時，按一下手勢鍵會執行「按鈕」頁設定的動作", "When off, a click runs the action chosen on the Buttons page")) {
                Toggle("", isOn: $model.config.gestureMode).toggleStyle(.switch).labelsHidden()
            }
            Divider()
            Grid(horizontalSpacing: 18, verticalSpacing: 8) {
                ForEach(0..<2, id: \.self) { row in
                    GridRow {
                        ForEach(0..<2, id: \.self) { column in
                            let index = row * 2 + column
                            HStack(spacing: 8) {
                                Image(systemName: arrows[index]).font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.accentColor).frame(width: 18)
                                Text(directionNames[index]).font(.system(size: 12.5)).frame(width: 42, alignment: .leading)
                                ActionPicker(value: $model.config.gestures[index])
                            }
                        }
                    }
                }
            }
            .disabled(!model.config.gestureMode)
            .opacity(model.config.gestureMode ? 1 : 0.45)
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 14) {
                    Text(Lang.t("手勢靈敏度", "Sensitivity")).font(.system(size: 13)).frame(width: 86, alignment: .leading)
                    Text(Lang.t("低", "Low")).font(.system(size: 11.5)).foregroundStyle(.secondary)
                    Slider(value: $model.config.gestureSensitivity, in: 0...100) { editing in
                        if !editing { model.config.gestureSensitivity = (model.config.gestureSensitivity / 5).rounded() * 5 }
                    }
                    Text(Lang.t("高", "High")).font(.system(size: 11.5)).foregroundStyle(.secondary)
                    Text(verbatim: "\(Int(model.config.gestureSensitivity.rounded()))%").font(.system(size: 13, weight: .semibold))
                        .monospacedDigit().frame(width: 50, alignment: .trailing)
                }
                Text(Lang.t("越高，滑動越短的距離就會判定方向；目前約 \(Int((65 * model.config.gestureDistanceFactor).rounded())) pt。50% 是原本的距離",
                            "Higher means a shorter swipe picks a direction; currently about \(Int((65 * model.config.gestureDistanceFactor).rounded())) pt. 50% is the original distance"))
                    .font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .disabled(!model.config.gestureMode)
            .opacity(model.config.gestureMode ? 1 : 0.45)
        }
    }
}

// MARK: - 指標與滾輪

struct StatTile: View {
    let symbol: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 17)).foregroundStyle(Color.accentColor)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.accentColor.opacity(0.12)))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
                Text(value).font(.system(size: 13.5, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.07)))
    }
}

struct DevicePage: View {
    @ObservedObject var model: AppModel
    @Binding var page: Page
    @State private var dpi = 1000.0
    @State private var precisionDpi = 400.0
    @State private var freeSpin = false
    @State private var threshold = 12.0
    @State private var autoShift = true
    @State private var inverted = false
    @State private var loaded = false

    // 可以「按住」的按鍵。拇指手勢鍵與 Actions Ring 鍵要在手勢／圓環關閉時才是單純的按鍵。
    private var precisionInputs: [MouseInput] {
        var inputs: [MouseInput] = [.middle, .back, .forward]
        if !model.config.gestureMode || model.precisionTrigger == .gesture { inputs.append(.gesture) }
        if !model.config.ringMode || model.precisionTrigger == .actionRing { inputs.append(.actionRing) }
        return inputs
    }

    var body: some View {
        Group {
            if let snapshot = model.snapshot {
                HStack(spacing: 12) {
                    StatTile(symbol: snapshot.transport == "BOLT" ? "dot.radiowaves.left.and.right" : "wave.3.right",
                             title: Lang.t("連線", "Connection"), value: snapshot.transport == "BOLT" ? "Logi Bolt" : "Bluetooth")
                    StatTile(symbol: "battery.75percent", title: Lang.t("電量", "Battery"),
                             value: model.batteryText.isEmpty ? "—" : model.batteryText)
                    StatTile(symbol: "cpu", title: Lang.t("韌體", "Firmware"), value: snapshot.firmware.isEmpty ? "—" : snapshot.firmware)
                }

                if snapshot.dpi > 0 {
                    let step = Double(max(snapshot.dpiStep, 50))
                    let lowest = Double(max(snapshot.dpiMin, 200))
                    let highest = Double(max(snapshot.dpiMax, 4000))
                    Card(title: Lang.t("指標速度", "Pointer speed"),
                         subtitle: Lang.t("範圍", "Range") + " \(Int(lowest))–\(Int(highest)) DPI") {
                        HStack(spacing: 14) {
                            Image(systemName: "tortoise").foregroundStyle(.secondary)
                            // 不用 step：有刻度的滑桿會畫出上百條刻度線。改在套用時對齊步進。
                            Slider(value: $dpi, in: lowest...highest) { editing in
                                if !editing {
                                    dpi = snap(dpi, step: step)
                                    model.applyDpi(Int(dpi))
                                }
                            }
                            Image(systemName: "hare").foregroundStyle(.secondary)
                            Text(verbatim: "\(Int(snap(dpi, step: step))) DPI").font(.system(size: 13, weight: .semibold)).monospacedDigit()
                                .frame(width: 84, alignment: .trailing)
                        }
                        .disabled(model.precisionActive).opacity(model.precisionActive ? 0.45 : 1)

                        Divider()
                        SettingRow(title: Lang.t("精準模式", "Precision mode"),
                                   subtitle: Lang.t("按住觸發按鍵時暫時降到較低的速度，放開就恢復；適合修圖、對齊等精細操作",
                                                    "Hold the trigger to drop to a slower speed for detailed work; release to go back")) {
                            if model.precisionActive {
                                Text(Lang.t("使用中", "Active"))
                                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                                    .padding(.horizontal, 9).padding(.vertical, 3)
                                    .background(Capsule().fill(Color.accentColor))
                            }
                        }
                        HStack(spacing: 14) {
                            Text(Lang.t("精準速度", "Precision speed")).font(.system(size: 13)).frame(width: 110, alignment: .leading)
                            Slider(value: $precisionDpi, in: lowest...max(lowest + step, dpi)) { editing in
                                if !editing {
                                    precisionDpi = snap(precisionDpi, step: step)
                                    model.config.precisionDpi = Int(precisionDpi)
                                }
                            }
                            Text(verbatim: "\(Int(snap(precisionDpi, step: step))) DPI").font(.system(size: 13, weight: .semibold)).monospacedDigit()
                                .frame(width: 84, alignment: .trailing)
                        }
                        SettingRow(title: Lang.t("觸發按鍵", "Trigger"),
                                   subtitle: model.config.gestureMode || model.config.ringMode
                                    ? Lang.t("按住這顆鍵就進入精準模式；手勢鍵與圓環鍵要先關閉手勢或圓環才能選",
                                             "Hold it for precision mode; the gesture and ring buttons need their gestures or ring off")
                                    : Lang.t("按住這顆鍵就進入精準模式，放開即恢復", "Hold it for precision mode; release to go back")) {
                            Picker("", selection: Binding(get: { model.precisionTrigger?.rawValue ?? "" },
                                                          set: { model.setPrecisionTrigger(MouseInput(rawValue: $0)) })) {
                                Text(Lang.t("不使用", "None")).tag("")
                                ForEach(precisionInputs, id: \.self) { input in Text(input.title).tag(input.rawValue) }
                            }
                            .labelsHidden().frame(width: 200)
                        }
                    }
                }

                if snapshot.smartShiftPresent || snapshot.wheelInvertPresent {
                    Card(title: Lang.t("滾輪", "Wheel")) {
                        if snapshot.wheelInvertPresent {
                            SettingRow(title: Lang.t("捲動方向", "Scroll direction")) {
                                Picker("", selection: $inverted) {
                                    Text(Lang.t("自然", "Natural")).tag(false)
                                    Text(Lang.t("標準", "Standard")).tag(true)
                                }
                                .pickerStyle(.segmented).labelsHidden().frame(width: 220)
                                .onChange(of: inverted) { if loaded { applyInvert() } }
                            }
                        }
                        if snapshot.smartShiftPresent {
                            if snapshot.wheelInvertPresent { Divider() }
                            SettingRow(title: Lang.t("滾輪模式", "Wheel mode"),
                                       subtitle: Lang.t("段落：一格一格；自由滾動：無阻力。也可以把「切換段落／自由滾動」指派給按鍵或圓環",
                                                        "Ratchet: step by step; free spin: no resistance. \"Toggle ratchet / free spin\" can also go on a button or the ring")) {
                                Picker("", selection: $freeSpin) {
                                    Text(Lang.t("段落", "Ratchet")).tag(false)
                                    Text(Lang.t("自由滾動", "Free spin")).tag(true)
                                }
                                .pickerStyle(.segmented).labelsHidden().frame(width: 220)
                                .onChange(of: freeSpin) { if loaded { applySmartShift() } }
                            }
                            Divider()
                            SettingRow(title: "SmartShift", subtitle: Lang.t("快速滾動時自動切換為自由滾動", "Switch to free spin automatically when scrolling fast")) {
                                Toggle("", isOn: $autoShift).toggleStyle(.switch).labelsHidden()
                                    .onChange(of: autoShift) { if loaded { applySmartShift() } }
                            }
                            HStack(spacing: 14) {
                                Text(Lang.t("靈敏度", "Sensitivity")).font(.system(size: 12.5)).foregroundStyle(.secondary)
                                Slider(value: $threshold, in: 1...50) { editing in
                                    if !editing { threshold = snap(threshold, step: 1); applySmartShift() }
                                }
                                Text("\(Int(threshold.rounded()))").font(.system(size: 13, weight: .semibold)).monospacedDigit()
                                    .frame(width: 34, alignment: .trailing)
                            }
                            .disabled(!autoShift).opacity(autoShift ? 1 : 0.45)
                        }
                    }
                }
            } else {
                Card {
                    HStack(spacing: 12) {
                        Image(systemName: "computermouse").font(.system(size: 24)).foregroundStyle(.secondary)
                        Text(Lang.t("尚未連上滑鼠，無法讀取裝置設定。", "The mouse is not connected, so device settings cannot be read."))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Card(title: Lang.t("切換提示", "On-screen feedback")) {
                SettingRow(title: Lang.t("在畫面上顯示切換提示", "Show a hint when modes change"),
                           subtitle: Lang.t("精準模式或滾動模式切換時，在螢幕下方短暫顯示目前狀態。震動在「觸覺回饋」頁設定",
                                            "Briefly shows the new state at the bottom of the screen; the matching tap is set on the Haptics page")) {
                    Toggle("", isOn: $model.config.showModeHUD).toggleStyle(.switch).labelsHidden()
                }
            }

            HStack {
                Text(model.deviceMessage.isEmpty
                     ? Lang.t("數值由滑鼠確認後才會保存；滑鼠重新連線後會自動再套用。", "Values are saved once the mouse confirms them, and re-applied after it reconnects.")
                     : model.deviceMessage)
                    .font(.system(size: 11.5)).foregroundStyle(.secondary)
                Spacer()
                Button(Lang.t("重新讀取", "Reload")) { loaded = false; model.refreshDevice() }.controlSize(.small)
            }
            .padding(.horizontal, 4)
        }
        .onAppear { loaded = false; model.refreshDevice(); load() }
        .onChange(of: model.snapshot?.raw) { load() }
    }

    // 把滑鼠回報的值放進控制項。loaded 用來分辨「程式填值」與「使用者操作」。
    private func load() {
        guard let snapshot = model.snapshot else { return }
        loaded = false
        // 精準模式開著時滑鼠回報的是精準速度，滑桿要顯示正常速度。
        if model.precisionActive, let saved = model.config.device.dpi {
            dpi = Double(saved)
        } else if snapshot.dpi > 0 {
            dpi = Double(snapshot.dpi)
        }
        precisionDpi = Double(model.config.precisionDpi)
        freeSpin = snapshot.wheelMode == 1
        autoShift = snapshot.smartShift != 255 && snapshot.smartShift != 0
        if snapshot.smartShift >= 1 && snapshot.smartShift <= 50 { threshold = Double(snapshot.smartShift) }
        inverted = snapshot.wheelInverted
        DispatchQueue.main.async { loaded = true }
    }

    private func snap(_ value: Double, step: Double) -> Double { (value / step).rounded() * step }

    private func applySmartShift() {
        let mode = freeSpin ? 1 : 2
        let value = autoShift ? Int(threshold) : 255
        model.applyDevice("SmartShift", { $0.setSmartShift(mode: mode, threshold: value) }) {
            $0.wheelMode = mode
            $0.smartShift = value
        }
    }

    private func applyInvert() {
        let value = inverted
        model.applyDevice(Lang.t("捲動方向", "Scroll direction"), { $0.setWheelInvert(value) }) { $0.wheelInvert = value }
    }
}

// MARK: - 觸覺回饋

struct HapticsPage: View {
    @ObservedObject var model: AppModel
    @State private var haptic = 60.0
    @State private var loaded = false

    var body: some View {
        Group {
            Card(title: Lang.t("觸覺強度", "Strength"),
                 subtitle: Lang.t("滑鼠本身的震動強度。拉到最左邊為關閉，下方所有震動都會跟著停用",
                                  "The mouse's own haptic strength. Fully left turns it off, and every tap below with it")) {
                if let snapshot = model.snapshot, snapshot.hapticPresent {
                    HStack(spacing: 14) {
                        Image(systemName: "iphone.radiowaves.left.and.right").foregroundStyle(.secondary)
                        Slider(value: $haptic, in: 0...100) { editing in
                            if !editing { haptic = snap(haptic); applyHaptic() }
                        }
                        Text(snap(haptic) == 0 ? Lang.t("關閉", "Off") : "\(Int(snap(haptic)))")
                            .font(.system(size: 13, weight: .semibold)).monospacedDigit().frame(width: 84, alignment: .trailing)
                    }
                } else {
                    HStack(spacing: 12) {
                        Image(systemName: "computermouse").font(.system(size: 20)).foregroundStyle(.secondary)
                        Text(Lang.t("尚未連上滑鼠，無法讀取觸覺強度。下方的設定仍可先調整。",
                                    "The mouse is not connected, so the strength cannot be read. The settings below can still be changed."))
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
                Divider()
                SettingRow(title: Lang.t("電量低時暫停震動", "Pause haptics on low battery"),
                           subtitle: Lang.t("電量在 \(model.config.lowBatteryLevel)% 以下且沒有充電時，下方的震動都不播放（門檻在「進階」頁的「電池」）",
                                            "Below \(model.config.lowBatteryLevel)% and not charging, none of the taps below play (threshold under Battery on the Advanced page)")) {
                    Toggle("", isOn: $model.config.lowBatteryHapticPause).toggleStyle(.switch).labelsHidden()
                }
            }
            if model.hapticsPaused {
                Banner(symbol: "battery.25percent",
                       text: Lang.t("滑鼠電量低（\(model.snapshot?.batteryPercent ?? 0)%），震動已暫停；充電後自動恢復。「試震」按鈕仍會震。",
                                    "The mouse battery is low (\(model.snapshot?.batteryPercent ?? 0)%), so haptics are paused until it charges. The Try buttons still play."))
            }

            Card(title: Lang.t("震動時機", "When to tap"),
                 subtitle: Lang.t("選擇哪些操作要讓滑鼠輕震一下；每一種都可以挑不同的波形，選了會立刻在滑鼠上震一下",
                                  "Choose which moments make the mouse tap. Each can use its own waveform; picking one plays it on the mouse")) {
                HapticEventRow(model: model, symbol: "circle.hexagongrid",
                               title: Lang.t("Actions Ring 滑過選項", "Actions Ring slices"),
                               detail: Lang.t("游標移到圓環的另一格時", "As the pointer enters another slice"),
                               isOn: $model.config.ringHaptic, wave: $model.config.ringHapticWave)
                Divider()
                HapticEventRow(model: model, symbol: "hand.draw",
                               title: Lang.t("手勢方向確定", "Gesture recognized"),
                               detail: Lang.t("按住手勢鍵滑動、方向判定完成時", "When a thumb-gesture direction is locked in"),
                               isOn: $model.config.gestureHaptic, wave: $model.config.gestureHapticWave)
                Divider()
                HapticEventRow(model: model, symbol: "rectangle.on.rectangle",
                               title: Lang.t("切換電腦", "Computer switch"),
                               detail: Lang.t("MX Flow 或「切換到頻道」動作讓滑鼠離開之前", "Right before MX Flow or a Switch-to-channel action moves the mouse away"),
                               isOn: $model.config.flowHaptic, wave: $model.config.flowHapticWave)
                Divider()
                HapticEventRow(model: model, symbol: "scope",
                               title: Lang.t("模式切換", "Mode changes"),
                               detail: Lang.t("精準模式開關、段落／自由滾動切換時", "Precision mode on or off, ratchet / free spin"),
                               isOn: $model.config.modeHaptic, wave: $model.config.modeHapticWave)
            }

            HStack {
                Text(model.deviceMessage.isEmpty
                     ? Lang.t("震動由滑鼠播放，強度依上方設定；滑鼠沒有連上時不會震。", "Taps are played by the mouse at the strength above, and only while it is connected.")
                     : model.deviceMessage)
                    .font(.system(size: 11.5)).foregroundStyle(.secondary)
                Spacer()
                Button(Lang.t("重新讀取", "Reload")) { loaded = false; model.refreshDevice() }.controlSize(.small)
            }
            .padding(.horizontal, 4)
        }
        .onAppear { loaded = false; model.refreshDevice(); load() }
        .onChange(of: model.snapshot?.raw) { load() }
    }

    private func load() {
        guard let snapshot = model.snapshot else { return }
        loaded = false
        haptic = Double(snapshot.hapticLevel)
        DispatchQueue.main.async { loaded = true }
    }

    private func snap(_ value: Double) -> Double { (value / 5).rounded() * 5 }

    private func applyHaptic() {
        let value = Int(haptic)
        model.applyDevice(Lang.t("觸覺強度", "Haptic strength"), { $0.setHaptic(value) }) { $0.haptic = value }
    }
}

// 一種震動時機：圖示、名稱與說明，右邊是波形、試震與開關。
struct HapticEventRow: View {
    @ObservedObject var model: AppModel
    let symbol: String
    let title: String
    let detail: String
    @Binding var isOn: Bool
    @Binding var wave: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 15)).foregroundStyle(Color.accentColor)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.accentColor.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13))
                Text(detail).font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Group {
                Picker("", selection: $wave) {
                    ForEach(HapticWave.all) { Text($0.title).tag($0.id) }
                }
                .labelsHidden().frame(width: 140)
                Button(Lang.t("試震", "Try")) { model.hidpp.playHaptic(UInt8(clamping: wave)) }
            }
            .disabled(!isOn).opacity(isOn ? 1 : 0.45)
            Toggle("", isOn: $isOn).toggleStyle(.switch).labelsHidden()
        }
        .onChange(of: wave) { model.hidpp.playHaptic(UInt8(clamping: wave)) }
    }
}

// MARK: - 進階

// MARK: - 切換電腦

struct SwitchPage: View {
    @ObservedObject var model: AppModel

    private var ready: Bool {
        if case .ready = model.status { return true }
        return false
    }

    // 還沒讀到頻道時（滑鼠不在線）先列出三個，讓設定仍然看得到。
    private var channels: [Int] { model.hosts.isEmpty ? [0, 1, 2] : model.hosts.map(\.index) }

    var body: some View {
        Card(title: "MX Flow",
             subtitle: Lang.t("游標貼著邊緣並持續往外推，滑鼠就切到指定的 Easy-Switch 頻道",
                              "Keep pushing the pointer against an edge and the mouse moves to the chosen Easy-Switch channel")) {
            SettingRow(title: Lang.t("啟用 MX Flow", "Enable MX Flow"),
                       subtitle: Lang.t("拖曳中、圓環或手勢進行中不會切換", "Never switches while dragging or while the ring or a gesture is active")) {
                Toggle("", isOn: $model.config.edgeSwitch.enabled).toggleStyle(.switch).labelsHidden()
            }
            Divider()
            VStack(spacing: 8) {
                ForEach(ScreenEdge.allCases, id: \.self) { edge in
                    HStack(spacing: 10) {
                        Image(systemName: edge.symbol).font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.accentColor).frame(width: 22)
                        Text(edge.title).font(.system(size: 13)).frame(width: 90, alignment: .leading)
                        Spacer(minLength: 8)
                        Picker("", selection: Binding(get: { model.config.edgeSwitch.target(edge) ?? -1 },
                                                      set: { model.setEdgeTarget(edge, $0 < 0 ? nil : $0) })) {
                            Text(Lang.t("不切換", "Off")).tag(-1)
                            ForEach(channels, id: \.self) { index in
                                Text(model.hostTitle(index) + (index == model.currentHost ? Lang.t("（這台電腦）", " (this computer)") : ""))
                                    .tag(index)
                            }
                        }
                        .labelsHidden().frame(width: 300)
                    }
                }
            }
            .disabled(!model.config.edgeSwitch.enabled).opacity(model.config.edgeSwitch.enabled ? 1 : 0.45)
            Text(model.displayCount > 1
                 ? Lang.t("偵測到 \(model.displayCount) 個螢幕：只有最外側螢幕的外緣會觸發，螢幕之間相接的邊與角落不會。",
                          "\(model.displayCount) displays detected: only the outer edge of the outermost display triggers; edges between displays and corners never do.")
                 : Lang.t("角落不會觸發。接上多個螢幕時，只有最外側螢幕的外緣會觸發。",
                          "Corners never trigger. With several displays, only the outer edge of the outermost display triggers."))
                .font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Divider()
            HStack(spacing: 14) {
                Text(Lang.t("觸發時間", "Trigger time")).font(.system(size: 13)).frame(width: 86, alignment: .leading)
                Slider(value: Binding(get: { model.config.edgeSwitch.dwell },
                                      set: { model.config.edgeSwitch.dwell = ($0 * 10).rounded() / 10 }),
                       in: EdgeSwitchSettings.dwellRange)
                Text(verbatim: String(format: "%.1f ", model.config.edgeSwitch.dwell) + Lang.t("秒", "s"))
                    .font(.system(size: 13, weight: .semibold)).monospacedDigit().frame(width: 60, alignment: .trailing)
            }
            .disabled(!model.config.edgeSwitch.enabled).opacity(model.config.edgeSwitch.enabled ? 1 : 0.45)
            SettingRow(title: Lang.t("要按住按鍵才切換", "Require a held key"),
                       subtitle: Lang.t("按住選定的鍵再把游標推到邊緣才會切換。選滑鼠按鍵時，它原本的動作改在放開時執行",
                                        "Hold the chosen key while pushing against the edge. A mouse button chosen here runs its own action on release instead")) {
                Picker("", selection: $model.config.edgeSwitch.modifier) {
                    Text(EdgeSwitchSettings.modifierTitle("none")).tag("none")
                    Section(Lang.t("鍵盤", "Keyboard")) {
                        ForEach(EdgeSwitchSettings.keyboardModifiers, id: \.self) { name in
                            Text(EdgeSwitchSettings.modifierTitle(name)).tag(name)
                        }
                    }
                    Section(Lang.t("滑鼠", "Mouse")) {
                        ForEach(EdgeSwitchSettings.mouseModifiers, id: \.self) { input in
                            Text(input.title).tag(input.rawValue)
                        }
                    }
                }
                .labelsHidden().frame(width: 200)
            }
            .disabled(!model.config.edgeSwitch.enabled).opacity(model.config.edgeSwitch.enabled ? 1 : 0.45)
            SettingRow(title: Lang.t("切回來時把游標移到邊緣", "Place the pointer at the edge on return"),
                       subtitle: Lang.t("只設定一個邊緣時有效；滑鼠重新連上這台電腦時游標會出現在那一側",
                                        "Works when exactly one edge is set; the pointer appears on that side when the mouse reconnects")) {
                Toggle("", isOn: $model.config.edgeSwitch.placeCursor).toggleStyle(.switch).labelsHidden()
            }
            .disabled(!model.config.edgeSwitch.enabled).opacity(model.config.edgeSwitch.enabled ? 1 : 0.45)
        }
        .onAppear { model.refreshHosts() }

        Card(title: Lang.t("Easy-Switch 頻道", "Easy-Switch channels"),
             subtitle: Lang.t("滑鼠記錄的三個連線對象；名稱由各電腦上的軟體寫入，可能是空的或舊的",
                              "The three hosts stored on the mouse; names are written by software on each computer and may be empty or stale")) {
            if model.hosts.isEmpty {
                Text(Lang.t("滑鼠連上後會顯示頻道。", "Channels appear once the mouse is connected."))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            ForEach(model.hosts, id: \.index) { host in
                HStack(spacing: 10) {
                    NumberBadge(text: "\(host.index + 1)", active: host.index == model.currentHost)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(host.name.isEmpty ? Lang.t("（沒有名稱）", "(no name)") : host.name).font(.system(size: 13))
                        Text([host.busName, host.paired ? "" : Lang.t("未配對", "Not paired"),
                              host.index == model.currentHost ? Lang.t("目前使用中", "In use now") : ""]
                            .filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.system(size: 11.5)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(Lang.t("切換過去", "Switch")) { model.switchHost(host.index, reason: "manual") }
                        .controlSize(.small).disabled(host.index == model.currentHost || !host.paired || !ready)
                }
            }
            Text(Lang.t("切過去之後，另一台電腦也要執行本程式並設定邊緣，才能用同樣方式切回來；否則請按滑鼠底部的 Easy-Switch 鍵。不會傳送剪貼簿或檔案，鍵盤也不會跟著切換。",
                        "To come back the same way, the other computer must also run this app with an edge set; otherwise press the Easy-Switch button under the mouse. No clipboard or files are transferred, and the keyboard does not follow."))
                .font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    var buttonTitle = Lang.t("開啟設定", "Open Settings")
    let action: () -> Void

    var body: some View {
        SettingRow(title: title, subtitle: detail) {
            if granted {
                Label(Lang.t("已允許", "Granted"), systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(.green)
            } else {
                Button(buttonTitle, action: action)
            }
        }
    }
}

struct AdvancedPage: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Card(title: Lang.t("一般", "General")) {
            SettingRow(title: Lang.t("啟用按鍵對應", "Enable button mapping"),
                       subtitle: Lang.t("關閉時所有按鍵恢復原本功能", "When off, every button behaves normally")) {
                Toggle("", isOn: Binding(get: { model.enabled }, set: { model.setEnabled($0) })).toggleStyle(.switch).labelsHidden()
            }
            Divider()
            SettingRow(title: Lang.t("登入時自動啟動", "Launch at login"),
                       subtitle: Lang.t("在選單列常駐，不顯示 Dock 圖示", "Lives in the menu bar with no Dock icon")) {
                Toggle("", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) })).toggleStyle(.switch).labelsHidden()
            }
            Divider()
            SettingRow(title: Lang.t("介面語言", "Language"), subtitle: Lang.t("重新啟動程式後生效", "Takes effect after restarting the app")) {
                Picker("", selection: $model.config.language) {
                    Text(Lang.t("跟隨系統", "System")).tag("Auto")
                    Text("繁體中文").tag("zh")
                    Text("English").tag("en")
                }
                .labelsHidden().frame(width: 150)
            }
        }

        Card(title: Lang.t("電池", "Battery"),
             subtitle: Lang.t("電量由滑鼠回報；低於門檻且沒有在充電時才算電量低", "Reported by the mouse; low means below the threshold while not charging")) {
            SettingRow(title: Lang.t("低電量提醒", "Low-battery alert"),
                       subtitle: Lang.t("電量降到門檻時發出一次系統通知；充電後再降下來才會再提醒",
                                        "Sends one system notification when the level drops to the threshold; it alerts again only after charging")) {
                Toggle("", isOn: $model.config.lowBatteryAlert).toggleStyle(.switch).labelsHidden()
                    .onChange(of: model.config.lowBatteryAlert) { model.batterySettingsChanged() }
            }
            Divider()
            SettingRow(title: Lang.t("電量低的門檻", "Low-battery threshold"),
                       subtitle: Lang.t("也用於「觸覺回饋」頁的低電量暫停震動", "Also used by the low-battery haptics pause on the Haptics page")) {
                Picker("", selection: $model.config.lowBatteryLevel) {
                    ForEach(Config.lowBatteryLevels, id: \.self) { Text(verbatim: "\($0)%").tag($0) }
                }
                .labelsHidden().frame(width: 120)
                .onChange(of: model.config.lowBatteryLevel) { model.batterySettingsChanged() }
            }
        }

        Card(title: Lang.t("權限", "Permissions"), subtitle: Lang.t("輸入監控與輔助使用在「系統設定 → 隱私權與安全性」，通知在「系統設定 → 通知」",
                                                                   "In System Settings: the first two under Privacy & Security, notifications under Notifications")) {
            PermissionRow(title: Lang.t("輸入監控", "Input Monitoring"),
                          detail: Lang.t("與滑鼠通訊：專用按鍵、電量、裝置設定", "Talks to the mouse: special buttons, battery, device settings"),
                          granted: model.status != .needsInputMonitoring) { model.openInputMonitoringSettings() }
            Divider()
            PermissionRow(title: Lang.t("輔助使用", "Accessibility"),
                          detail: Lang.t("送出快捷鍵、攔截側鍵與拇指滾輪", "Sends shortcuts and intercepts side buttons and the thumb wheel"),
                          granted: model.trusted) {
                model.requestAccessibility()
                model.openAccessibilitySettings()
            }
            Divider()
            PermissionRow(title: Lang.t("通知", "Notifications"),
                          detail: Lang.t("低電量提醒用；不允許時改在螢幕下方提示", "For low-battery alerts; without it a hint shows at the bottom of the screen instead"),
                          granted: [.authorized, .provisional].contains(model.notificationStatus),
                          buttonTitle: model.notificationStatus == .notDetermined ? Lang.t("允許通知", "Allow") : Lang.t("開啟設定", "Open Settings")) {
                model.requestNotifications()
            }
        }
        .onAppear { model.refreshNotificationStatus() }

        Card(title: Lang.t("工程模式", "Engineering mode"), subtitle: Lang.t("檢視滑鼠事件，方便回報問題", "Inspect mouse events when reporting a problem")) {
            HStack(spacing: 8) {
                Toggle(Lang.t("寫入記錄檔", "Write to log file"), isOn: Binding(get: { model.logging }, set: { model.setLogging($0) }))
                    .toggleStyle(.switch).controlSize(.small)
                Spacer()
                Button(Lang.t("清除", "Clear")) { model.clearLog() }
                Button(Lang.t("複製", "Copy")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.logLines.joined(separator: "\n"), forType: .string)
                }
                Button(Lang.t("開啟資料夾", "Open folder")) { NSWorkspace.shared.open(Config.directory) }
            }
            .controlSize(.small)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(model.logLines.enumerated()), id: \.offset) { index, line in
                            Text(line).font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Color(white: 0.86))
                                .frame(maxWidth: .infinity, alignment: .leading).id(index)
                        }
                    }
                    .padding(10)
                }
                .frame(height: 170)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color(white: 0.12)))
                .onChange(of: model.logLines.count) {
                    let count = model.logLines.count
                    if count > 0 { proxy.scrollTo(count - 1, anchor: .bottom) }
                }
            }
        }

        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("MX Master Mac \(AppModel.version)").font(.system(size: 12, weight: .medium))
                Text(Lang.t("個人作品，與 Logitech 無任何關係。", "An independent project, not affiliated with Logitech."))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Button(Lang.t("結束程式", "Quit")) { NSApp.terminate(nil) }
        }
        .padding(.horizontal, 4)
    }
}
