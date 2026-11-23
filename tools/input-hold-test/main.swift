// 按住型操作的純邏輯測試：只編譯 Sources/InputHold.swift。
// 執行：swiftc -o /tmp/hold-test ../../Sources/InputHold.swift main.swift && /tmp/hold-test
import Foundation

var failures = 0
func check(_ name: String, _ ok: Bool) {
    print((ok ? "PASS " : "FAIL ") + name)
    if !ok { failures += 1 }
}

// 第 8 項：放開沿用按下時的處理
var ledger = PressLedger<String, String>()
ledger.down("G6", .swallowed("ring"))
check("H1 按下被吃掉，按住時改成放行 → 放開還是吃掉", ledger.up("G6") == .swallowed("ring"))
ledger.down("G7", .passed)
check("H2 按下時放行，按住時才設定動作 → 放開照樣放行", ledger.up("G7") == .passed)
check("H3 沒看到按下（App 啟動時就按著）→ 放開照原樣放行", ledger.up("G8") == nil)
ledger.down("A:6", .swallowed("x"))
check("H4 不同滑鼠的同一鍵號分開記", ledger.up("B:6") == nil && ledger.up("A:6") == .swallowed("x"))
check("H5 放開後就清掉，不會再吃一次", ledger.up("A:6") == nil)

var left = SwallowedRelease()
left.arm(10)
check("H6 圓環吃掉的左鍵放開：另一隻滑鼠的放開不消耗", !left.consume(20))
check("H7 同一隻滑鼠的放開才吃掉，而且只吃一次", left.consume(10) && !left.consume(10))
left.arm(10); left.clear()
check("H8 暫停或切換頻道清掉後不再吃", !left.consume(10))

// 第 9 項：圓環與手勢只有按下那顆鍵的放開才算
var owner = HoldOwner()
owner.takeOver("A")
check("H9 B 鍵放開不會結束 A 鍵按住的圓環", !owner.release("B") && owner.owner == "A")
check("H10 A 鍵放開才結束", owner.release("A") && owner.owner == nil)
owner.takeOver("A"); owner.cancel()
check("H11 取消後舊鍵的放開不會再觸發", !owner.release("A"))

// 第 10 項：放開時補取最後位置
var g = GestureTracker()
g.sample(dx: 10, dy: 0, factor: 1)
check("H12 還沒越過門檻 → 沒有方向", g.direction == -1 && g.moved)
check("H13 最後一次取樣後才越過門檻就放開 → 方向還是算數", g.end(dx: 80, dy: 0, factor: 1) == .direction(1))
g.reset()
check("H14 完全沒動 → 算按一下", g.end(dx: 2, dy: 1, factor: 1) == .tap)
g.reset()
check("H15 動了但沒到門檻 → 不執行也不算按一下", g.end(dx: 30, dy: 0, factor: 1) == .ambiguous)
g.reset()
check("H16 斜向分不出方向 → 不執行", g.end(dx: 70, dy: 70, factor: 1) == .ambiguous)
g.reset()
g.sample(dx: 0, dy: 80, factor: 1)
check("H17 方向鎖定後放開前回彈也不變", g.end(dx: 90, dy: 0, factor: 1) == .direction(0))
g.reset()
let locked = g.sample(dx: -70, dy: 0, factor: 1)
check("H18 第一次越過門檻回報鎖定（要提示與震動），之後不重複", locked && !g.sample(dx: -80, dy: 0, factor: 1) && g.direction == 3)
g.reset()
check("H19 靈敏度倍率會縮放門檻", g.end(dx: 40, dy: 0, factor: 0.5) == .direction(1))

print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
