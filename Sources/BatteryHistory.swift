import SwiftUI
import Charts

// 電池歷史：MX Master 4、鍵盤與「其他裝置」的電量，存在本機
// ~/Library/Application Support/MXMasterMac/battery-history.json（不上傳、不連網）。記錄規則在 BatteryAlerts.swift。
final class BatteryHistoryStore: ObservableObject {
    @Published private(set) var data = BatteryHistoryData()
    private let url: URL?
    private let io = DispatchQueue(label: "mxmastermac.battery-history")

    init(demo: Bool = false) {
        if demo {
            url = nil
            data = BatteryHistoryStore.demoData()
            return
        }
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("MXMasterMac", isDirectory: true)
        url = folder?.appendingPathComponent("battery-history.json")
        if let url, let decoded = BatteryHistoryLogic.load(url) { data = decoded }
    }

    func record(_ key: String, name: String, percent: Int, charging: Bool, now: Date = Date()) {
        let t = now.timeIntervalSince1970
        let list = data.samples[key] ?? []
        guard BatteryHistoryLogic.shouldRecord(last: list.last, percent: percent, charging: charging, now: t) else { return }
        data.samples[key] = BatteryHistoryLogic.appended(list, BatterySample(t: t, p: percent, c: charging))
        if !name.isEmpty { data.names[key] = name }
        save()
    }

    func clear() {
        data = BatteryHistoryData()
        save()
    }

    private func save() {
        guard let url else { return }
        let snapshot = data
        io.async {
            guard let raw = try? JSONEncoder().encode(snapshot) else { return }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? raw.write(to: url, options: .atomic)
        }
    }

    // 截圖用（-demoOthers）：三台裝置各 7 天的假資料，中間有一段關機沒有資料。
    private static func demoData() -> BatteryHistoryData {
        var d = BatteryHistoryData()
        let now = Date().timeIntervalSince1970
        func series(_ key: String, _ name: String, start: Int, perHour: Double, chargeAtHour: Int?) {
            var list: [BatterySample] = []
            var p = Double(start)
            for step in stride(from: 7 * 24 * 6, through: 0, by: -1) {
                let t = now - Double(step) * 600
                let hour = (7 * 24 * 6 - step) / 6
                if (60...70).contains(hour) { continue }          // 關機
                if let c = chargeAtHour, (c..<(c + 2)).contains(hour) {
                    p = min(100, p + 8)
                    list.append(BatterySample(t: t, p: Int(p), c: true))
                } else {
                    p = max(3, p - perHour / 6)
                    list.append(BatterySample(t: t, p: Int(p.rounded()), c: false))
                }
            }
            d.samples[key] = list
            d.names[key] = name
        }
        series(BatteryDeviceKey.mouse, "MX Master 4", start: 90, perHour: 0.35, chargeAtHour: 120)
        series(BatteryDeviceKey.keyboard, "MX Mechanical Mini", start: 100, perHour: 0.12, chargeAtHour: nil)
        series(BatteryDeviceKey.other(wpid: "407F"), "G502 LIGHTSPEED Wireless Gaming Mouse", start: 95, perHour: 0.9, chargeAtHour: 90)
        return d
    }
}

// MARK: - 裝置小圖（自己畫的線條圖，不用羅技的原廠圖片）

enum DeviceGlyphStyle {
    case ergonomic      // MX Master 系列：大拇指托
    case gaming         // G 系列：兩側有側翼
    case keyboard
    case mouse          // 其他滑鼠
    case generic

    static func of(_ d: OtherDeviceSnapshot) -> DeviceGlyphStyle {
        if d.kind == 0 { return .keyboard }
        guard d.isPointing else { return .generic }
        let name = d.name.uppercased()
        if name.hasPrefix("G") || name.contains("PRO") || name.contains("LIGHTSPEED") { return .gaming }
        if name.contains("MX MASTER") { return .ergonomic }
        return .mouse
    }

    static func of(key: String, name: String) -> DeviceGlyphStyle {
        if key == BatteryDeviceKey.mouse { return .ergonomic }
        if key == BatteryDeviceKey.keyboard { return .keyboard }
        let upper = name.uppercased()
        if upper.contains("KEYBOARD") || upper.contains("KEYS") { return .keyboard }
        return upper.hasPrefix("G") || upper.contains("PRO") ? .gaming : .mouse
    }
}

struct DeviceGlyph: View {
    let style: DeviceGlyphStyle
    var size: CGFloat = 22

    var body: some View {
        Group {
            switch style {
            case .generic:
                Image(systemName: "dot.radiowaves.left.and.right").font(.system(size: size * 0.75))
            default:
                Canvas { context, canvas in
                    let r = CGRect(origin: .zero, size: canvas)
                    let line = StrokeStyle(lineWidth: max(1.3, size / 14), lineCap: .round, lineJoin: .round)
                    for path in DeviceGlyph.paths(style, in: r) { context.stroke(path, with: .foreground, style: line) }
                }
                .frame(width: size, height: size)
            }
        }
        .accessibilityHidden(true)
    }

    // 以 0–1 的座標畫，再縮放到 rect。
    static func paths(_ style: DeviceGlyphStyle, in rect: CGRect) -> [Path] {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height) }
        switch style {
        case .keyboard:
            var body = Path(roundedRect: CGRect(x: rect.minX + rect.width * 0.04, y: rect.minY + rect.height * 0.24,
                                                width: rect.width * 0.92, height: rect.height * 0.52), cornerRadius: rect.width * 0.08)
            var keys = Path()
            for row in 0..<2 {
                for col in 0..<5 {
                    let x = 0.17 + CGFloat(col) * 0.165, y = 0.38 + CGFloat(row) * 0.13
                    keys.move(to: p(x, y)); keys.addLine(to: p(x + 0.001, y))
                }
            }
            keys.move(to: p(0.3, 0.64)); keys.addLine(to: p(0.7, 0.64))
            body.closeSubpath()
            return [body, keys]
        case .gaming:
            var body = Path()
            body.move(to: p(0.5, 0.06))
            body.addCurve(to: p(0.8, 0.3), control1: p(0.7, 0.06), control2: p(0.8, 0.16))
            body.addLine(to: p(0.86, 0.46))                     // 右側翼
            body.addCurve(to: p(0.66, 0.94), control1: p(0.9, 0.7), control2: p(0.8, 0.92))
            body.addLine(to: p(0.34, 0.94))
            body.addCurve(to: p(0.12, 0.52), control1: p(0.2, 0.92), control2: p(0.08, 0.74))
            body.addLine(to: p(0.2, 0.3))                        // 左側翼（拇指鍵）
            body.addCurve(to: p(0.5, 0.06), control1: p(0.2, 0.16), control2: p(0.3, 0.06))
            var detail = Path()
            detail.move(to: p(0.5, 0.06)); detail.addLine(to: p(0.5, 0.36))       // 左右鍵分隔
            detail.move(to: p(0.5, 0.14)); detail.addLine(to: p(0.5, 0.24))       // 滾輪
            detail.move(to: p(0.2, 0.42)); detail.addLine(to: p(0.32, 0.4))       // 側鍵
            detail.move(to: p(0.2, 0.52)); detail.addLine(to: p(0.32, 0.5))
            return [body, detail]
        case .ergonomic:
            var body = Path()
            body.move(to: p(0.56, 0.06))
            body.addCurve(to: p(0.86, 0.42), control1: p(0.78, 0.08), control2: p(0.88, 0.24))
            body.addCurve(to: p(0.62, 0.94), control1: p(0.86, 0.7), control2: p(0.78, 0.94))
            body.addLine(to: p(0.3, 0.94))
            body.addCurve(to: p(0.06, 0.62), control1: p(0.12, 0.92), control2: p(0.04, 0.78))   // 拇指托
            body.addCurve(to: p(0.28, 0.46), control1: p(0.1, 0.52), control2: p(0.2, 0.48))
            body.addCurve(to: p(0.56, 0.06), control1: p(0.28, 0.24), control2: p(0.36, 0.06))
            var detail = Path()
            detail.move(to: p(0.58, 0.06)); detail.addLine(to: p(0.6, 0.36))
            detail.move(to: p(0.59, 0.14)); detail.addLine(to: p(0.595, 0.24))
            detail.move(to: p(0.14, 0.66)); detail.addCurve(to: p(0.3, 0.56), control1: p(0.18, 0.6), control2: p(0.24, 0.57))  // 拇指滾輪
            return [body, detail]
        case .mouse, .generic:
            var body = Path(roundedRect: CGRect(x: rect.minX + rect.width * 0.22, y: rect.minY + rect.height * 0.06,
                                                width: rect.width * 0.56, height: rect.height * 0.88), cornerRadius: rect.width * 0.28)
            body.closeSubpath()
            var detail = Path()
            detail.move(to: p(0.5, 0.06)); detail.addLine(to: p(0.5, 0.38))
            detail.move(to: p(0.5, 0.16)); detail.addLine(to: p(0.5, 0.26))
            return [body, detail]
        }
    }
}

// MARK: - 「進階」頁的電池歷史卡片

struct BatteryHistoryCard: View {
    @ObservedObject var store: BatteryHistoryStore
    @State private var selected = BatteryDeviceKey.mouse
    @State private var days = 7

    private var keys: [String] {
        let order = [BatteryDeviceKey.mouse, BatteryDeviceKey.keyboard]
        return store.data.samples.keys.sorted { a, b in
            let ia = order.firstIndex(of: a) ?? 9, ib = order.firstIndex(of: b) ?? 9
            return ia != ib ? ia < ib : a < b
        }
    }

    private func name(_ key: String) -> String {
        let raw = store.data.names[key] ?? (key == BatteryDeviceKey.mouse ? "MX Master 4" : key == BatteryDeviceKey.keyboard ? Lang.t("鍵盤", "Keyboard") : key)
        let filler: Set<String> = ["LIGHTSPEED", "WIRELESS", "GAMING", "MOUSE"]
        let short = raw.split(separator: " ").filter { !filler.contains($0.uppercased()) }.joined(separator: " ")
        return short.isEmpty ? raw : short
    }

    var body: some View {
        Card(title: Lang.t("電池歷史", "Battery history"),
             subtitle: Lang.t("只記在這台 Mac 上（保留 30 天）；斷開的地方是關機、睡眠或程式沒在執行的時段",
                              "Kept on this Mac only (30 days). Gaps are times the device was off, asleep or the app wasn't running")) {
            if keys.isEmpty {
                Text(Lang.t("還沒有資料：裝置連著時每 10 分鐘記一筆。", "No data yet: a reading is saved every 10 minutes while a device is connected."))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            } else {
                let key = keys.contains(selected) ? selected : keys[0]
                HStack(spacing: 10) {
                    Picker("", selection: Binding(get: { key }, set: { selected = $0 })) {
                        ForEach(keys, id: \.self) { Text(name($0)).tag($0) }
                    }
                    .labelsHidden().frame(width: 200)
                    Spacer()
                    Picker("", selection: $days) {
                        Text(Lang.t("24 小時", "24 h")).tag(1)
                        Text(Lang.t("7 天", "7 days")).tag(7)
                        Text(Lang.t("30 天", "30 days")).tag(30)
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 210)
                }
                chart(for: key)
            }
        }
    }

    @ViewBuilder
    private func chart(for key: String) -> some View {
        let since = Date().timeIntervalSince1970 - Double(days) * 86_400
        let list = (store.data.samples[key] ?? []).filter { $0.t >= since }
        let segments = BatteryHistoryLogic.segments(list)
        if list.count < 2 {
            Text(Lang.t("這段期間的資料還不夠畫圖。", "Not enough readings in this period yet."))
                .font(.system(size: 12)).foregroundStyle(.secondary).frame(height: 60)
        } else {
            Chart {
                ForEach(Array(segments.enumerated()), id: \.offset) { item in
                    ForEach(item.element, id: \.t) { s in
                        LineMark(x: .value("Time", Date(timeIntervalSince1970: s.t)), y: .value("Battery", s.p),
                                 series: .value("Segment", item.offset))
                            .foregroundStyle(Color.accentColor)
                            .interpolationMethod(.monotone)
                    }
                }
                ForEach(list.filter(\.c), id: \.t) { s in
                    PointMark(x: .value("Time", Date(timeIntervalSince1970: s.t)), y: .value("Battery", s.p))
                        .foregroundStyle(Color.green).symbolSize(10)
                }
            }
            .chartYScale(domain: 0...100)
            .chartYAxis { AxisMarks(values: [0, 25, 50, 75, 100]) { v in
                AxisGridLine(); AxisValueLabel { if let n = v.as(Int.self) { Text(verbatim: "\(n)%") } }
            } }
            .frame(height: 150)
            HStack(spacing: 16) {
                if let last = list.last {
                    Text(Lang.t("目前 \(last.p)%", "Now \(last.p)%"))
                }
                if let drain = BatteryHistoryLogic.dailyDrain(list) {
                    Text(Lang.t("平均每天約掉 \(String(format: "%.1f", drain))%", "About \(String(format: "%.1f", drain))% per day"))
                }
                if let charged = BatteryHistoryLogic.lastCharged(store.data.samples[key] ?? []) {
                    Text(Lang.t("最近充電：", "Last charged: ") + BatteryHistoryCard.dateText(charged))
                }
                Spacer()
                HStack(spacing: 4) {
                    Circle().fill(Color.green).frame(width: 6, height: 6)
                    Text(Lang.t("充電中", "Charging"))
                }
            }
            .font(.system(size: 11.5)).foregroundStyle(.secondary)
        }
    }

    static func dateText(_ t: TimeInterval) -> String {
        let f = DateFormatter()
        f.dateFormat = "M/d HH:mm"
        return f.string(from: Date(timeIntervalSince1970: t))
    }
}
