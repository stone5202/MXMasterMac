// 「其他裝置」純邏輯測試：只編譯 Sources/OtherDevicesProtocol.swift。
// 回覆封包取自 2026-11-19 對 G502 LIGHTSPEED（Lightspeed 接收器 C539）的只讀探測。
// 執行：swiftc -o /tmp/others-test ../../Sources/OtherDevicesProtocol.swift main.swift && /tmp/others-test
import Foundation

var failures = 0
func check(_ name: String, _ ok: Bool) {
    print((ok ? "PASS " : "FAIL ") + name)
    if !ok { failures += 1 }
}
func pad(_ b: [UInt8]) -> [UInt8] { b + [UInt8](repeating: 0, count: max(0, 20 - b.count)) }

typealias P = OtherDevicesProtocol

// 接收器暫存器
check("O1 配對資訊請求是 10 FF 83 B5 20", P.pairingRequest(slot: 1) == [0x10, 0xFF, 0x83, 0xB5, 0x20, 0, 0])
let pairing = P.pairing(pad([0x11, 0xFF, 0x83, 0xB5, 0x20, 0x07, 0x08, 0x40, 0x7F, 0x0C, 0x01, 0x02, 0xB3]), slot: 1)
check("O2 實測配對資訊 → WPID 407F、類型 2（滑鼠）", pairing?.wpid == "407F" && pairing?.kind == 2)
check("O3 子暫存器不符（槽位 2 的請求拿到槽位 1 的回覆）→ 不採用",
      P.pairing(pad([0x11, 0xFF, 0x83, 0xB5, 0x20, 0x07, 0x08, 0x40, 0x7F, 0x0C, 0x01, 0x02]), slot: 2) == nil)
check("O4 名稱暫存器 → G502", P.pairedName(pad([0x11, 0xFF, 0x83, 0xB5, 0x40, 0x04, 0x47, 0x35, 0x30, 0x32]), slot: 1) == "G502")
check("O5 接收器類型 2（滑鼠）→ HID++ 2.0 類型 3", P.kind(fromReceiver: 2) == 3 && P.kind(fromReceiver: 1) == 0 && P.kind(fromReceiver: 7) == -1)
check("O6 連線通知：旗標 bit6 = 中斷", P.connectionNotice([0x10, 0x01, 0x41, 0x10, 0x42, 0x7F, 0x40])?.connected == false &&
      P.connectionNotice([0x10, 0x01, 0x41, 0x10, 0x02, 0x7F, 0x40])?.connected == true)
check("O7 不是 0x41 或槽位不合理 → 不是連線通知",
      P.connectionNotice([0x10, 0x01, 0x40, 0, 0, 0, 0]) == nil && P.connectionNotice([0x10, 0xFF, 0x41, 0, 0, 0, 0]) == nil)

// 電量
check("O8 4016 mV → 83%（3989=80、4067=90 之間內插）", P.percent(millivolts: 4016) == 83)
check("O9 上限與下限：4300 → 100、3400 → 0、3500 → 0", P.percent(millivolts: 4300) == 100 && P.percent(millivolts: 3400) == 0 && P.percent(millivolts: 3500) == 0)
check("O10 剛好在表上的值：3811 → 50", P.percent(millivolts: 3811) == 50)
var monotonic = true
for mv in stride(from: 3450, through: 4250, by: 5) where P.percent(millivolts: mv) < P.percent(millivolts: mv - 5) { monotonic = false }
check("O11 電壓越高百分比不會變少", monotonic)
let discharging = P.voltage(pad([0x11, 0x01, 0x06, 0x0D, 0x0F, 0xB0, 0x00]))
check("O12 實測 0F B0 00 → 4016 mV、未充電", discharging?.mv == 4016 && discharging?.charging == false && discharging?.full == false)
let charging = P.voltage(pad([0x11, 0x01, 0x06, 0x0D, 0x10, 0x0C, 0x90]))
check("O13 實測 10 0C 90 → 4108 mV、充電中", charging?.mv == 4108 && charging?.charging == true && charging?.full == false)
check("O14 旗標 81 → 已充飽", P.voltage(pad([0x11, 0x01, 0x06, 0x0D, 0x10, 0x60, 0x81]))?.full == true)
check("O15 旗標 82（接上電源但沒在充）→ 不算充電", P.voltage(pad([0x11, 0x01, 0x06, 0x0D, 0x10, 0x00, 0x82]))?.charging == false)
check("O16 電壓 0 → 不採用", P.voltage(pad([0x11, 0x01, 0x06, 0x0D, 0, 0, 0])) == nil)
check("O17 0x1004：55%、充電中", P.unifiedBattery(pad([0x11, 1, 5, 0x1D, 55, 2, 1]))?.percent == 55 && P.unifiedBattery(pad([0x11, 1, 5, 0x1D, 55, 2, 1]))?.charging == true)
check("O18 0x1004 百分比超過 100 → 不採用", P.unifiedBattery(pad([0x11, 1, 5, 0x1D, 0xFF, 0, 0])) == nil)
check("O19 0x1000：狀態 3 = 充飽", P.batteryStatus(pad([0x11, 1, 5, 0x0D, 100, 0, 3]))?.full == true)
check("O20 平均：4000、4010、4040 → 4017", P.smoothed([4000, 4010, 4040]) == 4017 && P.smoothed([]) == 0)

// DPI、回報率、韌體
let range = P.dpiRange(pad([0x11, 0x01, 0x0C, 0x1D, 0x00, 0x00, 0x64, 0xE0, 0x32, 0x64, 0x00]))
check("O21 實測 DPI 清單 00 64 E0 32 64 00 → 100–25600（步進值不算）", range?.min == 100 && range?.max == 25600)
check("O22 實測目前 DPI 0C 80 03 20 → 3200", P.currentDpi(pad([0x11, 0x01, 0x0C, 0x2D, 0x00, 0x0C, 0x80, 0x03, 0x20])) == 3200)
check("O23 目前 DPI 是 0 時用預設值", P.currentDpi(pad([0x11, 0x01, 0x0C, 0x2D, 0x00, 0, 0, 0x03, 0x20])) == 800)
check("O24 回報率 1 ms → 1000 Hz、8 ms → 125 Hz、0 → 0", P.reportRateHz(ms: 1) == 1000 && P.reportRateHz(ms: 8) == 125 && P.reportRateHz(ms: 0) == 0)
check("O25 實測韌體（類型 0）→ MPM 17.00.B0008",
      P.firmware(pad([0x11, 0x01, 0x02, 0x1D, 0x00, 0x4D, 0x50, 0x4D, 0x17, 0x00, 0x00, 0x08, 0x01, 0x40, 0x7F, 0x21])) == "MPM 17.00.B0008")
check("O26 開機程式（類型 1）→ 不採用", P.firmware(pad([0x11, 0x01, 0x02, 0x1D, 0x01, 0x42, 0x4F, 0x54, 0x92, 0, 0, 0x08])) == nil)
check("O27 G502 接收器 C539 在支援清單、Bolt C548 不在", P.lightspeedReceivers.contains(0xC539) && !P.lightspeedReceivers.contains(0xC548))

// 低電量提醒（門檻 15）
var r = P.lowBattery(percent: 14, charging: false, threshold: 15, below: 0, notified: false, alertOn: true)
check("O28 第一次低於門檻 → 先不通知", r.below == 1 && !r.notify)
r = P.lowBattery(percent: 13, charging: false, threshold: 15, below: r.below, notified: r.notified, alertOn: true)
check("O29 連續第二次 → 通知", r.notify && r.notified)
r = P.lowBattery(percent: 12, charging: false, threshold: 15, below: r.below, notified: r.notified, alertOn: true)
check("O30 已通知過 → 不再通知", !r.notify)
r = P.lowBattery(percent: 17, charging: false, threshold: 15, below: r.below, notified: r.notified, alertOn: true)
check("O31 回到門檻＋3 以內（17%）→ 保持已通知", r.notified && !r.notify)
r = P.lowBattery(percent: 14, charging: false, threshold: 15, below: r.below, notified: r.notified, alertOn: true)
check("O32 再掉下去也不重複通知", !r.notify)
r = P.lowBattery(percent: 14, charging: true, threshold: 15, below: r.below, notified: r.notified, alertOn: true)
check("O33 充電 → 重新計算", !r.notified && r.below == 0)
let a = P.lowBattery(percent: 14, charging: false, threshold: 15, below: 0, notified: false, alertOn: false)
let b = P.lowBattery(percent: 14, charging: false, threshold: 15, below: a.below, notified: a.notified, alertOn: false)
check("O34 提醒關著 → 不通知也不標成已通知", !b.notify && !b.notified)
let c = P.lowBattery(percent: 16, charging: false, threshold: 15, below: 1, notified: false, alertOn: true)
check("O35 中間跳回門檻之上 → 連續次數歸零", c.below == 0)
check("O36 電量未知（-1）→ 不動", P.lowBattery(percent: -1, charging: false, threshold: 15, below: 1, notified: false, alertOn: true) == (1, false, false))

// 讀取時機（2026-11-20：使用者回報滑鼠用到一半會閃現；舊版每 5 分鐘與每次開視窗都把 G502 整台重讀）
check("O37 已連著的同一台、功能表在 → 只讀電量",
      P.readPlan(known: true, sameDevice: true, online: true, hasFeatures: true, forceFull: false) == .battery)
check("O38 新裝置／換了裝置／原本沒回應／沒有功能表 → 讀全部",
      P.readPlan(known: false, sameDevice: true, online: true, hasFeatures: true, forceFull: false) == .full &&
      P.readPlan(known: true, sameDevice: false, online: true, hasFeatures: true, forceFull: false) == .full &&
      P.readPlan(known: true, sameDevice: true, online: false, hasFeatures: true, forceFull: false) == .full &&
      P.readPlan(known: true, sameDevice: true, online: true, hasFeatures: false, forceFull: false) == .full)
check("O39 按「重新整理」→ 讀全部", P.readPlan(known: true, sameDevice: true, online: true, hasFeatures: true, forceFull: true) == .full)
check("O40 任何一種滑鼠事件 2 秒內發生過 → 不算停下來",
      !P.mouseIdle(secondsSinceEvents: [10, 1.9, 10]) && !P.mouseIdle(secondsSinceEvents: [0, 30]))
check("O41 全部至少 2 秒沒動 → 停下來", P.mouseIdle(secondsSinceEvents: [2, 5, 100]))

// 讀取時機與掃描合併
// 第 2 項：一批開始後滑鼠又動 → 後面的問答不送
func batch(_ idleSequence: [Bool], requests: Int) -> (sent: Int, interrupted: Bool) {
    var gate = OtherReadGate()
    gate.begin()
    var seq = idleSequence[...]
    var sent = 0
    for _ in 0..<requests {
        let ok = gate.allow(idle: { seq.isEmpty ? false : seq.removeFirst() }, wait: { _ in })
        if ok { sent += 1 }
    }
    return (sent, gate.interrupted)
}
let moving = batch([true] + [Bool](repeating: false, count: 100), requests: 6)
check("O42 第一筆後開始移動 → 只送 1 筆、整批中斷", moving.sent == 1 && moving.interrupted)
let brief = batch([true, false, false, true, true, true, true, true], requests: 6)
check("O43 只動一下（3 秒內停下）→ 等一等再繼續，6 筆都送", brief.sent == 6 && !brief.interrupted)
var g = OtherReadGate()
_ = g.allow(idle: { false }, wait: { _ in })
g.begin()
check("O44 中斷後下一批重新開始", g.allow(idle: { true }, wait: { _ in }) && !g.interrupted)

var q = OtherScanQueue()
let first = q.request("C539", full: false)
let second = q.request("C539", full: true)
check("O45 連按兩次重新整理（或連續兩筆連線通知）→ 只排一次，合併成整台重讀",
      first && !second && q.take("C539") == true && q.take("C539") == nil)
check("O46 不同接收器各排各的", q.request("A", full: false) && q.request("B", full: false))

// 第 4 項：讀配對資訊逾時 ≠ 空槽
check("O47 逾時 → 不知道（保留卡片）", P.slotState(.timeout, slot: 1) == .unknown)
check("O48 接收器回錯誤 → 空槽", P.slotState(.error, slot: 1) == .empty)
check("O49 實測配對回覆 → 有裝置 407F",
      P.slotState(.reply(pad([0x11, 0xFF, 0x83, 0xB5, 0x20, 0x07, 0x08, 0x40, 0x7F, 0x0C, 0x01, 0x02])), slot: 1) == .paired(wpid: "407F", kind: 2))
check("O50 WPID 0000 → 空槽；子暫存器對不上 → 不知道",
      P.slotState(.reply(pad([0x11, 0xFF, 0x83, 0xB5, 0x20, 0, 0, 0, 0, 0, 0, 0])), slot: 1) == .empty &&
      P.slotState(.reply(pad([0x11, 0xFF, 0x83, 0xB5, 0x21, 0x07, 0x08, 0x40, 0x7F, 0x0C, 0x01, 0x02])), slot: 1) == .unknown)

// 第 5 項：低電量只數新讀到的電量；同槽換裝置從頭算
var st: OtherLowBatteryState? = nil
var step = P.lowBatteryStep(previous: st, wpid: "407F", seq: 1, percent: 10, charging: false, threshold: 15, alertOn: true)
st = step.state
step = P.lowBatteryStep(previous: st, wpid: "407F", seq: 1, percent: 10, charging: false, threshold: 15, alertOn: true)
check("O51 同一筆 10%（序號沒變）發布兩次 → 不通知", !step.notify && step.state.below == 1)
st = step.state
step = P.lowBatteryStep(previous: st, wpid: "407F", seq: 2, percent: 10, charging: false, threshold: 15, alertOn: true)
check("O52 第二次新讀到 10% → 通知", step.notify)
st = step.state
step = P.lowBatteryStep(previous: st, wpid: "4099", seq: 1, percent: 9, charging: false, threshold: 15, alertOn: true)
st = step.state
step = P.lowBatteryStep(previous: st, wpid: "4099", seq: 2, percent: 9, charging: false, threshold: 15, alertOn: true)
check("O53 同槽位換成另一台（WPID 不同），連續兩次低電量 → 會通知", step.notify)

// 第 6 項：0x1D4B 索引在沒回應後保留；配對清單檢查看時間
check("O54 沒回應後只留 0x1D4B", P.featuresAfterNoAnswer([0x1D4B: 0x0B, 0x1001: 0x07]) == [0x1D4B: 0x0B] &&
      P.featuresAfterNoAnswer([0x1001: 0x07]).isEmpty && P.featuresAfterNoAnswer(nil).isEmpty)
let now = Date()
check("O55 上次掃描 6 分鐘前（中間略過幾輪）→ 這輪補做；4 分鐘前 → 還不用；從沒掃過 → 要做",
      P.pairingCheckDue(last: now.addingTimeInterval(-360), now: now) &&
      !P.pairingCheckDue(last: now.addingTimeInterval(-240), now: now) && P.pairingCheckDue(last: nil, now: now))

// 充電狀態完整解析
check("O56 0x1001 旗標 0x82（接電、狀態 2）→ 已接電未充，不算充電也不算充飽",
      P.voltageInfo(pad([0x11, 1, 7, 0, 0x10, 0x0A, 0x82]))?.state == .pluggedNotCharging &&
      P.voltage(pad([0x11, 1, 7, 0, 0x10, 0x0A, 0x82]))?.charging == false)
check("O57 0x1001 旗標 0x83／0x87 → 充電錯誤（舊版 0x83 也是錯誤，但 0x84 被當成充電中）",
      P.voltageInfo(pad([0x11, 1, 7, 0, 0x10, 0x0A, 0x83]))?.state == .error &&
      P.voltageInfo(pad([0x11, 1, 7, 0, 0x10, 0x0A, 0x84]))?.state == .error)
let fast = P.voltageInfo(pad([0x11, 1, 7, 0, 0x10, 0x0A, 0x88]))
let slow = P.voltageInfo(pad([0x11, 1, 7, 0, 0x10, 0x0A, 0x90]))
check("O58 0x88 快充、0x90 慢充（都是充電中）", fast?.state == .charging && fast?.fast == true && slow?.slow == true && slow?.fast == false)
check("O59 沒接電（bit7 = 0）→ 放電，忽略其他位元", P.voltageInfo(pad([0x11, 1, 7, 0, 0x0F, 0xB3, 0x09]))?.state == .discharging)
check("O60 0x1004 狀態 4 → 錯誤、2 → 慢充", P.unifiedBatteryInfo(pad([0x11, 1, 7, 0x10, 50, 0, 4]))?.state == .error &&
      P.unifiedBatteryInfo(pad([0x11, 1, 7, 0x10, 50, 0, 2]))?.slow == true)
check("O61 0x1000 狀態 6（溫度錯誤）→ 錯誤，4 → 慢充", P.batteryStatusInfo(pad([0x11, 1, 7, 0, 50, 0, 6]))?.state == .error &&
      P.batteryStatusInfo(pad([0x11, 1, 7, 0, 50, 0, 4]))?.slow == true)

// 2026-11-23：內建設定檔（實測 G502：5 個設定檔、設定檔 1 的五段 450／800／1600／3200／6400、目前第 3 段）
let dirData: [UInt8] = [0x00, 0x01, 0x01, 0xFF, 0x00, 0x02, 0x01, 0xFF, 0x00, 0x03, 0x01, 0xFF, 0x00, 0x04, 0x01, 0xFF,
                        0x00, 0x05, 0x01, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]
check("O62 實測目錄 → 設定檔 0001–0005", P.directory(dirData) == [1, 2, 3, 4, 5])
check("O63 停用的設定檔（啟用 byte 0）不列出", P.directory([0x00, 0x01, 0x01, 0xFF, 0x00, 0x02, 0x00, 0xFF, 0xFF, 0xFF, 0, 0]) == [1])
let profData: [UInt8] = [0x01, 0x03, 0x03, 0xC2, 0x01, 0x20, 0x03, 0x40, 0x06, 0x80, 0x0C, 0x00, 0x19, 0xFF, 0xFF, 0xFF]
check("O64 實測設定檔開頭 → 五段 450／800／1600／3200／6400（little-endian）", P.profileStages(profData) == [450, 800, 1600, 3200, 6400])
check("O65 沒用的段（FFFF）→ 0；全部沒用 → nil",
      P.profileStages([1, 0, 0, 0x20, 0x03, 0xFF, 0xFF, 0, 0, 0xFF, 0xFF, 0xFF, 0xFF]) == [800, 0, 0, 0, 0] &&
      P.profileStages([1, 0, 0] + [UInt8](repeating: 0xFF, count: 10)) == nil)
check("O66 實測函式 4 → 設定檔 0001、函式 0xB → 第 3 段（索引 2）",
      P.activeProfile(pad([0x11, 1, 9, 0x4E, 0x00, 0x01])) == 1 && P.stageIndex(pad([0x11, 1, 9, 0xBE, 0x02])) == 2)
check("O67 實測按 DPI 鍵事件 11 01 09 10 03 → 第 4 段", P.onboardEvent(pad([0x11, 1, 9, 0x10, 0x03]), featureIndex: 9) == .stageChanged(3))
check("O68 設定檔切換事件（函式欄 0）→ profileChanged；別的功能或我們自己的回覆（軟體 ID ≠ 0）→ 不是事件",
      P.onboardEvent(pad([0x11, 1, 9, 0x00, 0x00, 0x02]), featureIndex: 9) == .profileChanged &&
      P.onboardEvent(pad([0x11, 1, 7, 0x10, 0x03]), featureIndex: 9) == nil &&
      P.onboardEvent(pad([0x11, 1, 9, 0xCD, 0x03]), featureIndex: 9) == nil &&
      P.onboardEvent(pad([0x11, 1, 9, 0x10, 0x03]), featureIndex: 0) == nil)
check("O69 切段讀資料參數：sector 0001 位移 0 → 00 01 00 00；位移 16 → 00 00 00 10",
      P.readDataParameters(sector: 1, offset: 0) == [0, 1, 0, 0] && P.readDataParameters(sector: 0, offset: 16) == [0, 0, 0, 0x10])
check("O70 段 → DPI；沒用的段或超出範圍 → nil",
      P.dpi(forStage: 3, in: [450, 800, 1600, 3200, 6400]) == 3200 && P.dpi(forStage: 1, in: [800, 0]) == nil &&
      P.dpi(forStage: 7, in: [800]) == nil)
var g5 = OtherDeviceSnapshot(receiver: "C539@20120000", slot: 1)
g5.onboardMode = 1; g5.dpiStages = [450, 800, 1600, 3200, 6400]; g5.profiles = [1, 2, 3, 4, 5]; g5.activeProfile = 2
check("O71 內建模式＋有段＋連著才可切；設定檔 0002 是第 2 個", g5.canSwitchStage && g5.profileNumber == 2)
g5.onboardMode = 2
check("O72 主機模式不顯示切段", !g5.canSwitchStage)
g5.onboardMode = 1; g5.link = .receiverGone
check("O73 接收器未連接不顯示切段", !g5.canSwitchStage && g5.receiverPID == "C539")

// 2026-11-23：接收器拔掉保留卡片；換孔插回時拿掉舊卡
var gone = OtherDeviceSnapshot(receiver: "C539@20120000", slot: 1); gone.link = .receiverGone
var bolt = OtherDeviceSnapshot(receiver: "C547@20120000", slot: 1); bolt.link = .receiverGone
check("O74 同一個孔插回 → 沿用（不拿掉）", P.staleAfterReceiverFound([gone], foundKey: "C539@20120000").isEmpty)
check("O75 換孔插回同型號 → 拿掉舊卡；別的型號的舊卡不動",
      P.staleAfterReceiverFound([gone, bolt], foundKey: "C539@14100000") == [gone.id])

// 2026-11-23：設定檔按鍵（實測 G502 設定檔 1 整個 sector，255 bytes）
let g502Sector: [UInt8] = [0x01, 0x03, 0x03, 0xC2, 0x01, 0x20, 0x03, 0x40, 0x06, 0x80, 0x0C, 0x00, 0x19, 0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x80, 0x01, 0x00, 0x01, 0x80, 0x01, 0x00, 0x02, 0x80, 0x01, 0x00, 0x04, 0x80, 0x01, 0x00, 0x08, 0x80, 0x01, 0x00, 0x10, 0x90, 0x07, 0x00, 0x00, 0x90, 0x04, 0x00, 0x00, 0x90, 0x03, 0x00, 0x00, 0x90, 0x0C, 0x00, 0x00, 0x90, 0x02, 0x00, 0x00, 0x90, 0x01, 0x00, 0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x80, 0x01, 0x00, 0x01, 0x80, 0x01, 0x00, 0x02, 0x80, 0x01, 0x00, 0x04, 0x80, 0x01, 0x00, 0x08, 0x80, 0x01, 0x00, 0x10, 0x90, 0x07, 0x00, 0x00, 0x90, 0x04, 0x00, 0x00, 0x90, 0x03, 0x00, 0x00, 0x90, 0x0C, 0x00, 0x00, 0x90, 0x02, 0x00, 0x00, 0x90, 0x01, 0x00, 0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x50, 0x00, 0x52, 0x00, 0x4F, 0x00, 0x46, 0x00, 0x49, 0x00, 0x4C, 0x00, 0x45, 0x00, 0x5F, 0x00, 0x4E, 0x00, 0x41, 0x00, 0x4D, 0x00, 0x45, 0x00, 0x5F, 0x00, 0x44, 0x00, 0x45, 0x00, 0x46, 0x00, 0x41, 0x00, 0x55, 0x00, 0x4C, 0x00, 0x54, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x13, 0x88, 0x64, 0x00, 0x00, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x13, 0x88, 0x64, 0x00, 0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0xDF, 0x70]
check("O76 實測 sector 是 255 bytes、CRC DF70 正確", g502Sector.count == 255 && P.crcValid(g502Sector) && P.crc(Array(g502Sector.dropLast(2))) == 0xDF70)
let btns = P.profileButtons(g502Sector, count: 11)
check("O77 實測按鍵表：左右中上下頁、狙擊、DPI−、DPI＋、電量、右撥、左撥",
      btns == [.mouse(1), .mouse(2), .mouse(3), .mouse(4), .mouse(5), .function(7), .function(4), .function(3), .function(0x0C),
               .function(2), .function(1)])
check("O78 編碼來回一致（滑鼠鍵遮罩、鍵盤、媒體、停用）",
      OtherButtonAssignment([0x80, 0x01, 0x00, 0x20]) == .mouse(6) && OtherButtonAssignment.mouse(6).bytes == [0x80, 0x01, 0x00, 0x20] &&
      OtherButtonAssignment.key(modifiers: 0x08, usage: 0x06).bytes == [0x80, 0x02, 0x08, 0x06] &&
      OtherButtonAssignment.consumer(0xE9).bytes == [0x80, 0x03, 0x00, 0xE9] && OtherButtonAssignment([0x80, 0, 0, 0]) == .disabled &&
      OtherButtonAssignment.mouse(6).appButton == 6 && OtherButtonAssignment.mouse(5).appButton == nil)
let patched = P.patchedProfile(g502Sector, buttons: [5: .consumer(0xCD)])
check("O79 改第 6 鍵（狙擊）→ 只動那 4 bytes＋CRC，CRC 重算後有效",
      patched != nil && P.crcValid(patched!) && patched![0x34..<0x38] == [0x80, 0x03, 0x00, 0xCD] &&
      zip(patched!, g502Sector).enumerated().filter { $0.element.0 != $0.element.1 }.allSatisfy { (0x34..<0x38).contains($0.offset) || $0.offset >= 253 })
var broken = g502Sector; broken[10] ^= 0xFF
check("O80 原本 CRC 不對 → 不改（nil）", P.patchedProfile(broken, buttons: [5: .disabled]) == nil)
let plan = P.writePlan(sector: 1, data: g502Sector)
check("O81 寫入計畫：函式 6 [00 01 00 00 00 FF]、16 筆函式 7（最後 15 bytes）、函式 8",
      plan.first!.function == 6 && plan.first!.parameters == [0, 1, 0, 0, 0, 0xFF] && plan.filter { $0.function == 7 }.count == 16 &&
      plan[16].parameters.count == 15 && plan.last!.function == 8 && plan.count == 18)
check("O82 讀 255 bytes 的位移：0…224 與最後對齊的 239", P.readOffsets(sectorSize: 255) == Array(stride(from: 0, to: 240, by: 16)) + [239])
check("O83 交給 App 的鍵號：沒用過 → 6；6 已被別顆用 → 7；同一顆重選沿用",
      P.freeAppButton(btns, except: 5) == 6 &&
      P.freeAppButton(btns.enumerated().map { $0.offset == 8 ? .mouse(6) : $0.element }, except: 5) == 7 &&
      P.freeAppButton(btns.enumerated().map { $0.offset == 5 ? .mouse(6) : $0.element }, except: 5) == 6)
check("O84 G502 第 4 鍵叫「上一頁（G4）」，別的裝置叫第 N 鍵",
      P.buttonName(wpid: "407F", index: 3).zh == "上一頁（G4）" && P.buttonName(wpid: "4099", index: 3).zh == "第 4 鍵")
var g6 = OtherDeviceSnapshot(receiver: "C539@1", slot: 1); g6.wpid = "407F"; g6.onboardFormatOK = true; g6.onboardMode = 1; g6.activeProfile = 1; g6.buttons = btns; g6.sectorSize = 255
check("O85 可寫的設定檔才能改；ROM 設定檔（0x0101）不行", g6.canEditButtons && { var r = g6; r.activeProfile = 0x0101; return !r.canEditButtons }())

// 2026-11-23：改各段 DPI 與開機預設段
let ps = P.patchedStages(g502Sector, stages: [400, 800, 1600, 3200, 12000], defaultIndex: 2, min: 100, max: 25600)
check("O86 改第 1、5 段（450→400、6400→12000）與預設段 → 只動那幾個 byte＋CRC，CRC 有效",
      ps != nil && P.crcValid(ps!) && P.profileStages(ps!) == [400, 800, 1600, 3200, 12000] && P.defaultStage(ps!) == 2 &&
      zip(ps!, g502Sector).enumerated().filter { $0.element.0 != $0.element.1 }.allSatisfy { [1, 3, 4, 11, 12].contains($0.offset) || $0.offset >= 253 })
check("O87 超出範圍、不是 50 的倍數、段數不對 → nil",
      P.patchedStages(g502Sector, stages: [450, 800, 1600, 3200, 30000], defaultIndex: nil, min: 100, max: 25600) == nil &&
      P.patchedStages(g502Sector, stages: [455, 800, 1600, 3200, 6400], defaultIndex: nil, min: 100, max: 25600) == nil &&
      P.patchedStages(g502Sector, stages: [450, 800], defaultIndex: nil, min: 100, max: 25600) == nil)
check("O88 預設段指到沒用的段 → nil；實測預設段是第 4 段（索引 3）",
      P.patchedStages(g502Sector, stages: [450, 0, 1600, 3200, 6400], defaultIndex: 1, min: 100, max: 25600) == nil &&
      P.defaultStage(g502Sector) == 3)

// 2026-11-23：燈光
let lights = P.profileLights(g502Sector)
check("O89 實測兩區都是色彩循環、5000 ms、亮度 100", lights == [.cycle(period: 5000, brightness: 100), .cycle(period: 5000, brightness: 100)])
check("O90 編碼：循環＝實測原樣；固定顏色、關閉、呼吸（Solaar 格式）",
      OtherLightEffect.cycle(period: 5000, brightness: 100).bytes == [3, 0, 0, 0, 0, 0, 0x13, 0x88, 0x64, 0, 0] &&
      OtherLightEffect.fixed(r: 255, g: 0, b: 128).bytes == [1, 255, 0, 128, 0, 0, 0, 0, 0, 0, 0] &&
      OtherLightEffect.off.bytes == [UInt8](repeating: 0, count: 11) &&
      OtherLightEffect(OtherLightEffect.breathe(r: 1, g: 2, b: 3, period: 4000, brightness: 60).bytes) == .breathe(r: 1, g: 2, b: 3, period: 4000, brightness: 60))
let pl = P.patchedLights(g502Sector, [1: .fixed(r: 0, g: 255, b: 0)])
check("O91 只改 G 標誌 → 只動 0xDB–0xE5 與 CRC，CRC 有效、主要區域不變",
      pl != nil && P.crcValid(pl!) && P.profileLights(pl!) == [.cycle(period: 5000, brightness: 100), .fixed(r: 0, g: 255, b: 0)] &&
      zip(pl!, g502Sector).enumerated().filter { $0.element.0 != $0.element.1 }.allSatisfy { (0xDB..<0xE6).contains($0.offset) || $0.offset >= 253 })
check("O92 區域超出 0–1 → nil", P.patchedLights(g502Sector, [2: .off]) == nil)

// 2026-11-23：回報率（設定檔 byte 0）
let pr = P.patchedReportRate(g502Sector, ms: 4)
check("O93 1 ms → 4 ms（250 Hz）：只動 byte 0 與 CRC",
      pr != nil && P.crcValid(pr!) && pr![0] == 4 &&
      zip(pr!, g502Sector).enumerated().filter { $0.element.0 != $0.element.1 }.allSatisfy { $0.offset == 0 || $0.offset >= 253 })
check("O94 不支援的值（3 ms、0）→ nil", P.patchedReportRate(g502Sector, ms: 3) == nil && P.patchedReportRate(g502Sector, ms: 0) == nil)

// 2026-11-23：使用者在等畫面時短暫停下就讀；沒回應的裝置有滑鼠動作時較快重試
check("O95 快速門檻：0.1 秒前動過 → 不讀；0.3 秒 → 可讀；定時讀取的 2 秒門檻不變",
      !P.mouseIdle(secondsSinceEvents: [0.1, 5], threshold: P.quickIdleSeconds) &&
      P.mouseIdle(secondsSinceEvents: [0.3, 5], threshold: P.quickIdleSeconds) &&
      !P.mouseIdle(secondsSinceEvents: [0.3, 5]))
let wakeNow = Date()
check("O96 沒問過 → 要問", P.wakeCheckDue(lastPing: nil, now: wakeNow, secondsSinceMouse: 1000))
check("O97 3 秒前才問過，就算滑鼠剛動 → 不問", !P.wakeCheckDue(lastPing: wakeNow - 3, now: wakeNow, secondsSinceMouse: 0.5))
check("O98 6 秒前問過：滑鼠剛動 → 問；滑鼠很久沒動 → 不問",
      P.wakeCheckDue(lastPing: wakeNow - 6, now: wakeNow, secondsSinceMouse: 1) &&
      !P.wakeCheckDue(lastPing: wakeNow - 6, now: wakeNow, secondsSinceMouse: 100))
check("O99 滑鼠都沒動 → 還是每分鐘問一次", P.wakeCheckDue(lastPing: wakeNow - 61, now: wakeNow, secondsSinceMouse: 1000))

// 2026-11-23：接收器的上線／離線通知
check("O100 旗標全關 → 只開 0x000100", P.wirelessNoticesOn([0x10, 0xFF, 0x81, 0x00, 0, 0, 0]) == false &&
      P.enableWirelessNotices([0x10, 0xFF, 0x81, 0x00, 0, 0, 0]) == [0x10, 0xFF, 0x80, 0x00, 0, 0x01, 0])
check("O101 其他位元照原值寫回", P.enableWirelessNotices([0x10, 0xFF, 0x81, 0x00, 0x10, 0x08, 0x02]) == [0x10, 0xFF, 0x80, 0x00, 0x10, 0x09, 0x02])
check("O102 已經開著 → 不寫", P.wirelessNoticesOn([0x10, 0xFF, 0x81, 0x00, 0, 0x01, 0]) == true &&
      P.enableWirelessNotices([0x10, 0xFF, 0x81, 0x00, 0, 0x01, 0]) == nil)
check("O103 不是這個暫存器的回覆 → 不寫", P.wirelessNoticesOn([0x10, 0xFF, 0x81, 0x02, 0, 0, 0]) == nil &&
      P.enableWirelessNotices([0x10, 0xFF, 0x8F, 0x81, 0x00, 0x02, 0]) == nil)

// 設定檔寫入流程：假裝置模擬斷線，不碰實體滑鼠。
final class FakeMouse {
    var sector: [UInt8]
    var activeProfile = 1
    var buffer: [UInt8] = []
    var writing = false
    var sentCommands: [UInt8] = []
    var dropAfter: Int?            // 第幾筆指令之後斷線：之後的指令和讀取都沒回應
    var dropWithoutChange = false  // 斷線但裝置內容沒動（資料未提交）
    var backupOK = true
    var backups = 0
    var reloadOK = true
    var switchAfterFirstCheck: Int?  // 第一次確認設定檔之後，使用者按滑鼠切到這個設定檔
    var checks = 0
    var online = true
    init(_ sector: [UInt8]) { self.sector = sector }

    var io: OtherProfileIO {
        OtherProfileIO(
            activeSector: { [unowned self] in
                self.checks += 1
                defer { if self.checks == 1, let s = self.switchAfterFirstCheck { self.activeProfile = s } }
                return self.online ? self.activeProfile : nil
            },
            read: { [unowned self] _ in self.online ? self.sector : nil },
            command: { [unowned self] function, parameters in
                if let limit = self.dropAfter, self.sentCommands.count >= limit { self.online = false }
                guard self.online else { return false }
                self.sentCommands.append(function)
                switch function {
                case 6: self.buffer = []; self.writing = true
                case 7: self.buffer += parameters
                case 8:
                    // 提交：韌體把收到的資料蓋上去（資料不完整就會留下損毀的設定檔）。
                    if self.writing { self.sector.replaceSubrange(0..<self.buffer.count, with: self.buffer) }
                    self.writing = false
                default: break
                }
                return true
            },
            backup: { [unowned self] _ in self.backups += 1; return self.backupOK },
            reload: { [unowned self] in self.reloadOK })
    }
}
func rate(_ ms: Int) -> OtherWriteMode { .patch { P.patchedReportRate($0, ms: ms) } }

var fm = FakeMouse(g502Sector)
var wo = OtherProfileWriter.run(sector: 1, mode: rate(4), io: fm.io)
check("O104 正常寫入：寫入、讀回一致、備份一次", wo.result == .written && fm.sector[0] == 4 && P.crcValid(fm.sector) && fm.backups == 1)

var damaged = g502Sector; damaged[40] ^= 0xFF
fm = FakeMouse(damaged)
wo = OtherProfileWriter.run(sector: 1, mode: .restore(g502Sector), io: fm.io)
check("O105 #1 設定檔已損毀（CRC 不對）→ 還原仍可執行，內容回到備份", wo.result == .written && fm.sector == g502Sector)
fm = FakeMouse(damaged)
wo = OtherProfileWriter.run(sector: 1, mode: rate(4), io: fm.io)
check("O106 #1 一般修改遇到損毀的設定檔 → 不寫", wo.result == .readFailed && fm.sentCommands.isEmpty)
fm = FakeMouse(damaged); fm.activeProfile = 0x101
wo = OtherProfileWriter.run(sector: 1, mode: .repair(g502Sector), io: fm.io)
check("O107 #1 修復不要求它是使用中的設定檔（韌體可能退回 ROM）", wo.result == .written && fm.sector == g502Sector)
fm = FakeMouse(g502Sector)
wo = OtherProfileWriter.run(sector: 1, mode: .restore(damaged), io: fm.io)
check("O108 #1 備份本身 CRC 不對 → 不還原", wo.result == .noBackup && fm.sentCommands.isEmpty)

fm = FakeMouse(g502Sector); fm.backupOK = false
wo = OtherProfileWriter.run(sector: 1, mode: rate(4), io: fm.io)
check("O109 #2 備份失敗 → 完全不寫", wo.result == .backupFailed && fm.sentCommands.isEmpty && fm.sector == g502Sector)

let backupRoot = FileManager.default.temporaryDirectory.appendingPathComponent("mx-backup-test-" + UUID().uuidString)
let store = OtherProfileBackups(folder: backupRoot)
var other = g502Sector; other[0] = 8
let otherCrc = P.crc(Array(other.dropLast(2))); other[other.count - 2] = UInt8(otherCrc >> 8); other[other.count - 1] = UInt8(otherCrc & 0xFF)
let keyA = OtherProfileBackups.deviceKey(wpid: "407F", unitId: "AAAA0001"), keyB = OtherProfileBackups.deviceKey(wpid: "407F", unitId: "BBBB0002")
let sameTime = Date(timeIntervalSince1970: 1_800_000_000)
check("O110 #2 兩隻同型號各存各的原始備份",
      store.save(g502Sector, device: keyA, sector: 1, now: sameTime) && store.save(other, device: keyB, sector: 1, now: sameTime) &&
      store.loadImage(store.originalURL(device: keyA, sector: 1), size: 255) == g502Sector &&
      store.loadImage(store.originalURL(device: keyB, sector: 1), size: 255) == other)
check("O111 #2 再存一次不會蓋掉原始備份", store.save(other, device: keyA, sector: 1, now: sameTime) &&
      store.loadImage(store.originalURL(device: keyA, sector: 1), size: 255) == g502Sector)
let stamped = ((try? FileManager.default.contentsOfDirectory(atPath: backupRoot.path)) ?? []).filter { $0.hasPrefix(keyA) && !$0.contains("original") }
check("O112 #2 同一毫秒的逐次備份不互相覆蓋", stamped.count == 2)
try? Data(g502Sector).write(to: backupRoot.appendingPathComponent("407F-0002-original.bin"))
store.adoptLegacy(wpid: "407F", unitId: "AAAA0001")
check("O113 #2 舊檔名的原始備份由第一台接手",
      store.loadImage(store.originalURL(device: keyA, sector: 2), size: 255) == g502Sector &&
      !FileManager.default.fileExists(atPath: backupRoot.appendingPathComponent("407F-0002-original.bin").path))
check("O114 #1 待修復內容：存得進去、找得到、清得掉",
      store.saveRepair(g502Sector, device: keyA, sector: 3) && store.pendingRepair(device: keyA) == 3 && store.pendingRepair(device: keyB) == nil &&
      { store.clearRepair(device: keyA, sector: 3); return store.pendingRepair(device: keyA) == nil }())
let unreadable = OtherProfileBackups(folder: URL(fileURLWithPath: "/dev/null/nope"))
check("O115 #2 備份資料夾建不起來 → 回報失敗", !unreadable.save(g502Sector, device: keyA, sector: 1))
try? FileManager.default.removeItem(at: backupRoot)
check("O116 #2 序號解析；全 0／全 F 當作沒有",
      P.unitId([0x11, 1, 2, 3, 2, 0xDE, 0xAD, 0xBE, 0xEF]) == "DEADBEEF" &&
      P.unitId([0x11, 1, 2, 3, 2, 0, 0, 0, 0]) == "" && P.unitId([0x11, 1, 2, 3, 2, 0xFF, 0xFF, 0xFF, 0xFF]) == "")

fm = FakeMouse(g502Sector); fm.activeProfile = 2
wo = OtherProfileWriter.run(sector: 1, mode: rate(4), io: fm.io)
check("O117 #3 滑鼠已切到別的設定檔 → 不寫", wo.result == .profileChanged && fm.sentCommands.isEmpty)
fm = FakeMouse(g502Sector); fm.switchAfterFirstCheck = 2
wo = OtherProfileWriter.run(sector: 1, mode: rate(4), io: fm.io)
check("O118 #3 讀取途中才切走 → 開始寫之前擋下", wo.result == .profileChanged && fm.sentCommands.isEmpty && fm.sector == g502Sector)
fm = FakeMouse(g502Sector); fm.reloadOK = false
wo = OtherProfileWriter.run(sector: 1, mode: rate(4), io: fm.io)
check("O119 #3 寫入成功但重新載入沒確認 → 分開回報", wo.result == .writtenNotApplied && fm.sector[0] == 4)

fm = FakeMouse(g502Sector); fm.dropAfter = 3
wo = OtherProfileWriter.run(sector: 1, mode: rate(4), io: fm.io)
check("O120 #4 傳到一半斷線 → 不送完成指令，資料不提交", !fm.sentCommands.contains(8) && fm.sector == g502Sector)
check("O121 #4 斷線又讀不回 → 標成待修復，內容是原本完好的", wo.result == .failedNeedsRepair && wo.repairImage == g502Sector)
fm = FakeMouse(damaged); fm.dropAfter = 0
wo = OtherProfileWriter.run(sector: 1, mode: .restore(g502Sector), io: fm.io)
check("O122 #1 還原途中斷線 → 待修復內容是備份，不是損毀的內容", wo.result == .failedNeedsRepair && wo.repairImage == g502Sector)

// 回覆遺失但其實已提交：看讀回，不重複改回去。
fm = FakeMouse(g502Sector)
var lostReply = fm.io
let realCommand = lostReply.command
lostReply.command = { function, parameters in
    let ok = realCommand(function, parameters)
    return function == 8 ? false : ok
}
wo = OtherProfileWriter.run(sector: 1, mode: rate(4), io: lostReply)
check("O123 #4 「完成」的回覆遺失但讀回一致 → 算成功，不回滾", wo.result == .written && fm.sector[0] == 4)
fm = FakeMouse(g502Sector)
var rejected = fm.io
rejected.command = { _, _ in false }
wo = OtherProfileWriter.run(sector: 1, mode: rate(4), io: rejected)
check("O124 #4 指令都沒成功但讀回和原本一樣 → 沒有改變，不回滾", wo.result == .failedUnchanged && fm.sector == g502Sector)

fm = FakeMouse(g502Sector)
var dataLost = fm.io
let forward = dataLost.command
var dataPackets = 0
dataLost.command = { function, parameters in
    if function == 7 {
        dataPackets += 1
        if dataPackets == 2 { return false }   // 這筆資料沒回覆，裝置還在線
    }
    return forward(function, parameters)
}
wo = OtherProfileWriter.run(sector: 1, mode: rate(4), io: dataLost)
check("O144 #4 其中一筆資料沒回覆、裝置還在 → 不提交不完整的資料", !fm.sentCommands.contains(8) && fm.sector == g502Sector && wo.result == .failedUnchanged)

var ids = OtherRequestIds()
let firstId = ids.take(now: 100)
check("O125 #4 連續問答的 ID 不同", firstId != ids.take(now: 100))
ids = OtherRequestIds()
let lateId = ids.take(now: 100)
ids.timedOut(lateId, now: 100)
check("O126 #4 逾時的 ID 隔離 5 秒，遲到的回覆不會配給之後的問答",
      !(0..<40).contains { _ in ids.take(now: 102) == lateId })
ids = OtherRequestIds()
let reuseId = ids.take(now: 100)
ids.timedOut(reuseId, now: 100)
check("O127 #4 隔離過了可以再用；ID 不會是 0（0 是裝置主動事件）",
      (0..<15).contains { _ in ids.take(now: 106) == reuseId } && (0..<40).allSatisfy { _ in ids.take(now: 200) != 0 })

check("O128 #5 按鍵寫入層擋住改左鍵", P.patchedProfile(g502Sector, buttons: [0: .disabled]) == nil &&
      P.patchedProfile(g502Sector, buttons: [0: .mouse(2)]) == nil && P.patchedProfile(g502Sector, buttons: [0: .mouse(1)]) != nil)
var noLeft = g502Sector
noLeft.replaceSubrange(P.buttonTableOffset..<(P.buttonTableOffset + 4), with: OtherButtonAssignment.disabled.bytes)
let noLeftCrc = P.crc(Array(noLeft.dropLast(2))); noLeft[noLeft.count - 2] = UInt8(noLeftCrc >> 8); noLeft[noLeft.count - 1] = UInt8(noLeftCrc & 0xFF)
fm = FakeMouse(g502Sector)
wo = OtherProfileWriter.run(sector: 1, mode: .restore(noLeft), io: fm.io)
check("O129 #5 備份的左鍵被改過 → 不還原", wo.result == .leftClickLocked && fm.sentCommands.isEmpty)
fm = FakeMouse(noLeft)
wo = OtherProfileWriter.run(sector: 1, mode: rate(4), io: fm.io)
check("O130 #5 使用者原本就這樣設（左鍵沒被這次修改動到）→ 可以改別的", wo.result == .written)

check("O131 #14 在用的段改成 0 → 拒絕", P.patchedStages(g502Sector, stages: [450, 0, 1600, 3200, 6400], defaultIndex: nil, min: 100, max: 25600) == nil)
check("O132 #14 編輯器：在用的段不接受 0，沒在用的段維持 0",
      !P.validStage(0, original: 800, min: 100, max: 25600) && P.validStage(850, original: 800, min: 100, max: 25600) &&
      P.validStage(0, original: 0, min: 100, max: 25600) && !P.validStage(800, original: 0, min: 100, max: 25600))

var sq = OtherScanQueue()
_ = sq.request("R", full: false)
let staleToken = sq.token("R") ?? 0
_ = sq.take("R")              // 定時器先取走 A
_ = sq.request("R", full: true)   // 之後排進 B
check("O133 #6 舊回呼不會吃掉之後才排進來的請求", sq.take("R", token: staleToken) == nil && sq.token("R") != nil)
let currentToken = sq.token("R") ?? 0
check("O134 #6 自己那一筆取得到", sq.take("R", token: currentToken) == true && sq.token("R") == nil)
let reconnectNow = Date()
check("O135 #6 剛完整讀過的裝置，重複的通知不再讀",
      !P.reconnectReadNeeded(online: true, lastFullRead: reconnectNow - 1, now: reconnectNow))
check("O136 #6 不在線或超過 3 秒 → 要讀",
      P.reconnectReadNeeded(online: false, lastFullRead: reconnectNow - 1, now: reconnectNow) &&
      P.reconnectReadNeeded(online: true, lastFullRead: reconnectNow - 4, now: reconnectNow) &&
      P.reconnectReadNeeded(online: true, lastFullRead: nil, now: reconnectNow))
check("O137 #7 途中有逾時且裝置不再回應 → 不算上線", !P.readConfirmsOnline(timeouts: 3, stillAnswers: { false }))
var askedAgain = false
check("O138 #7 沒有逾時 → 不用多問；有逾時但還在 → 算上線",
      P.readConfirmsOnline(timeouts: 0, stillAnswers: { askedAgain = true; return false }) && !askedAgain &&
      P.readConfirmsOnline(timeouts: 1, stillAnswers: { true }))

var profA = OtherDeviceSnapshot(receiver: "C539@1", slot: 1, wpid: "407F")
profA.unitId = "AAAA0001"; profA.activeProfile = 1; profA.buttons = [.mouse(1), .mouse(6)]
var profB = profA; profB.activeProfile = 2
check("O139 #11 不同設定檔的同一鍵號分開存", P.appActionKey(profA, number: 6) != P.appActionKey(profB, number: 6))
var otherMouse = profA; otherMouse.unitId = "BBBB0002"
check("O140 #11 兩隻滑鼠的同一鍵號分開存", P.appActionKey(profA, number: 6) != P.appActionKey(otherMouse, number: 6))
let movedActions = P.migratedAppActions(["6": "ring", "9": "keep"], device: profA)
check("O141 #11 舊設定搬到目前設定檔用到的鍵號；沒用到的留著",
      movedActions?[P.appActionKey(profA, number: 6)] == "ring" && movedActions?["6"] == nil && movedActions?["9"] == "keep")
check("O142 #11 已搬過或還沒讀到序號 → 不動",
      P.migratedAppActions(movedActions ?? [:], device: profA) == nil &&
      P.migratedAppActions(["6": "ring"], device: OtherDeviceSnapshot(receiver: "C539@1", slot: 1, wpid: "407F", buttons: [.mouse(6)])) == nil)
var onOtherReceiver = otherMouse; onOtherReceiver.receiver = "C539@2"
check("O143 #11 事件依接收器對到正確的滑鼠",
      P.device(forAppButton: 6, receiver: "C539@2", in: [profA, onOtherReceiver])?.unitId == "BBBB0002")

// 2.5 同步：Nano／Unifying、短名稱、多裝置分頁
check("O145 掃描清單含 C52F、C52B、C532 與全部 Lightspeed，不含 Bolt C548",
      P.unifyingNanoReceivers.isSubset(of: P.scannedReceivers) && P.lightspeedReceivers.isSubset(of: P.scannedReceivers) && !P.scannedReceivers.contains(0xC548))
check("O146 Nano／Unifying 不算 Lightspeed（M331 這類滑鼠維持原本的按鍵對應）",
      P.lightspeedReceivers.isDisjoint(with: P.unifyingNanoReceivers))
check("O147 接收器種類", P.receiverKind("C52F") == "Nano" && P.receiverKind("C52B") == "Unifying" && P.receiverKind("C532") == "Unifying" && P.receiverKind("C539") == "Lightspeed")
check("O148 短名稱：M331、G502、沒名稱",
      P.shortName("Wireless Mouse B330/M330/M331") == "M330/M331" && P.shortName("G502 LIGHTSPEED Wireless Gaming Mouse") == "G502" && P.shortName("") == "")
check("O149 短名稱：全是贅字時保留原名前 12 字", P.shortName("Wireless Mouse") == "Wireless Mou")
let tabOnline = OtherDeviceSnapshot(receiver: "C539@1", slot: 1, link: .online)
let tabAsleep = OtherDeviceSnapshot(receiver: "C52F@1", slot: 1, link: .noAnswer)
check("O150 選到的裝置離線時不跳走", P.resolveSelection([tabOnline, tabAsleep], current: tabAsleep.id) == tabAsleep.id)
check("O151 選到的裝置不見時選第一台連著的", P.resolveSelection([tabAsleep, tabOnline], current: "gone#1") == tabOnline.id)
check("O152 都沒連時選第一台、沒有裝置時是 nil",
      P.resolveSelection([tabAsleep], current: nil) == tabAsleep.id && P.resolveSelection([], current: "x") == nil)
check("O153 三台放得下：不用箭頭、寬度不超過上限",
      P.tabLayout(count: 3, available: 600) == OtherTabLayout(width: 150, fit: 3, overflow: false))
let tabsPaged = P.tabLayout(count: 8, available: 600)
check("O154 八台放不下：有箭頭、每頁至少一個、總寬不超出",
      tabsPaged.overflow && tabsPaged.fit >= 1 && tabsPaged.fit < 8 &&
      Double(tabsPaged.fit) * tabsPaged.width + Double(tabsPaged.fit - 1) * P.tabGap + 2 * (P.tabArrowWidth + P.tabGap) <= 600.001)
check("O155 新選到的分頁會捲到看得見", P.tabFirst(0, count: 8, fit: 4, revealing: 6) == 3 && P.tabFirst(5, count: 8, fit: 3, revealing: 1) == 1)
check("O156 按箭頭的位置不被拉回、超出範圍會夾住", P.tabFirst(2, count: 8, fit: 4) == 2 && P.tabFirst(9, count: 8, fit: 4) == 4 && P.tabFirst(-1, count: 8, fit: 4) == 0)

print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
