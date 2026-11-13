import AppKit
import IOKit.hid

// 接收器頁顯示的狀態。
struct BoltReceiverSnapshot: Equatable {
    var present = false
    var multiple = false        // 插著不只一支 Bolt 接收器：不列出、不配對、不解除
    var slots: [BoltSlot] = []
    var phase: BoltPhase = .idle
}

// Logi Bolt 接收器的配對管理：列出已配對裝置、配對新裝置、解除配對。
// 協定在 BoltProtocol.swift；這裡只負責和接收器收送封包。和滑鼠、鍵盤各自的 HID 管理器分開，
// 只處理接收器本身（裝置編號 0xFF）的回覆與通知，以及配對期間新槽位的連線通知；其餘回報一律不看、不記錄。
enum BoltUnpairResult { case done, failed, changed }   // changed：槽位裡已經不是確認時的裝置，沒有送出

final class BoltReceiver {
    private static let vendor = 0x046D
    private static let product = 0xC548
    private static let pairingDeadline: Double = 120     // 安全上限；正常情況接收器自己會在逾時後送出結果

    var onLog: ((String) -> Void)?
    var onChange: ((BoltReceiverSnapshot) -> Void)?

    private let work = DispatchQueue(label: "mxmastermac.bolt")
    private var manager: IOHIDManager?
    private var opened = false              // 只在 HID 執行緒上讀寫

    // 以下狀態只在 work 佇列上讀寫。
    private var device: IOHIDDevice?
    private var receivers: [IOHIDDevice] = []   // 所有接收器的 HID++ 介面；超過一支就停用操作
    private var snapshot = BoltReceiverSnapshot()
    private var flow = BoltPairingFlow()
    private var restoreFlags: Int?          // 配對前把 WIRELESS 通知打開了，結束後要還原的原值（還原確認前一直保留）
    private var deadline: DispatchWorkItem?
    private var grace: DispatchWorkItem?
    private var stopped = false
    private var shuttingDown = false
    private var unknownSlots: [Int] = []    // 讀不到配對資訊的槽位（不確定是空的）
    private var lastRequestRejected = false // 上一個請求收到錯誤回覆（不是逾時）
    private var activeDevice: IOHIDDevice?  // device 的副本，給 HID 執行緒過濾來源用（lock 保護）

    private let lock = NSLock()
    private var pendingRequest: [UInt8]?
    private var pendingReply: [UInt8]?
    private var pendingFailed = false
    private var pendingSemaphore: DispatchSemaphore?

    func start() {
        let thread = Thread { [weak self] in self?.runLoop() }
        thread.name = "MXMasterMac Bolt HID"
        thread.start()
    }

    func stop() {
        work.sync {
            shuttingDown = true
            if flow.phase.active { cancelOnQueue() }
            restoreOwedFlags()
            stopped = true
        }
    }

    func refresh() {
        work.async { [weak self] in
            guard let self, self.device != nil, !self.flow.phase.active else { return }
            self.restoreOwedFlags()
            self.readSlots()
            self.publish()
        }
    }

    func startPairing() {
        work.async { [weak self] in self?.startOnQueue() }
    }

    func cancelPairing() {
        work.async { [weak self] in self?.cancelOnQueue() }
    }

    // 成功或失敗的結果看完了，回到一般畫面。
    func dismissResult() {
        work.async { [weak self] in
            guard let self, !self.flow.phase.active else { return }
            self.flow = BoltPairingFlow()
            self.publish()
        }
    }

    // 送出前重讀槽位：裡面已經不是確認時看到的裝置（WPID 或序號不同）就不送，回傳 changed。
    func unpair(_ expected: BoltSlot, completion: @escaping (BoltUnpairResult) -> Void) {
        work.async { [weak self] in
            guard let self, self.device != nil, !self.snapshot.multiple, !self.flow.phase.active else {
                DispatchQueue.main.async { completion(.failed) }
                return
            }
            let slot = expected.slot
            let now = self.request(BoltPackets.readPairing(slot: slot)).flatMap { BoltPackets.slot(slot, pairingReply: $0, nameReply: nil) }
            let result: BoltUnpairResult
            if now == nil || now?.wpid != expected.wpid || now?.serial != expected.serial {
                result = .changed
                self.log("unpair slot \(slot) skipped: the slot changed")
            } else {
                result = self.request(BoltPackets.unpair(slot: slot)) != nil ? .done : .failed
                self.log("unpair slot \(slot) " + (result == .done ? "ok" : "failed"))
            }
            self.readSlots()
            self.publish()
            DispatchQueue.main.async { completion(result) }
        }
    }

    // MARK: - HID 執行緒

    private func runLoop() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: BoltReceiver.vendor,
                                                kIOHIDProductIDKey: BoltReceiver.product] as CFDictionary)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            Unmanaged<BoltReceiver>.fromOpaque(context!).takeUnretainedValue().matched(device)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            Unmanaged<BoltReceiver>.fromOpaque(context!).takeUnretainedValue().removed(device)
        }, context)
        IOHIDManagerRegisterInputReportCallback(manager, { context, _, sender, _, _, report, length in
            // 只看 HID++ 封包（0x10 短、0x11 長）；一般的滑鼠移動、打字回報不處理也不保留。
            guard let sender, length >= 7, report[0] == 0x10 || report[0] == 0x11 else { return }
            let source = Unmanaged<IOHIDDevice>.fromOpaque(sender).takeUnretainedValue()
            let bytes = Array(UnsafeBufferPointer(start: report, count: length))
            Unmanaged<BoltReceiver>.fromOpaque(context!).takeUnretainedValue().received(source, bytes)
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        open(manager)
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

    private func matched(_ candidate: IOHIDDevice) {
        // 接收器有好幾個介面；HID++ 那個的輸出報告是 20 bytes。
        let output = IOHIDDeviceGetProperty(candidate, kIOHIDMaxOutputReportSizeKey as CFString) as? Int ?? 0
        guard opened, output >= 20 else { return }
        work.async { [weak self] in
            guard let self, !self.stopped, !self.receivers.contains(where: { CFEqual($0, candidate) }) else { return }
            self.receivers.append(candidate)
            if self.device == nil { self.select(candidate) }
            self.log("receiver found" + (self.receivers.count > 1 ? " (\(self.receivers.count) receivers plugged in)" : ""))
            self.updateMultiple()
            self.readSlots()
            self.publish()
        }
    }

    private func removed(_ gone: IOHIDDevice) {
        work.async { [weak self] in
            guard let self, self.receivers.contains(where: { CFEqual($0, gone) }) else { return }
            self.receivers.removeAll { CFEqual($0, gone) }
            if let current = self.device, CFEqual(current, gone) {
                self.log("receiver removed")
                self.deadline?.cancel()
                self.grace?.cancel()
                self.restoreFlags = nil
                self.flow = BoltPairingFlow()
                self.snapshot = BoltReceiverSnapshot()
                self.unknownSlots = []
                self.select(self.receivers.first)
            }
            self.updateMultiple()
            if self.device != nil { self.readSlots() }
            self.publish()
        }
    }

    private func select(_ candidate: IOHIDDevice?) {
        device = candidate
        snapshot.present = candidate != nil
        lock.lock()
        activeDevice = candidate
        lock.unlock()
    }

    // 不只一支接收器時，槽位號碼和回覆分不清是哪一支的，所以停用列出、配對與解除。
    private func updateMultiple() {
        snapshot.multiple = receivers.count > 1
        if snapshot.multiple { snapshot.slots = [] }
    }

    private func received(_ source: IOHIDDevice, _ bytes: [UInt8]) {
        lock.lock()
        guard let active = activeDevice, CFEqual(active, source) else {
            lock.unlock()
            return
        }
        if let request = pendingRequest, BoltPackets.isReply(bytes, to: request) || BoltPackets.isError(bytes, to: request) {
            pendingFailed = BoltPackets.isError(bytes, to: request)
            pendingReply = bytes
            pendingRequest = nil
            pendingSemaphore?.signal()
            lock.unlock()
            return
        }
        lock.unlock()
        let notice = bytes[1] == 0xFF ? [0x4D, 0x4E, 0x4F, 0x53, 0x54].contains(bytes[2]) : bytes[2] == 0x41
        guard notice else { return }
        work.async { [weak self] in self?.notification(bytes) }
    }

    // MARK: - 配對流程（work 佇列）

    private func startOnQueue() {
        guard device != nil, !snapshot.multiple, !flow.phase.active else { return }
        grace?.cancel()
        // 讀不到的槽位也當作有裝置，免得那裡的裝置醒來被當成新配對的。
        flow.begin(knownSlots: Set(snapshot.slots.map(\.slot) + unknownSlots))
        guard let flags = request(BoltPackets.readFlags()).flatMap(BoltPackets.flags(fromReply:)) else {
            abort("notification flags could not be read", cleanup: false)
            return
        }
        if flags & BoltPackets.wirelessFlag == 0 {
            // 從這裡起就要負責還原，即使寫入的回覆遺失。
            if restoreFlags == nil { restoreFlags = flags }
            _ = request(BoltPackets.writeFlags(flags | BoltPackets.wirelessFlag))
            guard let now = request(BoltPackets.readFlags()).flatMap(BoltPackets.flags(fromReply:)),
                  now & BoltPackets.wirelessFlag != 0 else {
                abort("pairing notifications could not be turned on", cleanup: false)
                return
            }
        }
        guard request(BoltPackets.discover(start: true)) != nil else {
            abort("discovery did not start", cleanup: true)
            return
        }
        log("pairing: searching")
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.flow.phase.active else { return }
            self.log("pairing: gave up after \(Int(BoltReceiver.pairingDeadline)) s")
            for packet in self.flow.cleanupPackets { _ = self.request(packet) }
            self.flow.fail(.timeout)
            self.finish()
        }
        deadline = item
        work.asyncAfter(deadline: .now() + BoltReceiver.pairingDeadline, execute: item)
        publish()
    }

    private func cancelOnQueue() {
        guard flow.phase.active else { return }
        for packet in flow.cancel() { _ = request(packet) }
        log("pairing: cancelled")
        finish()
    }

    private func notification(_ bytes: [UInt8]) {
        guard !stopped, flow.phase.active else { return }
        let before = flow.phase
        switch flow.handle(bytes) {
        case .none:
            break
        case .send(let packet):
            if case .pairing(let name, let kind) = flow.phase { log("pairing: found \(name) (kind \(kind)); pairing") }
            if request(packet) == nil {
                abort("pair command not accepted", cleanup: true)
                return
            }
        case .finished:
            finish()
            return
        case .closedWithoutResult:
            // 有些情況接收器先關閉配對狀態，新裝置的連線通知才到；等一下再判斷。
            let item = DispatchWorkItem { [weak self] in
                guard let self, self.flow.phase.active else { return }
                self.flow.fail(.failed)
                self.finish()
            }
            grace = item
            work.asyncAfter(deadline: .now() + 3, execute: item)
        }
        if case .passkey(_, _, let keyboard) = flow.phase, before != flow.phase {
            log("pairing: passkey requested (" + (keyboard ? "keyboard" : "mouse buttons") + ")")
        }
        publish()
    }

    // 指令沒有可用的回覆：它可能其實已經執行了，cleanup 時先叫接收器停止搜尋或配對，再算失敗。
    private func abort(_ reason: String, cleanup: Bool) {
        log("pairing: " + reason)
        if cleanup { for packet in flow.cleanupPackets { _ = request(packet) } }
        flow.fail(.noAnswer)
        finish()
    }

    private func finish() {
        deadline?.cancel()
        deadline = nil
        grace?.cancel()
        grace = nil
        restoreOwedFlags()
        switch flow.phase {
        case .succeeded(let slot, let name): log("pairing: paired \(name) on slot \(slot)")
        case .failed(let failure): log("pairing: failed (\(failure))")
        default: break
        }
        if shuttingDown { return }
        readSlots()
        publish()
    }

    // 把通知旗標改回配對前的值，回讀確認才算完成；失敗就保留，下次重新讀取或結束時再試。
    private func restoreOwedFlags() {
        guard let flags = restoreFlags, device != nil else { return }
        for _ in 0..<2 {
            _ = request(BoltPackets.writeFlags(flags))
            if request(BoltPackets.readFlags()).flatMap(BoltPackets.flags(fromReply:)) == flags {
                restoreFlags = nil
                return
            }
        }
        log("pairing: notification flags not restored yet; will retry")
    }

    // MARK: - 已配對的裝置與傳輸（work 佇列）

    private func readSlots() {
        guard device != nil, !snapshot.multiple else { return }
        var slots: [BoltSlot] = []
        var unknown: [Int] = []
        for slot in 1...6 {
            guard let pairing = request(BoltPackets.readPairing(slot: slot)) else {
                // 錯誤回覆代表空槽位；完全沒有回覆則不確定。
                if !lastRequestRejected { unknown.append(slot) }
                continue
            }
            let name = request(BoltPackets.readName(slot: slot))
            if let entry = BoltPackets.slot(slot, pairingReply: pairing, nameReply: name) { slots.append(entry) }
        }
        snapshot.slots = slots
        unknownSlots = unknown
    }

    private func request(_ packet: [UInt8], timeout: Double = 1.0) -> [UInt8]? {
        guard let device else { return nil }
        let semaphore = DispatchSemaphore(value: 0)
        lock.lock()
        pendingRequest = packet
        pendingReply = nil
        pendingFailed = false
        pendingSemaphore = semaphore
        lock.unlock()

        var result = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(packet[0]), packet, packet.count)
        if result != kIOReturnSuccess && packet[0] == 0x10 {
            // 這個介面不收短報告時，改用長報告送同一個指令。
            var long = [UInt8](repeating: 0, count: 20)
            for (i, byte) in packet.enumerated() { long[i] = byte }
            long[0] = 0x11
            result = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0x11, long, long.count)
        }
        if result == kIOReturnSuccess { _ = semaphore.wait(timeout: .now() + timeout) }
        lock.lock()
        let reply = pendingFailed ? nil : pendingReply
        lastRequestRejected = pendingFailed && pendingReply != nil
        pendingRequest = nil
        pendingReply = nil
        pendingSemaphore = nil
        lock.unlock()
        return reply
    }

    private func publish() {
        snapshot.phase = flow.phase
        let copy = snapshot
        DispatchQueue.main.async { [weak self] in self?.onChange?(copy) }
    }

    private func log(_ text: String) {
        DispatchQueue.main.async { [weak self] in self?.onLog?("Bolt " + text) }
    }
}
