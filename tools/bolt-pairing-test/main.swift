// Logi Bolt 配對協定的測試：只編譯 Sources/BoltProtocol.swift，用假接收器的通知驅動配對流程。
// 通知的內容照 Solaar notifications.py 解析的位置組出來（report = [報告 ID, 裝置, sub, address, data…]）。
// 執行：swiftc -o /tmp/bolt-test ../../Sources/BoltProtocol.swift main.swift && /tmp/bolt-test
import Foundation

var failures = 0
func check(_ name: String, _ ok: Bool) {
    print((ok ? "PASS " : "FAIL ") + name)
    if !ok { failures += 1 }
}
func hex(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02X", $0) }.joined(separator: " ") }

func long(_ device: UInt8, _ sub: UInt8, _ address: UInt8, _ data: [UInt8]) -> [UInt8] {
    var report = [UInt8](repeating: 0, count: 20)
    report[0] = 0x11; report[1] = device; report[2] = sub; report[3] = address
    for (i, byte) in data.enumerated() where i + 4 < 20 { report[i + 4] = byte }
    return report
}
func short(_ device: UInt8, _ sub: UInt8, _ address: UInt8, _ data: [UInt8]) -> [UInt8] {
    var report = [UInt8](repeating: 0, count: 7)
    report[0] = 0x10; report[1] = device; report[2] = sub; report[3] = address
    for (i, byte) in data.enumerated() where i + 4 < 7 { report[i + 4] = byte }
    return report
}

let keyboardAddress: [UInt8] = [0xA1, 0xB2, 0xC3, 0xD4, 0xE5, 0xF6]
// 0x4F 第 0 段：data[0] 計數高位、data[1] 段號 0、data[3] 類型、data[6..11] 地址、data[14] 驗證方式
func discovery0(counter: UInt8 = 0x07, kind: UInt8, address: [UInt8], auth: UInt8) -> [UInt8] {
    var data = [UInt8](repeating: 0, count: 16)
    data[0] = 0; data[1] = 0; data[3] = kind
    for i in 0..<6 { data[6 + i] = address[i] }
    data[14] = auth
    return long(0xFF, 0x4F, counter, data)
}
// 0x4F 第 1 段：data[1] 段號 1、data[2] 名稱長度、data[3…] 名稱
func discovery1(counter: UInt8 = 0x07, name: String) -> [UInt8] {
    let bytes = Array(name.utf8)
    return long(0xFF, 0x4F, counter, [0, 1, UInt8(bytes.count)] + bytes)
}

// ── 封包格式 ──
check("1 開始搜尋 = 10 FF 80 C0 1E 01 00", hex(BoltPackets.discover(start: true)) == "10 FF 80 C0 1E 01 00")
check("2 取消搜尋 = 10 FF 80 C0 1E 02 00", hex(BoltPackets.discover(start: false)) == "10 FF 80 C0 1E 02 00")
let pairPacket = BoltPackets.pair(address: keyboardAddress, authentication: 0x01, entropy: 20)
check("3 配對 = 11 FF 82 C1 01 00 <地址> 01 14（長封包 20 bytes）",
      pairPacket.count == 20 && hex(Array(pairPacket[0..<14])) == "11 FF 82 C1 01 00 A1 B2 C3 D4 E5 F6 01 14")
check("4 解除配對槽位 2 = 11 FF 82 C1 03 02（長封包）", hex(Array(BoltPackets.unpair(slot: 2)[0..<6])) == "11 FF 82 C1 03 02" && BoltPackets.unpair(slot: 2).count == 20)
check("5 讀槽位 3 配對資訊 = 10 FF 83 B5 53 00 00", hex(BoltPackets.readPairing(slot: 3)) == "10 FF 83 B5 53 00 00")
check("6 讀槽位 3 名稱 = 10 FF 83 B5 63 01 00", hex(BoltPackets.readName(slot: 3)) == "10 FF 83 B5 63 01 00")
check("7 讀通知旗標 = 10 FF 81 00 00 00 00", hex(BoltPackets.readFlags()) == "10 FF 81 00 00 00 00")
check("8 寫通知旗標 0x000900 = 10 FF 80 00 00 09 00", hex(BoltPackets.writeFlags(0x000900)) == "10 FF 80 00 00 09 00")
check("9 取消配對 = 11 FF 82 C1 02 00 …00 14", hex(Array(BoltPackets.cancelPairing()[0..<14])) == "11 FF 82 C1 02 00 00 00 00 00 00 00 00 14")

// ── 回覆比對 ──
let readSlot2 = BoltPackets.readPairing(slot: 2)
check("10 0x83B5 回覆要比對子暫存器（52 對、53 不對）",
      BoltPackets.isReply(long(0xFF, 0x83, 0xB5, [0x52]), to: readSlot2) && !BoltPackets.isReply(long(0xFF, 0x83, 0xB5, [0x53]), to: readSlot2))
check("11 空槽位的錯誤 10 FF 8F 83 B5 02 認得出來", BoltPackets.isError(short(0xFF, 0x8F, 0x83, [0xB5, 0x02]), to: readSlot2))
check("12 別的裝置的回報不算回覆", !BoltPackets.isReply(long(0x02, 0x83, 0xB5, [0x52]), to: readSlot2))

// ── 已配對裝置解析（WPID 是 [7][6]、類型 [5] 低 4 位、序號 [8..11]）──
let pairingReply = long(0xFF, 0x83, 0xB5, [0x52, 0x02, 0x34, 0xB0, 0x11, 0x22, 0x33, 0x44])
let nameReply = long(0xFF, 0x83, 0xB5, [0x62, 0x01, 11] + Array("MX Master 4".utf8))
let parsed = BoltPackets.slot(2, pairingReply: pairingReply, nameReply: nameReply)
check("13 槽位資訊：滑鼠、WPID B034、序號 11223344、名稱 MX Master 4",
      parsed == BoltSlot(slot: 2, kind: 2, wpid: "B034", serial: "11223344", name: "MX Master 4"))
check("14 全 0 的槽位當作沒有裝置", BoltPackets.slot(4, pairingReply: long(0xFF, 0x83, 0xB5, [0x54]), nameReply: nil) == nil)
let longName = long(0xFF, 0x83, 0xB5, [0x63, 0x01, 20] + Array("ABCDEFGHIJKLMNOP".utf8))
check("15 名稱長度超過封包時只取封包內的 13 個字", BoltPackets.slot(3, pairingReply: pairingReply, nameReply: longName)?.name == "ABCDEFGHIJKLM")

// ── 滑鼠驗證碼（Solaar：f"{int(passkey):010b}"，1 = 右）──
let sequence = BoltPackets.mouseSequence("000613")    // 613 = 1001100101
check("16 滑鼠驗證碼 613 → 右左左右右左左右左右", sequence == [true, false, false, true, true, false, false, true, false, true])

// ── 配對流程：鍵盤 ──
var flow = BoltPairingFlow()
flow.begin(knownSlots: [1, 2])
check("17 開始後是搜尋中", flow.phase == .searching)
_ = flow.handle(long(0xFF, 0x53, 0x00, [0x00]))
var out = flow.handle(discovery0(kind: 0x01, address: keyboardAddress, auth: 0x01))
check("18 只有第 0 段還不送配對", out == .none)
out = flow.handle(discovery1(name: "MX MCHNCL M"))
check("19 兩段都到 → 送配對（鍵盤熵值 20）", out == .send(BoltPackets.pair(address: keyboardAddress, authentication: 0x01, entropy: 20)))
check("20 狀態變成配對中", flow.phase == .pairing(name: "MX MCHNCL M", kind: 1))
_ = flow.handle(long(0xFF, 0x53, 0x01, [0x00]))     // 搜尋結束（已送配對，不算失敗）
check("21 送出配對後搜尋結束不算失敗", flow.phase == .pairing(name: "MX MCHNCL M", kind: 1))
_ = flow.handle(long(0xFF, 0x54, 0x00, [0x00]))
out = flow.handle(long(0xFF, 0x4D, 0x00, Array("482913".utf8)))
check("22 驗證碼：鍵盤輸入 482913", flow.phase == .passkey(code: "482913", name: "MX MCHNCL M", keyboard: true))
out = flow.handle(long(0xFF, 0x54, 0x02, [0x00, 0, 0, 0, 0, 0, 0, 0x03]))
check("23 配對完成：槽位 3", out == .finished && flow.phase == .succeeded(slot: 3, name: "MX MCHNCL M"))
check("24 結束後不再吃通知", flow.handle(long(0xFF, 0x54, 0x00, [0])) == .none)

// ── 滑鼠：熵值 10、驗證方式不是鍵盤 ──
flow.begin(knownSlots: [])
let mouseAddress: [UInt8] = [1, 2, 3, 4, 5, 6]
_ = flow.handle(discovery1(counter: 0x09, name: "MX Master 4"))
out = flow.handle(discovery0(counter: 0x09, kind: 0x02, address: mouseAddress, auth: 0x02))
check("25 滑鼠：名稱先到也可以，熵值 10", out == .send(BoltPackets.pair(address: mouseAddress, authentication: 0x02, entropy: 10)))
_ = flow.handle(long(0xFF, 0x4D, 0x00, Array("000613".utf8)))
check("26 滑鼠驗證碼：用按鍵", flow.phase == .passkey(code: "000613", name: "MX Master 4", keyboard: false))

// ── 只理會第一個找到的裝置 ──
flow.begin(knownSlots: [])
_ = flow.handle(discovery0(counter: 0x10, kind: 0x01, address: keyboardAddress, auth: 0x01))
_ = flow.handle(discovery0(counter: 0x11, kind: 0x02, address: mouseAddress, auth: 0x02))
out = flow.handle(discovery1(counter: 0x10, name: "MX MCHNCL M"))
check("27 第二個裝置（計數不同）不會蓋掉第一個", out == .send(BoltPackets.pair(address: keyboardAddress, authentication: 0x01, entropy: 20)))

// ── 失敗與取消 ──
flow.begin(knownSlots: [])
_ = flow.handle(long(0xFF, 0x53, 0x00, [0x00]))
out = flow.handle(long(0xFF, 0x53, 0x01, [0x01]))
check("28 搜尋逾時沒找到裝置 → 沒有找到", out == .finished && flow.phase == .failed(.notFound))

flow.begin(knownSlots: [])
_ = flow.handle(discovery0(kind: 1, address: keyboardAddress, auth: 1)); _ = flow.handle(discovery1(name: "K"))
_ = flow.handle(long(0xFF, 0x54, 0x00, [0x00]))
out = flow.handle(long(0xFF, 0x54, 0x01, [0x02]))
check("29 配對失敗（錯誤 2，例如驗證碼錯）", out == .finished && flow.phase == .failed(.failed))

flow.begin(knownSlots: [])
_ = flow.handle(discovery0(kind: 1, address: keyboardAddress, auth: 1)); _ = flow.handle(discovery1(name: "K"))
out = flow.handle(long(0xFF, 0x54, 0x01, [0x01]))
check("30 驗證逾時（錯誤 1）", out == .finished && flow.phase == .failed(.timeout))

flow.begin(knownSlots: [1, 2])
_ = flow.handle(discovery0(kind: 1, address: keyboardAddress, auth: 1)); _ = flow.handle(discovery1(name: "K"))
out = flow.handle(long(0xFF, 0x54, 0x01, [0x00]))
check("31 配對狀態關閉但沒結果 → 先等", out == .closedWithoutResult && flow.phase.active)
check("32 舊槽位 2 的連線通知不算新裝置", flow.handle(short(0x02, 0x41, 0x04, [0x00, 0x34, 0xB0])) == .none)
out = flow.handle(short(0x04, 0x41, 0x04, [0x00, 0x67, 0xB3]))
check("33 新槽位 4 的連線通知 → 配對完成", out == .finished && flow.phase == .succeeded(slot: 4, name: "K"))

flow.begin(knownSlots: [])
check("34 搜尋中取消：只送取消搜尋", flow.cancel() == [BoltPackets.discover(start: false)] && flow.phase == .idle)
flow.begin(knownSlots: [])
_ = flow.handle(discovery0(kind: 1, address: keyboardAddress, auth: 1)); _ = flow.handle(discovery1(name: "K"))
_ = flow.handle(long(0xFF, 0x53, 0x01, [0x00])); _ = flow.handle(long(0xFF, 0x54, 0x00, [0x00]))
check("35 配對中取消：送取消配對", flow.cancel() == [BoltPackets.cancelPairing()])

flow.begin(knownSlots: [])
check("36 沒開始搜尋前的雜訊（滑鼠 HID++ 回報）不影響", flow.handle(long(0x02, 0x0D, 0x00, [0, 0xC3])) == .none && flow.phase == .searching)

flow.begin(knownSlots: [1])
_ = flow.handle(discovery0(kind: 2, address: mouseAddress, auth: 2)); _ = flow.handle(discovery1(name: "M"))
_ = flow.handle(long(0xFF, 0x54, 0x00, [0x00])); _ = flow.handle(long(0xFF, 0x4D, 0x00, Array("000613".utf8)))
out = flow.handle(short(0x02, 0x41, 0x04, [0x00, 0x67, 0xB3]))
check("37 驗證中，清單沒列到的舊裝置醒來（槽位 2 連線通知）不算配對成功", out == .none && flow.phase == .passkey(code: "000613", name: "M", keyboard: false))

print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
