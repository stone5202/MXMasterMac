import Foundation

// Easy-Switch 頻道上記錄的電腦名稱（HID++ 0x1815 Hosts Info）。裝置目前連著這台電腦的頻道，名稱和電腦名稱不同時
// （例如 Bolt 配對的頻道記成「Logitech Bolt receiver」，或電腦改過名），把電腦名稱寫進裝置，
// 和 Logi Options+、Solaar（hidpp20.py 的 get_host_names／set_host_name）的做法相同。只寫目前頻道，其他頻道不動。
// 0x1815 函式 0：[能力旗標（bit0 可讀、bit1 可寫）, ?, 頻道數, 目前頻道]
//        函式 1：[頻道, 狀態, 連線方式, ?, 名稱長度, 名稱上限]
//        函式 4：寫名稱 [目前頻道, 位移, 最多 14 bytes]
// 這個檔案只有純邏輯，tools/host-name-test 單獨測試。
enum HostName {
    static let chunkSize = 14

    // 系統設定裡的電腦名稱（和藍牙配對時裝置記下的名稱相同）。
    static var computerName: String { Host.current().localizedName ?? "" }

    // 引號、前後空白與大小寫的差別不算不同（藍牙配對記的是直引號，系統名稱常是彎引號）。
    static func same(_ a: String, _ b: String) -> Bool { normalize(a) == normalize(b) }

    private static func normalize(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{2019}", with: "'").replacingOccurrences(of: "\u{2018}", with: "'")
            .trimmingCharacters(in: .whitespaces).lowercased()
    }

    // UTF-8，不超過 maxLength bytes，也不把一個字切成兩半。
    static func encode(_ name: String, maxLength: Int) -> [UInt8] {
        var bytes: [UInt8] = []
        for character in name {
            let piece = Array(String(character).utf8)
            if bytes.count + piece.count > maxLength { break }
            bytes += piece
        }
        return bytes
    }

    // 要不要寫：裝置可以寫、電腦名稱不是空的、和裝置上的名稱不同（用截到上限後的名稱比，免得名稱太長時每次都重寫）。
    static func needsWrite(capabilities: UInt8, stored: String, computer: String, maxLength: Int) -> Bool {
        guard capabilities & 0x02 != 0, maxLength > 0 else { return false }
        let fitted = String(decoding: encode(computer, maxLength: maxLength), as: UTF8.self)
        return !fitted.isEmpty && !same(stored, fitted)
    }

    // 函式 4 的參數：每段 [頻道, 位移, 最多 14 bytes]。
    static func writePackets(host: Int, name: [UInt8]) -> [[UInt8]] {
        stride(from: 0, to: name.count, by: chunkSize).map { offset in
            [UInt8(host), UInt8(offset)] + Array(name[offset..<min(offset + chunkSize, name.count)])
        }
    }
}
