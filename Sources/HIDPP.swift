import AppKit
import IOKit.hid

struct DeviceSnapshot {
    var transport = ""
    var batteryPercent = -1
    var charging = false
    var firmware = ""
    var dpi = 0
    var dpiMin = 0
    var dpiMax = 0
    var dpiStep = 0
    var wheelMode = 0            // 1 自由、2 段落
    var smartShift = 0
    var smartShiftPresent = false
    var wheelInvertPresent = false
    var wheelInverted = false
    var hapticPresent = false
    var hapticLevel = 0
    var raw: [String] = []
}

// Easy-Switch 頻道上記錄的主機。
struct HostEntry: Equatable {
    var index = 0
    var name = ""
    var paired = false
    var bus = 0                  // 4 = Bluetooth、5 = Logi Bolt（依實機回覆對照）

    var busName: String {
        switch bus {
        case 4: return "Bluetooth"
        case 5: return "Logi Bolt"
        default: return ""
        }
    }
}

enum DeviceStatus: Equatable {
    case searching
    case ready(String)       // "BLE" / "BOLT"
    case notFound
    case needsInputMonitoring
    case problem(String)
}

// 經 macOS 內建 HID 介面直接與滑鼠講 HID++ 2.0。功能編號與封包格式沿用 Windows 版
// （參考 Solaar／logiops 的公開實作）。每次寫入都會回讀，裝置確認了才算成功。
final class HIDPP {
    private static let vendor = 0x046D
    private static let directProduct = 0xB042      // MX Master 4（Bluetooth）
    private static let boltProduct = 0xC548        // Logi Bolt 接收器
    private static let softwareId: UInt8 = 0x0B
    private static let targetControls = [0x00C3, 0x01A0]

    var onLog: ((String) -> Void)?
    var onStatus: ((DeviceStatus) -> Void)?
    var onButton: ((Int, Bool) -> Void)?
    var onReady: (() -> Void)?
    var onBattery: ((Int, Bool) -> Void)?
    var onArrival: (() -> Void)?        // 滑鼠離開後又連回這台電腦

    private let work = DispatchQueue(label: "mxmastermac.hidpp")
    private var manager: IOHIDManager?
    private var thread: Thread?
    private var opened = false          // 只在 HID 執行緒上讀寫

    // 以下狀態只在 work 佇列上讀寫。
    private var device: IOHIDDevice?
    private var candidates: [IOHIDDevice] = []      // 目前在線、可講 HID++ 的介面（藍牙滑鼠或 Bolt 接收器）
    private var retryTimer: DispatchSourceTimer?
    private var isBolt = false
    private var deviceIndex: UInt8 = 0xFF
    private var reprogIndex: UInt8 = 0
    private var wirelessIndex: UInt8 = 0
    private var batteryIndex: UInt8 = 0
    private var wheelIndex: UInt8 = 0
    private var diverted: [Int] = []
    private var pressed = Set<Int>()
    private var featureIndexes: [Int: UInt8] = [:]
    private var desiredEnabled = true
    private var stopped = false
    private var everConnected = false
    private var lastMotion: Double = 0  // 最近一次收到滑鼠一般輸入回報的時間；0 = 這次連線還沒收過（由 lock 保護）

    // 等待中的要求；由 HID 執行緒填入回覆。
    private let lock = NSLock()
    private var hapticPending = false   // 只在主執行緒讀寫
    private var hapticFailureLogged = false
    private var pendingKey: (UInt8, UInt8, UInt8)?
    private var pendingReply: [UInt8]?
    private var pendingSemaphore: DispatchSemaphore?

    func start() {
        let thread = Thread { [weak self] in self?.runLoop() }
        thread.name = "MXMasterMac HID"
        self.thread = thread
        thread.start()
    }

    private func runLoop() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager
        let matches: [[String: Any]] = [
            [kIOHIDVendorIDKey: HIDPP.vendor, kIOHIDProductIDKey: HIDPP.directProduct],
            [kIOHIDVendorIDKey: HIDPP.vendor, kIOHIDProductIDKey: HIDPP.boltProduct],
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            Unmanaged<HIDPP>.fromOpaque(context!).takeUnretainedValue().matched(device)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            Unmanaged<HIDPP>.fromOpaque(context!).takeUnretainedValue().removed(device)
        }, context)
        IOHIDManagerRegisterInputReportCallback(manager, { context, _, sender, _, _, report, length in
            guard let sender, length >= 4 else { return }
            let device = Unmanaged<IOHIDDevice>.fromOpaque(sender).takeUnretainedValue()
            let bytes = Array(UnsafeBufferPointer(start: report, count: length))
            Unmanaged<HIDPP>.fromOpaque(context!).takeUnretainedValue().received(device, bytes)
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        open(manager)
        // 「輸入監控」權限是使用者到系統設定裡開的；開了之前定時重試。
        let retry = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            guard let self, !self.opened else { return }
            self.open(manager)
        }
        RunLoop.current.add(retry, forMode: .default)
        CFRunLoopRun()
    }

    private func open(_ manager: IOHIDManager) {
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if result != kIOReturnSuccess {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            if IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) != kIOHIDAccessTypeGranted {
                status(.needsInputMonitoring)
            } else {
                log("HID manager open failed: 0x" + String(UInt32(bitPattern: result), radix: 16))
            }
            return
        }
        opened = true
        log("HID manager opened")
        status(.searching)
        if let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> {
            for device in devices { matched(device) }
        }
        work.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self, self.device == nil, !self.stopped else { return }
            self.status(.notFound)
        }
    }

    // 讓系統跳出「輸入監控」的授權提示（只會跳一次）。
    static func requestInputMonitoring() {
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    // MARK: - 裝置出現／消失（HID 執行緒）

    private func matched(_ candidate: IOHIDDevice) {
        let output = IOHIDDeviceGetProperty(candidate, kIOHIDMaxOutputReportSizeKey as CFString) as? Int ?? 0
        let product = IOHIDDeviceGetProperty(candidate, kIOHIDProductIDKey as CFString) as? Int ?? 0
        guard opened, output >= 20 else { return }
        _ = product
        work.async { [weak self] in
            guard let self, !self.stopped else { return }
            if !self.candidates.contains(where: { CFEqual($0, candidate) }) { self.candidates.append(candidate) }
            self.startRetryTimer()
            // 已經連著別的介面時，新介面出現可能表示滑鼠換了連線方式（例如離開 Bolt 改用藍牙）；
            // 接收器不會消失，所以要主動確認原本那條連線還有沒有回應。
            if self.device != nil { self.verifyAlive() } else { self.tryConnect() }
        }
    }

    // 向目前連線的滑鼠問一次改道狀態；沒有回應就當作它已經離開這條連線，改試其他介面。
    private func verifyAlive() {
        guard device != nil, let cid = diverted.first else { return }
        if readDiversion(cid) != nil {
            ensureDiversion()
            return
        }
        log("\(transportName) connection no longer answers; looking for the mouse on other interfaces")
        reset()
        status(.searching)
        tryConnect()
        if device == nil { status(.notFound) }
    }

    private func removed(_ gone: IOHIDDevice) {
        work.async { [weak self] in
            guard let self else { return }
            self.candidates.removeAll { CFEqual($0, gone) }
            guard let current = self.device, CFEqual(current, gone) else { return }
            self.log("device removed")
            self.reset()
            self.status(.notFound)
            // 滑鼠可能只是換了連線方式（例如由藍牙改到 Bolt 接收器），馬上試其他介面。
            self.tryConnect()
        }
    }

    // 還沒連上時，逐一嘗試在線的介面。Bolt 接收器一直插著，滑鼠切過來時不會有「裝置出現」事件，
    // 所以另外靠接收器的連線通知與定時重試。
    private func tryConnect() {
        guard device == nil, !stopped else { return }
        for candidate in candidates {
            let product = IOHIDDeviceGetProperty(candidate, kIOHIDProductIDKey as CFString) as? Int ?? 0
            if connect(candidate, bolt: product == HIDPP.boltProduct) { return }
        }
    }

    private func startRetryTimer() {
        guard retryTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: work)
        timer.schedule(deadline: .now() + 3, repeating: 3)
        timer.setEventHandler { [weak self] in self?.tryConnect() }   // 已連線時 tryConnect 不做事
        timer.resume()
        retryTimer = timer
    }

    private func received(_ source: IOHIDDevice, _ bytes: [UInt8]) {
        guard bytes[0] == 0x11 || bytes[0] == 0x10 else {
            // 其餘是一般的移動／按鍵回報，只記時間，用來分辨游標是不是這隻滑鼠在動。
            lock.lock()
            lastMotion = ProcessInfo.processInfo.systemUptime
            lock.unlock()
            return
        }
        lock.lock()
        if let key = pendingKey, bytes[1] == key.0 {
            if bytes[2] == key.1 && bytes[3] == key.2 {
                pendingReply = bytes
                pendingKey = nil
                pendingSemaphore?.signal()
                lock.unlock()
                return
            }
            if bytes[2] == 0xFF && bytes.count >= 6 && bytes[3] == key.1 && bytes[4] == key.2 {
                pendingReply = nil
                pendingKey = nil
                pendingSemaphore?.signal()
                lock.unlock()
                log("HID++ error=" + String(format: "%02X", bytes[5]) + " for feature index " + String(format: "%02X", key.1))
                return
            }
            // Bolt 接收器對沒有裝置的槽位回 HID++ 1.0 格式的錯誤（10 idx 8F …）；馬上結束等待，不必等逾時。
            if bytes[2] == 0x8F && bytes.count >= 6 && bytes[3] == key.1 && bytes[4] == key.2 {
                pendingReply = nil
                pendingKey = nil
                pendingSemaphore?.signal()
                lock.unlock()
                return
            }
        }
        lock.unlock()
        // 接收器的裝置連線通知（10 idx 41 …）：滑鼠剛連上或剛離開這個接收器。
        if bytes[0] == 0x10 && bytes[2] == 0x41 {
            work.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self, !self.stopped else { return }
                self.log("receiver connection notice " + self.hex(bytes, 0, 7))
                if self.device == nil { self.tryConnect() } else { self.verifyAlive() }
            }
            return
        }
        // 軟體 ID 為 0 的是滑鼠主動送出的事件；其餘是別的程式（例如 Options+）的回覆。
        guard bytes[3] & 0x0F == 0 else { return }
        work.async { [weak self] in self?.handleEvent(source, bytes) }
    }

    // MARK: - 連線與改道（work 佇列）

    @discardableResult
    private func connect(_ candidate: IOHIDDevice, bolt: Bool) -> Bool {
        device = candidate
        isBolt = bolt
        let candidates: [UInt8] = bolt ? [1, 2, 3, 4, 5, 6] : [0xFF]
        var found = false
        for index in candidates {
            // 睡眠中的裝置可能要一秒左右才回覆。
            guard let root = request(index, 0, 0, [0x1B, 0x04, 0], timeout: 1.8), root[4] != 0 else { continue }
            deviceIndex = index
            reprogIndex = root[4]
            found = true
            log("\(transportName) dev=" + String(format: "%02X", index) + " feature 1B04 index=" +
                String(format: "%02X", root[4]) + " v\(root[6])")
            break
        }
        guard found else {
            reset()
            return false
        }
        wirelessIndex = findFeature(0x1D4B) ?? 0
        batteryIndex = findFeature(0x1004) ?? 0
        wheelIndex = findFeature(0x2121) ?? 0
        discoverControls()
        guard !diverted.isEmpty else {
            status(.problem(Lang.t("滑鼠沒有回報可改道的專用按鍵", "The mouse reported no divertable special buttons")))
            reset()
            return false
        }
        guard applyDiversion(desiredEnabled) else {
            reset()
            return false
        }
        status(.ready(transportName))
        notifyReady()
        if everConnected { notifyArrival() }
        everConnected = true
        return true
    }

    private var transportName: String { isBolt ? "BOLT" : "BLE" }

    private func reset() {
        device = nil
        deviceIndex = 0xFF
        reprogIndex = 0
        wirelessIndex = 0
        batteryIndex = 0
        wheelIndex = 0
        diverted.removeAll()
        pressed.removeAll()
        featureIndexes.removeAll()
        lock.lock()
        lastMotion = 0
        lock.unlock()
    }

    private func discoverControls() {
        diverted.removeAll()
        guard let countReply = request(deviceIndex, reprogIndex, 0, [], timeout: 0.6) else { return }
        let count = min(Int(countReply[4]), 64)
        for i in 0..<count {
            guard let info = request(deviceIndex, reprogIndex, 1, [UInt8(i)], timeout: 0.6) else { continue }
            let cid = Int(info[4]) << 8 | Int(info[5])
            guard HIDPP.targetControls.contains(cid) else { continue }
            let divertable = info[8] & 0x20 != 0
            log("CID " + String(format: "%04X", cid) + " flags=" + String(format: "%02X", info[8]) +
                (divertable ? " divertable" : " not-divertable"))
            if divertable { diverted.append(cid) }
        }
    }

    private func applyDiversion(_ enable: Bool) -> Bool {
        var allSucceeded = true
        for cid in diverted {
            let hi = UInt8(cid >> 8), lo = UInt8(cid & 0xFF)
            // bit 0 是暫時改道，bit 1 表示要更新 bit 0。
            var ok = request(deviceIndex, reprogIndex, 3, [hi, lo, enable ? 0x03 : 0x02, 0, 0], timeout: 0.7) != nil
            if ok { ok = readDiversion(cid) == enable }
            if ok {
                log("CID " + String(format: "%04X", cid) + " diversion=" + (enable ? "on" : "off") + " verified")
            } else {
                allSucceeded = false
                status(.problem(Lang.t("無法設定專用按鍵 ", "Could not set special button ") + String(format: "%04X", cid)))
            }
        }
        if !enable { pressed.removeAll() }
        return allSucceeded
    }

    private func readDiversion(_ cid: Int) -> Bool? {
        let hi = UInt8(cid >> 8), lo = UInt8(cid & 0xFF)
        guard let state = request(deviceIndex, reprogIndex, 2, [hi, lo], timeout: 0.7),
              state[4] == hi, state[5] == lo else { return nil }
        return state[6] & 0x01 != 0
    }

    // 暫時改道只在滑鼠當次連線有效：切換主機、睡眠或重開後就沒了，要補回去。
    private func ensureDiversion() {
        guard device != nil, reprogIndex != 0, !diverted.isEmpty else { return }
        for cid in diverted {
            guard let state = readDiversion(cid) else { return }
            if state != desiredEnabled {
                log("diversion state changed on the mouse; re-applying")
                if applyDiversion(desiredEnabled) {
                    status(.ready(transportName))
                    notifyReady()
                }
                return
            }
        }
    }

    private func handleEvent(_ source: IOHIDDevice, _ bytes: [UInt8]) {
        guard let current = device, CFEqual(current, source), bytes[1] == deviceIndex else { return }
        if bytes[2] == reprogIndex && reprogIndex != 0 && bytes[3] == 0x00 {
            var next = Set<Int>()
            var offset = 4
            while offset + 1 < bytes.count && offset < 12 {
                let cid = Int(bytes[offset]) << 8 | Int(bytes[offset + 1])
                if cid != 0 { next.insert(cid) }
                offset += 2
            }
            for cid in HIDPP.targetControls where pressed.contains(cid) != next.contains(cid) {
                let down = next.contains(cid)
                DispatchQueue.main.async { [weak self] in self?.onButton?(cid, down) }
            }
            pressed = next
        } else if bytes[2] == wirelessIndex && wirelessIndex != 0 && bytes[3] == 0x00 {
            log("wireless status event " + hex(bytes, 4, 3) + "; checking diversion")
            ensureDiversion()
            notifyArrival()
        } else if bytes[2] == batteryIndex && batteryIndex != 0 && bytes[3] == 0x00 {
            let percent = Int(bytes[4])
            let charging = bytes[6] == 1 || bytes[6] == 2
            DispatchQueue.main.async { [weak self] in self?.onBattery?(percent, charging) }
        } else if bytes[2] != reprogIndex && bytes[2] != wheelIndex {
            // 改道功能的其他通知與滾輪轉動通知（Options+ 開的）數量很大，不記錄。
            log("event " + hex(bytes, 0, 10))
        }
    }

    // MARK: - 對外操作

    func setEnabled(_ enabled: Bool) {
        work.async { [weak self] in
            guard let self else { return }
            self.desiredEnabled = enabled
            guard self.device != nil, self.reprogIndex != 0 else { return }
            _ = self.applyDiversion(enabled)
        }
    }

    // 系統喚醒或定時檢查時呼叫。
    func recheck() {
        work.async { [weak self] in
            guard let self else { return }
            if self.device != nil { self.verifyAlive() } else { self.tryConnect() }
        }
    }

    // 結束前解除改道，讓專用鍵回到原本功能。會等到完成或逾時。
    func shutdown() {
        work.sync {
            stopped = true
            retryTimer?.cancel()
            retryTimer = nil
            if device != nil, reprogIndex != 0, !diverted.isEmpty { _ = applyDiversion(false) }
            reset()
        }
    }

    func readDevice(_ completion: @escaping (DeviceSnapshot?) -> Void) {
        work.async { [weak self] in
            let snapshot = self?.snapshot()
            DispatchQueue.main.async { completion(snapshot) }
        }
    }

    // 在 work 佇列執行寫入，完成後在主執行緒回報是否經裝置回讀確認。
    func write(_ operation: @escaping (HIDPP) -> Bool, completion: @escaping (Bool) -> Void) {
        perform({ $0.device != nil && operation($0) ? true : nil }) { completion($0 ?? false) }
    }

    // 在 work 佇列執行一項裝置操作，結果在主執行緒交回；沒連上滑鼠時是 nil。
    func perform<T>(_ operation: @escaping (HIDPP) -> T?, completion: @escaping (T?) -> Void) {
        work.async { [weak self] in
            let result = self.flatMap { $0.device != nil ? operation($0) : nil }
            DispatchQueue.main.async { completion(result) }
        }
    }

    // 結束程式前用：等寫入做完才返回。
    func performNow(_ operation: (HIDPP) -> Void) {
        work.sync { if device != nil { operation(self) } }
    }

    // 把儲存的裝置設定寫回滑鼠；只寫與滑鼠回報不同的項目。
    func restore(_ settings: DeviceSettings, completion: @escaping (DeviceSnapshot?, [String]) -> Void) {
        work.async { [weak self] in
            guard let self, var current = self.snapshot() else {
                DispatchQueue.main.async { completion(nil, []) }
                return
            }
            var results: [String] = []
            if self.releaseWheelIfOrphaned() { results.append("wheel returned to system (HID++ target bit cleared) verified=true") }
            if let dpi = settings.dpi, current.dpi != 0, dpi != current.dpi,
               current.dpiMax == 0 || (dpi >= current.dpiMin && dpi <= current.dpiMax) {
                results.append("restore DPI \(dpi) verified=\(self.setDpi(dpi))")
            }
            if current.smartShiftPresent, let mode = settings.wheelMode, let threshold = settings.smartShift,
               mode != current.wheelMode || threshold != current.smartShift {
                results.append("restore SmartShift \(mode)/\(threshold) verified=\(self.setSmartShift(mode: mode, threshold: threshold))")
            }
            if current.wheelInvertPresent, let invert = settings.wheelInvert, invert != current.wheelInverted {
                results.append("restore wheel invert \(invert) verified=\(self.setWheelInvert(invert))")
            }
            if current.hapticPresent, let haptic = settings.haptic, haptic != current.hapticLevel {
                results.append("restore haptic \(haptic) verified=\(self.setHaptic(haptic))")
            }
            if !results.isEmpty, let again = self.snapshot() { current = again }
            let final = current
            DispatchQueue.main.async { completion(final, results) }
        }
    }

    // MARK: - Easy-Switch 頻道

    // 距離上一次收到滑鼠一般輸入回報多久；nil 表示這次連線還沒收過（無法判斷）。
    var motionAge: Double? {
        lock.lock()
        defer { lock.unlock() }
        return lastMotion == 0 ? nil : ProcessInfo.processInfo.systemUptime - lastMotion
    }

    // 讀出各頻道記錄的主機名稱與目前所在的頻道（0x1814 Change Host、0x1815 Hosts Info，格式依 Solaar）。
    func readHosts(_ completion: @escaping ([HostEntry], Int) -> Void) {
        work.async { [weak self] in
            var hosts: [HostEntry] = []
            var current = -1
            if let self, self.device != nil, let info = self.call(0x1814, 0) {
                current = Int(info[5])
                for index in 0..<min(Int(info[4]), 8) {
                    var entry = HostEntry(index: index)
                    if let host = self.call(0x1815, 1, [UInt8(index)]) {
                        entry.paired = host[5] != 0
                        entry.bus = Int(host[6])
                        let length = Int(host[8])
                        var name: [UInt8] = []
                        while name.count < length {
                            guard let piece = self.call(0x1815, 3, [UInt8(index), UInt8(name.count)]) else { break }
                            let chunk = Array(piece[6..<20].prefix(length - name.count))
                            if chunk.isEmpty { break }
                            name += chunk
                        }
                        entry.name = String(bytes: name, encoding: .utf8) ?? ""
                    }
                    hosts.append(entry)
                }
                self.log("hosts current=\(current) " + hosts.map { "\($0.index):\($0.name.isEmpty ? "-" : $0.name)/\($0.bus)" }.joined(separator: " "))
            }
            DispatchQueue.main.async { completion(hosts, current) }
        }
    }

    // 把滑鼠切到另一個頻道。滑鼠會立刻離開這台電腦，有時來不及回覆，所以送出就算完成；
    // 對方連不上時滑鼠可能自己回來，之後由定時重試接回。
    // haptic：切換前先讓滑鼠震一下的波形（在同一個佇列上先送，確定震完才離開）。
    func changeHost(_ host: Int, haptic: UInt8? = nil, completion: @escaping (Bool) -> Void) {
        work.async { [weak self] in
            var sent = false
            if let self, self.device != nil, let index = self.findFeature(0x1814),
               let info = self.request(self.deviceIndex, index, 0, [], timeout: 0.9),
               host >= 0, host < Int(info[4]), host != Int(info[5]) {
                if let haptic, let hapticIndex = self.findFeature(0x19B0) {
                    _ = self.request(self.deviceIndex, hapticIndex, 4, [haptic], timeout: 0.25)
                }
                self.log("change host \(Int(info[5])) -> \(host)")
                _ = self.request(self.deviceIndex, index, 1, [UInt8(host)], timeout: 0.3)
                sent = true
                self.reset()
                self.status(.notFound)
            }
            DispatchQueue.main.async { completion(sent) }
        }
    }

    // MARK: - 裝置資訊與設定（work 佇列）

    private func findFeature(_ feature: Int) -> UInt8? {
        if let cached = featureIndexes[feature] { return cached == 0 ? nil : cached }
        guard let root = request(deviceIndex, 0, 0, [UInt8(feature >> 8), UInt8(feature & 0xFF), 0], timeout: 1.8) else { return nil }
        featureIndexes[feature] = root[4]
        return root[4] == 0 ? nil : root[4]
    }

    private func call(_ feature: Int, _ function: UInt8, _ parameters: [UInt8] = []) -> [UInt8]? {
        guard let index = findFeature(feature) else { return nil }
        return request(deviceIndex, index, function, parameters, timeout: 0.9)
    }

    private func snapshot() -> DeviceSnapshot? {
        guard device != nil, reprogIndex != 0 else { return nil }
        var s = DeviceSnapshot()
        s.transport = transportName

        if let reply = call(0x1004, 1) {
            s.raw.append("1004 status=" + hex(reply, 4, 3))
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
        if let current = call(0x2201, 2, [0]) {
            s.raw.append("2201 dpi=" + hex(current, 4, 5))
            s.dpi = Int(current[5]) << 8 | Int(current[6])
            if s.dpi == 0 { s.dpi = Int(current[7]) << 8 | Int(current[8]) }
            if let list = call(0x2201, 1, [0]) {
                var values: [Int] = []
                var i = 5
                while i + 1 < list.count {
                    let value = Int(list[i]) << 8 | Int(list[i + 1])
                    if value == 0 { break }
                    values.append(value)
                    i += 2
                }
                // 最高三個位元都是 1 的值，是它前後兩個值之間的步進。
                if values.count >= 3 {
                    for j in 1..<(values.count - 1) where values[j] >> 13 == 7 {
                        s.dpiMin = values[j - 1]
                        s.dpiStep = values[j] & 0x1FFF
                        s.dpiMax = values[j + 1]
                        break
                    }
                }
            }
        }
        if let reply = call(0x2111, 1) {
            s.raw.append("2111 smartshift=" + hex(reply, 4, 3))
            s.smartShiftPresent = true
            s.wheelMode = Int(reply[4])
            s.smartShift = Int(reply[5])
        }
        if let reply = call(0x2121, 1) {
            s.raw.append("2121 mode=" + hex(reply, 4, 1))
            s.wheelInvertPresent = true
            s.wheelInverted = reply[4] & 0x04 != 0
        }
        if let reply = call(0x19B0, 1) {
            s.raw.append("19B0 haptic=" + hex(reply, 4, 2))
            s.hapticPresent = true
            s.hapticLevel = reply[4] & 0x01 != 0 ? Int(reply[5]) : 0
        }
        if let reply = call(0x19B0, 0) {
            s.raw.append("19B0 caps=" + hex(reply, 4, 8))
        }
        return s
    }

    func setDpi(_ dpi: Int) -> Bool {
        guard call(0x2201, 3, [0, UInt8(dpi >> 8), UInt8(dpi & 0xFF)]) != nil,
              let check = call(0x2201, 2, [0]) else { return false }
        return (Int(check[5]) << 8 | Int(check[6])) == dpi
    }

    // mode：1 自由、2 段落。threshold：1–50，255 表示不自動切換。
    func setSmartShift(mode: Int, threshold: Int) -> Bool {
        guard call(0x2111, 2, [UInt8(mode), UInt8(threshold)]) != nil,
              let check = call(0x2111, 1) else { return false }
        return Int(check[4]) == mode && Int(check[5]) == threshold
    }

    // 段落與自由滾動互換，SmartShift 門檻照讀到的值寫回。成功時回傳新的（模式, 門檻）。
    func toggleWheelMode() -> (mode: Int, threshold: Int)? {
        guard let reply = call(0x2111, 1) else { return nil }
        let mode = reply[4] == 1 ? 2 : 1
        let threshold = Int(reply[5])
        return setSmartShift(mode: mode, threshold: threshold) ? (mode, threshold) : nil
    }

    // 模式位元組：bit0 = 滾輪改送 HID++ 通知（Options+ 在 macOS 上會開），bit2 = 反轉。
    // Options+ 在執行時 bit0 照讀到的值寫回；沒在執行時清掉 bit0，否則沒有程式接手、滾輪會沒反應。
    func setWheelInvert(_ inverted: Bool) -> Bool {
        guard let mode = call(0x2121, 1) else { return false }
        var value = inverted ? mode[4] | 0x04 : mode[4] & ~0x04
        if !HIDPP.optionsPlusRunning { value &= ~0x01 }
        guard call(0x2121, 2, [value]) != nil, let check = call(0x2121, 1) else { return false }
        return (check[4] & 0x04 != 0) == inverted
    }

    // Options+ 沒在執行卻留著「滾輪改送 HID++」時，把滾輪還給系統。回傳是否有修改。
    func releaseWheelIfOrphaned() -> Bool {
        guard !HIDPP.optionsPlusRunning, let mode = call(0x2121, 1), mode[4] & 0x01 != 0 else { return false }
        guard call(0x2121, 2, [mode[4] & ~0x01]) != nil, let check = call(0x2121, 1) else { return false }
        return check[4] & 0x01 == 0
    }

    static var optionsPlusRunning: Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.executableURL?.lastPathComponent == "logioptionsplus_agent"
        }
    }

    // level：0 關閉，其餘 1–100。
    func setHaptic(_ level: Int) -> Bool {
        let sent = level <= 0 ? call(0x19B0, 2, [0x00, 0x32]) : call(0x19B0, 2, [0x01, UInt8(level)])
        guard sent != nil, let check = call(0x19B0, 1) else { return false }
        let enabled = check[4] & 0x01 != 0
        return level <= 0 ? !enabled : enabled && Int(check[5]) == level
    }

    // 叫滑鼠播一次觸覺波形（0x19B0 函式 4，波形編號參考 Solaar：0x04 = 輕微碰撞）。
    // 強度跟著滑鼠本身的觸覺回饋設定，關閉時不會震。上一次還沒送完就略過，避免排隊延遲。
    func playHaptic(_ waveform: UInt8) {
        guard !hapticPending else { return }
        hapticPending = true
        work.async { [weak self] in
            guard let self else { return }
            if self.device != nil, let index = self.findFeature(0x19B0),
               self.request(self.deviceIndex, index, 4, [waveform], timeout: 0.25) == nil, !self.hapticFailureLogged {
                self.hapticFailureLogged = true
                self.log("haptic play \(waveform) no reply")
            }
            DispatchQueue.main.async { self.hapticPending = false }
        }
    }

    // MARK: - 傳輸

    private func request(_ target: UInt8, _ feature: UInt8, _ function: UInt8, _ parameters: [UInt8],
                         timeout: Double) -> [UInt8]? {
        guard let device else { return nil }
        var packet = [UInt8](repeating: 0, count: 20)
        packet[0] = 0x11
        packet[1] = target
        packet[2] = feature
        packet[3] = (function << 4) | HIDPP.softwareId
        for (i, byte) in parameters.enumerated() where i + 4 < packet.count { packet[i + 4] = byte }

        let semaphore = DispatchSemaphore(value: 0)
        lock.lock()
        pendingKey = (target, feature, packet[3])
        pendingReply = nil
        pendingSemaphore = semaphore
        lock.unlock()

        let result = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0x11, packet, packet.count)
        var reply: [UInt8]?
        if result == kIOReturnSuccess {
            _ = semaphore.wait(timeout: .now() + timeout)
        } else {
            log("send failed: 0x" + String(UInt32(bitPattern: result), radix: 16))
        }
        lock.lock()
        reply = pendingReply
        pendingKey = nil
        pendingReply = nil
        pendingSemaphore = nil
        lock.unlock()
        guard let reply, reply.count >= 12 else { return nil }
        return reply
    }

    private func hex(_ bytes: [UInt8], _ from: Int, _ count: Int) -> String {
        bytes.dropFirst(from).prefix(count).map { String(format: "%02X", $0) }.joined(separator: "-")
    }

    private func log(_ text: String) {
        DispatchQueue.main.async { [weak self] in self?.onLog?("HID++ " + text) }
    }

    private func status(_ value: DeviceStatus) {
        DispatchQueue.main.async { [weak self] in self?.onStatus?(value) }
    }

    private func notifyArrival() {
        DispatchQueue.main.async { [weak self] in self?.onArrival?() }
    }

    private func notifyReady() {
        DispatchQueue.main.async { [weak self] in self?.onReady?() }
    }
}
