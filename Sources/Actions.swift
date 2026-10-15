import AppKit
import Carbon.HIToolbox

enum MappedAction: String, CaseIterable, Codable {
    case passThrough
    // 導覽
    case navigateBack, navigateForward
    case missionControl, appExpose, showDesktop, launchpad
    case spaceLeft, spaceRight, appSwitcher
    // 編輯
    case copy, paste, cut, undo, redo, selectAll, save, find
    // 媒體
    case playPause, nextTrack, prevTrack, volumeUp, volumeDown, mute
    // 分頁與視窗
    case newTab, closeTab, reopenTab, refresh, zoomIn, zoomOut
    case minimizeWindow, closeWindow, fullScreen, quitApp
    // 系統
    case spotlight, screenshot, screenshotArea, emoji, lockScreen
    case finder, systemSettings, calculator, activityMonitor
    // 輸入
    case insertDate, insertTime, enter, escape, delete
    // 本程式
    case openSettings
    // 自訂
    case customShortcut, launch
}

struct ActionBinding: Codable, Equatable, Hashable {
    var action: MappedAction
    var param: String = ""     // customShortcut: "修飾鍵旗標,keyCode"；launch: 路徑或網址
    var label: String = ""     // customShortcut 的顯示文字

    init(_ action: MappedAction, param: String = "", label: String = "") {
        self.action = action
        self.param = param
        self.label = label
    }

    var isPassThrough: Bool { action == .passThrough }

    var title: String {
        switch action {
        case .customShortcut: return label.isEmpty ? ActionCatalog.title(action) : label
        case .launch:
            if param.isEmpty { return ActionCatalog.title(action) }
            let name = (param as NSString).lastPathComponent
            return name.isEmpty ? param : name.replacingOccurrences(of: ".app", with: "")
        default: return ActionCatalog.title(action)
        }
    }
}

enum ActionCatalog {
    struct Group {
        let title: String
        let actions: [MappedAction]
    }

    static var groups: [Group] {
        [
            Group(title: Lang.t("一般", "General"), actions: [.passThrough, .openSettings]),
            Group(title: Lang.t("導覽", "Navigation"), actions: [
                .navigateBack, .navigateForward, .missionControl, .appExpose, .showDesktop,
                .launchpad, .spaceLeft, .spaceRight, .appSwitcher]),
            Group(title: Lang.t("編輯", "Editing"), actions: [
                .copy, .paste, .cut, .undo, .redo, .selectAll, .save, .find]),
            Group(title: Lang.t("媒體與音量", "Media & volume"), actions: [
                .playPause, .nextTrack, .prevTrack, .volumeUp, .volumeDown, .mute]),
            Group(title: Lang.t("分頁與視窗", "Tabs & windows"), actions: [
                .newTab, .closeTab, .reopenTab, .refresh, .zoomIn, .zoomOut,
                .minimizeWindow, .closeWindow, .fullScreen, .quitApp]),
            Group(title: Lang.t("系統", "System"), actions: [
                .spotlight, .screenshot, .screenshotArea, .emoji, .lockScreen,
                .finder, .systemSettings, .calculator, .activityMonitor]),
            Group(title: Lang.t("輸入", "Typing"), actions: [
                .insertDate, .insertTime, .enter, .escape, .delete]),
            Group(title: Lang.t("自訂", "Custom"), actions: [.customShortcut, .launch]),
        ]
    }

    static func title(_ action: MappedAction) -> String {
        switch action {
        case .passThrough: return Lang.t("保留原功能", "Keep default")
        case .navigateBack: return Lang.t("上一頁", "Back")
        case .navigateForward: return Lang.t("下一頁", "Forward")
        case .missionControl: return Lang.t("指揮中心", "Mission Control")
        case .appExpose: return Lang.t("App Exposé", "App Exposé")
        case .showDesktop: return Lang.t("顯示桌面", "Show Desktop")
        case .launchpad: return Lang.t("App 清單", "Apps")
        case .spaceLeft: return Lang.t("左邊的桌面", "Desktop left")
        case .spaceRight: return Lang.t("右邊的桌面", "Desktop right")
        case .appSwitcher: return Lang.t("切換 App", "Switch app")
        case .copy: return Lang.t("複製", "Copy")
        case .paste: return Lang.t("貼上", "Paste")
        case .cut: return Lang.t("剪下", "Cut")
        case .undo: return Lang.t("復原", "Undo")
        case .redo: return Lang.t("重做", "Redo")
        case .selectAll: return Lang.t("全選", "Select all")
        case .save: return Lang.t("儲存", "Save")
        case .find: return Lang.t("尋找", "Find")
        case .playPause: return Lang.t("播放／暫停", "Play / pause")
        case .nextTrack: return Lang.t("下一首", "Next track")
        case .prevTrack: return Lang.t("上一首", "Previous track")
        case .volumeUp: return Lang.t("音量調大", "Volume up")
        case .volumeDown: return Lang.t("音量調小", "Volume down")
        case .mute: return Lang.t("靜音", "Mute")
        case .newTab: return Lang.t("新增分頁", "New tab")
        case .closeTab: return Lang.t("關閉分頁", "Close tab")
        case .reopenTab: return Lang.t("重新開啟分頁", "Reopen tab")
        case .refresh: return Lang.t("重新整理", "Refresh")
        case .zoomIn: return Lang.t("放大", "Zoom in")
        case .zoomOut: return Lang.t("縮小", "Zoom out")
        case .minimizeWindow: return Lang.t("視窗縮到最小", "Minimize window")
        case .closeWindow: return Lang.t("關閉視窗", "Close window")
        case .fullScreen: return Lang.t("全螢幕", "Full screen")
        case .quitApp: return Lang.t("結束 App", "Quit app")
        case .spotlight: return Lang.t("Spotlight 搜尋", "Spotlight")
        case .screenshot: return Lang.t("螢幕截圖工具", "Screenshot tool")
        case .screenshotArea: return Lang.t("截取選取範圍", "Capture selection")
        case .emoji: return Lang.t("表情符號", "Emoji")
        case .lockScreen: return Lang.t("鎖定螢幕", "Lock screen")
        case .finder: return Lang.t("Finder", "Finder")
        case .systemSettings: return Lang.t("系統設定", "System Settings")
        case .calculator: return Lang.t("計算機", "Calculator")
        case .activityMonitor: return Lang.t("活動監視器", "Activity Monitor")
        case .insertDate: return Lang.t("輸入今天日期", "Type today's date")
        case .insertTime: return Lang.t("輸入目前時間", "Type current time")
        case .enter: return "Enter"
        case .escape: return "Esc"
        case .delete: return "Delete"
        case .openSettings: return Lang.t("MX設定", "MX Settings")
        case .customShortcut: return Lang.t("自訂快捷鍵…", "Custom shortcut…")
        case .launch: return Lang.t("開啟 App／檔案／網址…", "Open app / file / URL…")
        }
    }

    // 圓環每一格用的 SF Symbol。
    static func symbol(_ action: MappedAction) -> String {
        switch action {
        case .passThrough: return "circle.dashed"
        case .navigateBack: return "chevron.backward"
        case .navigateForward: return "chevron.forward"
        case .missionControl: return "rectangle.3.group"
        case .appExpose: return "macwindow.on.rectangle"
        case .showDesktop: return "menubar.dock.rectangle"
        case .launchpad: return "square.grid.3x3"
        case .spaceLeft: return "arrow.left.to.line"
        case .spaceRight: return "arrow.right.to.line"
        case .appSwitcher: return "rectangle.on.rectangle"
        case .copy: return "doc.on.doc"
        case .paste: return "doc.on.clipboard"
        case .cut: return "scissors"
        case .undo: return "arrow.uturn.backward"
        case .redo: return "arrow.uturn.forward"
        case .selectAll: return "checklist"
        case .save: return "square.and.arrow.down"
        case .find: return "magnifyingglass"
        case .playPause: return "playpause.fill"
        case .nextTrack: return "forward.end.fill"
        case .prevTrack: return "backward.end.fill"
        case .volumeUp: return "speaker.wave.3.fill"
        case .volumeDown: return "speaker.wave.1.fill"
        case .mute: return "speaker.slash.fill"
        case .newTab: return "plus.square.on.square"
        case .closeTab: return "xmark.square"
        case .reopenTab: return "arrow.counterclockwise.square"
        case .refresh: return "arrow.clockwise"
        case .zoomIn: return "plus.magnifyingglass"
        case .zoomOut: return "minus.magnifyingglass"
        case .minimizeWindow: return "minus.rectangle"
        case .closeWindow: return "xmark.rectangle"
        case .fullScreen: return "arrow.up.left.and.arrow.down.right"
        case .quitApp: return "power"
        case .spotlight: return "sparkle.magnifyingglass"
        case .screenshot: return "camera.viewfinder"
        case .screenshotArea: return "crop"
        case .emoji: return "face.smiling"
        case .lockScreen: return "lock.fill"
        case .finder: return "folder"
        case .systemSettings: return "gearshape"
        case .calculator: return "plus.forwardslash.minus"
        case .activityMonitor: return "waveform.path.ecg"
        case .insertDate: return "calendar"
        case .insertTime: return "clock"
        case .enter: return "return"
        case .escape: return "escape"
        case .delete: return "delete.left"
        case .openSettings: return "slider.horizontal.3"
        case .customShortcut: return "command"
        case .launch: return "arrow.up.forward.app"
        }
    }
}

enum ActionRunner {
    private static let source = CGEventSource(stateID: .hidSystemState)
    static var openSettings: (() -> Void)?     // 由 AppDelegate 設定：開啟本程式的設定視窗

    // 回傳 false 表示沒有送出任何東西（例如缺少輔助使用權限或參數是空的）。
    @discardableResult
    static func run(_ binding: ActionBinding) -> Bool {
        switch binding.action {
        case .passThrough: return false
        case .navigateBack: return combo(kVK_ANSI_LeftBracket, .maskCommand)
        case .navigateForward: return combo(kVK_ANSI_RightBracket, .maskCommand)
        // 送出系統預設的快捷鍵（⌃↑、⌃↓、F11）。macOS 27 上直接執行「指揮中心」App 已經沒有作用。
        case .missionControl: return combo(kVK_UpArrow, [.maskControl, .maskSecondaryFn])
        case .appExpose: return combo(kVK_DownArrow, [.maskControl, .maskSecondaryFn])
        case .showDesktop: return combo(kVK_F11, .maskSecondaryFn)
        case .launchpad: return openApp("/System/Applications/Apps.app", fallback: "/System/Applications/Launchpad.app")
        case .spaceLeft: return combo(kVK_LeftArrow, [.maskControl, .maskSecondaryFn])
        case .spaceRight: return combo(kVK_RightArrow, [.maskControl, .maskSecondaryFn])
        case .appSwitcher: return combo(kVK_Tab, .maskCommand)
        case .copy: return combo(kVK_ANSI_C, .maskCommand)
        case .paste: return combo(kVK_ANSI_V, .maskCommand)
        case .cut: return combo(kVK_ANSI_X, .maskCommand)
        case .undo: return combo(kVK_ANSI_Z, .maskCommand)
        case .redo: return combo(kVK_ANSI_Z, [.maskCommand, .maskShift])
        case .selectAll: return combo(kVK_ANSI_A, .maskCommand)
        case .save: return combo(kVK_ANSI_S, .maskCommand)
        case .find: return combo(kVK_ANSI_F, .maskCommand)
        case .playPause: return mediaKey(NX_KEYTYPE_PLAY)
        case .nextTrack: return mediaKey(NX_KEYTYPE_NEXT)
        case .prevTrack: return mediaKey(NX_KEYTYPE_PREVIOUS)
        case .volumeUp: return mediaKey(NX_KEYTYPE_SOUND_UP)
        case .volumeDown: return mediaKey(NX_KEYTYPE_SOUND_DOWN)
        case .mute: return mediaKey(NX_KEYTYPE_MUTE)
        case .newTab: return combo(kVK_ANSI_T, .maskCommand)
        case .closeTab: return combo(kVK_ANSI_W, .maskCommand)
        case .reopenTab: return combo(kVK_ANSI_T, [.maskCommand, .maskShift])
        case .refresh: return combo(kVK_ANSI_R, .maskCommand)
        case .zoomIn: return combo(kVK_ANSI_Equal, .maskCommand)
        case .zoomOut: return combo(kVK_ANSI_Minus, .maskCommand)
        case .minimizeWindow: return combo(kVK_ANSI_M, .maskCommand)
        case .closeWindow: return combo(kVK_ANSI_W, [.maskCommand, .maskShift])
        case .fullScreen: return combo(kVK_ANSI_F, [.maskCommand, .maskControl])
        case .quitApp: return combo(kVK_ANSI_Q, .maskCommand)
        case .spotlight: return combo(kVK_Space, .maskCommand)
        case .screenshot: return combo(kVK_ANSI_5, [.maskCommand, .maskShift])
        case .screenshotArea: return combo(kVK_ANSI_4, [.maskCommand, .maskShift])
        case .emoji: return combo(kVK_Space, [.maskCommand, .maskControl])
        case .lockScreen: return combo(kVK_ANSI_Q, [.maskCommand, .maskControl])
        case .finder: return open(FileManager.default.homeDirectoryForCurrentUser)
        case .systemSettings: return openApp("/System/Applications/System Settings.app")
        case .calculator: return openApp("/System/Applications/Calculator.app")
        case .activityMonitor: return openApp("/System/Applications/Utilities/Activity Monitor.app")
        case .insertDate: return type(format("yyyy/MM/dd"))
        case .insertTime: return type(format("HH:mm"))
        case .enter: return combo(kVK_Return, [])
        case .escape: return combo(kVK_Escape, [])
        case .delete: return combo(kVK_ForwardDelete, .maskSecondaryFn)
        case .customShortcut:
            guard let shortcut = Shortcut(param: binding.param) else { return false }
            return combo(shortcut.keyCode, shortcut.flags)
        case .launch: return launch(binding.param)
        case .openSettings:
            guard let openSettings else { return false }
            // 等圓環或手勢提示先收起來再開視窗。
            DispatchQueue.main.async { openSettings() }
            return true
        }
    }

    static var trusted: Bool { AXIsProcessTrusted() }

    private static func combo(_ key: Int, _ flags: CGEventFlags) -> Bool {
        guard trusted,
              let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(key), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(key), keyDown: false) else { return false }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    private static func mediaKey(_ key: Int32) -> Bool {
        guard trusted else { return false }
        for down in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
            let data1 = (Int(key) << 16) | ((down ? 0xA : 0xB) << 8)
            guard let event = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags,
                                                 timestamp: 0, windowNumber: 0, context: nil, subtype: 8,
                                                 data1: data1, data2: -1) else { return false }
            event.cgEvent?.post(tap: .cghidEventTap)
        }
        return true
    }

    private static func type(_ text: String) -> Bool {
        guard trusted else { return false }
        for scalar in Array(text.utf16) {
            var unit = scalar
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else { return false }
                event.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unit)
                event.post(tap: .cghidEventTap)
            }
        }
        return true
    }

    private static func format(_ pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = pattern
        return formatter.string(from: Date())
    }

    private static func openApp(_ path: String, fallback: String? = nil) -> Bool {
        if FileManager.default.fileExists(atPath: path) { return open(URL(fileURLWithPath: path)) }
        if let fallback, FileManager.default.fileExists(atPath: fallback) { return open(URL(fileURLWithPath: fallback)) }
        return false
    }

    private static func open(_ url: URL) -> Bool { NSWorkspace.shared.open(url) }

    private static func launch(_ target: String) -> Bool {
        let text = target.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return false }
        if text.hasPrefix("/") || text.hasPrefix("~") {
            return open(URL(fileURLWithPath: (text as NSString).expandingTildeInPath))
        }
        if let url = URL(string: text), url.scheme != nil { return open(url) }
        return false
    }
}

// 自訂快捷鍵：以鍵碼＋修飾鍵保存，不受鍵盤配置文字影響。
struct Shortcut {
    let keyCode: Int
    let flags: CGEventFlags

    init?(param: String) {
        let parts = param.split(separator: ",")
        guard parts.count == 2, let raw = UInt64(parts[0]), let key = Int(parts[1]) else { return nil }
        keyCode = key
        flags = CGEventFlags(rawValue: raw)
    }

    static func param(event: NSEvent) -> String {
        var flags: CGEventFlags = []
        let modifiers = event.modifierFlags
        if modifiers.contains(.command) { flags.insert(.maskCommand) }
        if modifiers.contains(.shift) { flags.insert(.maskShift) }
        if modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if modifiers.contains(.control) { flags.insert(.maskControl) }
        if modifiers.contains(.function) { flags.insert(.maskSecondaryFn) }
        return "\(flags.rawValue),\(event.keyCode)"
    }

    static func label(event: NSEvent) -> String {
        var text = ""
        let modifiers = event.modifierFlags
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        return text + keyName(Int(event.keyCode), characters: event.charactersIgnoringModifiers)
    }

    private static func keyName(_ keyCode: Int, characters: String?) -> String {
        switch keyCode {
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Space: return "Space"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_Escape: return "⎋"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_Home: return "Home"
        case kVK_End: return "End"
        case kVK_PageUp: return "PgUp"
        case kVK_PageDown: return "PgDn"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        default:
            let text = (characters ?? "").uppercased()
            return text.isEmpty ? "Key \(keyCode)" : text
        }
    }
}
