import Foundation

// 逐台電量提醒與電池歷史的純邏輯（不碰硬體、不碰畫面，可以單獨測試：tools/battery-alerts-test）。
// 每台裝置各自的門檻、低電量與充飽提醒。

// 每台裝置的提醒設定；沒有設定的裝置用預設值（門檻跟隨「電量低的門檻」）。
struct DeviceBatteryAlert: Codable, Equatable {
    var threshold = 0      // 0：跟隨預設門檻
    var low = true
    var full = false

    init(threshold: Int = 0, low: Bool = true, full: Bool = false) {
        self.threshold = threshold
        self.low = low
        self.full = full
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let level = (try? c.decode(Int.self, forKey: .threshold)) ?? 0
        threshold = level == 0 || [5, 10, 15, 20, 25, 30].contains(level) ? level : 0   // 同 Config.lowBatteryLevels（這個檔要能單獨編譯）
        low = (try? c.decode(Bool.self, forKey: .low)) ?? true
        full = (try? c.decode(Bool.self, forKey: .full)) ?? false
    }
}

enum BatteryDeviceKey {
    static let mouse = "mouse"
    static let keyboard = "keyboard"
    static func other(wpid: String) -> String { "other-" + wpid }
}

// 充飽提醒的狀態：看過「充電中」之後第一次變成充飽才通知；拔掉電源（放電）後重新開始。
struct FullChargeState: Equatable {
    var sawCharging = false
    var notified = false
}

enum BatteryAlerts {
    // 實際用的門檻與開關。defaultLow：沒有逐台設定時低電量提醒開不開（其他裝置沿用舊的「其他裝置的低電量提醒」）。
    static func effective(_ alerts: [String: DeviceBatteryAlert], key: String, defaultLow: Bool,
                          globalThreshold: Int) -> (threshold: Int, low: Bool, full: Bool) {
        guard let a = alerts[key] else { return (globalThreshold, defaultLow, false) }
        return (a.threshold > 0 ? a.threshold : globalThreshold, a.low, a.full)
    }

    // 充飽：裝置回報充飽，或充電中且到了 100%。
    // 同一次插電只通知一次：充飽後插著電補充（回到充電中）不重置，拔掉電源（放電）才算下一次。
    static func fullStep(_ state: FullChargeState, charging: Bool, full: Bool, percent: Int,
                         alertOn: Bool) -> (state: FullChargeState, notify: Bool) {
        var s = state
        let isFull = full || (charging && percent >= 100)
        if isFull {
            guard s.sawCharging, !s.notified else { return (s, false) }
            s.notified = true
            return (s, alertOn)
        }
        if charging {
            s.sawCharging = true
        } else {
            s = FullChargeState()
        }
        return (s, false)
    }

    // 只回報百分比的裝置（MX Master 4、鍵盤）：讀到一次在門檻以下就通知；充電或回到門檻＋3% 之上才重新計算。
    // 回傳 (新的已通知狀態, 要不要通知)。提醒關著時不標成已通知：之後打開，這次放電還會通知一次。
    static func lowStep(notified: Bool, percent: Int, charging: Bool, threshold: Int,
                        alertOn: Bool) -> (notified: Bool, notify: Bool) {
        guard percent >= 0 else { return (notified, false) }
        if charging || percent > threshold + 3 { return (false, false) }
        guard percent <= threshold, !notified, alertOn else { return (notified, false) }
        return (true, true)
    }
}

// MARK: - 電池歷史

struct BatterySample: Codable, Equatable {
    var t: TimeInterval     // 1970 起的秒數
    var p: Int              // 百分比
    var c: Bool             // 充電中（含充飽、接電）
}

struct BatteryHistoryData: Codable, Equatable {
    var names: [String: String] = [:]
    var samples: [String: [BatterySample]] = [:]
}

enum BatteryHistoryLogic {
    static let interval: TimeInterval = 600          // 沒變化時每 10 分鐘記一筆（App 的定時器也是 10 分鐘）
    static let minChangeInterval: TimeInterval = 60  // 有變化也至少隔 1 分鐘，電壓換算的百分比跳動不會灌滿
    static let keep: TimeInterval = 30 * 86_400      // 保留 30 天
    static let maxSamples = 6_000
    static let gap: TimeInterval = 25 * 60           // 兩筆相隔超過 25 分鐘：中間沒有資料（關機、睡眠、App 沒在跑），畫線時斷開

    // 只記裝置真的連著時的讀值：切到別台電腦後快取裡的舊電量不算。
    static func liveReading(connected: Bool, percent: Int) -> Int? { connected && percent >= 0 ? percent : nil }

    // 讀歷史檔。解不開的檔案改名留著（之後的儲存不會蓋掉它），回傳 nil 從空白開始。
    static func load(_ url: URL, now: Date = Date()) -> BatteryHistoryData? {
        guard let raw = try? Data(contentsOf: url) else { return nil }
        if let decoded = try? JSONDecoder().decode(BatteryHistoryData.self, from: raw) { return decoded }
        let aside = url.deletingPathExtension().appendingPathExtension("corrupt-\(Int(now.timeIntervalSince1970)).json")
        try? FileManager.default.moveItem(at: url, to: aside)
        return nil
    }

    static func shouldRecord(last: BatterySample?, percent: Int, charging: Bool, now: TimeInterval) -> Bool {
        guard percent >= 0, percent <= 100 else { return false }
        guard let last else { return true }
        let elapsed = now - last.t
        if elapsed < 0 { return true }               // 時鐘往回調
        if last.p != percent || last.c != charging { return elapsed >= minChangeInterval }
        return elapsed >= interval - 5               // 定時器的小誤差
    }

    static func appended(_ list: [BatterySample], _ sample: BatterySample) -> [BatterySample] {
        var out = list.filter { sample.t - $0.t <= keep && $0.t <= sample.t }
        out.append(sample)
        if out.count > maxSamples { out.removeFirst(out.count - maxSamples) }
        return out
    }

    // 依時間間隔切成幾段連續的線。
    static func segments(_ list: [BatterySample], gap: TimeInterval = gap) -> [[BatterySample]] {
        var result: [[BatterySample]] = []
        for sample in list.sorted(by: { $0.t < $1.t }) {
            if let last = result.last?.last, sample.t - last.t <= gap {
                result[result.count - 1].append(sample)
            } else {
                result.append([sample])
            }
        }
        return result
    }

    // 最近一次充電結束（最後一筆充電中的時間）。
    static func lastCharged(_ list: [BatterySample]) -> TimeInterval? {
        list.last(where: { $0.c })?.t
    }

    // 平均每天掉多少：只算連續、沒充電的相鄰兩筆的淨下降（電壓換算會上下跳，只加下降會高估），除以這些區間的總時間。
    // 不到 2 小時的資料不算。
    static func dailyDrain(_ list: [BatterySample], gap: TimeInterval = gap) -> Double? {
        var drop = 0.0
        var time = 0.0
        let sorted = list.sorted { $0.t < $1.t }
        for (a, b) in zip(sorted, sorted.dropFirst()) where !a.c && !b.c && b.t - a.t <= gap {
            drop += Double(a.p - b.p)
            time += b.t - a.t
        }
        guard time >= 7_200 else { return nil }
        return max(drop, 0) / time * 86_400
    }
}
