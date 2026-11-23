import Foundation

// 按住型操作的純邏輯（不碰畫面與硬體，可單獨測試：tools/input-hold-test）：
// 放開要沿用「按下當時」的處理方式，而且只有按下那顆鍵的放開才算數。

// 按下時怎麼處理：放行，或吃掉並執行某個動作。
enum HoldDisposition<Action: Equatable>: Equatable {
    case passed
    case swallowed(Action)
}

// 記住每一次按下的處理方式：按住時改了設定，放開還是照按下時的結果（吃掉就吃掉、放行就放行）。
struct PressLedger<Key: Hashable, Action: Equatable> {
    private var held: [Key: HoldDisposition<Action>] = [:]

    mutating func down(_ key: Key, _ disposition: HoldDisposition<Action>) { held[key] = disposition }

    // nil：沒看到這次按下（例如 App 啟動時就按著），放開照原樣放行。
    mutating func up(_ key: Key) -> HoldDisposition<Action>? { held.removeValue(forKey: key) }
}

// 目前是哪一顆鍵按住開著圓環或手勢。
struct HoldOwner: Equatable {
    private(set) var owner: String?

    mutating func takeOver(_ key: String) { owner = key }

    // 只有按下那顆鍵的放開才算數。
    mutating func release(_ key: String) -> Bool {
        guard owner == key else { return false }
        owner = nil
        return true
    }

    mutating func cancel() { owner = nil }
}

// 圓環點選吃掉左／右鍵的按下後，要吃掉「同一隻滑鼠」的放開；另一隻滑鼠的放開不能消耗掉它。
struct SwallowedRelease: Equatable {
    private var source: UInt64?

    mutating func arm(_ value: UInt64) { source = value }

    mutating func consume(_ value: UInt64) -> Bool {
        guard source == value else { return false }
        source = nil
        return true
    }

    mutating func clear() { source = nil }
}

// 四向手勢的判定。距離隨「手勢靈敏度」縮放；50% 時是 8pt／65pt。方向一旦鎖定就不再變，避免放開前游標回彈改變結果。
struct GestureTracker: Equatable {
    enum End: Equatable {
        case direction(Int)     // 0 上、1 右、2 下、3 左
        case ambiguous
        case tap
    }

    private(set) var direction = -1
    private(set) var moved = false

    mutating func reset() {
        direction = -1
        moved = false
    }

    // 回傳 true：這次取樣剛鎖定方向。
    @discardableResult
    mutating func sample(dx: Double, dy: Double, factor: Double) -> Bool {
        if abs(dx) > 8 * factor || abs(dy) > 8 * factor { moved = true }
        guard direction < 0, max(abs(dx), abs(dy)) >= 65 * factor else { return false }
        if abs(dx) >= abs(dy) * 1.35 {
            direction = dx > 0 ? 1 : 3
        } else if abs(dy) >= abs(dx) * 1.35 {
            direction = dy > 0 ? 0 : 2
        } else {
            return false
        }
        return true
    }

    // 放開時補取最後的位置：定時取樣之後才越過門檻的移動也算。
    mutating func end(dx: Double, dy: Double, factor: Double) -> End {
        sample(dx: dx, dy: dy, factor: factor)
        if direction >= 0 { return .direction(direction) }
        return moved ? .ambiguous : .tap
    }
}
