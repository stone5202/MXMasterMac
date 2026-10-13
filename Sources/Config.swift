import Foundation

// 介面語言：Auto 跟隨系統，zh / en 強制指定。
enum Lang {
    static var chinese: Bool = true

    static func load(_ setting: String) {
        switch setting {
        case "zh": chinese = true
        case "en": chinese = false
        default:
            let preferred = Locale.preferredLanguages.first ?? "en"
            chinese = preferred.hasPrefix("zh")
        }
    }

    static func t(_ zh: String, _ en: String) -> String { chinese ? zh : en }
}

// 可對應的實體輸入。rawValue 就是設定檔裡的鍵名。
enum MouseInput: String, CaseIterable, Codable {
    // 順序就是「按鈕」頁的列順序，也對應示意圖上的編號。
    case middle = "Middle"
    case gesture = "GestureButton"        // HID++ 0x00C3
    case back = "Back"            // 一般滑鼠按鍵 3
    case forward = "Forward"      // 一般滑鼠按鍵 4
    case wheelLeft = "WheelLeft"
    case wheelRight = "WheelRight"
    case actionRing = "ActionRingButton"  // HID++ 0x01A0

    var title: String {
        switch self {
        case .middle: return Lang.t("中鍵", "Middle button")
        case .back: return Lang.t("側鍵・上一頁", "Side button · Back")
        case .forward: return Lang.t("側鍵・下一頁", "Side button · Forward")
        case .wheelLeft: return Lang.t("拇指滾輪・向左", "Thumb wheel · Left")
        case .wheelRight: return Lang.t("拇指滾輪・向右", "Thumb wheel · Right")
        case .gesture: return Lang.t("拇指手勢鍵", "Gesture button")
        case .actionRing: return Lang.t("Actions Ring 鍵", "Actions Ring button")
        }
    }

    var hint: String {
        switch self {
        case .middle: return Lang.t("按下滾輪", "Press the wheel")
        case .back, .forward: return Lang.t("拇指上方的兩顆側鍵", "The two buttons above the thumb")
        case .wheelLeft, .wheelRight: return Lang.t("側面的水平滾輪", "The horizontal wheel on the side")
        case .gesture: return Lang.t("沒開手勢時按一下執行", "Runs on click when gestures are off")
        case .actionRing: return Lang.t("沒開圓環時按一下執行", "Runs on click when the ring is off")
        }
    }
}

struct DeviceSettings: Codable, Equatable {
    var dpi: Int?
    var wheelMode: Int?          // 1 自由、2 段落
    var smartShift: Int?         // 1–50，255 = 不自動切換
    var wheelInvert: Bool?
    var haptic: Int?             // 0–100
}

struct Config: Codable {
    var mappings: [String: ActionBinding] = [:]
    var ring: [ActionBinding] = Config.defaultRing
    var gestures: [ActionBinding] = Config.defaultGestures   // 上、右、下、左
    var gestureMode = true
    var ringMode = true
    var ringClick = false
    var ringStyle = "ring"       // "ring" 分格圓環、"bubble" 圓形圖示
    var ringSize = 50.0          // 整體大小 0–100%，50% 是預設
    var bubbleSize = 50.0        // 泡泡圓圈大小 0–100%，50% 是預設
    var ringOpacity = 1.0        // 0.4–1.0
    var language = "Auto"
    var device = DeviceSettings()
    var edgeSwitch = EdgeSwitchSettings()
    var diagnosticsToFile = false

    static let defaultRing: [ActionBinding] = [
        ActionBinding(.copy), ActionBinding(.playPause), ActionBinding(.spaceRight), ActionBinding(.paste),
        ActionBinding(.showDesktop), ActionBinding(.missionControl), ActionBinding(.spaceLeft), ActionBinding(.appSwitcher),
    ]
    static let defaultGestures: [ActionBinding] = [
        ActionBinding(.missionControl), ActionBinding(.spaceRight), ActionBinding(.appExpose), ActionBinding(.spaceLeft),
    ]
    static let defaultMappings: [MouseInput: ActionBinding] = [
        .middle: ActionBinding(.passThrough),
        .back: ActionBinding(.navigateBack),
        .forward: ActionBinding(.navigateForward),
        .wheelLeft: ActionBinding(.passThrough),
        .wheelRight: ActionBinding(.passThrough),
        .gesture: ActionBinding(.missionControl),
        .actionRing: ActionBinding(.launchpad),
    ]

    // 50% 對應設計尺寸的 0.7 倍（使用者選定的預設大小）；0% 是它的一半，100% 是 1.5 倍。
    var ringScaleFactor: Double { 0.7 * (0.5 + ringSize / 100) }
    static let maxRingScaleFactor = 0.7 * 1.5

    // 相對設計圓圈（半徑 39pt）的倍率：0% = 0.6 倍、50% = 0.8 倍（使用者選定的預設）、
    // 100% = 1.025 倍（使用者選定的上限）。
    var bubbleScaleFactor: Double {
        bubbleSize <= 50 ? 0.6 + 0.2 * (bubbleSize / 50) : 0.8 + 0.225 * ((bubbleSize - 50) / 50)
    }

    func binding(for input: MouseInput) -> ActionBinding {
        mappings[input.rawValue] ?? Config.defaultMappings[input] ?? ActionBinding(.passThrough)
    }

    // 設定檔放在使用者的 Application Support，不寫入系統位置。
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("MXMasterMac", isDirectory: true)
    }
    static var fileURL: URL { directory.appendingPathComponent("config.json") }
    static var logURL: URL { directory.appendingPathComponent("events.log") }

    static func load() -> Config {
        guard let data = try? Data(contentsOf: fileURL),
              var config = try? JSONDecoder().decode(Config.self, from: data) else { return Config() }
        if config.ring.count != 8 { config.ring = defaultRing }
        if config.gestures.count != 4 { config.gestures = defaultGestures }
        return config
    }

    func save() {
        do {
            try FileManager.default.createDirectory(at: Config.directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(self).write(to: Config.fileURL, options: .atomic)
        } catch {
            NSLog("MXMasterMac: could not save config: \(error)")
        }
    }

    // 舊版或手改的設定檔缺欄位時用預設值補上。
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mappings = (try? c.decode([String: ActionBinding].self, forKey: .mappings)) ?? [:]
        ring = (try? c.decode([ActionBinding].self, forKey: .ring)) ?? Config.defaultRing
        gestures = (try? c.decode([ActionBinding].self, forKey: .gestures)) ?? Config.defaultGestures
        gestureMode = (try? c.decode(Bool.self, forKey: .gestureMode)) ?? true
        ringMode = (try? c.decode(Bool.self, forKey: .ringMode)) ?? true
        ringClick = (try? c.decode(Bool.self, forKey: .ringClick)) ?? false
        ringStyle = (try? c.decode(String.self, forKey: .ringStyle)) ?? "ring"
        ringSize = min(max((try? c.decode(Double.self, forKey: .ringSize)) ?? 50, 0), 100)
        bubbleSize = min(max((try? c.decode(Double.self, forKey: .bubbleSize)) ?? 50, 0), 100)
        ringOpacity = min(max((try? c.decode(Double.self, forKey: .ringOpacity)) ?? 1.0, 0.4), 1.0)
        language = (try? c.decode(String.self, forKey: .language)) ?? "Auto"
        device = (try? c.decode(DeviceSettings.self, forKey: .device)) ?? DeviceSettings()
        diagnosticsToFile = (try? c.decode(Bool.self, forKey: .diagnosticsToFile)) ?? false
        edgeSwitch = (try? c.decode(EdgeSwitchSettings.self, forKey: .edgeSwitch)) ?? EdgeSwitchSettings()
        edgeSwitch.dwell = min(max(edgeSwitch.dwell, EdgeSwitchSettings.dwellRange.lowerBound), EdgeSwitchSettings.dwellRange.upperBound)
    }
}
