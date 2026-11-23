import Foundation

// 「其他裝置」頁的純邏輯：Lightspeed、Unifying、Nano 接收器上的羅技裝置（例如 G502 LIGHTSPEED、M331）。
// 這個檔案不碰硬體，可以單獨編譯測試（見 tools/other-devices-test）。
// 封包格式參考 Solaar（hidpp10.py 的接收器暫存器、hidpp20.py 的電量／DPI／回報率）。
//
// 接收器暫存器（裝置編號 0xFF）：
//   0x2B5 子暫存器 0x2N（N = 槽位-1）配對資訊：[0x2N, ?, ?, WPID 2 bytes, ?, ?, 類型]；0x4N 名稱：[0x4N, 長度, 名稱…]
// 裝置功能：0x0005 名稱與類型、0x0003 韌體、0x1004／0x1000／0x1001 電量、0x2201 DPI、0x8060 回報率、0x8100 內建設定檔

enum OtherDeviceLink: Equatable {
    case online
    case reading            // 接收器列出了這台，詳細資料還在等滑鼠停一下才讀
    case noAnswer           // 配對在接收器上，但沒有回應（睡眠中或關機）
    case receiverGone       // 接收器拔掉了：保留上次的資料（顯示未連線，不讓卡片消失）
}

// 充電狀態（0x1001 的旗標：bit7 外接電源、bit4 慢充、bit3 快充、低 3 位狀態）。
enum OtherChargeState: Equatable {
    case discharging
    case charging
    case full
    case pluggedNotCharging // 接上電源但沒在充
    case error              // 充電錯誤（溫度、電池異常等）
}

enum OtherBatterySource: Equatable {
    case none
    case percent            // 0x1004／0x1000：裝置直接回報百分比
    case voltage            // 0x1001：只有電壓，百分比是換算的估計值
}

struct OtherDeviceSnapshot: Equatable, Identifiable {
    var receiver = ""       // 接收器識別（PID＋位置），和槽位一起當作 id
    var slot = 0
    var name = ""
    var kind = -1           // 0x0005 函式 2：0 鍵盤、3 滑鼠、4 軌跡球、5 觸控板；-1 不知道（先用接收器配對資訊推測）
    var wpid = ""
    var link: OtherDeviceLink = .online
    var batterySource: OtherBatterySource = .none
    var batteryPercent = -1
    var millivolts = 0
    var charging = false
    var full = false
    var firmware = ""
    var dpi = 0
    var dpiMin = 0
    var dpiMax = 0
    var reportRateMs = 0
    var onboardMode = 0     // 1 內建設定檔、2 主機控制；0 沒有這項功能
    var profileCount = 0
    var batterySeq = 0      // 電量成功讀取（或收到電量事件）的次數；低電量判斷用它分辨新舊資料
    var chargeState: OtherChargeState = .discharging
    var fastCharge = false  // 只有 0x1001 會分快充／慢充
    var slowCharge = false
    var lastSeen: Date?     // 最後一次收到裝置回覆或事件的時間
    // 內建設定檔（0x8100）：目前的設定檔（sector）、啟用中的設定檔清單、這個設定檔的各段 DPI（0 = 這段沒用）與目前第幾段。
    var activeProfile = 0
    var profiles: [Int] = []
    var dpiStages: [Int] = []
    var stageIndex = -1
    var buttonCount = 0     // 0x8100 描述：按鍵數（G502 11）與 sector 大小（G502 255）
    var sectorSize = 0
    var buttons: [OtherButtonAssignment] = []   // 目前設定檔的按鍵表
    var defaultStage = -1   // 設定檔裡開機預設的段
    var lights: [OtherLightEffect] = []   // 設定檔裡的燈光（G502：主要區域、G 標誌）
    var unitId = ""         // 0x0003 的序號：區分同型號的兩隻滑鼠（備份與按鍵動作用）
    var repairSector: Int?  // 上次寫入沒完成、等著修復的設定檔
    var profileSlots: [Int] = []   // 目錄裡所有設定檔（含停用的）：裝置回報的編號是這份清單的位置（libratbag）
    var onboardFormatOK = false    // 記憶體、設定檔、巨集格式都是 libratbag 認得的
    var backupKey: String { OtherProfileBackups.deviceKey(wpid: wpid, unitId: unitId) }
    var id: String { receiver + "#\(slot)" }
    // 寫入只開放實機驗證過的型號，而且格式要認得。
    var writeVerified: Bool { onboardFormatOK && OtherDevicesProtocol.writeVerifiedModels.contains(wpid) }
    // 可以改按鍵：已驗證的型號、連著、內建模式、目前是可寫的設定檔（ROM 的 0x01xx 不能寫）、讀到按鍵表
    var canEditButtons: Bool {
        writeVerified && link == .online && onboardMode == 1 && (1..<0x100).contains(activeProfile) && !buttons.isEmpty && sectorSize >= 0x50
    }
    // 接收器 PID（識別字串開頭的 4 個十六進位字）
    var receiverPID: String { String(receiver.prefix(4)) }
    var canSwitchStage: Bool { link == .online && onboardMode == 1 && dpiStages.contains { $0 > 0 } }
    var profileNumber: Int? { profiles.firstIndex(of: activeProfile).map { $0 + 1 } }

    var isPointing: Bool { kind == 3 || kind == 4 || kind == 5 }
}

struct OtherTabLayout: Equatable {
    var width: Double
    var fit: Int
    var overflow: Bool
}

enum OtherDevicesProtocol {
    static let vendor = 0x046D
    // Lightspeed 接收器（參考 Solaar 的 base_usb.py）。Bolt（C548）不在這裡：由滑鼠與接收器頁處理。
    // 這份清單也決定哪些滑鼠「不套用 MX Master 4 的按鍵對應」（EventTap），所以 Unifying／Nano 另外列。
    static let lightspeedReceivers: Set<Int> = [0xC539, 0xC53A, 0xC53D, 0xC53F, 0xC541, 0xC545, 0xC547, 0xC54D]
    static let unifyingNanoReceivers: Set<Int> = [0xC52B, 0xC52F, 0xC532]
    // 「其他裝置」頁要讀的全部接收器。
    static let scannedReceivers = lightspeedReceivers.union(unifyingNanoReceivers)

    static func receiverKind(_ pid: String) -> String {
        switch pid {
        case "C52B", "C532": return "Unifying"
        case "C52F": return "Nano"
        default: return "Lightspeed"
        }
    }

    // 左下角與分頁用的短名稱：「G502 LIGHTSPEED Wireless Gaming Mouse」→「G502」、
    // 「Wireless Mouse B330/M330/M331」→「M330/M331」。沒有名稱時回傳空字串。
    static func shortName(_ name: String) -> String {
        let filler: Set<String> = ["LIGHTSPEED", "WIRELESS", "GAMING", "MOUSE", "KEYBOARD", "LOGITECH"]
        let short = name.split(separator: " ").filter { !filler.contains($0.uppercased()) }.joined(separator: " ")
        let text = short.isEmpty ? name : short
        if text.count > 12, let slash = text.firstIndex(of: "/"), slash != text.startIndex {
            let names = text.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            var joined = names[names.count - 1]
            for candidate in names.dropLast().reversed() {
                guard candidate.count + 1 + joined.count <= 12 else { break }
                joined = candidate + "/" + joined
            }
            return joined
        }
        return String(text.prefix(12))
    }

    // 目前選的裝置還在就不動（裝置離線時畫面不跳走）；不在了才選第一台連著的，都沒連就選第一台。
    static func resolveSelection(_ devices: [OtherDeviceSnapshot], current: String?) -> String? {
        if let current, devices.contains(where: { $0.id == current }) { return current }
        return (devices.first { $0.link == .online } ?? devices.first)?.id
    }

    // 多裝置分頁的排法（同 Windows 版）：放得下就平分，放不下每頁顯示幾個並加左右箭頭。
    // 最小寬度要放得下「M330/M331」加電量，比 Windows 版寬。
    static let tabMinWidth = 130.0, tabMaxWidth = 150.0, tabGap = 6.0, tabArrowWidth = 30.0

    static func tabLayout(count: Int, available: Double) -> OtherTabLayout {
        guard count > 0, available > 0 else { return OtherTabLayout(width: tabMinWidth, fit: 1, overflow: false) }
        let width = max(tabMinWidth, min(tabMaxWidth, (available - tabGap * Double(count - 1)) / Double(count)))
        let fit = Int((available + tabGap) / (width + tabGap))
        guard count > fit else { return OtherTabLayout(width: width, fit: count, overflow: false) }
        let room = available - 2 * (tabArrowWidth + tabGap)
        let paged = max(1, Int((room + tabGap) / (tabMinWidth + tabGap)))
        return OtherTabLayout(width: max(60, (room - tabGap * Double(paged - 1)) / Double(paged)), fit: paged, overflow: true)
    }

    // 分頁從第幾個開始顯示；revealing 是新選到的裝置，要捲到看得見（按箭頭時傳 nil，不會被拉回去）。
    static func tabFirst(_ first: Int, count: Int, fit: Int, revealing: Int? = nil) -> Int {
        var start = first
        if let revealing, revealing >= 0 {
            if revealing < start { start = revealing } else if revealing >= start + fit { start = revealing - fit + 1 }
        }
        return max(0, min(start, count - fit))
    }

    // MARK: 接收器暫存器

    static func pairingRequest(slot: Int) -> [UInt8] { [0x10, 0xFF, 0x83, 0xB5, UInt8(0x20 + slot - 1), 0, 0] }
    static func nameRequest(slot: Int) -> [UInt8] { [0x10, 0xFF, 0x83, 0xB5, UInt8(0x40 + slot - 1), 0, 0] }

    // 配對資訊回覆（11 FF 83 B5 2N …）→ (WPID, HID++ 1.0 類型：1 鍵盤、2 滑鼠…)
    static func pairing(_ reply: [UInt8], slot: Int) -> (wpid: String, kind: Int)? {
        guard reply.count >= 12, reply[0] == 0x11, reply[1] == 0xFF, reply[2] == 0x83, reply[3] == 0xB5,
              reply[4] == UInt8(0x20 + slot - 1) else { return nil }
        let wpid = String(format: "%02X%02X", reply[7], reply[8])
        return wpid == "0000" ? nil : (wpid, Int(reply[11] & 0x0F))
    }

    static func pairedName(_ reply: [UInt8], slot: Int) -> String {
        guard reply.count >= 7, reply[0] == 0x11, reply[2] == 0x83, reply[3] == 0xB5, reply[4] == UInt8(0x40 + slot - 1) else { return "" }
        let length = min(Int(reply[5]), reply.count - 6)
        guard length > 0 else { return "" }
        return String(bytes: reply[6..<(6 + length)], encoding: .utf8)?.trimmingCharacters(in: .controlCharacters) ?? ""
    }

    // HID++ 1.0 類型（接收器配對資訊）→ HID++ 2.0 類型（0x0005）：2 滑鼠→3、1 鍵盤→0、8 軌跡球→4、9 觸控板→5
    static func kind(fromReceiver kind: Int) -> Int {
        switch kind {
        case 1: return 0
        case 2: return 3
        case 8: return 4
        case 9: return 5
        default: return -1
        }
    }

    // 接收器的連線通知（10 槽位 41 協定 旗標 …）：旗標 bit6 = 連線中斷。
    static func connectionNotice(_ bytes: [UInt8]) -> (slot: Int, connected: Bool)? {
        guard bytes.count >= 5, bytes[0] == 0x10, bytes[2] == 0x41, (1...6).contains(bytes[1]) else { return nil }
        return (Int(bytes[1]), bytes[4] & 0x40 == 0)
    }

    // 接收器暫存器 0x00 的通知旗標（3 bytes）；0x000100 = 裝置上線／離線時通知（Solaar 的 NotificationFlag.WIRELESS）。
    // 只開這一位，其他位元照原值寫回；Solaar 另外開的 SOFTWARE_PRESENT 不開，免得改變裝置行為。
    static let notificationFlagsRead: [UInt8] = [0x10, 0xFF, 0x81, 0x00, 0, 0, 0]

    static func wirelessNoticesOn(_ reply: [UInt8]) -> Bool? {
        guard reply.count >= 7, reply[0] == 0x10 || reply[0] == 0x11, reply[1] == 0xFF, reply[2] == 0x81, reply[3] == 0x00 else { return nil }
        return reply[5] & 0x01 != 0
    }

    // 要寫入的封包；回覆不對或已經開著就是 nil。
    static func enableWirelessNotices(_ reply: [UInt8]) -> [UInt8]? {
        guard wirelessNoticesOn(reply) == false else { return nil }
        return [0x10, 0xFF, 0x80, 0x00, reply[4], reply[5] | 0x01, reply[6]]
    }

    // MARK: 電量

    // 鋰電池電壓對照表（數值同 Solaar 的 estimate_battery_level_percentage），中間線性內插。
    static let voltageTable: [(mv: Int, percent: Int)] = [
        (4186, 100), (4067, 90), (3989, 80), (3922, 70), (3859, 60), (3811, 50),
        (3778, 40), (3751, 30), (3717, 20), (3671, 10), (3646, 5), (3579, 2), (3500, 0),
    ]

    static func percent(millivolts mv: Int) -> Int {
        guard let first = voltageTable.first, let last = voltageTable.last else { return -1 }
        if mv >= first.mv { return first.percent }
        if mv <= last.mv { return 0 }
        for i in 0..<(voltageTable.count - 1) {
            let high = voltageTable[i], low = voltageTable[i + 1]
            if mv > low.mv && mv <= high.mv {
                let ratio = Double(mv - low.mv) / Double(high.mv - low.mv)
                return low.percent + Int((ratio * Double(high.percent - low.percent)).rounded())
            }
        }
        return 0
    }

    // 0x1001 函式 0 的回覆或電量事件：電壓（2 bytes，big-endian）＋旗標。
    // 旗標 bit7 = 接上電源；這時低 3 位：0 充電中、1 已充飽、2 接上電源但沒在充、其他是錯誤；bit3 快充、bit4 慢充。
    // （舊版只看低 2 位，「接電沒充」與「錯誤」都被當成放電。）
    static func voltage(_ bytes: [UInt8]) -> (mv: Int, charging: Bool, full: Bool)? {
        guard let v = voltageInfo(bytes) else { return nil }
        return (v.mv, v.state == .charging, v.state == .full)
    }

    static func voltageInfo(_ bytes: [UInt8]) -> (mv: Int, state: OtherChargeState, fast: Bool, slow: Bool)? {
        guard bytes.count >= 7 else { return nil }
        let mv = Int(bytes[4]) << 8 | Int(bytes[5])
        guard mv > 0 else { return nil }
        let flags = bytes[6]
        guard flags & 0x80 != 0 else { return (mv, .discharging, false, false) }
        let state: OtherChargeState
        switch flags & 0x07 {
        case 0: state = .charging
        case 1: state = .full
        case 2: state = .pluggedNotCharging
        default: state = .error
        }
        return (mv, state, state == .charging && flags & 0x08 != 0, state == .charging && flags & 0x10 != 0)
    }

    // 0x1004 函式 1：百分比、等級、充電狀態（0 放電、1 充電中、2 慢充、3 充飽、4 錯誤）。
    static func unifiedBattery(_ bytes: [UInt8]) -> (percent: Int, charging: Bool, full: Bool)? {
        guard let b = unifiedBatteryInfo(bytes) else { return nil }
        return (b.percent, b.state == .charging, b.state == .full)
    }

    static func unifiedBatteryInfo(_ bytes: [UInt8]) -> (percent: Int, state: OtherChargeState, slow: Bool)? {
        guard bytes.count >= 7, bytes[4] <= 100 else { return nil }
        let state: OtherChargeState
        switch bytes[6] {
        case 0: state = .discharging
        case 1, 2: state = .charging
        case 3: state = .full
        default: state = .error
        }
        return (Int(bytes[4]), state, bytes[6] == 2)
    }

    // 0x1000 函式 0：目前百分比、下一級、狀態（0 放電、1 充電中、2 快充飽、3 充飽、4 慢充、5 電池異常、6 溫度錯誤）。
    static func batteryStatus(_ bytes: [UInt8]) -> (percent: Int, charging: Bool, full: Bool)? {
        guard let b = batteryStatusInfo(bytes) else { return nil }
        return (b.percent, b.state == .charging, b.state == .full)
    }

    static func batteryStatusInfo(_ bytes: [UInt8]) -> (percent: Int, state: OtherChargeState, slow: Bool)? {
        guard bytes.count >= 7, bytes[4] <= 100 else { return nil }
        let state: OtherChargeState
        switch bytes[6] {
        case 0: state = .discharging
        case 1, 2, 4: state = .charging
        case 3: state = .full
        default: state = .error
        }
        return (Int(bytes[4]), state, bytes[6] == 4)
    }

    // 電壓會隨負載跳動：取最近幾次的平均再換算。充電狀態改變時重新開始（外面負責清空）。
    static func smoothed(_ samples: [Int]) -> Int {
        guard !samples.isEmpty else { return 0 }
        return Int((Double(samples.reduce(0, +)) / Double(samples.count)).rounded())
    }

    // MARK: DPI、回報率、韌體、名稱

    // 0x2201 函式 1 的清單（從 bytes[5] 起，2 bytes 一個值，0 結束；最高三個位元都是 1 的是前後兩值之間的步進）。
    static func dpiRange(_ bytes: [UInt8]) -> (min: Int, max: Int)? {
        var values: [Int] = []
        var i = 5
        while i + 1 < bytes.count {
            let value = Int(bytes[i]) << 8 | Int(bytes[i + 1])
            if value == 0 { break }
            if value >> 13 != 7 { values.append(value) }
            i += 2
        }
        guard let low = values.min(), let high = values.max() else { return nil }
        return (low, high)
    }

    // 0x2201 函式 2：[感測器, 目前 2 bytes, 預設 2 bytes]
    static func currentDpi(_ bytes: [UInt8]) -> Int {
        guard bytes.count >= 9 else { return 0 }
        let current = Int(bytes[5]) << 8 | Int(bytes[6])
        return current != 0 ? current : Int(bytes[7]) << 8 | Int(bytes[8])
    }

    static func reportRateHz(ms: Int) -> Int { ms > 0 ? 1000 / ms : 0 }

    // 0x0003 函式 1：類型 0 是主程式；名稱 3 字元＋版本＋組建。
    static func firmware(_ info: [UInt8]) -> String? {
        guard info.count >= 12, info[4] & 0x0F == 0 else { return nil }
        let name = String(bytes: info[5...7], encoding: .ascii)?.trimmingCharacters(in: .controlCharacters) ?? ""
        return name + " " + String(format: "%02X.%02X.B%04X", info[8], info[9], Int(info[10]) << 8 | Int(info[11]))
    }

    // MARK: 低電量提醒

    // 每台裝置各自記錄：連續兩次讀到門檻以下（沒在充電）才通知，避免電壓跳動誤報；
    // 充電或回到門檻＋3% 之上才重新計算。回傳 (新的連續次數, 新的已通知狀態, 這次要不要通知)。
    static func lowBattery(percent: Int, charging: Bool, threshold: Int, below: Int, notified: Bool,
                           alertOn: Bool) -> (below: Int, notified: Bool, notify: Bool) {
        guard percent >= 0 else { return (below, notified, false) }
        if charging || percent > threshold + 3 { return (0, false, false) }
        guard percent <= threshold else { return (0, notified, false) }
        let count = below + 1
        guard alertOn, !notified, count >= 2 else { return (count, notified, false) }
        return (count, true, true)
    }

    // MARK: 讀取時機（避免游標卡頓）

    // 每一次 HID++ 問答都要佔用無線通道；G502 回報率 1 ms，移動中連續問二三十次會讓游標卡一下或跳一段。
    // 所以只在滑鼠停下來（各種滑鼠事件都至少 idleSeconds 沒發生）時才讀。
    static let idleSeconds: Double = 2
    // 使用者正在等畫面的讀取（剛連上、重新整理、裝置醒來）：只要短暫停下就讀，移動中仍然不送（2026-11-23）。
    static let quickIdleSeconds: Double = 0.3

    static func mouseIdle(secondsSinceEvents: [Double], threshold: Double = idleSeconds) -> Bool {
        secondsSinceEvents.allSatisfy { $0 >= threshold }
    }

    // 沒回應的裝置要不要再問一次：平常每分鐘一次；剛有滑鼠動作（可能正是它被叫醒）就每 5 秒一次。
    static func wakeCheckDue(lastPing: Date?, now: Date, secondsSinceMouse: Double) -> Bool {
        guard let lastPing else { return true }
        let age = now.timeIntervalSince(lastPing)
        return age >= 60 || (age >= 5 && secondsSinceMouse < 6)
    }

    enum ReadPlan: Equatable {
        case battery        // 已經連著的同一台：只讀電量（＋DPI、回報率），功能表沿用
        case full           // 新裝置、換了裝置、原本沒回應、或使用者按「重新整理」：讀全部
    }

    // 掃描接收器時，對已配對的槽位要讀多少。
    static func readPlan(known: Bool, sameDevice: Bool, online: Bool, hasFeatures: Bool, forceFull: Bool) -> ReadPlan {
        if forceFull || !known || !sameDevice || !online || !hasFeatures { return .full }
        return .battery
    }
}

// MARK: - 內建設定檔（0x8100）：讀目前設定檔與段、切段、切設定檔
// 函式：0 描述、2 模式、3 切換設定檔（2 bytes sector）、4 目前設定檔、5 讀資料（sector 2 bytes＋位移 2 bytes → 16 bytes）、
// 0xB 目前段、0xC 切到第幾段（1 byte）。事件：0 設定檔切換、1 段切換（參數 1 byte 新的段）。
// 切段等同按 DPI 鍵：只改目前用哪一段，不改設定檔內容（11-19 直接寫 0x2201 會被設定檔蓋回去，這個不會）。

enum OtherOnboardEvent: Equatable {
    case profileChanged
    case stageChanged(Int)
}

extension OtherDevicesProtocol {
    static let onboardSetProfile: UInt8 = 3
    static let onboardActiveProfile: UInt8 = 4
    static let onboardReadData: UInt8 = 5
    static let onboardStageIndex: UInt8 = 0xB
    static let onboardSetStage: UInt8 = 0xC

    static func readDataParameters(sector: Int, offset: Int) -> [UInt8] {
        [UInt8(sector >> 8 & 0xFF), UInt8(sector & 0xFF), UInt8(offset >> 8 & 0xFF), UInt8(offset & 0xFF)]
    }

    // 目錄（sector 0）：每 4 bytes 一筆 [sector 高, sector 低, 啟用, ?]，0xFFFF 結束。只回傳啟用的。
    static func directory(_ data: [UInt8]) -> [Int] {
        var list: [Int] = []
        var i = 0
        while i + 3 < data.count {
            let sector = Int(data[i]) << 8 | Int(data[i + 1])
            if sector == 0xFFFF { break }
            if data[i + 2] != 0 && sector != 0 { list.append(sector) }
            i += 4
        }
        return list
    }

    // 設定檔開頭：[回報率, 預設段, 切換鍵段, 5 段 DPI（各 2 bytes little-endian）…]。0 或 0xFFFF 表示那段沒用，回傳 0。
    static func profileStages(_ data: [UInt8]) -> [Int]? {
        guard data.count >= 13 else { return nil }
        let stages = (0..<5).map { i -> Int in
            let value = Int(data[3 + i * 2]) | Int(data[4 + i * 2]) << 8
            return value == 0xFFFF ? 0 : value
        }
        return stages.contains { $0 > 0 } ? stages : nil
    }

    // 函式 4 的回覆 → sector；函式 0xB → 段
    static func activeProfile(_ reply: [UInt8]) -> Int? {
        guard reply.count >= 6 else { return nil }
        let sector = Int(reply[4]) << 8 | Int(reply[5])
        return sector == 0 ? nil : sector
    }

    static func stageIndex(_ reply: [UInt8]) -> Int? {
        guard reply.count >= 5, reply[4] < 5 else { return nil }
        return Int(reply[4])
    }

    // 裝置主動送出的 0x8100 事件（軟體 ID 0）：函式欄 0 設定檔切換、1 段切換。實測 G502：11 01 09 10 03 …（第 4 段）。
    static func onboardEvent(_ bytes: [UInt8], featureIndex: UInt8) -> OtherOnboardEvent? {
        guard bytes.count >= 5, bytes[0] == 0x11, featureIndex != 0, bytes[2] == featureIndex, bytes[3] & 0x0F == 0 else { return nil }
        switch bytes[3] >> 4 {
        case 0: return .profileChanged
        case 1: return bytes[4] < 5 ? .stageChanged(Int(bytes[4])) : nil
        default: return nil
        }
    }

    // 段改了：目前 DPI 跟著換成那段的值（之後再讀 0x2201 確認）。
    static func dpi(forStage index: Int, in stages: [Int]) -> Int? {
        guard stages.indices.contains(index), stages[index] > 0 else { return nil }
        return stages[index]
    }

    // 接收器重新插上：同型號、不同位置（換了 USB 孔）的舊卡片要拿掉，免得同一台出現兩張。
    static func staleAfterReceiverFound(_ devices: [OtherDeviceSnapshot], foundKey: String) -> [String] {
        let pid = String(foundKey.prefix(4))
        return devices.filter { $0.link == .receiverGone && $0.receiverPID == pid && $0.receiver != foundKey }.map(\.id)
    }
}

// MARK: - 讀取流程的輔助邏輯

// 接收器暫存器問答的結果：回覆、錯誤回覆（槽位沒配對時接收器回 8F）、逾時（沒收到）。
enum OtherRegisterOutcome: Equatable {
    case reply([UInt8])
    case error
    case timeout
}

enum OtherSlotState: Equatable {
    case paired(wpid: String, kind: Int)
    case empty          // 接收器確定說這個槽位沒有裝置
    case unknown        // 沒收到或回覆對不上：保留上次的資料，不要把卡片清掉
}

// 每一筆 HID++ 送出前都重看一次滑鼠：動起來就等一下（最多 maxWait 秒），還在動就中斷這一批，
// 後面的問答全部不送，等下一輪。舊版只在一批開始前看一次，移動中仍會把剩下的二十幾筆送完。
struct OtherReadGate {
    private(set) var interrupted = false

    mutating func begin() { interrupted = false }

    mutating func allow(idle: () -> Bool, wait: (Double) -> Void, maxWait: Double = 3, step: Double = 0.2) -> Bool {
        if interrupted { return false }
        var waited = 0.0
        while !idle() {
            if waited >= maxWait {
                interrupted = true
                return false
            }
            wait(step)
            waited += step
        }
        return true
    }
}

// 等滑鼠停下時排隊的接收器掃描：同一台接收器只排一次，重複要求合併（有一次要整台重讀就整台重讀）。
struct OtherScanQueue {
    private var queued: [String: (full: Bool, token: UInt64)] = [:]
    private var nextToken: UInt64 = 0

    // 回傳 true：要新排一次；false：已經排著，只合併 full。
    mutating func request(_ key: String, full: Bool) -> Bool {
        if let existing = queued[key] {
            queued[key] = (existing.full || full, existing.token)
            return false
        }
        nextToken += 1
        queued[key] = (full, nextToken)
        return true
    }

    // 這次排隊的識別：等待中的回呼只能取走自己那一筆，不會吃掉之後才排進來的請求。
    func token(_ key: String) -> UInt64? { queued[key]?.token }

    // 輪到執行（或放棄）時取出；nil 表示已經被取走。
    mutating func take(_ key: String) -> Bool? { queued.removeValue(forKey: key)?.full }

    mutating func take(_ key: String, token: UInt64) -> Bool? {
        guard queued[key]?.token == token else { return nil }
        return queued.removeValue(forKey: key)?.full
    }
}

// HID++ 問答的軟體 ID：每筆輪替，逾時的 ID 隔離一段時間，遲到的回覆不會被當成下一筆的結果。
struct OtherRequestIds {
    static let hold: Double = 5
    private var next: UInt8 = 1
    private var quarantine: [UInt8: Double] = [:]

    mutating func take(now: Double) -> UInt8 {
        quarantine = quarantine.filter { $0.value > now }
        for _ in 0..<15 {
            let id = next
            next = next >= 0x0F ? 1 : next + 1
            if quarantine[id] == nil { return id }
        }
        // 全部都在隔離中：用最快解除的那個。
        let id = quarantine.min { $0.value < $1.value }?.key ?? 1
        quarantine[id] = nil
        return id
    }

    mutating func timedOut(_ id: UInt8, now: Double) { quarantine[id] = now + OtherRequestIds.hold }
}

// MARK: - 設定檔寫入流程（純邏輯，傳輸由呼叫端提供）

enum OtherWriteResult: Equatable {
    case written             // 寫入、讀回一致、已重新載入
    case writtenNotApplied   // 寫入、讀回一致，但重新載入或切回原本的段沒有確認
    case unchanged           // 內容相同，沒有寫
    case profileChanged      // 滑鼠目前的設定檔不是使用者在編輯的那一個，沒有寫
    case readFailed
    case backupFailed
    case unexpectedContent
    case leftClickLocked
    case noBackup
    case failedUnchanged     // 寫入沒成功，讀回和原本一樣
    case failedRolledBack    // 寫入沒成功，已改回原本的內容
    case failedNeedsRepair   // 寫入沒成功也沒能改回：裝置連回來後要修復
}

enum OtherWriteMode {
    case patch(([UInt8]) -> [UInt8]?)
    case restore([UInt8]?)   // 還原原本的設定檔：目前內容損毀也要能還原
    case repair([UInt8]?)    // 修復上次沒寫完的設定檔：不要求它還是目前使用中的設定檔
}

struct OtherProfileIO {
    var activeSector: () -> Int?
    var read: (Int) -> [UInt8]?
    var command: (UInt8, [UInt8]) -> Bool   // 0x8100 的函式與參數；收到回覆才是 true
    var backup: ([UInt8]) -> Bool
    var reload: () -> Bool
}

struct OtherWriteOutcome: Equatable {
    var result: OtherWriteResult
    var target: [UInt8]? = nil
    var repairImage: [UInt8]? = nil   // result 是 failedNeedsRepair 時，之後要寫回去的內容
}

enum OtherProfileWriter {
    // 任何一步沒回覆就停，不送「完成寫入」：未確認的資料不提交，結果一律看讀回。
    static func transfer(sector: Int, data: [UInt8], io: OtherProfileIO) -> Bool {
        for step in OtherDevicesProtocol.writePlan(sector: sector, data: data) {
            guard io.command(step.function, step.parameters) else { return false }
        }
        return true
    }

    static func run(sector: Int, mode: OtherWriteMode, io: OtherProfileIO) -> OtherWriteOutcome {
        var isRepair = false
        if case .repair = mode { isRepair = true }
        if !isRepair, io.activeSector() != sector { return OtherWriteOutcome(result: .profileChanged) }
        let current = io.read(sector)
        let currentValid = current.map(OtherDevicesProtocol.crcValid) ?? false

        let target: [UInt8]
        switch mode {
        case .patch(let patch):
            guard let current, currentValid else { return OtherWriteOutcome(result: .readFailed) }
            guard let patched = patch(current) else { return OtherWriteOutcome(result: .unexpectedContent) }
            target = patched
        case .restore(let image), .repair(let image):
            guard let image, OtherDevicesProtocol.crcValid(image), current == nil || image.count == current?.count else {
                return OtherWriteOutcome(result: .noBackup)
            }
            target = image
        }
        guard OtherDevicesProtocol.leftClickSafe(target, current: currentValid ? current : nil) else {
            return OtherWriteOutcome(result: .leftClickLocked)
        }
        if target == current { return OtherWriteOutcome(result: .unchanged, target: target) }
        // 目前內容有效才需要備份；損毀的內容不值得為它擋下還原。
        if let current, currentValid, !io.backup(current) { return OtherWriteOutcome(result: .backupFailed) }
        // 讀整個 sector 要一點時間，寫之前再確認一次沒有被切走。
        if !isRepair, io.activeSector() != sector { return OtherWriteOutcome(result: .profileChanged) }

        _ = transfer(sector: sector, data: target, io: io)
        let verify = io.read(sector)
        if verify == target {
            return OtherWriteOutcome(result: io.reload() ? .written : .writtenNotApplied, target: target)
        }
        if let verify, verify == current { return OtherWriteOutcome(result: .failedUnchanged) }
        guard let current, currentValid else {
            return OtherWriteOutcome(result: .failedNeedsRepair, repairImage: target)
        }
        _ = transfer(sector: sector, data: current, io: io)
        if io.read(sector) == current { return OtherWriteOutcome(result: .failedRolledBack) }
        return OtherWriteOutcome(result: .failedNeedsRepair, repairImage: current)
    }
}

// 設定檔備份：以實體裝置（WPID＋序號）區分，不覆蓋既有檔案，存完讀回確認。
struct OtherProfileBackups {
    let folder: URL

    static func deviceKey(wpid: String, unitId: String) -> String { unitId.isEmpty ? wpid : wpid + "-" + unitId }

    func originalURL(device: String, sector: Int) -> URL {
        folder.appendingPathComponent(String(format: "%@-%04X-original.bin", device, sector))
    }

    func repairURL(device: String, sector: Int) -> URL {
        folder.appendingPathComponent(String(format: "%@-%04X-repair.bin", device, sector))
    }

    func loadImage(_ url: URL, size: Int) -> [UInt8]? {
        guard let raw = try? Data(contentsOf: url), raw.count == size else { return nil }
        let bytes = [UInt8](raw)
        return OtherDevicesProtocol.crcValid(bytes) ? bytes : nil
    }

    private func writeNew(_ data: [UInt8], to url: URL) -> Bool {
        let temp = folder.appendingPathComponent(".tmp-" + UUID().uuidString)
        do {
            try Data(data).write(to: temp, options: .atomic)
            try FileManager.default.moveItem(at: temp, to: url)   // 目的地已存在會失敗，不會覆蓋
        } catch {
            try? FileManager.default.removeItem(at: temp)
            return false
        }
        return (try? Data(contentsOf: url)) == Data(data)
    }

    // 第一次改這個設定檔時存「原本」的內容，每次寫入前另存一份帶時間的；都存好才回傳 true。
    func save(_ data: [UInt8], device: String, sector: Int, now: Date = Date()) -> Bool {
        guard (try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)) != nil else { return false }
        let original = originalURL(device: device, sector: sector)
        if !FileManager.default.fileExists(atPath: original.path), !writeNew(data, to: original) { return false }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss-SSS"
        let stem = String(format: "%@-%04X-", device, sector) + f.string(from: now)
        for attempt in 0..<100 {
            let url = folder.appendingPathComponent(stem + (attempt == 0 ? "" : "-\(attempt)") + ".bin")
            if FileManager.default.fileExists(atPath: url.path) { continue }
            return writeNew(data, to: url)
        }
        return false
    }

    func saveRepair(_ data: [UInt8], device: String, sector: Int) -> Bool {
        guard (try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)) != nil else { return false }
        let url = repairURL(device: device, sector: sector)
        // 已經有待修復的內容就保留最早那份：它才是最後一次確認完好的設定檔。
        if FileManager.default.fileExists(atPath: url.path) { return true }
        return writeNew(data, to: url)
    }

    func clearRepair(device: String, sector: Int) {
        try? FileManager.default.removeItem(at: repairURL(device: device, sector: sector))
    }

    func pendingRepair(device: String) -> Int? {
        let prefix = device + "-", suffix = "-repair.bin"
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { $0.hasPrefix(prefix) && $0.hasSuffix(suffix) }.compactMap {
            Int($0.dropFirst(prefix.count).dropLast(suffix.count), radix: 16)
        }.min()
    }

    // 舊版的原始備份檔名只有 WPID：第一台讀到序號的裝置接手，之後別台同型號就不會誤用。
    func adoptLegacy(wpid: String, unitId: String) {
        guard !unitId.isEmpty else { return }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for name in names where name.hasPrefix(wpid + "-") && name.hasSuffix("-original.bin") {
            let middle = name.dropFirst(wpid.count + 1).dropLast("-original.bin".count)
            guard middle.count == 4, let sector = Int(middle, radix: 16) else { continue }
            let target = originalURL(device: OtherProfileBackups.deviceKey(wpid: wpid, unitId: unitId), sector: sector)
            guard !FileManager.default.fileExists(atPath: target.path) else { continue }
            try? FileManager.default.moveItem(at: folder.appendingPathComponent(name), to: target)
        }
    }
}

extension OtherDevicesProtocol {
    // 0x0003 函式 0 回覆的序號（bytes 5–8）；全 0 或全 F 當作沒有。
    static func unitId(_ reply: [UInt8]) -> String {
        guard reply.count >= 9 else { return "" }
        let bytes = Array(reply[5..<9])
        if bytes.allSatisfy({ $0 == 0 }) || bytes.allSatisfy({ $0 == 0xFF }) { return "" }
        return bytes.map { String(format: "%02X", $0) }.joined()
    }

    // 左鍵不能被改掉：目標要是左鍵，或和目前有效內容相同（使用者原本就這樣設）。
    static func leftClickSafe(_ target: [UInt8], current: [UInt8]?) -> Bool {
        guard let left = profileButtons(target, count: 1).first else { return false }
        if left == .mouse(1) { return true }
        guard let current, let before = profileButtons(current, count: 1).first else { return false }
        return before == left
    }

    // 編輯器的 DPI 驗證：有在用的段不能填 0；沒在用的段維持 0。
    static func validStage(_ value: Int, original: Int, min: Int, max: Int, step: Int = 50) -> Bool {
        if original == 0 { return value == 0 }
        return value >= min && value <= max && value % step == 0
    }

    // 重新連線的通知（0x41、0x1D4B）要不要重讀：裝置不在線，或超過 3 秒沒完整讀過才讀，同一次開機只讀一輪。
    static func reconnectReadNeeded(online: Bool, lastFullRead: Date?, now: Date) -> Bool {
        guard online, let lastFullRead else { return true }
        return now.timeIntervalSince(lastFullRead) > 3
    }

    // 讀取途中有問答逾時：要再問一次裝置還在不在，才能標成上線。
    static func readConfirmsOnline(timeouts: Int, stillAnswers: () -> Bool) -> Bool {
        timeouts == 0 || stillAnswers()
    }

    // 「交給 App」的動作分裝置、分設定檔存。
    static func appActionKey(_ d: OtherDeviceSnapshot, number: Int) -> String {
        String(format: "%@-%04X:%d", d.backupKey, d.activeProfile, number)
    }

    // 舊版的鍵（只有鍵號）搬到目前設定檔用到那個鍵號的位置；沒有變動回傳 nil。
    static func migratedAppActions<V>(_ actions: [String: V], device d: OtherDeviceSnapshot) -> [String: V]? {
        guard !d.unitId.isEmpty, d.activeProfile != 0 else { return nil }
        var out = actions, changed = false
        for button in d.buttons {
            guard let n = button.appButton, let value = out["\(n)"] else { continue }
            let key = appActionKey(d, number: n)
            if out[key] == nil { out[key] = value }
            out["\(n)"] = nil
            changed = true
        }
        return changed ? out : nil
    }

    // 這個鍵號的事件來自哪一台：優先比對接收器，再看目前設定檔有用到這個鍵號的裝置。
    static func device(forAppButton n: Int, receiver: String, in list: [OtherDeviceSnapshot]) -> OtherDeviceSnapshot? {
        let candidates = list.filter { $0.link == .online && $0.buttons.contains(.mouse(n)) }
        return candidates.first { $0.receiver == receiver } ?? candidates.first
    }
}

// 每台其他裝置的低電量狀態。seq 是電量成功讀取的次數，同一筆快取重複發布不算第二次；
// wpid 不同表示同一個槽位換了裝置，從頭算。
struct OtherLowBatteryState: Equatable {
    var wpid = ""
    var seq = -1
    var below = 0
    var notified = false
}

extension OtherDevicesProtocol {
    static func slotState(_ outcome: OtherRegisterOutcome, slot: Int) -> OtherSlotState {
        switch outcome {
        case .timeout:
            return .unknown
        case .error:
            return .empty
        case .reply(let bytes):
            if let p = pairing(bytes, slot: slot) { return .paired(wpid: p.wpid, kind: p.kind) }
            // 子暫存器對得上但 WPID 是 0000：沒有裝置；對不上：不是這次的回覆。
            let matches = bytes.count >= 12 && bytes[0] == 0x11 && bytes[1] == 0xFF && bytes[2] == 0x83 &&
                bytes[3] == 0xB5 && bytes[4] == UInt8(0x20 + slot - 1)
            return matches ? .empty : .unknown
        }
    }

    // 裝置沒回應時清掉功能表（重連後重查），但留著 0x1D4B 的索引：重連事件要靠它才認得出來。
    static func featuresAfterNoAnswer(_ table: [Int: UInt8]?) -> [Int: UInt8] {
        guard let index = table?[0x1D4B] else { return [:] }
        return [0x1D4B: index]
    }

    // 用「上次檢查的時間」判斷配對清單檢查到了沒有：滑鼠一直在動、略過幾輪後，停下來的第一輪就會補做。
    static let pairingCheckInterval: TimeInterval = 300
    static func pairingCheckDue(last: Date?, now: Date) -> Bool {
        guard let last else { return true }
        return now.timeIntervalSince(last) >= pairingCheckInterval
    }

    static func lowBatteryStep(previous: OtherLowBatteryState?, wpid: String, seq: Int, percent: Int, charging: Bool,
                               threshold: Int, alertOn: Bool) -> (state: OtherLowBatteryState, notify: Bool) {
        var state = previous ?? OtherLowBatteryState()
        if state.wpid != wpid { state = OtherLowBatteryState(wpid: wpid) }
        guard seq != state.seq else { return (state, false) }
        state.seq = seq
        let r = lowBattery(percent: percent, charging: charging, threshold: threshold, below: state.below,
                           notified: state.notified, alertOn: alertOn)
        state.below = r.below
        state.notified = r.notified
        return (state, r.notify)
    }
}

// MARK: - 內建設定檔的按鍵（2026-11-23）
// 設定檔 0x20 起每顆鍵 4 bytes（G502 共 11 顆；0x60 起是 G-shift 那一組，不動）。格式（Solaar hidpp20 Button，實測 G502 相同）：
//   80 01 <遮罩 2 bytes>  送出滑鼠鍵（bit0 左鍵、bit1 右鍵、bit2 中鍵、bit3 上一頁、bit4 下一頁、bit5 起是第 6 鍵…）
//   80 02 <修飾鍵> <鍵碼>  送出鍵盤按鍵（HID 鍵碼；修飾鍵 01 Ctrl、02 Shift、04 Option、08 Command）
//   80 03 <碼 2 bytes>    送出媒體鍵（Consumer：E9 音量＋、EA 音量－、E2 靜音、CD 播放／暫停、B5 下一首、B6 上一首）
//   80 00 00 00           不做事（停用）
//   90 <功能> 00 00       滑鼠自己的功能（01 滾輪左撥、02 右撥、03 DPI＋、04 DPI－、05 循環 DPI、07 狙擊、08 下一個設定檔…）
// 最後 2 bytes 是 CRC-CCITT（初值 0xFFFF、多項式 0x1021，算到倒數第 3 個 byte 為止；實測 G502 設定檔 1 = DF70）。
// 寫入：函式 6 [sector 2, 位移 2, 長度 2]、函式 7 每次 16 bytes、函式 8 結束。

enum OtherButtonAssignment: Equatable, Hashable {
    case mouse(Int)                  // 第幾顆滑鼠鍵（1 起算）
    case key(modifiers: UInt8, usage: UInt8)
    case consumer(UInt16)
    case function(UInt8)
    case disabled
    case unknown([UInt8])

    init(_ b: [UInt8]) {
        guard b.count >= 4 else { self = .unknown(b); return }
        switch (b[0], b[1]) {
        case (0x80, 0x01):
            let mask = Int(b[2]) << 8 | Int(b[3])
            if mask != 0 && mask & (mask - 1) == 0 { self = .mouse(mask.trailingZeroBitCount + 1) } else { self = .unknown(Array(b.prefix(4))) }
        case (0x80, 0x02): self = .key(modifiers: b[2], usage: b[3])
        case (0x80, 0x03): self = .consumer(UInt16(b[2]) << 8 | UInt16(b[3]))
        case (0x80, 0x00): self = .disabled
        case (0x90, _): self = .function(b[1])
        default: self = .unknown(Array(b.prefix(4)))
        }
    }

    var bytes: [UInt8] {
        switch self {
        case .mouse(let n):
            let mask = 1 << (n - 1)
            return [0x80, 0x01, UInt8(mask >> 8 & 0xFF), UInt8(mask & 0xFF)]
        case .key(let m, let u): return [0x80, 0x02, m, u]
        case .consumer(let c): return [0x80, 0x03, UInt8(c >> 8), UInt8(c & 0xFF)]
        case .disabled: return [0x80, 0x00, 0x00, 0x00]
        case .function(let f): return [0x90, f, 0x00, 0x00]
        case .unknown(let raw): return raw
        }
    }

    // 「交給 App」：第 6 鍵起，滑鼠送出這顆鍵，App 收到後執行使用者選的動作（App 開著才有效）。
    var appButton: Int? {
        if case .mouse(let n) = self, n >= 6 { return n }
        return nil
    }
}

extension OtherDevicesProtocol {
    static let buttonTableOffset = 0x20
    static let maxButtons = 16

    static func profileButtons(_ sector: [UInt8], count: Int) -> [OtherButtonAssignment] {
        let n = min(max(count, 0), maxButtons)
        return (0..<n).compactMap { i -> OtherButtonAssignment? in
            let start = buttonTableOffset + i * 4
            guard start + 4 <= sector.count else { return nil }
            return OtherButtonAssignment(Array(sector[start..<(start + 4)]))
        }
    }

    static func crc(_ bytes: [UInt8]) -> UInt16 {
        var c: UInt16 = 0xFFFF
        for byte in bytes {
            c ^= UInt16(byte) << 8
            for _ in 0..<8 { c = c & 0x8000 != 0 ? (c << 1) ^ 0x1021 : c << 1 }
        }
        return c
    }

    static func crcValid(_ sector: [UInt8]) -> Bool {
        guard sector.count >= 3 else { return false }
        let stored = UInt16(sector[sector.count - 2]) << 8 | UInt16(sector[sector.count - 1])
        return crc(Array(sector.dropLast(2))) == stored
    }

    // 改按鍵後的整個設定檔（含新的 CRC）。原本 CRC 不對（讀錯或內容異常）就不改，回傳 nil。
    static func patchedProfile(_ sector: [UInt8], buttons: [Int: OtherButtonAssignment]) -> [UInt8]? {
        guard sector.count > buttonTableOffset + 4, crcValid(sector) else { return nil }
        // 左鍵固定是左鍵（畫面以外的路徑也擋）。
        if let left = buttons[0], left != .mouse(1) { return nil }
        var out = sector
        for (index, assignment) in buttons {
            let start = buttonTableOffset + index * 4
            let raw = assignment.bytes
            guard index >= 0, index < maxButtons, raw.count == 4, start + 4 <= out.count - 2 else { return nil }
            out.replaceSubrange(start..<(start + 4), with: raw)
        }
        let c = crc(Array(out.dropLast(2)))
        out[out.count - 2] = UInt8(c >> 8)
        out[out.count - 1] = UInt8(c & 0xFF)
        return out
    }

    // 寫入的每一筆：(函式, 參數)。
    static func writePlan(sector: Int, data: [UInt8]) -> [(function: UInt8, parameters: [UInt8])] {
        var plan: [(UInt8, [UInt8])] = [(6, [UInt8(sector >> 8 & 0xFF), UInt8(sector & 0xFF), 0, 0,
                                             UInt8(data.count >> 8 & 0xFF), UInt8(data.count & 0xFF)])]
        for start in stride(from: 0, to: data.count, by: 16) {
            plan.append((7, Array(data[start..<min(start + 16, data.count)])))
        }
        plan.append((8, []))
        return plan
    }

    // 讀整個 sector 的位移：每次 16 bytes，最後一次往前對齊，免得讀超過 sector 結尾（實測 G502 sector 255 bytes）。
    static func readOffsets(sectorSize: Int) -> [Int] {
        guard sectorSize >= 16 else { return [0] }
        return stride(from: 0, to: sectorSize, by: 16).map { min($0, sectorSize - 16) }
    }

    // 「交給 App」要用的鍵號：這個設定檔裡還沒用到的第 6–16 鍵中最小的。
    static func freeAppButton(_ buttons: [OtherButtonAssignment], except index: Int) -> Int? {
        let used = Set(buttons.enumerated().compactMap { $0.offset == index ? nil : $0.element.appButton })
        return (6...16).first { !used.contains($0) }
    }

    // G502 LIGHTSPEED（WPID 407F）各鍵的名稱（照設定檔順序，實測前 8 顆與預設功能對得上）；其他裝置用「第 N 鍵」。回傳 (中文, 英文)。
    static func buttonName(wpid: String, index: Int) -> (zh: String, en: String) {
        let g502: [(String, String)] = [("左鍵", "Left button"), ("右鍵", "Right button"), ("滾輪按下", "Wheel click"),
                                        ("上一頁（G4）", "Back (G4)"), ("下一頁（G5）", "Forward (G5)"), ("狙擊（G6）", "Sniper (G6)"),
                                        ("DPI 下（G7）", "DPI down (G7)"), ("DPI 上（G8）", "DPI up (G8)"), ("G9 鍵", "G9 button"),
                                        ("滾輪右撥", "Wheel tilt right"), ("滾輪左撥", "Wheel tilt left")]
        if wpid == "407F", g502.indices.contains(index) { return g502[index] }
        return ("第 \(index + 1) 鍵", "Button \(index + 1)")
    }

    // 改各段 DPI（與開機預設段）後的整個設定檔（含新的 CRC）。值要在範圍內、是 step 的倍數；原本 CRC 不對就不改。
    // 位置：byte 1 預設段、byte 3 起 5 段各 2 bytes little-endian（實測 G502）。沒在用的段維持 0；在用的段不能改成 0。
    static func patchedStages(_ sector: [UInt8], stages: [Int], defaultIndex: Int?, min: Int, max: Int, step: Int = 50) -> [UInt8]? {
        guard sector.count >= 16, crcValid(sector), stages.count == 5, min > 0, max >= min else { return nil }
        var out = sector
        for (i, value) in stages.enumerated() {
            if value == 0 {
                guard sector[3 + i * 2] == 0, sector[4 + i * 2] == 0 else { return nil }
                continue
            }
            guard value >= min, value <= max, value % step == 0 else { return nil }
            out[3 + i * 2] = UInt8(value & 0xFF)
            out[4 + i * 2] = UInt8(value >> 8 & 0xFF)
        }
        if let d = defaultIndex {
            guard stages.indices.contains(d), stages[d] != 0 else { return nil }
            out[1] = UInt8(d)
        }
        let c = crc(Array(out.dropLast(2)))
        out[out.count - 2] = UInt8(c >> 8)
        out[out.count - 1] = UInt8(c & 0xFF)
        return out
    }

    // 回報率：設定檔 byte 0（毫秒；G502 支援 1／2／4／8，11-19 實測 0x8060）。
    static let reportRates = [1, 2, 4, 8]

    static func patchedReportRate(_ sector: [UInt8], ms: Int) -> [UInt8]? {
        guard sector.count >= 16, crcValid(sector), reportRates.contains(ms) else { return nil }
        var out = sector
        out[0] = UInt8(ms)
        let c = crc(Array(out.dropLast(2)))
        out[out.count - 2] = UInt8(c >> 8)
        out[out.count - 1] = UInt8(c & 0xFF)
        return out
    }

    static func defaultStage(_ head: [UInt8]) -> Int? {
        guard head.count >= 2, head[1] < 5 else { return nil }
        return Int(head[1])
    }

    // MARK: 燈光（設定檔 0xD0 起每區 11 bytes：G502 0 主要區域、1 G 標誌；格式照 Solaar LEDEffectSetting，
    // 實測 G502 預設兩區都是「03 00 00 00 00 00 13 88 64 00 00」＝色彩循環、週期 5000 ms、亮度 100）。
    static let lightOffset = 0xD0
    static let lightSize = 11

    static func profileLights(_ sector: [UInt8], zones: Int = 2) -> [OtherLightEffect] {
        (0..<zones).compactMap { i in
            let start = lightOffset + i * lightSize
            guard start + lightSize <= sector.count else { return nil }
            return OtherLightEffect(Array(sector[start..<(start + lightSize)]))
        }
    }

    static func patchedLights(_ sector: [UInt8], _ lights: [Int: OtherLightEffect]) -> [UInt8]? {
        guard sector.count >= lightOffset + 2 * lightSize + 2, crcValid(sector) else { return nil }
        var out = sector
        for (zone, effect) in lights {
            let raw = effect.bytes
            let start = lightOffset + zone * lightSize
            guard (0..<2).contains(zone), raw.count == lightSize else { return nil }
            out.replaceSubrange(start..<(start + lightSize), with: raw)
        }
        let c = crc(Array(out.dropLast(2)))
        out[out.count - 2] = UInt8(c >> 8)
        out[out.count - 1] = UInt8(c & 0xFF)
        return out
    }
}

// MARK: - 依 libratbag 的型號規則（2026-11-23）
extension OtherDevicesProtocol {
    // 實機驗證過寫入流程的型號。其他型號只讀，切段與切設定檔照常（等同按實體鍵）。
    static let writeVerifiedModels: Set<String> = ["407F"]

    // 0x8100 函式 0：[記憶體模型, 設定檔格式, 巨集格式, …]。libratbag 只接受 1／1–5／1。
    static func onboardFormatSupported(_ info: [UInt8]) -> Bool {
        guard info.count >= 7 else { return false }
        return info[4] == 1 && (1...5).contains(info[5]) && info[6] == 1
    }

    // 目錄的全部項目（含停用的），到 0xFFFF 為止。裝置回報與切換用的編號都是這份清單的位置。
    static func directoryEntries(_ data: [UInt8]) -> [Int] {
        var list: [Int] = []
        var i = 0
        while i + 3 < data.count {
            let sector = Int(data[i]) << 8 | Int(data[i + 1])
            if sector == 0xFFFF { break }
            list.append(sector)
            i += 4
        }
        return list
    }

    // 函式 4 的回覆 → 目前的設定檔 sector。libratbag：bytes[5] 是編號，INDEX_OFFSET 的型號從 1 算，其他從 0 算。
    // 不在型號表的裝置不猜；高位元組不是 0（ROM 設定檔）只有從 1 算的型號才照原值用（G502 實測 0x0101）。
    static func resolvedActiveProfile(_ reply: [UInt8], wpid: String, slots: [Int]) -> Int? {
        guard reply.count >= 6, let model = OtherDeviceCatalog.models[wpid] else { return nil }
        let raw = Int(reply[4]) << 8 | Int(reply[5])
        if reply[4] != 0 { return model.oneBasedProfile ? raw : nil }
        let number = Int(reply[5])
        let index = model.oneBasedProfile && number > 0 ? number - 1 : number
        if slots.indices.contains(index) { return slots[index] }
        return model.oneBasedProfile && slots.isEmpty && number > 0 ? raw : nil
    }

    // 切換設定檔（函式 3）：libratbag 一律送 [0, 位置＋1]；不在目錄裡的（ROM）照 sector 送。
    static func setProfileParameters(sector: Int, slots: [Int]) -> [UInt8] {
        if let index = slots.firstIndex(of: sector), index < 255 { return [0, UInt8(index + 1)] }
        return [UInt8(sector >> 8 & 0xFF), UInt8(sector & 0xFF)]
    }

    static func lightSlots(wpid: String) -> [Int] {
        OtherDeviceCatalog.models[wpid]?.secondLightSlot == true ? [1] : [0, 1]
    }

    static func profileLights(_ sector: [UInt8], wpid: String) -> [OtherLightEffect] {
        let all = profileLights(sector, zones: 2)
        return lightSlots(wpid: wpid).compactMap { all.indices.contains($0) ? all[$0] : nil }
    }

    // 接收器只給短名稱或沒有名稱時，用型號表補上。
    static func applyCatalog(_ d: inout OtherDeviceSnapshot) {
        guard let model = OtherDeviceCatalog.models[d.wpid] else { return }
        if d.name.isEmpty { d.name = model.name }
        if d.kind < 0 { d.kind = model.kind }
    }
}

// BEGIN GENERATED device catalog
// 由 MXMasterWin/tools/other-devices-test/catalog.py 產生，不要手改。資料來源：libratbag 1aec93b2f810 (MIT)，授權見 THIRD_PARTY_NOTICES.md。
struct OtherDeviceModel: Equatable {
    let name: String
    let kind: Int
    let oneBasedProfile: Bool   // INDEX_OFFSET：目前設定檔的編號從 1 算
    let secondLightSlot: Bool   // G502X_PLUS：燈光在第 2 個槽位
}

enum OtherDeviceCatalog {
    static let source = "libratbag 1aec93b2f810 (MIT)"
    static let models: [String: OtherDeviceModel] = [
        "400A": OtherDeviceModel(name: "Logitech M325", kind: 3, oneBasedProfile: false, secondLightSlot: false),
        "4011": OtherDeviceModel(name: "Logitech Wireless Touchpad", kind: 3, oneBasedProfile: false, secondLightSlot: false),
        "402C": OtherDeviceModel(name: "Logitech G602", kind: 3, oneBasedProfile: false, secondLightSlot: false),
        "4041": OtherDeviceModel(name: "Logitech MX Master", kind: 3, oneBasedProfile: false, secondLightSlot: false),
        "404A": OtherDeviceModel(name: "Logitech MX Anywhere 2", kind: 3, oneBasedProfile: false, secondLightSlot: false),
        "4052": OtherDeviceModel(name: "Logitech M545", kind: 3, oneBasedProfile: false, secondLightSlot: false),
        "4053": OtherDeviceModel(name: "Logitech G900", kind: 3, oneBasedProfile: false, secondLightSlot: false),
        "405D": OtherDeviceModel(name: "Logitech G403 Wireless", kind: 3, oneBasedProfile: false, secondLightSlot: false),
        "405E": OtherDeviceModel(name: "Logitech M720", kind: 3, oneBasedProfile: false, secondLightSlot: false),
        "405F": OtherDeviceModel(name: "Logitech G Powerplay", kind: -1, oneBasedProfile: false, secondLightSlot: false),
        "4060": OtherDeviceModel(name: "Logitech MX Master", kind: 3, oneBasedProfile: false, secondLightSlot: false),
        "4063": OtherDeviceModel(name: "Logitech MX Anywhere 2", kind: 3, oneBasedProfile: false, secondLightSlot: false),
        "4067": OtherDeviceModel(name: "Logitech G903", kind: 3, oneBasedProfile: false, secondLightSlot: false),
        "4069": OtherDeviceModel(name: "Logitech MX Master 2S", kind: 3, oneBasedProfile: false, secondLightSlot: false),
        "406A": OtherDeviceModel(name: "Logitech MX Anywhere 2S", kind: 3, oneBasedProfile: false, secondLightSlot: false),
        "406B": OtherDeviceModel(name: "Logitech M585/M590", kind: 3, oneBasedProfile: false, secondLightSlot: false),
        "406C": OtherDeviceModel(name: "Logitech G603", kind: 3, oneBasedProfile: false, secondLightSlot: false),
        "406D": OtherDeviceModel(name: "Logitech Marathon M705", kind: 3, oneBasedProfile: false, secondLightSlot: false),
        "406F": OtherDeviceModel(name: "Logitech MX Ergo", kind: 3, oneBasedProfile: false, secondLightSlot: false),
        "4070": OtherDeviceModel(name: "Logitech G703", kind: 3, oneBasedProfile: false, secondLightSlot: false),
        "4071": OtherDeviceModel(name: "Logitech MX Master", kind: 3, oneBasedProfile: false, secondLightSlot: false),
        "4072": OtherDeviceModel(name: "Logitech MX Anywhere 2", kind: 3, oneBasedProfile: false, secondLightSlot: false),
        "4074": OtherDeviceModel(name: "Logitech Gaming Mouse G305", kind: 3, oneBasedProfile: false, secondLightSlot: false),
        "4079": OtherDeviceModel(name: "Logitech G Pro Wireless", kind: 3, oneBasedProfile: false, secondLightSlot: false),
        "407B": OtherDeviceModel(name: "Logitech MX Vertical", kind: 3, oneBasedProfile: false, secondLightSlot: false),
        "407F": OtherDeviceModel(name: "Logitech G502 Hero Wireless", kind: 3, oneBasedProfile: true, secondLightSlot: false),
        "4082": OtherDeviceModel(name: "Logitech MX Master 3", kind: 3, oneBasedProfile: false, secondLightSlot: false),
        "4085": OtherDeviceModel(name: "Logitech G604", kind: 3, oneBasedProfile: true, secondLightSlot: false),
        "4086": OtherDeviceModel(name: "Logitech G703 Hero", kind: 3, oneBasedProfile: false, secondLightSlot: false),
        "4087": OtherDeviceModel(name: "Logitech G903 Hero", kind: 3, oneBasedProfile: false, secondLightSlot: false),
        "4090": OtherDeviceModel(name: "Logitech MX Anywhere 3", kind: 3, oneBasedProfile: false, secondLightSlot: false),
        "4093": OtherDeviceModel(name: "Logitech G Pro X Wireless Superlight", kind: 3, oneBasedProfile: false, secondLightSlot: false),
        "4099": OtherDeviceModel(name: "Logitech G502 X PLUS", kind: 3, oneBasedProfile: true, secondLightSlot: true),
        "409D": OtherDeviceModel(name: "Logitech G705", kind: 3, oneBasedProfile: false, secondLightSlot: true),
        "409F": OtherDeviceModel(name: "Logitech G502 X Wireless", kind: 3, oneBasedProfile: true, secondLightSlot: false),
    ]
}
// END GENERATED device catalog

// 一個燈區的效果。週期單位毫秒，亮度 1–100。
enum OtherLightEffect: Equatable {
    case off
    case fixed(r: UInt8, g: UInt8, b: UInt8)
    case cycle(period: Int, brightness: Int)
    case breathe(r: UInt8, g: UInt8, b: UInt8, period: Int, brightness: Int)
    case unknown([UInt8])

    init(_ b: [UInt8]) {
        guard b.count >= 11 else { self = .unknown(b); return }
        switch b[0] {
        case 0x00: self = .off
        case 0x01: self = .fixed(r: b[1], g: b[2], b: b[3])
        // 亮度 0 代表 100%（libratbag hidpp20_led_cycle／breath）。
        case 0x03: self = .cycle(period: Int(b[6]) << 8 | Int(b[7]), brightness: b[8] == 0 ? 100 : Int(b[8]))
        case 0x0A: self = .breathe(r: b[1], g: b[2], b: b[3], period: Int(b[4]) << 8 | Int(b[5]), brightness: b[7] == 0 ? 100 : Int(b[7]))
        default: self = .unknown(Array(b.prefix(11)))
        }
    }

    var bytes: [UInt8] {
        var b = [UInt8](repeating: 0, count: 11)
        switch self {
        case .off: break
        case .fixed(let r, let g, let bl):
            b[0] = 0x01; b[1] = r; b[2] = g; b[3] = bl
        case .cycle(let period, let brightness):
            b[0] = 0x03; b[6] = UInt8(period >> 8 & 0xFF); b[7] = UInt8(period & 0xFF); b[8] = UInt8(min(max(brightness, 1), 100))
        case .breathe(let r, let g, let bl, let period, let brightness):
            b[0] = 0x0A; b[1] = r; b[2] = g; b[3] = bl
            b[4] = UInt8(period >> 8 & 0xFF); b[5] = UInt8(period & 0xFF); b[7] = UInt8(min(max(brightness, 1), 100))
        case .unknown(let raw): return raw
        }
        return b
    }
}
