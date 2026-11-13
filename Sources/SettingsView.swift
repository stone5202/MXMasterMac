import AppKit
import SwiftUI
import UserNotifications

// MARK: - 共用外觀

enum Page: Int, CaseIterable {
    case buttons, ring, device, haptics, switching, keyboard, receiver, advanced

    var title: String {
        switch self {
        case .buttons: return Lang.t("按鈕", "Buttons")
        case .ring: return Lang.t("手勢與圓環", "Gestures & Ring")
        case .device: return Lang.t("指標與滾輪", "Pointer & Wheel")
        case .haptics: return Lang.t("觸覺回饋", "Haptics")
        case .switching: return "MX Flow"
        case .keyboard: return Lang.t("鍵盤", "Keyboard")
        case .receiver: return Lang.t("接收器", "Receiver")
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
        case .keyboard: return Lang.t("Logitech 鍵盤的電量、背光與 F 鍵，以及跟著滑鼠切換電腦", "Battery, backlight and F-keys of a Logitech keyboard, and switching computers with the mouse")
        case .receiver: return Lang.t("在 Logi Bolt 接收器上配對新的滑鼠或鍵盤，或解除配對", "Pair a mouse or keyboard with a Logi Bolt receiver, or unpair one")
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
        case .keyboard: return "keyboard"
        case .receiver: return "antenna.radiowaves.left.and.right"
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
                batteryRow(device: "computermouse", percent: snapshot.batteryPercent, charging: snapshot.charging,
                           detail: snapshot.transport == "BOLT" ? "Logi Bolt" : "Bluetooth")
            }
            // 鍵盤連到這台電腦時多一列；鍵盤名稱太長，只標連線方式。
            if let kb = model.keyboardSnapshot, kb.batteryPercent >= 0 {
                batteryRow(device: "keyboard", percent: kb.batteryPercent, charging: kb.charging,
                           detail: kb.transport == "BOLT" ? "Logi Bolt" : "Bluetooth")
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

    // 左下角的一列電量：裝置圖示、電池、百分比、連線方式。
    private func batteryRow(device: String, percent: Int, charging: Bool, detail: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: device).font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 18)
            Image(systemName: batterySymbol(percent: percent, charging: charging)).font(.system(size: 15))
                .foregroundStyle(percent <= 15 && !charging ? Color.red : Color.green)
            Text("\(percent)%").font(.system(size: 13, weight: .semibold)).monospacedDigit()
            Text(detail).font(.system(size: 11.5)).foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func batterySymbol(percent: Int, charging: Bool) -> String {
        if charging { return "battery.100percent.bolt" }
        switch percent {
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
                    case .switching: SwitchPage(model: model, page: $page)
                    case .keyboard: KeyboardPage(model: model, page: $page)
                    case .receiver: ReceiverPage(model: model)
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
    @State private var torque = 50.0
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

                if snapshot.smartShiftPresent || snapshot.wheelInvertPresent || snapshot.thumbInverted != nil {
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
                        if snapshot.ratchetTorque != nil {
                            Divider()
                            HStack(spacing: 14) {
                                Text(Lang.t("段落力道", "Ratchet torque")).font(.system(size: 13))
                                Slider(value: $torque, in: 1...100) { editing in
                                    if !editing {
                                        let value = Int(torque.rounded())
                                        model.applyDevice(Lang.t("段落力道", "Ratchet torque"), { $0.setRatchetTorque(value) }) { $0.ratchetTorque = value }
                                    }
                                }
                                Text("\(Int(torque.rounded()))").monospacedDigit().frame(width: 34)
                            }
                        }
                        if let value = snapshot.thumbInverted {
                            Divider()
                            SettingRow(title: Lang.t("拇指滾輪反轉", "Invert thumb wheel")) {
                                Toggle("", isOn: Binding(get: { value }, set: { newValue in
                                    model.applyDevice(Lang.t("拇指滾輪", "Thumb wheel"), { $0.setThumbInvert(newValue) }) { $0.thumbInvert = newValue }
                                })).toggleStyle(.switch).labelsHidden()
                            }
                        }
                        if let value = snapshot.hiresResolution {
                            Divider()
                            SettingRow(title: Lang.t("主滾輪高解析度", "High resolution wheel"),
                                       subtitle: Lang.t("開啟後捲動可能變快", "Scrolling may become faster when enabled")) {
                                Toggle("", isOn: Binding(get: { value }, set: { newValue in
                                    model.applyDevice(Lang.t("高解析度滾輪", "High resolution wheel"), { $0.setHiresResolution(newValue) }) { $0.hiresResolution = newValue }
                                })).toggleStyle(.switch).labelsHidden()
                            }
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
        if let value = snapshot.ratchetTorque { torque = Double(value) }
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
    @Binding var page: Page

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
        .onAppear { model.refreshHosts(); model.refreshKeyboard() }

        KeyboardFollowCard(model: model, page: $page, channels: channels)

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
            Text(Lang.t("切過去之後，另一台電腦也要執行本程式並設定邊緣，才能用同樣方式切回來；否則請按滑鼠底部的 Easy-Switch 鍵。不會傳送剪貼簿或檔案。",
                        "To come back the same way, the other computer must also run this app with an edge set; otherwise press the Easy-Switch button under the mouse. No clipboard or files are transferred."))
                .font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MX Flow 頁：滑鼠切換時鍵盤一起切，以及每個滑鼠頻道對應到鍵盤的哪個頻道。
struct KeyboardFollowCard: View {
    @ObservedObject var model: AppModel
    @Binding var page: Page
    let channels: [Int]

    private var keyboardChannels: [Int] {
        guard let kb = model.keyboardSnapshot, !kb.hosts.isEmpty else { return [0, 1, 2] }
        return kb.hosts.map(\.index)
    }

    private func autoTitle(_ channel: Int) -> String {
        guard let target = model.autoKeyboardChannel(forMouse: channel) else { return Lang.t("自動（不切換鍵盤）", "Auto (keyboard stays)") }
        return Lang.t("自動：", "Auto: ") + model.keyboardHostTitle(target)
    }

    var body: some View {
        Card(title: Lang.t("鍵盤一起切換", "Keyboard follows"),
             subtitle: Lang.t("滑鼠切到另一台電腦時，Logitech 鍵盤也切到對應的 Easy-Switch 頻道（MX Flow、「切換到頻道」動作與下方按鈕都適用）",
                              "When the mouse moves to another computer, the Logitech keyboard moves to the matching Easy-Switch channel (MX Flow, Switch-to-channel actions and the buttons below)")) {
            SettingRow(title: Lang.t("滑鼠切換時鍵盤一起切換", "Switch the keyboard with the mouse"),
                       subtitle: model.keyboardSnapshot.map { Lang.t("已連上：", "Connected: ") + ($0.name.isEmpty ? Lang.t("鍵盤", "Keyboard") : $0.name) }
                        ?? Lang.t("沒有偵測到以藍牙連到這台電腦的 Logitech 鍵盤", "No Logitech keyboard connected to this computer over Bluetooth")) {
                Toggle("", isOn: $model.config.keyboard.followSwitch).toggleStyle(.switch).labelsHidden()
            }
            Divider()
            VStack(spacing: 8) {
                ForEach(channels, id: \.self) { channel in
                    HStack(spacing: 10) {
                        Image(systemName: "computermouse").font(.system(size: 12)).foregroundStyle(Color.accentColor).frame(width: 22)
                        Text(model.hostTitle(channel)).font(.system(size: 13)).lineLimit(1)
                        Spacer(minLength: 8)
                        Image(systemName: "arrow.right").font(.system(size: 11)).foregroundStyle(.secondary)
                        Image(systemName: "keyboard").font(.system(size: 12)).foregroundStyle(Color.accentColor)
                        Picker("", selection: Binding(get: { model.config.keyboard.channels[String(channel)] ?? -2 },
                                                      set: { model.setKeyboardChannel(forMouse: channel, $0 == -2 ? nil : $0) })) {
                            Text(autoTitle(channel)).tag(-2)
                            ForEach(keyboardChannels, id: \.self) { index in
                                Text(model.keyboardHostTitle(index)).tag(index)
                            }
                            Text(Lang.t("不切換鍵盤", "Keyboard stays")).tag(-1)
                        }
                        .labelsHidden().frame(width: 250)
                    }
                }
            }
            .disabled(!model.config.keyboard.followSwitch).opacity(model.config.keyboard.followSwitch ? 1 : 0.45)
            Text(Lang.t("自動：鍵盤上有同名電腦的頻道就用它，否則用同一個頻道號。用 Bolt 接收器配對的頻道，鍵盤常記成「Logitech Bolt receiver」，請手動指定。要用同樣方式切回來，另一台電腦也要執行有這項功能的版本；否則請按鍵盤上的 Easy-Switch 鍵。",
                        "Auto uses the keyboard channel with the same computer name, otherwise the same channel number. Channels paired through a Bolt receiver are often stored as \"Logitech Bolt receiver\" on the keyboard; choose them by hand. To come back the same way the other computer must run a version with this feature; otherwise press the Easy-Switch key on the keyboard."))
                .font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if model.keyboardSnapshot != nil {
                Button(Lang.t("鍵盤設定…", "Keyboard settings…")) { page = .keyboard }.controlSize(.small)
            }
        }
    }
}

// 鍵盤頁：狀態三格、背光、F 鍵、頻道。設定存在鍵盤上，不寫進設定檔。
struct KeyboardPage: View {
    @ObservedObject var model: AppModel
    @Binding var page: Page
    @State private var level = 0.0

    private func batteryText(_ kb: KeyboardSnapshot) -> String {
        guard kb.batteryPercent >= 0 else { return "—" }
        return "\(kb.batteryPercent)%" + (kb.charging ? Lang.t("（充電中）", " (charging)") : "")
    }

    private func batterySymbol(_ kb: KeyboardSnapshot) -> String {
        if kb.charging { return "battery.100percent.bolt" }
        switch kb.batteryPercent {
        case 88...: return "battery.100percent"
        case 63...: return "battery.75percent"
        case 38...: return "battery.50percent"
        case 13...: return "battery.25percent"
        default: return "battery.0percent"
        }
    }

    // 背光選單的值：-1 關閉、1 自動、3 手動；其他是鍵盤自己的模式。
    private func backlightChoice(_ kb: KeyboardSnapshot) -> Int { kb.backlightEnabled ? kb.backlightMode : -1 }

    var body: some View {
        Group {
            if let kb = model.keyboardSnapshot {
                Text(kb.name.isEmpty ? Lang.t("Logitech 鍵盤", "Logitech keyboard") : kb.name)
                    .font(.system(size: 15, weight: .semibold)).padding(.horizontal, 4)
                HStack(spacing: 12) {
                    StatTile(symbol: "wave.3.right", title: Lang.t("連線", "Connection"), value: "Bluetooth")
                    StatTile(symbol: batterySymbol(kb), title: Lang.t("電量", "Battery"), value: batteryText(kb))
                    StatTile(symbol: "cpu", title: Lang.t("韌體", "Firmware"), value: kb.firmware.isEmpty ? "—" : kb.firmware)
                }

                if kb.backlightPresent {
                    Card(title: Lang.t("背光", "Backlight")) {
                        SettingRow(title: Lang.t("背光模式", "Backlight mode"),
                                   subtitle: Lang.t("自動：手靠近時亮起，亮度跟著環境光調整；手動：固定亮度",
                                                    "Auto: lights up as your hands approach and follows ambient light; Manual: fixed brightness")) {
                            Picker("", selection: Binding(get: { backlightChoice(kb) }, set: { choice in
                                let enabled = choice != -1
                                let mode = enabled ? choice : kb.backlightMode
                                // 背光關閉時鍵盤回報亮度 0；改成手動時用中間亮度，免得看起來沒亮。
                                let value = level >= 1 ? Int(level.rounded()) : max(1, kb.backlightLevels / 2)
                                model.applyKeyboard(Lang.t("背光", "Backlight")) { $0.setBacklight(enabled: enabled, mode: mode, level: value) }
                            })) {
                                if kb.backlightAuto { Text(Lang.t("自動", "Auto")).tag(1) }
                                if kb.backlightManual { Text(Lang.t("手動", "Manual")).tag(3) }
                                if kb.backlightEnabled && kb.backlightMode != 1 && kb.backlightMode != 3 {
                                    Text(Lang.t("鍵盤預設", "Keyboard default")).tag(kb.backlightMode)
                                }
                                Text(Lang.t("關閉", "Off")).tag(-1)
                            }
                            .pickerStyle(.segmented).labelsHidden().frame(width: 220)
                        }
                        if kb.backlightEnabled && kb.backlightMode == 3 && kb.backlightLevels > 1 {
                            HStack(spacing: 14) {
                                Text(Lang.t("亮度", "Brightness")).font(.system(size: 13)).frame(width: 86, alignment: .leading)
                                Image(systemName: "sun.min").foregroundStyle(.secondary)
                                Slider(value: $level, in: 0...Double(kb.backlightLevels - 1), step: 1) { editing in
                                    guard !editing else { return }
                                    let value = Int(level.rounded())
                                    guard value != kb.backlightLevel else { return }
                                    model.applyKeyboard(Lang.t("背光亮度", "Backlight brightness")) { $0.setBacklight(enabled: true, mode: 3, level: value) }
                                }
                                Image(systemName: "sun.max").foregroundStyle(.secondary)
                                Text("\(Int(level.rounded()))").font(.system(size: 13, weight: .semibold)).monospacedDigit().frame(width: 28, alignment: .trailing)
                            }
                        }
                        if kb.backlightDelays.count == 3 {
                            Divider()
                            ForEach(0..<3, id: \.self) { field in
                                KeyboardDelayRow(model: model, field: field, current: kb.backlightDelays[field])
                            }
                            Text(Lang.t("1–600 秒；鍵盤以 5 秒為單位向上取整。", "1–600 seconds; rounded up to 5-second units by the keyboard."))
                                .font(.system(size: 11.5)).foregroundStyle(.secondary)
                        }
                    }
                }

                KeyboardExtraSettings(model: model, kb: kb)

                if kb.fnPresent {
                    Card(title: Lang.t("F 鍵", "F-keys"),
                         subtitle: Lang.t("每個 Easy-Switch 頻道各自記錄；這裡改的是這台電腦的頻道",
                                          "Stored per Easy-Switch channel; this changes the channel of this computer")) {
                        SettingRow(title: Lang.t("最上排按鍵預設", "Top row by default"),
                                   subtitle: Lang.t("另一種功能要按住 Fn 再按", "Hold Fn for the other function")) {
                            Picker("", selection: Binding(get: { kb.fnMediaFirst }, set: { value in
                                model.applyKeyboard(Lang.t("F 鍵", "F-keys")) { $0.setFnMediaFirst(value) }
                            })) {
                                Text(Lang.t("媒體鍵", "Media keys")).tag(true)
                                Text("F1–F12").tag(false)
                            }
                            .pickerStyle(.segmented).labelsHidden().frame(width: 200)
                        }
                    }
                }

                Card(title: Lang.t("Easy-Switch 頻道", "Easy-Switch channels"),
                     subtitle: Lang.t("鍵盤記錄的連線對象；滑鼠切換時要不要帶鍵盤，在 MX Flow 頁設定",
                                      "The hosts stored on the keyboard; whether it follows the mouse is set on the MX Flow page")) {
                    ForEach(kb.hosts, id: \.index) { host in
                        HStack(spacing: 10) {
                            NumberBadge(text: "\(host.index + 1)", active: host.index == kb.currentHost)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(host.name.isEmpty ? Lang.t("（沒有名稱）", "(no name)") : host.name).font(.system(size: 13))
                                Text([host.busName, host.paired ? "" : Lang.t("未配對", "Not paired"),
                                      host.index == kb.currentHost ? Lang.t("目前使用中", "In use now") : ""]
                                    .filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.system(size: 11.5)).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                    Button(Lang.t("MX Flow 設定…", "MX Flow settings…")) { page = .switching }.controlSize(.small)
                }
            } else {
                Card {
                    Text(Lang.t("沒有偵測到以藍牙連到這台電腦的 Logitech 鍵盤。鍵盤切到別台電腦、睡眠或關機時也會這樣；按一下鍵盤任一鍵後再重新讀取。目前還不支援經 Bolt 接收器連線的鍵盤。",
                                "No Logitech keyboard is connected to this computer over Bluetooth. This also happens while it is on another computer, asleep or off; press a key and reload. Keyboards on a Bolt receiver are not supported yet."))
                        .font(.system(size: 12.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack {
                Text(model.keyboardMessage.isEmpty
                     ? Lang.t("設定存在鍵盤上，由鍵盤確認後才算套用。", "Settings live on the keyboard and count as applied once it confirms them.")
                     : model.keyboardMessage)
                    .font(.system(size: 11.5)).foregroundStyle(.secondary)
                Spacer()
                Button(Lang.t("重新讀取", "Reload")) { model.refreshKeyboard() }.controlSize(.small)
            }
            .padding(.horizontal, 4)
        }
        .onAppear { model.keyboardMessage = ""; model.refreshKeyboard(); level = Double(model.keyboardSnapshot?.backlightLevel ?? 0) }
        .onChange(of: model.keyboardSnapshot?.backlightLevel) { level = Double(model.keyboardSnapshot?.backlightLevel ?? 0) }
    }
}

private struct KeyboardDelayRow: View {
    @ObservedObject var model: AppModel
    let field: Int
    let current: Int
    @State private var seconds = 30
    private var title: String {
        [Lang.t("手離開", "Hands away"), Lang.t("手靠近", "Hands near"), Lang.t("接電源", "External power")][field]
    }
    var body: some View {
        SettingRow(title: title, subtitle: Lang.t("目前：", "Current: ") + "\(current) " + Lang.t("秒", "seconds")) {
            Stepper("\(seconds) " + Lang.t("秒", "s"), value: $seconds, in: 1...600).frame(width: 140)
            Button(Lang.t("套用", "Apply")) {
                let value = seconds
                model.applyKeyboard(title) { $0.setBacklightDelay(field: field, seconds: value) }
            }.controlSize(.small)
        }
        .onAppear { seconds = min(600, max(1, current)) }
        .onChange(of: current) { seconds = min(600, max(1, current)) }
    }
}

private struct KeyboardExtraSettings: View {
    @ObservedObject var model: AppModel
    let kb: KeyboardSnapshot
    var body: some View {
        if kb.disabledKeysMask != 0 {
            Card(title: Lang.t("停用按鍵", "Disable keys")) {
                ForEach(0..<8, id: \.self) { bit in
                    if kb.disabledKeysMask & (1 << bit) != 0 {
                        SettingRow(title: SolaarFeatures.disableName(bit)) {
                            Toggle("", isOn: Binding(get: { kb.disabledKeys & (1 << bit) != 0 }, set: { value in
                                model.applyKeyboard(SolaarFeatures.disableName(bit)) { $0.setDisabledKey(bit: bit, disabled: value) }
                            })).toggleStyle(.switch).labelsHidden()
                        }
                    }
                }
            }
        }
        if !kb.platforms.isEmpty {
            Card(title: Lang.t("作業系統配置", "Operating system layout"),
                 subtitle: Lang.t("只變更目前 Easy-Switch 頻道", "Changes only the current Easy-Switch channel")) {
                SettingRow(title: Lang.t("平台", "Platform")) {
                    Picker("", selection: Binding(get: { kb.currentPlatform }, set: { value in
                        model.applyKeyboard(Lang.t("作業系統配置", "OS layout")) { $0.setPlatform(value) }
                    })) {
                        if !kb.platforms.contains(where: { $0.id == kb.currentPlatform }) {
                            Text(Lang.t("目前配置", "Current layout") + " (\(kb.currentPlatform))").tag(kb.currentPlatform)
                        }
                        ForEach(kb.platforms) { choice in Text(choice.name).tag(choice.id) }
                    }.labelsHidden().frame(width: 220)
                }
            }
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

// MARK: - 接收器（Logi Bolt 配對）

struct ReceiverPage: View {
    @ObservedObject var model: AppModel
    @State private var unpairTarget: BoltSlot?

    private static let pointing: Set<Int> = [2, 8, 9]

    private func kindName(_ kind: Int) -> String {
        switch kind {
        case 1: return Lang.t("鍵盤", "Keyboard")
        case 2: return Lang.t("滑鼠", "Mouse")
        case 3: return Lang.t("數字鍵盤", "Numpad")
        case 4: return Lang.t("簡報器", "Presenter")
        case 8: return Lang.t("軌跡球", "Trackball")
        case 9: return Lang.t("觸控板", "Touchpad")
        default: return Lang.t("裝置", "Device")
        }
    }

    private func kindSymbol(_ kind: Int) -> String {
        if ReceiverPage.pointing.contains(kind) { return "computermouse" }
        if kind == 1 || kind == 3 { return "keyboard" }
        return "dot.radiowaves.left.and.right"
    }

    private func displayName(_ slot: BoltSlot) -> String { slot.name.isEmpty ? kindName(slot.kind) : slot.name }

    private func failureText(_ failure: BoltFailure) -> String {
        switch failure {
        case .noAnswer:
            return Lang.t("接收器沒有接受配對指令。如果開著 Logi Options+ 或 Logi Bolt，請先結束再試一次。",
                          "The receiver did not accept the pairing command. If Logi Options+ or Logi Bolt is running, quit it and try again.")
        case .notFound:
            return Lang.t("30 秒內沒有找到要配對的裝置。請長按頻道鍵，直到燈號快速閃爍。",
                          "No device asked to pair within 30 seconds. Hold the channel button until the light blinks fast.")
        case .timeout:
            return Lang.t("驗證沒有在時間內完成。", "Authentication was not completed in time.")
        case .failed:
            return Lang.t("配對沒有完成，可能是驗證碼按錯了。請再試一次。", "Pairing did not complete; the code may have been entered wrong. Please try again.")
        }
    }

    var body: some View {
        Group {
            if model.receiver.multiple {
                Card(title: Lang.t("偵測到多個 Logi Bolt 接收器", "More than one Logi Bolt receiver found"),
                     subtitle: Lang.t("請只留一個接收器插在這台 Mac，再配對或解除配對",
                                      "Leave only one receiver plugged into this Mac to pair or unpair")) {
                    EmptyView()
                }
            } else if model.receiver.present {
                Text("Logi Bolt").font(.system(size: 15, weight: .semibold)).padding(.horizontal, 4)
                pairingCard
                pairedCard
            } else {
                Card(title: Lang.t("沒有偵測到 Logi Bolt 接收器", "No Logi Bolt receiver found"),
                     subtitle: Lang.t("把接收器插到這台 Mac，這一頁就能配對新裝置或解除配對",
                                      "Plug the receiver into this Mac to pair or unpair devices here")) {
                    Text(Lang.t("只支援 Logi Bolt 接收器；Unifying 與 Lightspeed 接收器不支援。",
                                "Only Logi Bolt receivers are supported, not Unifying or Lightspeed."))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { model.refreshReceiver() }
        .alert(unpairTarget.map { Lang.t("解除「\(displayName($0))」的配對？", "Unpair \(displayName($0))?") } ?? "",
               isPresented: Binding(get: { unpairTarget != nil }, set: { if !$0 { unpairTarget = nil } }),
               presenting: unpairTarget) { slot in
            Button(Lang.t("解除配對", "Unpair"), role: .destructive) { model.unpair(slot) }
            Button(Lang.t("取消", "Cancel"), role: .cancel) {}
        } message: { slot in
            Text(unpairWarning(slot))
        }
    }

    private func unpairWarning(_ slot: BoltSlot) -> String {
        var text = Lang.t("裝置會從這個接收器斷線，要再用就得重新配對。",
                          "The device disconnects from this receiver and has to be paired again to use it.")
        if ReceiverPage.pointing.contains(slot.kind) {
            text += Lang.t("如果這是你正在用的滑鼠，解除後游標會立刻不能動。", " If this is the mouse you are using, the pointer stops moving right away.")
        } else if slot.kind == 1 {
            text += Lang.t("如果這是你正在用的鍵盤，解除後會立刻不能打字。", " If this is the keyboard you are using, typing stops right away.")
        }
        return text
    }

    @ViewBuilder private var pairingCard: some View {
        Card(title: Lang.t("配對新裝置", "Pair a device"),
             subtitle: Lang.t("讓滑鼠或鍵盤的一個 Easy-Switch 頻道改連到這個接收器",
                              "Connect one Easy-Switch channel of a mouse or keyboard to this receiver")) {
            switch model.receiver.phase {
            case .idle:
                VStack(alignment: .leading, spacing: 4) {
                    Text(Lang.t("1. 按「開始配對」。", "1. Click Start Pairing."))
                    Text(Lang.t("2. 30 秒內長按裝置上要用的 Easy-Switch 頻道鍵，直到燈號快速閃爍。",
                                "2. Within 30 seconds, hold the Easy-Switch channel button you want to use until its light blinks fast."))
                    Text(Lang.t("3. 照畫面上的指示完成驗證。", "3. Follow the on-screen instructions to authenticate."))
                }
                .font(.system(size: 12.5)).fixedSize(horizontal: false, vertical: true)
                Text(Lang.t("配對會取代那個頻道原本的連線（例如原本以藍牙連到另一台電腦）。",
                            "Pairing replaces whatever that channel was connected to before (for example Bluetooth to another computer)."))
                    .font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button(Lang.t("開始配對", "Start Pairing")) { model.startPairing() }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.receiver.slots.count >= 6)
                    if model.receiver.slots.count >= 6 {
                        Text(Lang.t("6 個槽位都用完了，請先解除一個裝置的配對。", "All 6 slots are in use; unpair a device first."))
                            .font(.system(size: 11.5)).foregroundStyle(.secondary)
                    }
                }
            case .searching:
                waiting(Lang.t("正在尋找裝置… 請長按要配對的頻道鍵，直到燈號快速閃爍。",
                               "Looking for a device… Hold the channel button until its light blinks fast."))
            case .pairing(let name, _):
                waiting(Lang.t("找到「\(name)」，正在配對…", "Found \(name); pairing…"))
            case .passkey(let code, let name, let keyboard):
                if keyboard {
                    Text(Lang.t("在「\(name)」上輸入下面的數字，再按 Enter：", "On \(name), type these digits and press Enter:"))
                        .font(.system(size: 12.5))
                    Text(code.map(String.init).joined(separator: " "))
                        .font(.system(size: 30, weight: .bold, design: .monospaced)).padding(.vertical, 4)
                } else {
                    Text(Lang.t("在「\(name)」上依序按下面的按鍵，最後左右鍵一起按：",
                                "On \(name), click these buttons in order, then press left and right together:"))
                        .font(.system(size: 12.5)).fixedSize(horizontal: false, vertical: true)
                    sequenceView(BoltPackets.mouseSequence(code))
                }
                Button(Lang.t("取消", "Cancel")) { model.cancelPairing() }
            case .succeeded(let slot, let name):
                Label(Lang.t("已配對「\(name)」（槽位 \(slot)）", "Paired \(name) (slot \(slot))"), systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.green)
                Text(Lang.t("裝置現在用剛才那個頻道連到這個接收器；要切回其他電腦時，按裝置上的 Easy-Switch 鍵。",
                            "The device now uses that channel for this receiver; press its Easy-Switch button to go back to other computers."))
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button(Lang.t("完成", "Done")) { model.dismissPairingResult() }
            case .failed(let failure):
                Label(failureText(failure), systemImage: "xmark.octagon.fill")
                    .font(.system(size: 12.5)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button(Lang.t("再試一次", "Try Again")) { model.startPairing() }.buttonStyle(.borderedProminent)
                    Button(Lang.t("關閉", "Close")) { model.dismissPairingResult() }
                }
            }
        }
    }

    private func waiting(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(text).font(.system(size: 12.5)).fixedSize(horizontal: false, vertical: true)
            }
            Button(Lang.t("取消", "Cancel")) { model.cancelPairing() }
        }
    }

    private func sequenceView(_ sequence: [Bool]) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(sequence.enumerated()), id: \.offset) { _, right in
                Text(right ? Lang.t("右", "R") : Lang.t("左", "L"))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(right ? Color.white : Color.accentColor)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 7).fill(right ? Color.accentColor : Color.clear))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.accentColor, lineWidth: 1.5))
            }
            Text(Lang.t("＋ 左右一起", "+ both")).font(.system(size: 12.5, weight: .semibold)).padding(.leading, 4)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private var pairedCard: some View {
        Card(title: Lang.t("已配對的裝置", "Paired devices"),
             subtitle: Lang.t("已使用 \(model.receiver.slots.count)／6 個槽位", "\(model.receiver.slots.count) of 6 slots in use")) {
            if model.receiver.slots.isEmpty {
                Text(Lang.t("這個接收器還沒有配對任何裝置。", "No devices are paired with this receiver yet."))
                    .font(.system(size: 12.5)).foregroundStyle(.secondary)
            }
            ForEach(model.receiver.slots) { slot in
                HStack(spacing: 10) {
                    NumberBadge(text: "\(slot.slot)")
                    Image(systemName: kindSymbol(slot.kind)).font(.system(size: 15)).foregroundStyle(.secondary).frame(width: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(displayName(slot)).font(.system(size: 13, weight: .medium))
                        Text(kindName(slot.kind) + " · WPID " + slot.wpid).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Button(Lang.t("解除配對", "Unpair")) { unpairTarget = slot }
                        .disabled(model.receiver.phase.active)
                }
            }
            if !model.receiverMessage.isEmpty {
                Text(model.receiverMessage).font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            if model.receiver.slots.contains(where: { $0.kind == 1 }) {
                Text(Lang.t("經接收器連線的鍵盤可以正常打字；「鍵盤」頁的電量、背光等設定目前只支援藍牙連線的鍵盤。",
                            "A keyboard on the receiver types normally; the battery, backlight and other settings on the Keyboard page currently need a Bluetooth keyboard."))
                    .font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
