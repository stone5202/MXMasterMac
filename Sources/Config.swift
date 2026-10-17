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

// 短促的觸覺波形（MX Master 4 的 0x19B0 都支援；編號參考 Solaar）。各種震動時機共用這份清單。
struct HapticWave: Identifiable {
    let id: Int
    let title: String

    static let defaultWave = 0x04
    static func valid(_ id: Int, or fallback: Int) -> Int { all.contains { $0.id == id } ? id : fallback }
    static func title(_ id: Int) -> String { all.first { $0.id == id }?.title ?? "" }
    static var all: [HapticWave] {
        [
            HapticWave(id: 0x1B, title: Lang.t("極輕", "Whisper")),
            HapticWave(id: 0x04, title: Lang.t("輕微", "Subtle")),
            HapticWave(id: 0x01, title: Lang.t("柔和", "Soft")),
            HapticWave(id: 0x03, title: Lang.t("柔和碰撞", "Soft bump")),
            HapticWave(id: 0x00, title: Lang.t("清脆", "Crisp")),
            HapticWave(id: 0x02, title: Lang.t("清脆碰撞", "Crisp bump")),
        ]
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
    var ringColor = "dark"       // "dark" 深色、"light" 白色
    var ringHaptic = true        // 游標滑過圓環選項時讓滑鼠震一下
    var ringHapticWave = 0x04    // 震動波形，見 HapticWave
    var gestureHaptic = true     // 手勢方向判定完成時
    var gestureHapticWave = 0x03
    var flowHaptic = true        // MX Flow 切換電腦前
    var flowHapticWave = 0x02
    var modeHaptic = true        // 精準模式、段落／自由滾動切換時
    var modeHapticWave = 0x00
    var precisionDpi = 400       // 精準模式的指標速度
    var showModeHUD = true       // 切換模式時在螢幕下方顯示提示
    var gestureSensitivity = 50.0   // 手勢靈敏度 0–100%，50% 是原本的距離
    var lowBatteryAlert = true   // 電量降到門檻以下（沒在充電）時通知一次
    var lowBatteryLevel = 15     // 低電量門檻（%）
    var lowBatteryHapticPause = true   // 低電量時暫停所有震動
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

    // 50% 對應設計尺寸的 0.658 倍；0% 是它的一半，100% 是 1.5 倍。
    // 2026-10-17 與 Windows 版一致縮小：原本基準 0.7，舊的 44%（0.7 × 0.94）變成新的 50%。
    static let ringScaleBase = 0.7 * 0.94
    var ringScaleFactor: Double { Config.ringScaleBase * (0.5 + ringSize / 100) }
    static let maxRingScaleFactor = ringScaleBase * 1.5

    // 相對設計圓圈（半徑 39pt）的倍率：0% = 0.6 倍、50% = 0.8 倍（使用者選定的預設）、
    // 100% = 1.025 倍（使用者選定的上限）。
    var bubbleScaleFactor: Double {
        bubbleSize <= 50 ? 0.6 + 0.2 * (bubbleSize / 50) : 0.8 + 0.225 * ((bubbleSize - 50) / 50)
    }

    static let lowBatteryLevels = [5, 10, 15, 20, 25, 30]

    // 手勢要滑多遠才鎖定方向的倍率：0% = 2 倍距離（較不靈敏）、50% = 原本的距離、100% = 一半。
    var gestureDistanceFactor: Double { pow(2, (50 - gestureSensitivity) / 50) }

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
        ringColor = (try? c.decode(String.self, forKey: .ringColor)) == "light" ? "light" : "dark"
        ringHaptic = (try? c.decode(Bool.self, forKey: .ringHaptic)) ?? true
        ringHapticWave = HapticWave.valid((try? c.decode(Int.self, forKey: .ringHapticWave)) ?? -1, or: HapticWave.defaultWave)
        gestureHaptic = (try? c.decode(Bool.self, forKey: .gestureHaptic)) ?? true
        gestureHapticWave = HapticWave.valid((try? c.decode(Int.self, forKey: .gestureHapticWave)) ?? -1, or: 0x03)
        flowHaptic = (try? c.decode(Bool.self, forKey: .flowHaptic)) ?? true
        flowHapticWave = HapticWave.valid((try? c.decode(Int.self, forKey: .flowHapticWave)) ?? -1, or: 0x02)
        modeHaptic = (try? c.decode(Bool.self, forKey: .modeHaptic)) ?? true
        modeHapticWave = HapticWave.valid((try? c.decode(Int.self, forKey: .modeHapticWave)) ?? -1, or: 0x00)
        precisionDpi = min(max((try? c.decode(Int.self, forKey: .precisionDpi)) ?? 400, 50), 8000)
        showModeHUD = (try? c.decode(Bool.self, forKey: .showModeHUD)) ?? true
        gestureSensitivity = min(max((try? c.decode(Double.self, forKey: .gestureSensitivity)) ?? 50, 0), 100)
        lowBatteryAlert = (try? c.decode(Bool.self, forKey: .lowBatteryAlert)) ?? true
        let level = (try? c.decode(Int.self, forKey: .lowBatteryLevel)) ?? 15
        lowBatteryLevel = Config.lowBatteryLevels.contains(level) ? level : 15
        lowBatteryHapticPause = (try? c.decode(Bool.self, forKey: .lowBatteryHapticPause)) ?? true
        language = (try? c.decode(String.self, forKey: .language)) ?? "Auto"
        device = (try? c.decode(DeviceSettings.self, forKey: .device)) ?? DeviceSettings()
        diagnosticsToFile = (try? c.decode(Bool.self, forKey: .diagnosticsToFile)) ?? false
        edgeSwitch = (try? c.decode(EdgeSwitchSettings.self, forKey: .edgeSwitch)) ?? EdgeSwitchSettings()
        edgeSwitch.dwell = min(max(edgeSwitch.dwell, EdgeSwitchSettings.dwellRange.lowerBound), EdgeSwitchSettings.dwellRange.upperBound)
    }
}
