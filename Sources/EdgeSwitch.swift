import AppKit

// 螢幕邊緣。rawValue 就是設定檔裡的鍵名。
enum ScreenEdge: String, CaseIterable, Codable {
    case left, right, top, bottom

    var title: String {
        switch self {
        case .left: return Lang.t("左邊緣", "Left edge")
        case .right: return Lang.t("右邊緣", "Right edge")
        case .top: return Lang.t("上邊緣", "Top edge")
        case .bottom: return Lang.t("下邊緣", "Bottom edge")
        }
    }

    var symbol: String {
        switch self {
        case .left: return "arrow.left.to.line"
        case .right: return "arrow.right.to.line"
        case .top: return "arrow.up.to.line"
        case .bottom: return "arrow.down.to.line"
        }
    }
}

// 游標推到螢幕邊緣時，把滑鼠切到另一個 Easy-Switch 頻道。
struct EdgeSwitchSettings: Codable, Equatable {
    var enabled = false
    var targets: [String: Int] = [:]     // 邊緣 → 頻道（0 起算）；沒有的邊緣不會觸發
    var dwell = 0.3                      // 要持續推著邊緣多久才切換（秒）
    var placeCursor = true               // 滑鼠切回這台電腦時，把游標移到對應的邊緣
    var modifier = "none"                // 要同時按住的鍵：none、鍵盤的 control／option／shift／command，或 MouseInput 的 rawValue

    static let dwellRange = 0.1...2.0
    static let keyboardModifiers = ["control", "option", "shift", "command"]
    static let mouseModifiers: [MouseInput] = [.middle, .back, .forward, .gesture, .actionRing]

    // 設定檔缺欄位時用預設值補上。
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = (try? c.decode(Bool.self, forKey: .enabled)) ?? false
        targets = (try? c.decode([String: Int].self, forKey: .targets)) ?? [:]
        dwell = (try? c.decode(Double.self, forKey: .dwell)) ?? 0.3
        placeCursor = (try? c.decode(Bool.self, forKey: .placeCursor)) ?? true
        modifier = (try? c.decode(String.self, forKey: .modifier)) ?? "none"
    }

    // 需要按住的滑鼠按鍵；nil 表示不是用滑鼠按鍵。
    var modifierInput: MouseInput? {
        MouseInput(rawValue: modifier).flatMap { EdgeSwitchSettings.mouseModifiers.contains($0) ? $0 : nil }
    }

    // 需要按住的鍵盤按鍵；nil 表示不是用鍵盤。
    var modifierFlag: NSEvent.ModifierFlags? {
        switch modifier {
        case "control": return .control
        case "option": return .option
        case "shift": return .shift
        case "command": return .command
        default: return nil
        }
    }

    static func modifierTitle(_ name: String) -> String {
        switch name {
        case "control": return "Control ⌃"
        case "option": return "Option ⌥"
        case "shift": return "Shift ⇧"
        case "command": return "Command ⌘"
        default: return MouseInput(rawValue: name)?.title ?? Lang.t("不需要", "None")
        }
    }

    func target(_ edge: ScreenEdge) -> Int? { targets[edge.rawValue] }
}

// 以 Quartz 的全域座標（原點在主螢幕左上角、y 向下）計算。
enum EdgeGeometry {
    static func displays() -> [CGRect] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count)).map { CGDisplayBounds($0) }
    }

    private static func union(_ displays: [CGRect]) -> CGRect {
        displays.dropFirst().reduce(displays.first ?? .zero) { $0.union($1) }
    }

    // 這個螢幕在指定方向上是不是整個桌面最外側的那一個。
    private static func outermost(_ display: CGRect, _ edge: ScreenEdge, in all: CGRect) -> Bool {
        switch edge {
        case .left: return display.minX <= all.minX + 0.5
        case .right: return display.maxX >= all.maxX - 0.5
        case .top: return display.minY <= all.minY + 0.5
        case .bottom: return display.maxY >= all.maxY - 0.5
        }
    }

    // 游標貼著哪一個外緣。多螢幕時只算最外側螢幕的外緣，螢幕之間相接的邊不算；
    // 角落同時貼著兩個邊，不算（也避開系統的熱點角落）。
    static func edge(at point: CGPoint, displays: [CGRect]) -> ScreenEdge? {
        guard let display = displays.first(where: { $0.insetBy(dx: -1, dy: -1).contains(point) }) else { return nil }
        let all = union(displays)
        var found: [ScreenEdge] = []
        // 游標座標的範圍是 minX ... maxX-1，所以右、下兩邊多留一點。
        if point.x <= display.minX + 1, outermost(display, .left, in: all) { found.append(.left) }
        if point.x >= display.maxX - 2, outermost(display, .right, in: all) { found.append(.right) }
        if point.y <= display.minY + 1, outermost(display, .top, in: all) { found.append(.top) }
        if point.y >= display.maxY - 2, outermost(display, .bottom, in: all) { found.append(.bottom) }
        return found.count == 1 ? found[0] : nil
    }

    // 滑鼠切回來時游標要放的位置：指定外緣往內一點，沿著邊緣的座標盡量維持原位。
    static func arrivalPoint(for edge: ScreenEdge, near point: CGPoint, displays: [CGRect]) -> CGPoint? {
        let all = union(displays)
        let outer = displays.filter { outermost($0, edge, in: all) }
        let horizontal = edge == .left || edge == .right
        guard let display = outer.first(where: { horizontal ? ($0.minY...$0.maxY).contains(point.y) : ($0.minX...$0.maxX).contains(point.x) })
                ?? outer.first else { return nil }
        let inset: CGFloat = 24
        let x = min(max(point.x, display.minX + inset), display.maxX - inset)
        let y = min(max(point.y, display.minY + inset), display.maxY - inset)
        switch edge {
        case .left: return CGPoint(x: display.minX + inset, y: y)
        case .right: return CGPoint(x: display.maxX - inset, y: y)
        case .top: return CGPoint(x: x, y: display.minY + inset)
        case .bottom: return CGPoint(x: x, y: display.maxY - inset)
        }
    }
}
