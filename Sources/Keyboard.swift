import AppKit
import IOKit.hid

// 鍵盤讀到的狀態與設定。
struct KeyboardSnapshot: Equatable {
    var name = ""
    var transport = "BLE"
    var batteryPercent = -1
    var charging = false
    var firmware = ""
    var hosts: [HostEntry] = []
    var currentHost = -1
    var backlightPresent = false
    var backlightEnabled = false
    var backlightMode = 0            // 1 自動、3 手動；其他值是鍵盤自己的模式
    var backlightLevel = 0
    var backlightLevels = 0          // 手動亮度可選的段數（0…段數-1）
    var backlightAuto = false        // 支援自動（感應手靠近與環境光）
    var backlightManual = false      // 支援固定亮度
    var fnPresent = false
    var fnMediaFirst = true          // true：F 鍵預設是媒體鍵，按住 Fn 才是 F1–F12
}

// 和 Logitech 藍牙鍵盤講 HID++ 2.0（目前實測 MX Mechanical Mini）。與滑鼠的 HIDPP 分開：
// 各自的 HID 管理器、執行緒與佇列，滑鼠那邊的連線邏輯完全不受影響。
// 功能編號與封包格式參考 Solaar：0x1814／0x1815 頻道、0x1982 背光、0x40A3 Fn 鍵、0x1004 電量。
// 只讀 HID++ 回報；一般的按鍵輸入回報直接丟掉，不記錄。
final class KeyboardHIDPP {
    private static let vendor = 0x046D
    private static let excludedProducts: Set<Int> = [0xB042, 0xC548]   // MX Master 4、Bolt 接收器（滑鼠那邊管）
    private static let softwareId: UInt8 = 0x0C

    var onLog: ((String) -> Void)?
    var onChange: ((KeyboardSnapshot?) -> Void)?    // nil：沒有連上鍵盤

    private let work = DispatchQueue(label: "mxmastermac.keyboard")
    private var manager: IOHIDManager?
    private var opened = false              // 只在 HID 執行緒上讀寫

    // 以下狀態只在 work 佇列上讀寫。
    private var device: IOHIDDevice?
    private var candidates: [IOHIDDevice] = []
    private var rejected: [IOHIDDevice] = []    // 問過、確定不是鍵盤的介面
    private var featureIndexes: [Int: UInt8] = [:]
    private var stopped = false

    private let lock = NSLock()
    private var pendingKey: (UInt8, UInt8)?
    private var pendingReply: [UInt8]?
    private var pendingSemaphore: DispatchSemaphore?

    func start() {
        let thread = Thread { [weak self] in self?.runLoop() }
        thread.name = "MXMasterMac Keyboard HID"
        thread.start()
    }

    private func runLoop() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: KeyboardHIDPP.vendor] as CFDictionary)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            Unmanaged<KeyboardHIDPP>.fromOpaque(context!).takeUnretainedValue().matched(device)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            Unmanaged<KeyboardHIDPP>.fromOpaque(context!).takeUnretainedValue().removed(device)
        }, context)
        IOHIDManagerRegisterInputReportCallback(manager, { context, _, sender, _, _, report, length in
            // 只看 HID++ 長封包（0x11）；其餘是打字的輸入回報，不處理也不保留。
            guard let sender, length >= 7, report[0] == 0x11 else { return }
            let device = Unmanaged<IOHIDDevice>.fromOpaque(sender).takeUnretainedValue()
            let bytes = Array(UnsafeBufferPointer(start: report, count: length))
            Unmanaged<KeyboardHIDPP>.fromOpaque(context!).takeUnretainedValue().received(device, bytes)
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        open(manager)
        // 「輸入監控」權限開之前定時重試（權限提示由滑鼠那邊負責）。
        let retry = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            guard let self, !self.opened else { return }
            self.open(manager)
        }
        RunLoop.current.add(retry, forMode: .default)
        CFRunLoopRun()
    }

    private func open(_ manager: IOHIDManager) {
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            return
        }
        opened = true
        if let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> {
            for device in devices { matched(device) }
        }
    }

    // MARK: - 裝置出現／消失

    private func matched(_ candidate: IOHIDDevice) {
        let product = IOHIDDeviceGetProperty(candidate, kIOHIDProductIDKey as CFString) as? Int ?? 0
        let output = IOHIDDeviceGetProperty(candidate, kIOHIDMaxOutputReportSizeKey as CFString) as? Int ?? 0
        let transport = IOHIDDeviceGetProperty(candidate, kIOHIDTransportKey as CFString) as? String ?? ""
        // 目前只支援藍牙直連的鍵盤；Bolt 接收器上的鍵盤要和滑鼠共用接收器，之後再做。
        guard opened, output >= 20, transport.hasPrefix("Bluetooth"),
              !KeyboardHIDPP.excludedProducts.contains(product) else { return }
        work.async { [weak self] in
            guard let self, !self.stopped else { return }
            if !self.candidates.contains(where: { CFEqual($0, candidate) }) { self.candidates.append(candidate) }
            if self.device == nil { self.tryConnect() }
        }
    }

    private func removed(_ gone: IOHIDDevice) {
        work.async { [weak self] in
            guard let self else { return }
            self.candidates.removeAll { CFEqual($0, gone) }
            self.rejected.removeAll { CFEqual($0, gone) }
            guard let current = self.device, CFEqual(current, gone) else { return }
            self.log("keyboard removed")
            self.reset()
            self.publish(nil)
            self.tryConnect()
        }
    }

    private func tryConnect() {
        guard device == nil, !stopped else { return }
        var unanswered = false
        for candidate in candidates where !rejected.contains(where: { CFEqual($0, candidate) }) {
            device = candidate
            // 0x0005 函式 2 回報裝置類型：0 = 鍵盤（滑鼠是 3）。睡眠中的鍵盤可能要一秒左右才回覆。
            let type = call(0x0005, 2, timeout: 1.8)
            if let type, type[4] == 0, findFeature(0x1814) != nil {
                let snapshot = readSnapshot()
                log("keyboard connected: \(snapshot.name) battery=\(snapshot.batteryPercent) fw=\(snapshot.firmware) hosts current=\(snapshot.currentHost) " +
                    snapshot.hosts.map { "\($0.index):\($0.name.isEmpty ? "-" : $0.name)/\($0.bus)" }.joined(separator: " "))
                publish(snapshot)
                return
            }
            reset()
            // 明確回答「不是鍵盤」才排除；沒回應（睡眠、剛連上）的稍後再問。
            if type != nil { rejected.append(candidate) } else { unanswered = true }
        }
        if unanswered {
            work.asyncAfter(deadline: .now() + 5) { [weak self] in self?.tryConnect() }
        }
    }

    private func reset() {
        device = nil
        featureIndexes.removeAll()
    }

    private func received(_ source: IOHIDDevice, _ bytes: [UInt8]) {
        lock.lock()
        if let key = pendingKey {
            if bytes[2] == key.0 && bytes[3] == key.1 {
                pendingReply = bytes
                pendingKey = nil
                pendingSemaphore?.signal()
                lock.unlock()
                return
            }
            if bytes[2] == 0xFF && bytes[3] == key.0 && bytes[4] == key.1 {
                pendingReply = nil
                pendingKey = nil
                pendingSemaphore?.signal()
                lock.unlock()
                log("keyboard HID++ error=" + String(format: "%02X", bytes[5]) + " for feature index " + String(format: "%02X", key.0))
                return
            }
        }
        lock.unlock()
        // 軟體 ID 為 0 的是鍵盤主動送出的通知；只處理電量變化。
        guard bytes[3] & 0x0F == 0 else { return }
        work.async { [weak self] in
            guard let self, let current = self.device, CFEqual(current, source),
                  let battery = self.featureIndexes[0x1004], battery != 0, bytes[2] == battery else { return }
            self.publish(self.readSnapshot())
        }
    }

    // MARK: - 對外操作

    func refresh() {
        work.async { [weak self] in
            guard let self else { return }
            if self.device != nil { self.publish(self.readSnapshot()) } else { self.tryConnect() }
        }
    }

    func stop() {
        work.sync {
            stopped = true
            reset()
        }
    }

    // 把鍵盤切到另一個頻道。和滑鼠一樣，鍵盤會立刻離開，送出就算完成。
    func changeHost(_ host: Int, completion: @escaping (Bool) -> Void) {
        work.async { [weak self] in
            var sent = false
            if let self, self.device != nil, let info = self.call(0x1814, 0),
               host >= 0, host < Int(info[4]), host != Int(info[5]) {
                self.log("keyboard change host \(Int(info[5])) -> \(host)")
                _ = self.call(0x1814, 1, [UInt8(host)], timeout: 0.3)
                sent = true
                self.reset()
                self.publish(nil)
            }
            DispatchQueue.main.async { completion(sent) }
        }
    }

    // 寫入一項設定；鍵盤回讀確認才算成功。完成後在主執行緒回報，並送出最新狀態。
    func write(_ operation: @escaping (KeyboardHIDPP) -> Bool, completion: @escaping (Bool) -> Void) {
        work.async { [weak self] in
            guard let self, self.device != nil else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            let ok = operation(self)
            self.publish(self.readSnapshot())
            DispatchQueue.main.async { completion(ok) }
        }
    }

    // 背光：enabled 關閉時保留原本的模式；mode 1 自動、3 手動；level 只在手動模式寫入。
    // 寫入格式（Solaar）：enabled, options, 0xFF, level, 手離開延遲, 手靠近延遲, 接電時延遲（各 2 bytes，照讀到的值寫回）。
    func setBacklight(enabled: Bool, mode: Int, level: Int) -> Bool {
        guard let r = call(0x1982, 0) else { return false }
        let options = (r[5] & 0x07) | UInt8((mode & 0x03) << 3)
        let value = mode == 3 ? UInt8(clamping: level) : r[9]
        guard call(0x1982, 1, [enabled ? 1 : 0, options, 0xFF, value, r[10], r[11], r[12], r[13], r[14], r[15]]) != nil,
              let check = call(0x1982, 0) else { return false }
        guard (check[4] != 0) == enabled else { return false }
        if !enabled { return true }
        return Int((check[5] >> 3) & 0x03) == mode && (mode != 3 || check[9] == value)
    }

    // F 鍵：mediaFirst = true 時 F 鍵預設是媒體鍵。0xFF 表示目前連線的這台電腦（每個頻道各自記錄）。
    func setFnMediaFirst(_ mediaFirst: Bool) -> Bool {
        guard call(0x40A3, 1, [0xFF, mediaFirst ? 1 : 0]) != nil,
              let check = call(0x40A3, 0, [0xFF]) else { return false }
        return (check[5] != 0) == mediaFirst
    }

    // MARK: - 讀取（work 佇列）

    private func readSnapshot() -> KeyboardSnapshot {
        var s = KeyboardSnapshot()
        if let count = call(0x0005, 0) {
            var name: [UInt8] = []
            let length = min(Int(count[4]), 64)
            while name.count < length {
                guard let piece = call(0x0005, 1, [UInt8(name.count)]) else { break }
                let chunk = Array(piece[4..<min(piece.count, 20)].prefix(length - name.count))
                if chunk.isEmpty { break }
                name += chunk
            }
            s.name = String(bytes: name, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters) ?? ""
        }
        if let reply = call(0x1004, 1) {
            s.batteryPercent = Int(reply[4])
            s.charging = reply[6] == 1 || reply[6] == 2
        }
        if let count = call(0x0003, 0) {
            for i in 0..<min(Int(count[4]), 8) {
                guard let info = call(0x0003, 1, [UInt8(i)]) else { continue }
                if info[4] & 0x0F != 0 { continue }
                let name = String(bytes: info[5...7], encoding: .ascii)?.trimmingCharacters(in: .controlCharacters) ?? ""
                s.firmware = name + " " + String(format: "%02X.%02X.B%04X", info[8], info[9], Int(info[10]) << 8 | Int(info[11]))
                break
            }
        }
        if let info = call(0x1814, 0) {
            s.currentHost = Int(info[5])
            for index in 0..<min(Int(info[4]), 8) {
                var entry = HostEntry(index: index)
                if let host = call(0x1815, 1, [UInt8(index)]) {
                    entry.paired = host[5] != 0
                    entry.bus = Int(host[6])
                    let length = Int(host[8])
                    var name: [UInt8] = []
                    while name.count < length {
                        guard let piece = call(0x1815, 3, [UInt8(index), UInt8(name.count)]) else { break }
                        let chunk = Array(piece[6..<20].prefix(length - name.count))
                        if chunk.isEmpty { break }
                        name += chunk
                    }
                    entry.name = String(bytes: name, encoding: .utf8) ?? ""
                }
                s.hosts.append(entry)
            }
        }
        if let reply = call(0x1982, 0) {
            s.backlightPresent = true
            s.backlightEnabled = reply[4] != 0
            s.backlightMode = Int((reply[5] >> 3) & 0x03)
            s.backlightAuto = reply[6] & 0x08 != 0
            s.backlightManual = reply[6] & 0x20 != 0
            s.backlightLevel = Int(reply[9])
            if let levels = call(0x1982, 2) { s.backlightLevels = Int(levels[4]) }
        }
        if let reply = call(0x40A3, 0, [0xFF]) {
            s.fnPresent = true
            s.fnMediaFirst = reply[5] != 0
        }
        return s
    }

    // MARK: - 傳輸（work 佇列）

    private func findFeature(_ feature: Int) -> UInt8? {
        if let cached = featureIndexes[feature] { return cached == 0 ? nil : cached }
        guard let root = request(0, 0, [UInt8(feature >> 8), UInt8(feature & 0xFF), 0], timeout: 1.8) else { return nil }
        featureIndexes[feature] = root[4]
        return root[4] == 0 ? nil : root[4]
    }

    private func call(_ feature: Int, _ function: UInt8, _ parameters: [UInt8] = [], timeout: Double = 0.9) -> [UInt8]? {
        guard let index = findFeature(feature) else { return nil }
        return request(index, function, parameters, timeout: timeout)
    }

    private func request(_ feature: UInt8, _ function: UInt8, _ parameters: [UInt8], timeout: Double) -> [UInt8]? {
        guard let device else { return nil }
        var packet = [UInt8](repeating: 0, count: 20)
        packet[0] = 0x11
        packet[1] = 0xFF
        packet[2] = feature
        packet[3] = (function << 4) | KeyboardHIDPP.softwareId
        for (i, byte) in parameters.enumerated() where i + 4 < packet.count { packet[i + 4] = byte }

        let semaphore = DispatchSemaphore(value: 0)
        lock.lock()
        pendingKey = (feature, packet[3])
        pendingReply = nil
        pendingSemaphore = semaphore
        lock.unlock()

        if IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0x11, packet, packet.count) == kIOReturnSuccess {
            _ = semaphore.wait(timeout: .now() + timeout)
        }
        lock.lock()
        let reply = pendingReply
        pendingKey = nil
        pendingReply = nil
        pendingSemaphore = nil
        lock.unlock()
        guard let reply, reply.count >= 16 else { return nil }
        return reply
    }

    private func log(_ text: String) {
        DispatchQueue.main.async { [weak self] in self?.onLog?("Keyboard " + text) }
    }

    private func publish(_ snapshot: KeyboardSnapshot?) {
        DispatchQueue.main.async { [weak self] in self?.onChange?(snapshot) }
    }
}
