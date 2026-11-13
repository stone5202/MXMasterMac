import Foundation

// Logi Bolt 接收器的配對協定：HID++ 1.0 暫存器與接收器通知。封包格式照 Solaar
// （lib/logitech_receiver/receiver.py 的 BoltReceiver、notifications.py、base.py 的 request／write）。
// 這個檔案只有純邏輯、不碰硬體，可以單獨編譯，用假接收器測試（見 tools/bolt-pairing-test）。
//
// 暫存器（裝置編號 0xFF = 接收器本身）：
//   0x00   通知旗標（3 bytes，WIRELESS = 0x000100 才會送配對通知）
//   0xC0   搜尋裝置：[逾時秒數, 1 開始／2 取消]
//   0x2C1  配對：[1 配對／2 取消／3 解除, 槽位, 地址 6 bytes, 驗證方式, 熵值（鍵盤 20、其他 10）]
//   0x2B5  接收器資訊：子暫存器 0x5N 槽位 N 的配對資訊、0x6N 01 槽位 N 的名稱
// 通知（10/11 FF <sub> <address> data…）：
//   0x53 搜尋狀態（address 0 = 搜尋中）、0x4F 找到的裝置、0x54 配對狀態（address 0 = 進行中、2 = 完成）、
//   0x4D 驗證碼、0x4E 驗證碼按下

struct BoltSlot: Equatable, Identifiable {
    let slot: Int
    var kind: Int           // HID++ 1.0 裝置類型：1 鍵盤、2 滑鼠、3 數字鍵盤、4 簡報器、8 軌跡球、9 觸控板
    var wpid: String
    var serial: String
    var name: String
    var id: Int { slot }
}

enum BoltFailure: Equatable {
    case noAnswer           // 接收器不接受搜尋或配對指令
    case notFound           // 搜尋結束了，沒有裝置要求配對
    case timeout            // 裝置沒有在時間內完成（例如驗證碼沒按完）
    case failed             // 接收器回報配對失敗（例如驗證碼錯誤）
}

enum BoltPhase: Equatable {
    case idle
    case searching
    case pairing(name: String, kind: Int)
    case passkey(code: String, name: String, keyboard: Bool)
    case succeeded(slot: Int, name: String)
    case failed(BoltFailure)

    var active: Bool {
        switch self {
        case .searching, .pairing, .passkey: return true
        default: return false
        }
    }
}

enum BoltPackets {
    static let wirelessFlag = 0x000100
    static let searchSeconds: UInt8 = 30

    // HID++ 1.0 暫存器請求：寫 0x80、讀 0x81，0x2xx 的長暫存器再加 2（0x82／0x83）。
    // 參數超過 3 bytes 或寫長暫存器時用長封包（0x11，20 bytes），否則短封包（0x10，7 bytes）。
    static func register(_ register: Int, write: Bool, _ parameters: [UInt8] = []) -> [UInt8] {
        let sub = (write ? 0x80 : 0x81) | ((register >> 8) & 0x02)
        let long = parameters.count > 3 || sub == 0x82
        var packet = [UInt8](repeating: 0, count: long ? 20 : 7)
        packet[0] = long ? 0x11 : 0x10
        packet[1] = 0xFF
        packet[2] = UInt8(sub)
        packet[3] = UInt8(register & 0xFF)
        for (i, byte) in parameters.enumerated() where i + 4 < packet.count { packet[i + 4] = byte }
        return packet
    }

    static func readFlags() -> [UInt8] { register(0x00, write: false) }
    static func writeFlags(_ flags: Int) -> [UInt8] {
        register(0x00, write: true, [UInt8((flags >> 16) & 0xFF), UInt8((flags >> 8) & 0xFF), UInt8(flags & 0xFF)])
    }
    static func discover(start: Bool) -> [UInt8] { register(0xC0, write: true, [searchSeconds, start ? 0x01 : 0x02]) }
    static func pair(address: [UInt8], authentication: UInt8, entropy: UInt8) -> [UInt8] {
        register(0x2C1, write: true, [0x01, 0x00] + address.prefix(6) + [authentication, entropy])
    }
    static func cancelPairing() -> [UInt8] { register(0x2C1, write: true, [0x02, 0x00, 0, 0, 0, 0, 0, 0, 0x00, 20]) }
    static func unpair(slot: Int) -> [UInt8] { register(0x2C1, write: true, [0x03, UInt8(slot)]) }
    static func readPairing(slot: Int) -> [UInt8] { register(0x2B5, write: false, [UInt8(0x50 + slot)]) }
    static func readName(slot: Int) -> [UInt8] { register(0x2B5, write: false, [UInt8(0x60 + slot), 0x01]) }

    // 這個回報是不是 request 的回覆（0x83 B5 還要比對子暫存器）。
    static func isReply(_ reply: [UInt8], to request: [UInt8]) -> Bool {
        guard reply.count >= 5, request.count >= 5, reply[1] == 0xFF, reply[2] == request[2], reply[3] == request[3] else { return false }
        if request[2] == 0x83 && request[3] == 0xB5 { return reply[4] == request[4] }
        return true
    }

    // 接收器對 request 回的錯誤（10 FF 8F <sub> <address> <錯誤碼>）。
    static func isError(_ reply: [UInt8], to request: [UInt8]) -> Bool {
        reply.count >= 6 && reply[0] == 0x10 && reply[1] == 0xFF && reply[2] == 0x8F &&
            reply[3] == request[2] && reply[4] == request[3]
    }

    static func flags(fromReply reply: [UInt8]) -> Int? {
        guard reply.count >= 7 else { return nil }
        return (Int(reply[4]) << 16) | (Int(reply[5]) << 8) | Int(reply[6])
    }

    // 0x2B5 0x5N 的回覆：類型在 [5] 低 4 位，WPID 是 [7][6]，序號 [8..11]。
    static func slot(_ slot: Int, pairingReply reply: [UInt8], nameReply: [UInt8]?) -> BoltSlot? {
        guard reply.count >= 12 else { return nil }
        let kind = Int(reply[5] & 0x0F)
        let wpid = String(format: "%02X%02X", reply[7], reply[6])
        guard kind != 0 || wpid != "0000" else { return nil }
        let serial = reply[8..<12].map { String(format: "%02X", $0) }.joined()
        var name = ""
        if let nameReply, nameReply.count >= 8 {
            let length = min(14, Int(nameReply[6]), nameReply.count - 7)
            if length > 0 { name = String(decoding: nameReply[7..<(7 + length)], as: UTF8.self) }
        }
        return BoltSlot(slot: slot, kind: kind, wpid: wpid, serial: serial, name: name)
    }

    // 滑鼠的驗證碼：數字轉成 10 位二進位，1 = 右鍵、0 = 左鍵（true = 右鍵）。
    static func mouseSequence(_ code: String) -> [Bool] {
        guard let value = Int(code) else { return [] }
        var bits = String(value, radix: 2)
        if bits.count < 10 { bits = String(repeating: "0", count: 10 - bits.count) + bits }
        return bits.map { $0 == "1" }
    }
}

// 配對流程：開始搜尋之後，依序吃進接收器的通知，決定下一步要送什麼。
struct BoltPairingFlow {
    enum Output: Equatable {
        case none
        case send([UInt8])          // 送出這個封包（找到裝置後的配對指令）
        case finished               // 成功或失敗，流程結束
        case closedWithoutResult    // 配對狀態關閉但沒有結果：等一下看有沒有新裝置的連線通知
    }

    private(set) var phase: BoltPhase = .idle
    private(set) var pairSent = false
    private(set) var lockOpen = false
    private(set) var discovering = false
    private(set) var closedWaiting = false   // 配對狀態關閉但沒有結果：由新槽位的連線通知決定
    private var counter: Int?
    private var kind = 0
    private var address: [UInt8]?
    private var authentication: UInt8?
    private var name: String?
    private var knownSlots: Set<Int> = []

    mutating func begin(knownSlots: Set<Int>) {
        self = BoltPairingFlow()
        self.knownSlots = knownSlots
        phase = .searching
        discovering = true
    }

    mutating func fail(_ failure: BoltFailure) {
        guard phase.active else { return }
        phase = .failed(failure)
    }

    // 要停止接收器上可能還在進行的動作時送出的封包：要求過配對就取消配對、搜尋可能還在就取消搜尋。
    // 使用者取消、或指令沒有回覆（可能其實已經執行了）時用。
    var cleanupPackets: [[UInt8]] {
        var packets: [[UInt8]] = []
        if pairSent || lockOpen { packets.append(BoltPackets.cancelPairing()) }
        if discovering { packets.append(BoltPackets.discover(start: false)) }
        return packets
    }

    // 使用者取消：回傳要送出的封包。
    mutating func cancel() -> [[UInt8]] {
        let packets = cleanupPackets
        phase = .idle
        return packets
    }

    mutating func handle(_ report: [UInt8]) -> Output {
        guard phase.active, report.count >= 7, report[0] == 0x10 || report[0] == 0x11 else { return .none }
        if report[1] != 0xFF {
            // 配對狀態關閉但沒有結果之後，原本沒配對的槽位發出連線通知（10 slot 41 …，[4] bit 6 為 0 = 已連線）
            // 才代表配對完成；在那之前不算，否則已配對的裝置剛好醒來會被當成新裝置。
            let slot = Int(report[1])
            if pairSent, closedWaiting, report[2] == 0x41, report[4] & 0x40 == 0, (1...6).contains(slot), !knownSlots.contains(slot) {
                phase = .succeeded(slot: slot, name: name ?? "")
                return .finished
            }
            return .none
        }
        let address = report[3]
        let error = report[4]
        switch report[2] {
        case 0x53:      // 搜尋狀態
            discovering = address == 0x00
            guard !discovering, !pairSent else { return .none }
            phase = .failed(error == 0x01 || error == 0 ? .notFound : .failed)
            return .finished
        case 0x4F:      // 找到的裝置（第 0 段：類型、地址、驗證方式；第 1 段：名稱）
            guard !pairSent, report.count >= 20 else { return .none }
            let count = Int(address) + Int(report[4]) * 256
            if counter == nil { counter = count } else if counter != count { return .none }
            if report[5] == 0 {
                kind = Int(report[7])
                self.address = Array(report[10..<16])
                authentication = report[18]
            } else if report[5] == 1 {
                let length = min(Int(report[6]), report.count - 7)
                name = length > 0 ? String(decoding: report[7..<(7 + length)], as: UTF8.self) : ""
            }
            guard let found = self.address, let authentication, let name else { return .none }
            pairSent = true
            phase = .pairing(name: name, kind: kind)
            return .send(BoltPackets.pair(address: found, authentication: authentication, entropy: kind == 1 ? 20 : 10))
        case 0x54:      // 配對狀態
            if address == 0x00 { lockOpen = true; return .none }
            lockOpen = false
            if error != 0 {
                phase = .failed(error == 0x01 ? .timeout : .failed)
                return .finished
            }
            if address == 0x02, report.count >= 12 {
                phase = .succeeded(slot: Int(report[11]), name: name ?? "")
                return .finished
            }
            closedWaiting = true
            return .closedWithoutResult
        case 0x4D:      // 驗證碼（6 個 ASCII 數字）
            guard report.count >= 10 else { return .none }
            let code = String(decoding: report[4..<10], as: UTF8.self).filter(\.isNumber)
            phase = .passkey(code: code, name: name ?? "", keyboard: (authentication ?? 0) & 0x01 != 0)
            return .none
        default:
            return .none
        }
    }
}
