// 逐台提醒與電池歷史的純邏輯測試：只編譯 Sources/BatteryAlerts.swift。
// 執行：swiftc -o /tmp/alerts-test ../../Sources/BatteryAlerts.swift main.swift && /tmp/alerts-test
import Foundation

var failures = 0
func check(_ name: String, _ ok: Bool) {
    print((ok ? "PASS " : "FAIL ") + name)
    if !ok { failures += 1 }
}
typealias A = BatteryAlerts
typealias H = BatteryHistoryLogic

// 門檻與開關
let alerts = ["mouse": DeviceBatteryAlert(threshold: 25, low: true, full: true), "other-407F": DeviceBatteryAlert(threshold: 0, low: false)]
check("A1 有逐台設定 → 用自己的門檻", A.effective(alerts, key: "mouse", defaultLow: true, globalThreshold: 15) == (25, true, true))
check("A2 門檻 0 → 跟隨預設", A.effective(alerts, key: "other-407F", defaultLow: true, globalThreshold: 15) == (15, false, false))
check("A3 沒有設定 → 預設門檻、defaultLow、不提醒充飽", A.effective(alerts, key: "keyboard", defaultLow: false, globalThreshold: 10) == (10, false, false))
let decoded = try! JSONDecoder().decode(DeviceBatteryAlert.self, from: #"{"threshold": 17, "low": false}"#.data(using: .utf8)!)
check("A4 設定檔裡不合法的門檻（17）→ 0（預設），缺欄位用預設", decoded == DeviceBatteryAlert(threshold: 0, low: false, full: false))

// 充飽
var f = FullChargeState()
var r = A.fullStep(f, charging: false, full: true, percent: 100, alertOn: true)
check("A5 一開始就是充飽（沒看過充電中，例如開程式時已插著）→ 不通知", !r.notify)
f = A.fullStep(f, charging: true, full: false, percent: 80, alertOn: true).state
r = A.fullStep(f, charging: true, full: false, percent: 100, alertOn: true)
check("A6 充電中到 100% → 通知一次", r.notify)
r = A.fullStep(r.state, charging: true, full: false, percent: 100, alertOn: true)
check("A7 之後還是 100% 充電中 → 不再通知", !r.notify)
f = A.fullStep(r.state, charging: false, full: false, percent: 99, alertOn: true).state
f = A.fullStep(f, charging: true, full: false, percent: 99, alertOn: true).state
check("A8 拔掉再充 → 下次充飽會再通知", A.fullStep(f, charging: false, full: true, percent: 100, alertOn: true).notify)
check("A9 提醒關著 → 不通知", !A.fullStep(f, charging: false, full: true, percent: 100, alertOn: false).notify)

// 只回報百分比的低電量
var low = A.lowStep(notified: false, percent: 14, charging: false, threshold: 15, alertOn: true)
check("A10 第一次讀到門檻以下 → 通知", low.notify && low.notified)
low = A.lowStep(notified: low.notified, percent: 12, charging: false, threshold: 15, alertOn: true)
check("A11 已通知過 → 不再通知", !low.notify)
check("A12 回到門檻＋3% 之上 → 重新計算", !A.lowStep(notified: true, percent: 19, charging: false, threshold: 15, alertOn: true).notified)
check("A13 提醒關著 → 不標成已通知", !A.lowStep(notified: false, percent: 10, charging: false, threshold: 15, alertOn: false).notified)

// 歷史記錄規則
let s0 = BatterySample(t: 1_000, p: 80, c: false)
check("H1 沒有資料 → 記", H.shouldRecord(last: nil, percent: 80, charging: false, now: 1_000))
check("H2 沒變化、5 分鐘 → 不記；10 分鐘 → 記",
      !H.shouldRecord(last: s0, percent: 80, charging: false, now: 1_300) && H.shouldRecord(last: s0, percent: 80, charging: false, now: 1_600))
check("H3 有變化但不到 1 分鐘 → 不記（電壓跳動）；1 分鐘後 → 記",
      !H.shouldRecord(last: s0, percent: 79, charging: false, now: 1_030) && H.shouldRecord(last: s0, percent: 79, charging: false, now: 1_060))
check("H4 不合理的百分比 → 不記", !H.shouldRecord(last: nil, percent: -1, charging: false, now: 0))
let old = [BatterySample(t: 0, p: 90, c: false), BatterySample(t: 100, p: 89, c: false)]
check("H5 超過 30 天的舊資料會被丟掉", H.appended(old, BatterySample(t: 31 * 86_400, p: 50, c: false)).count == 1)
let segs = H.segments([BatterySample(t: 0, p: 90, c: false), BatterySample(t: 600, p: 89, c: false),
                       BatterySample(t: 600 + 3_600, p: 85, c: false)])
check("H6 相隔 1 小時 → 斷成兩段", segs.count == 2 && segs[0].count == 2)
var drain: [BatterySample] = []
for i in 0...24 { drain.append(BatterySample(t: Double(i) * 600, p: 90 - i / 2 + (i % 2 == 0 ? 0 : 1), c: false)) }
let d = H.dailyDrain(drain) ?? -1
check("H7 4 小時掉 12%、中間上下跳 → 約每天 72%（不因跳動高估）", abs(d - 72) < 0.5)
check("H8 不到 2 小時 → 不算", H.dailyDrain(Array(drain.prefix(5))) == nil)
check("H9 最近充電時間", H.lastCharged([BatterySample(t: 5, p: 50, c: true), BatterySample(t: 9, p: 60, c: false)]) == 5)

// 提醒的邊界情況
var ff = A.fullStep(FullChargeState(), charging: true, full: false, percent: 99, alertOn: true).state
var fr = A.fullStep(ff, charging: false, full: true, percent: 100, alertOn: true)
check("A14 #12 99% 充電中 → 回報已充飽（charging=false, full=true）→ 通知", fr.notify)
fr = A.fullStep(fr.state, charging: true, full: false, percent: 99, alertOn: true)
check("A15 #12 插著電回到充電中 → 不算新的一次", !fr.notify && fr.state.notified)
fr = A.fullStep(fr.state, charging: false, full: true, percent: 100, alertOn: true)
check("A16 #12 同一次插電再充飽 → 不重複通知", !fr.notify)
fr = A.fullStep(fr.state, charging: false, full: false, percent: 98, alertOn: true)
fr = A.fullStep(fr.state, charging: true, full: false, percent: 98, alertOn: true)
fr = A.fullStep(fr.state, charging: false, full: true, percent: 100, alertOn: true)
check("A17 #12 拔掉再插 → 下一次充飽會通知", fr.notify)

check("H10 #13 裝置不在線 → 舊電量不記", H.liveReading(connected: false, percent: 80) == nil)
check("H11 #13 在線才記；沒讀到電量不記", H.liveReading(connected: true, percent: 80) == 80 && H.liveReading(connected: true, percent: -1) == nil)
let historyDir = FileManager.default.temporaryDirectory.appendingPathComponent("mx-history-test-" + UUID().uuidString)
try? FileManager.default.createDirectory(at: historyDir, withIntermediateDirectories: true)
let historyFile = historyDir.appendingPathComponent("battery-history.json")
try? Data("{ 壞掉的內容".utf8).write(to: historyFile)
let loaded = H.load(historyFile, now: Date(timeIntervalSince1970: 1_800_000_000))
let aside = ((try? FileManager.default.contentsOfDirectory(atPath: historyDir.path)) ?? []).filter { $0.contains("corrupt") }
check("H12 #13 解不開的歷史檔改名留著，不會被下一次儲存蓋掉",
      loaded == nil && aside.count == 1 && !FileManager.default.fileExists(atPath: historyFile.path) &&
      (try? Data(contentsOf: historyDir.appendingPathComponent(aside[0]))) == Data("{ 壞掉的內容".utf8))
let goodHistory = BatteryHistoryData(names: ["mouse": "MX"], samples: ["mouse": [s0]])
try? JSONEncoder().encode(goodHistory).write(to: historyFile)
check("H13 #13 正常的歷史檔照常讀取", H.load(historyFile) == goodHistory)
try? FileManager.default.removeItem(at: historyDir)

print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
