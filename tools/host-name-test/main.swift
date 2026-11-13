// 頻道名稱寫入的判斷測試：只編譯 Sources/HostName.swift。
// 執行：swiftc -o /tmp/host-test ../../Sources/HostName.swift main.swift && /tmp/host-test
import Foundation

var failures = 0
func check(_ name: String, _ ok: Bool) {
    print((ok ? "PASS " : "FAIL ") + name)
    if !ok { failures += 1 }
}

check("H1 Bolt 頻道記成 Logitech Bolt receiver → 要寫",
      HostName.needsWrite(capabilities: 0x03, stored: "Logitech Bolt receiver", computer: "YUCHEN-Z13", maxLength: 32))
check("H2 名稱相同 → 不寫", !HostName.needsWrite(capabilities: 0x03, stored: "YUCHEN-Z13", computer: "YUCHEN-Z13", maxLength: 32))
check("H3 只差彎引號／直引號與大小寫 → 不寫",
      !HostName.needsWrite(capabilities: 0x03, stored: "YuChen's MacBook Pro", computer: "Yuchen\u{2019}s MacBook Pro", maxLength: 32))
check("H4 裝置不支援寫入（bit1 沒開）→ 不寫", !HostName.needsWrite(capabilities: 0x01, stored: "", computer: "YUCHEN-Z13", maxLength: 32))
check("H5 電腦名稱是空的 → 不寫", !HostName.needsWrite(capabilities: 0x03, stored: "X", computer: "", maxLength: 32))
check("H6 名稱超過上限：已經寫過截斷後的名稱 → 不再重寫",
      !HostName.needsWrite(capabilities: 0x03, stored: "ABCDEFGHIJ", computer: "ABCDEFGHIJKLMNOP", maxLength: 10))
check("H7 截斷不切斷中文字（「辦公室電腦」上限 10 bytes → 3 個字 9 bytes）",
      HostName.encode("辦公室電腦", maxLength: 10) == Array("辦公室".utf8))
let packets = HostName.writePackets(host: 2, name: Array("Logitech Office Computer".utf8))
check("H8 24 bytes 分兩段：[2, 0, 14 bytes]、[2, 14, 10 bytes]",
      packets.count == 2 && packets[0].prefix(2) == [2, 0] && packets[0].count == 16 && packets[1].prefix(2) == [2, 14] && packets[1].count == 12)
check("H9 上限 0 → 不寫", !HostName.needsWrite(capabilities: 0x03, stored: "", computer: "PC", maxLength: 0))
print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
