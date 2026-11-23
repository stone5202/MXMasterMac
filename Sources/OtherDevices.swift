import Foundation
import IOKit.hid
import CoreGraphics

// 「其他裝置」：Lightspeed 接收器上的羅技裝置（實測 G502 LIGHTSPEED）。讀：名稱、電量、連線、DPI、回報率、韌體、內建設定檔。
// 唯一的寫入是使用者按的「切段／切設定檔」（0x8100 函式 0xC／3，等同按滑鼠上的 DPI 鍵與設定檔鍵，不改設定檔內容）。
// 和滑鼠的 HIDPP、鍵盤的 KeyboardHIDPP 分開：各自的 HID 管理器、執行緒與佇列，MX Master 4 的連線完全不受影響。
// 協定與解析在 OtherDevicesProtocol.swift。接收器的連線通知預設是關的，找到接收器時打開（只開上線／離線這一位，2026-11-23），
// 裝置關機馬上知道；定時讀取當備援：連著的裝置每 5 分鐘讀一次電量，沒回應的每分鐘問一次（剛有滑鼠動作時每 5 秒）。
// 每次問答都佔用無線通道（G502 回報率 1 ms），所以：已連著的裝置平常只讀電量（3 次問答），
// 整台重讀只在新連上、重新連線、按「重新整理」時；移動中一律不送（2026-11-20 使用者回報游標閃現）。
// 定時讀取等滑鼠停 2 秒；使用者正在等畫面的讀取只等 0.3 秒，配對清單由接收器回答、不經無線，馬上列出（2026-11-23）。
final class OtherDevicesHIDPP {
    private static let batteryInterval: TimeInterval = 300

    var onLog: ((String) -> Void)?
    var onChange: (([OtherDeviceSnapshot]) -> Void)?

    private let work = DispatchQueue(label: "mxmastermac.others")
    private var manager: IOHIDManager?
    private var opened = false              // 只在 HID 執行緒上讀寫

    // 以下狀態只在 work 佇列上讀寫。
    private var receivers: [IOHIDDevice] = []
    private var devices: [String: OtherDeviceSnapshot] = [:]
    private var features: [String: [Int: UInt8]] = [:]
    private var samples: [String: [Int]] = [:]          // 電壓（mV），最近 5 次
    private var lastBattery: [String: Date] = [:]
    private var lastScan: [String: Date] = [:]          // 接收器上次掃描的時間（開視窗與進頁面會連著要求重新整理）
    private var lastPing: [String: Date] = [:]          // 沒回應的裝置上次問的時間
    private var lastLightTry: [String: Date] = [:]      // 上次試著讀電量的時間（讀不到時不要每輪重試）
    private var idleNeeded = OtherDevicesProtocol.idleSeconds   // 這一批讀取要求滑鼠停多久
    private var requestIds = OtherRequestIds()           // 每筆問答的軟體 ID
    private var timeouts = 0                             // 問答逾時的累計次數（判斷這輪讀取是否可信）
    private var lastFullRead: [String: Date] = [:]       // 上次完整讀到裝置的時間（合併重複的重新連線通知）
    private var reconnectPending = Set<String>()         // 已排定要重讀的接收器
    private var timer: DispatchSourceTimer?
    private var gate = OtherReadGate()                   // 每筆送出前重看滑鼠；動了就中斷這一批
    private var scanQueue = OtherScanQueue()             // 等滑鼠停下的掃描，同一台接收器只排一次
    private var sent = 0                                 // 送出的 HID++ 問答次數（記錄用，看每輪佔用多少無線通道）
    private var stopped = false

    private let lock = NSLock()
    private var pending: (device: IOHIDDevice, key: [UInt8])?   // 回覆的 bytes[1...]（暫存器多比對子暫存器）
    private var pendingReply: [UInt8]?
    private var pendingError = false
    private var pendingSemaphore: DispatchSemaphore?

    func start() {
        let thread = Thread { [weak self] in self?.runLoop() }
        thread.name = "MXMasterMac Other Devices HID"
        thread.start()
        work.async { [weak self] in self?.startTimer() }
    }

    func stop() {
        work.sync {
            stopped = true
            timer?.cancel()
            timer = nil
        }
    }

    // 設定視窗打開、電腦睡醒時：重新掃一次所有接收器（連著的只讀電量）。full：使用者按「重新整理」，整台重讀。
    func refresh(full: Bool = false) {
        work.async { [weak self] in
            guard let self, !self.stopped else { return }
            for receiver in self.receivers
            where full || Date().timeIntervalSince(self.lastScan[self.receiverKey(receiver)] ?? .distantPast) > 3 {
                self.requestScan(receiver, full: full, giveUpAfter: 30)
            }
        }
    }

    // 等滑鼠停下再掃描（work 佇列）。同一台接收器已經排著就只合併 full，不會連做兩輪；
    // 掃到一半因為滑鼠又動而中斷，再排一次（retry 次）。
    private func requestScan(_ receiver: IOHIDDevice, full: Bool, giveUpAfter: TimeInterval, retry: Int = 3) {
        let key = receiverKey(receiver)
        guard scanQueue.request(key, full: full), let token = scanQueue.token(key) else { return }
        whenIdle(giveUpAfter: giveUpAfter, quick: true, onGiveUp: { _ = self.scanQueue.take(key, token: token) }) {
            guard let full = self.scanQueue.take(key, token: token), self.receivers.contains(where: { CFEqual($0, receiver) }) else { return }
            if !self.scan(receiver, full: full) && retry > 0 {
                self.requestScan(receiver, full: full, giveUpAfter: 60, retry: retry - 1)
            }
        }
    }

    // 滑鼠停下來才執行（work 佇列）；一直在動就每秒再看一次，超過 giveUpAfter 秒就放棄，等下一輪定時。
    // 開始之後每一筆送出前還會再看一次（send 裡的 gate），中途動了就中斷。
    // quick：使用者正在等畫面，滑鼠短暫停下就讀。
    private func whenIdle(giveUpAfter: TimeInterval, quick: Bool = false, onGiveUp: (() -> Void)? = nil,
                          _ action: @escaping () -> Void) {
        let limit = Date().addingTimeInterval(giveUpAfter)
        let threshold = quick ? OtherDevicesProtocol.quickIdleSeconds : OtherDevicesProtocol.idleSeconds
        func attempt() {
            guard !stopped else { return }
            if mouseIdle(threshold) {
                idleNeeded = threshold
                action()
                idleNeeded = OtherDevicesProtocol.idleSeconds
            } else if Date() < limit {
                work.asyncAfter(deadline: .now() + (quick ? 0.25 : 1)) { attempt() }
            } else {
                onGiveUp?()
            }
        }
        attempt()
    }

    private func secondsSinceMouseEvents() -> [Double] {
        let types: [CGEventType] = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
                                    .scrollWheel, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        return types.map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }
    }

    private func mouseIdle(_ threshold: Double) -> Bool {
        OtherDevicesProtocol.mouseIdle(secondsSinceEvents: secondsSinceMouseEvents(), threshold: threshold)
    }

    private func runLoop() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager
        // 只開接收器的廠商介面（usage page 0xFF00）：滑鼠移動的一般回報走另一個介面，不會收進來。
        // Lightspeed 的 0xFF00 是獨立介面（主要用途）；Nano／Unifying 的 HID++ 可能和媒體鍵合在同一個介面，
        // 主要用途是 0x0C，要改比對介面內的用途清單（C52F 實測：滑鼠介面沒有 0xFF00，不會被打開）。
        let lightspeed = OtherDevicesProtocol.lightspeedReceivers.sorted().map {
            [kIOHIDVendorIDKey: OtherDevicesProtocol.vendor, kIOHIDProductIDKey: $0, kIOHIDPrimaryUsagePageKey: 0xFF00]
        }
        let unifyingNano = OtherDevicesProtocol.unifyingNanoReceivers.sorted().map {
            [kIOHIDVendorIDKey: OtherDevicesProtocol.vendor, kIOHIDProductIDKey: $0, kIOHIDDeviceUsagePageKey: 0xFF00]
        }
        let matches = lightspeed + unifyingNano
        IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            Unmanaged<OtherDevicesHIDPP>.fromOpaque(context!).takeUnretainedValue().matched(device)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            Unmanaged<OtherDevicesHIDPP>.fromOpaque(context!).takeUnretainedValue().removed(device)
        }, context)
        IOHIDManagerRegisterInputReportCallback(manager, { context, _, sender, _, _, report, length in
            guard let sender, length >= 7, report[0] == 0x10 || report[0] == 0x11 else { return }
            let device = Unmanaged<IOHIDDevice>.fromOpaque(sender).takeUnretainedValue()
            let bytes = Array(UnsafeBufferPointer(start: report, count: length))
            Unmanaged<OtherDevicesHIDPP>.fromOpaque(context!).takeUnretainedValue().received(device, bytes)
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

    // MARK: - 接收器出現／消失

    private func matched(_ candidate: IOHIDDevice) {
        let output = IOHIDDeviceGetProperty(candidate, kIOHIDMaxOutputReportSizeKey as CFString) as? Int ?? 0
        guard opened, output >= 20 else { return }
        work.async { [weak self] in
            guard let self, !self.stopped, !self.receivers.contains(where: { CFEqual($0, candidate) }) else { return }
            self.receivers.append(candidate)
            let key = self.receiverKey(candidate)
            self.log("Lightspeed receiver \(key) found")
            // 換了 USB 孔重新插上：位置不同、識別不同，舊的「接收器未連接」卡片拿掉（同一個孔會直接沿用）。
            for id in OtherDevicesProtocol.staleAfterReceiverFound(Array(self.devices.values), foundKey: key) { self.forget(id) }
            self.enableConnectionNotices(candidate)
            self.listPaired(candidate)
            // 放棄了也沒關係：定時的配對清單檢查會補讀。
            self.requestScan(candidate, full: false, giveUpAfter: 120)
        }
    }

    // 打開接收器的上線／離線通知（接收器自己回答、不經無線；拔掉接收器後會失效，所以每次找到都檢查）。
    private func enableConnectionNotices(_ receiver: IOHIDDevice) {
        let read = OtherDevicesProtocol.notificationFlagsRead
        func flags() -> [UInt8]? {
            if case .reply(let reply) = send(receiver, read, key: Array(read[1...3]), timeout: 1.0, userAction: true) { return reply }
            return nil
        }
        guard let current = flags(), let on = OtherDevicesProtocol.wirelessNoticesOn(current) else {
            log("receiver connection notices: couldn't read flags")
            return
        }
        if on {
            log("receiver connection notices already on")
            return
        }
        guard let write = OtherDevicesProtocol.enableWirelessNotices(current) else { return }
        _ = send(receiver, write, key: Array(write[1...3]), timeout: 1.0, userAction: true)
        let verified = flags().flatMap { OtherDevicesProtocol.wirelessNoticesOn($0) } == true
        log("receiver connection notices enabled verified=\(verified)")
    }

    // 先把配對清單列出來：接收器自己回答、不經無線，不必等滑鼠停下，畫面馬上有卡片（標成「讀取中」）。
    private func listPaired(_ receiver: IOHIDDevice) {
        let key = receiverKey(receiver)
        for slot in 1...6 {
            let id = key + "#\(slot)"
            guard case .paired(let wpid, let kind) = OtherDevicesProtocol.slotState(
                register(receiver, OtherDevicesProtocol.pairingRequest(slot: slot)), slot: slot) else { continue }
            if var known = devices[id], known.wpid == wpid {
                // 同一個孔插回來：保留上次的資料，等讀完再更新。
                if known.link == .receiverGone { known.link = .reading; devices[id] = known }
                continue
            }
            var card = OtherDeviceSnapshot()
            card.receiver = key
            card.slot = slot
            card.wpid = wpid
            card.kind = OtherDevicesProtocol.kind(fromReceiver: kind)
            card.link = .reading
            if case .reply(let named) = register(receiver, OtherDevicesProtocol.nameRequest(slot: slot)) {
                card.name = OtherDevicesProtocol.pairedName(named, slot: slot)
            }
            OtherDevicesProtocol.applyCatalog(&card)
            forget(id)
            devices[id] = card
            log("other device slot \(slot) listed: \(card.name) wpid=\(wpid)")
        }
        publish()
    }

    private func removed(_ gone: IOHIDDevice) {
        work.async { [weak self] in
            guard let self, self.receivers.contains(where: { CFEqual($0, gone) }) else { return }
            let key = self.receiverKey(gone)
            self.receivers.removeAll { CFEqual($0, gone) }
            // 等待中的讀取作廢，舊回呼不會再對拔掉的接收器讀取。
            _ = self.scanQueue.take(key)
            self.reconnectPending.remove(key)
            // 卡片保留、標成「接收器未連接」（舊版直接拿掉）；功能表與電壓平均作廢，插回來整台重讀。
            for (id, var d) in self.devices where d.receiver == key {
                d.link = .receiverGone
                self.devices[id] = d
                self.features[id] = nil
                self.samples[id] = nil
            }
            self.log("Lightspeed receiver \(key) removed")
            self.publish()
        }
    }

    private func receiverKey(_ device: IOHIDDevice) -> String {
        let product = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
        let location = IOHIDDeviceGetProperty(device, kIOHIDLocationIDKey as CFString) as? Int ?? 0
        return String(format: "%04X@%08X", product, location)
    }

    private func forget(_ id: String) {
        devices[id] = nil
        features[id] = nil
        samples[id] = nil
        lastBattery[id] = nil
        lastPing[id] = nil
        lastLightTry[id] = nil
        lastFullRead[id] = nil
    }

    // 裝置回來了（0x41 連線通知或 0x1D4B）：併成同一輪讀取；剛讀完的不再重讀。
    private func deviceCameBack(_ source: IOHIDDevice, slot: Int) {
        let key = receiverKey(source), id = key + "#\(slot)"
        func needed() -> Bool {
            OtherDevicesProtocol.reconnectReadNeeded(online: devices[id]?.link == .online, lastFullRead: lastFullRead[id], now: Date())
        }
        guard needed(), reconnectPending.insert(key).inserted else { return }
        // 剛連上要等一下才回得了話。
        work.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            self.reconnectPending.remove(key)
            guard !self.stopped, needed(), let receiver = self.receivers.first(where: { self.receiverKey($0) == key }) else { return }
            self.requestScan(receiver, full: true, giveUpAfter: 60)
        }
    }

    // MARK: - 定時讀取（work 佇列）

    private func startTimer() {
        let timer = DispatchSource.makeTimerSource(queue: work)
        // 每 5 秒看一次要不要讀（各項自己看時間，連著的裝置還是 5 分鐘才讀電量）；等待上限小於間隔，不會重疊。
        timer.schedule(deadline: .now() + 5, repeating: 5)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let waiting = self.devices.values.contains { $0.link == .noAnswer || $0.link == .reading }
            self.whenIdle(giveUpAfter: waiting ? 1.5 : 4, quick: waiting) { [weak self] in self?.tick() }
        }
        timer.resume()
        self.timer = timer
    }

    private func tick() {
        guard !stopped else { return }
        // 每 5 分鐘重新看一次接收器的配對清單（接收器自己回答，不必喚醒裝置）。看的是上次掃完的時間，
        // 滑鼠一直在動、略過幾輪之後，停下來的第一輪就會補做（舊版數輪次，略過的輪不算，會一直往後延）。
        let due = receivers.filter { OtherDevicesProtocol.pairingCheckDue(last: lastScan[receiverKey($0)], now: Date()) }
        if !due.isEmpty {
            for receiver in due {
                // 已經排著的掃描併進來做，免得等一下又做一次。
                let full = scanQueue.take(receiverKey(receiver)) ?? false
                if !scan(receiver, full: full) { break }
            }
            return
        }
        gate.begin()
        var changed = false
        for (id, snapshot) in devices {
            if gate.interrupted { break }
            guard let receiver = receivers.first(where: { receiverKey($0) == snapshot.receiver }) else { continue }
            if snapshot.link == .noAnswer || snapshot.link == .reading {
                // 這台接收器已經排著讀取：不另外再讀一輪。
                let key = receiverKey(receiver)
                if scanQueue.token(key) != nil || reconnectPending.contains(key) { continue }
                guard OtherDevicesProtocol.wakeCheckDue(lastPing: lastPing[id], now: Date(),
                                                        secondsSinceMouse: secondsSinceMouseEvents().min() ?? .infinity) else { continue }
                lastPing[id] = Date()
                if ping(receiver, snapshot.slot) {
                    readDevice(receiver, slot: snapshot.slot, paired: snapshot)
                    changed = true
                } else if snapshot.link == .reading, !gate.interrupted {
                    markNoAnswer(id)
                    changed = true
                }
            } else if Date().timeIntervalSince(lastBattery[id] ?? .distantPast) >= OtherDevicesHIDPP.batteryInterval,
                      Date().timeIntervalSince(lastLightTry[id] ?? .distantPast) >= 60 {
                lastLightTry[id] = Date()
                readLight(receiver, id)
                changed = true
            }
        }
        if changed { publish() }
    }

    // 連著的裝置只讀電量與 DPI／回報率；讀不到再 ping，沒回應就標成「沒有回應」。
    private func readLight(_ receiver: IOHIDDevice, _ id: String) {
        guard let snapshot = devices[id] else { return }
        let before = sent
        if readBattery(receiver, id) {
            readSpeed(receiver, id)
        } else if !gate.interrupted, !ping(receiver, snapshot.slot), !gate.interrupted {
            markNoAnswer(id)
        }
        if gate.interrupted { return }      // 讀到一半滑鼠動了：不算沒回應，下一輪再讀
        let d = devices[id] ?? snapshot
        log("other device \(d.name) battery read (\(sent - before) requests): \(d.batteryPercent)% \(d.millivolts)mV dpi=\(d.dpi)")
    }

    // 逐一看接收器的槽位：配對清單是接收器自己回答（不經無線）；有配對才問裝置。
    // 已連著的同一台只讀電量（full 時整台重讀）；沒回應的保留上次讀到的資料，標成「沒有回應」。
    // 回傳 false：滑鼠動了，中途中斷（沒讀到的維持原狀）。
    @discardableResult
    private func scan(_ receiver: IOHIDDevice, full: Bool) -> Bool {
        let key = receiverKey(receiver)
        gate.begin()
        for slot in 1...6 {
            let id = key + "#\(slot)"
            let outcome = register(receiver, OtherDevicesProtocol.pairingRequest(slot: slot))
            if gate.interrupted { break }
            let pairing: (wpid: String, kind: Int)
            switch OtherDevicesProtocol.slotState(outcome, slot: slot) {
            case .empty:
                if devices[id] != nil { forget(id) }
                continue
            case .unknown:
                // 逾時或回覆對不上：不知道有沒有裝置，保留上次的卡片（舊版當成空槽，卡片會消失）。
                continue
            case .paired(let wpid, let kind):
                pairing = (wpid, kind)
            }
            var base = devices[id] ?? OtherDeviceSnapshot()
            base.receiver = key
            base.slot = slot
            if base.wpid != pairing.wpid {
                // 槽位換了裝置：舊資料作廢。
                forget(id)
                base = OtherDeviceSnapshot()
                base.receiver = key
                base.slot = slot
            }
            base.wpid = pairing.wpid
            if base.kind < 0 || base.name.isEmpty { base.kind = OtherDevicesProtocol.kind(fromReceiver: pairing.kind) }
            if base.name.isEmpty, case .reply(let named) = register(receiver, OtherDevicesProtocol.nameRequest(slot: slot)) {
                base.name = OtherDevicesProtocol.pairedName(named, slot: slot)
            }
            OtherDevicesProtocol.applyCatalog(&base)
            if gate.interrupted { break }
            let plan = OtherDevicesProtocol.readPlan(known: devices[id] != nil, sameDevice: true,
                                                     online: devices[id]?.link == .online,
                                                     hasFeatures: !(features[id]?.isEmpty ?? true), forceFull: full)
            if plan == .battery {
                devices[id] = base
                // 剛讀過（例如開視窗連著兩次）就不再問。
                if Date().timeIntervalSince(lastBattery[id] ?? .distantPast) > 30 { readLight(receiver, id) }
            } else if ping(receiver, slot) {
                readDevice(receiver, slot: slot, paired: base)
            } else if !gate.interrupted {
                base.link = .noAnswer
                devices[id] = base
                log("other device slot \(slot) (\(base.name)) paired but not answering")
            }
            if gate.interrupted { break }
        }
        let done = !gate.interrupted
        if done { lastScan[key] = Date() } else { log("scan of \(key) interrupted: mouse moving (\(sent) requests so far)") }
        publish()
        return done
    }

    private func markNoAnswer(_ id: String) {
        guard var snapshot = devices[id], snapshot.link != .noAnswer else { return }
        snapshot.link = .noAnswer
        devices[id] = snapshot
        // 下次連上重新查功能（韌體更新後可能不同），但留著 0x1D4B 的索引，重連事件才認得出來。
        features[id] = OtherDevicesProtocol.featuresAfterNoAnswer(features[id])
        log("other device \(snapshot.name) not answering")
    }

    // 連著的裝置：讀全部資訊。
    private func readDevice(_ receiver: IOHIDDevice, slot: Int, paired: OtherDeviceSnapshot) {
        guard receivers.contains(where: { CFEqual($0, receiver) }) else { return }
        let before = sent, timeoutsBefore = timeouts
        let id = paired.id
        if features[id] == nil { features[id] = [:] }   // 功能表沿用（沒回應時 markNoAnswer 會清掉，重連後重查）
        var s = paired
        s.link = .online
        if let count = call(receiver, id, slot, 0x0005, 0) {
            var name: [UInt8] = []
            let length = min(Int(count[4]), 64)
            while name.count < length {
                guard let piece = call(receiver, id, slot, 0x0005, 1, [UInt8(name.count)]) else { break }
                let chunk = Array(piece[4..<min(piece.count, 20)].prefix(length - name.count))
                if chunk.isEmpty { break }
                name += chunk
            }
            let full = String(bytes: name, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters) ?? ""
            if !full.isEmpty { s.name = full }
            if let type = call(receiver, id, slot, 0x0005, 2) { s.kind = Int(type[4]) }
        }
        if let count = call(receiver, id, slot, 0x0003, 0) {
            let unit = OtherDevicesProtocol.unitId(count)
            if !unit.isEmpty { s.unitId = unit }
            for i in 0..<min(Int(count[4]), 8) {
                if let info = call(receiver, id, slot, 0x0003, 1, [UInt8(i)]), let text = OtherDevicesProtocol.firmware(info) {
                    s.firmware = text
                    break
                }
            }
        }
        if let list = call(receiver, id, slot, 0x2201, 1, [0]), let range = OtherDevicesProtocol.dpiRange(list) {
            s.dpiMin = range.min
            s.dpiMax = range.max
        }
        if let current = call(receiver, id, slot, 0x2201, 2, [0]) { s.dpi = OtherDevicesProtocol.currentDpi(current) }
        if let rate = call(receiver, id, slot, 0x8060, 1) { s.reportRateMs = Int(rate[4]) }
        if let info = call(receiver, id, slot, 0x8100, 0) {
            s.profileCount = Int(info[7])
            s.buttonCount = Int(info[9])
            s.sectorSize = Int(info[11]) << 8 | Int(info[12])
            s.onboardFormatOK = OtherDevicesProtocol.onboardFormatSupported(info)
            log("other device slot \(slot) onboard format memory=\(info[4]) profile=\(info[5]) macro=\(info[6]) supported=\(s.onboardFormatOK)")
        }
        if let mode = call(receiver, id, slot, 0x8100, 2) { s.onboardMode = Int(mode[4]) }
        if s.onboardMode == 1 { readOnboard(receiver, &s, directory: true) }
        // 0x1D4B 重新連線事件要先知道功能索引才認得（舊版從來沒查，收到也不會處理）。
        _ = findFeature(receiver, id, slot, 0x1D4B)
        if gate.interrupted {
            log("other device slot \(slot) read interrupted: mouse moving")
            return
        }
        // 途中有問答逾時（例如剛好關機）：再問一次，還在才算上線。
        guard OtherDevicesProtocol.readConfirmsOnline(timeouts: timeouts - timeoutsBefore, stillAnswers: { ping(receiver, slot) }) else {
            if gate.interrupted { return }
            devices[id] = paired
            markNoAnswer(id)
            return
        }
        if let backups {
            backups.adoptLegacy(wpid: s.wpid, unitId: s.unitId)
            s.repairSector = backups.pendingRepair(device: s.backupKey)
        }
        s.lastSeen = Date()
        lastFullRead[id] = Date()
        devices[id] = s
        _ = readBattery(receiver, id)
        let d = devices[id] ?? s
        log("other device slot \(slot) connected (\(sent - before) requests): \(d.name) wpid=\(d.wpid) battery=\(d.batteryPercent)% " +
            "\(d.millivolts)mV charging=\(d.charging) dpi=\(d.dpi) rate=\(d.reportRateMs)ms onboard=\(d.onboardMode) fw=\(d.firmware) " +
            "profile=\(d.profileNumber ?? 0)/\(d.profiles.count) stage=\(d.stageIndex) stages=\(d.dpiStages)")
    }

    // 內建設定檔：目前的設定檔、段，以及那個設定檔的各段 DPI（設定檔換了才重讀）。directory：連設定檔清單一起讀。
    private func readOnboard(_ receiver: IOHIDDevice, _ s: inout OtherDeviceSnapshot, directory: Bool, userAction: Bool = false) {
        guard s.onboardFormatOK else { return }   // 不認得的格式不解析
        let id = s.id, slot = s.slot
        if directory {
            var data: [UInt8] = []
            for offset in [0, 16] {
                guard let r = call(receiver, id, slot, 0x8100, OtherDevicesProtocol.onboardReadData,
                                   OtherDevicesProtocol.readDataParameters(sector: 0, offset: offset), userAction: userAction) else { break }
                data += r[4..<20]
                if data.count >= 4 * (s.profileCount + 1) { break }
            }
            let list = OtherDevicesProtocol.directory(data)
            if !list.isEmpty {
                s.profiles = list
                s.profileSlots = OtherDevicesProtocol.directoryEntries(data)
            }
        }
        let before = s.activeProfile
        if let r = call(receiver, id, slot, 0x8100, OtherDevicesProtocol.onboardActiveProfile, userAction: userAction),
           let sector = OtherDevicesProtocol.resolvedActiveProfile(r, wpid: s.wpid, slots: s.profileSlots) { s.activeProfile = sector }
        if let r = call(receiver, id, slot, 0x8100, OtherDevicesProtocol.onboardStageIndex, userAction: userAction),
           let index = OtherDevicesProtocol.stageIndex(r) { s.stageIndex = index }
        // 設定檔開頭 0x50 bytes：各段 DPI（0x03 起）與按鍵表（0x20 起）。設定檔換了才重讀。
        if s.activeProfile != 0 && (s.activeProfile != before || s.dpiStages.isEmpty || s.buttons.isEmpty) {
            var head: [UInt8] = []
            for offset in stride(from: 0, to: s.buttonCount > 0 ? 0x50 : 0x10, by: 16) {
                guard let r = call(receiver, id, slot, 0x8100, OtherDevicesProtocol.onboardReadData,
                                   OtherDevicesProtocol.readDataParameters(sector: s.activeProfile, offset: offset),
                                   userAction: userAction) else { break }
                head += r[4..<20]
            }
            if let stages = OtherDevicesProtocol.profileStages(head) { s.dpiStages = stages }
            if let d = OtherDevicesProtocol.defaultStage(head) { s.defaultStage = d }
            if head.count >= 0x50 { s.buttons = OtherDevicesProtocol.profileButtons(head, count: min(s.buttonCount, 12)) }
            // 燈光在 0xD0 起（兩區 22 bytes）：sector 夠大才讀（G502 255）。
            if s.sectorSize >= OtherDevicesProtocol.lightOffset + 2 * OtherDevicesProtocol.lightSize + 2 {
                var light: [UInt8] = []
                for offset in [OtherDevicesProtocol.lightOffset, OtherDevicesProtocol.lightOffset + 16] {
                    guard let r = call(receiver, id, slot, 0x8100, OtherDevicesProtocol.onboardReadData,
                                       OtherDevicesProtocol.readDataParameters(sector: s.activeProfile, offset: offset),
                                       userAction: userAction) else { break }
                    light += r[4..<20]
                }
                if light.count >= 2 * OtherDevicesProtocol.lightSize {
                    s.lights = OtherDevicesProtocol.profileLights([UInt8](repeating: 0, count: OtherDevicesProtocol.lightOffset) + light, wpid: s.wpid)
                }
            }
        }
    }

    // MARK: - 改按鍵（寫入設定檔；work 佇列）
    // 先讀整個設定檔並備份成檔案，改按鍵表、重算 CRC，寫入後讀回比對；不一致就把原本的內容寫回去。
    // 寫完重新載入設定檔（函式 3）再切回原本的段，新的按鍵才會生效、指標速度也不會跳。

    static var backupFolder: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("MXMasterMac/profile-backups", isDirectory: true)
    }

    private var backups: OtherProfileBackups? { OtherDevicesHIDPP.backupFolder.map(OtherProfileBackups.init(folder:)) }

    static func originalBackup(_ d: OtherDeviceSnapshot) -> URL? {
        backupFolder.map { OtherProfileBackups(folder: $0).originalURL(device: d.backupKey, sector: d.activeProfile) }
    }

    private enum WriteKind {
        case patch(([UInt8], OtherDeviceSnapshot) -> [UInt8]?)
        case restoreOriginal
        case repair
    }

    // 每個寫入都帶「使用者正在編輯的設定檔」：滑鼠已經切到別的設定檔就不寫。completion 在主執行緒：nil 成功，否則是說明。
    func writeButtons(_ id: String, sector: Int, _ changes: [Int: OtherButtonAssignment], restoreOriginal: Bool = false,
                      completion: @escaping (String?) -> Void) {
        let kind: WriteKind = restoreOriginal ? .restoreOriginal : .patch { current, _ in
            OtherDevicesProtocol.patchedProfile(current, buttons: changes)
        }
        writeProfile(id, sector: sector, kind: kind, completion: completion)
    }

    func writeReportRate(_ id: String, sector: Int, ms: Int, completion: @escaping (String?) -> Void) {
        writeProfile(id, sector: sector, kind: .patch { current, _ in
            OtherDevicesProtocol.patchedReportRate(current, ms: ms)
        }, completion: completion)
    }

    func writeLights(_ id: String, sector: Int, _ lights: [Int: OtherLightEffect], completion: @escaping (String?) -> Void) {
        writeProfile(id, sector: sector, kind: .patch { current, _ in
            OtherDevicesProtocol.patchedLights(current, lights)
        }, completion: completion)
    }

    // 改各段 DPI 與開機預設段（同一套寫入流程：備份、寫入、讀回比對、失敗改回）。
    func writeStages(_ id: String, sector: Int, _ stages: [Int], defaultIndex: Int?, completion: @escaping (String?) -> Void) {
        writeProfile(id, sector: sector, kind: .patch { current, s in
            OtherDevicesProtocol.patchedStages(current, stages: stages, defaultIndex: defaultIndex,
                                              min: s.dpiMin > 0 ? s.dpiMin : 100, max: s.dpiMax > 0 ? s.dpiMax : 25_600)
        }, completion: completion)
    }

    // 把上次沒寫完的設定檔寫回最後一次確認完好的內容。
    func repairProfile(_ id: String, completion: @escaping (String?) -> Void) {
        work.async { [weak self] in
            guard let self else { return }
            guard let sector = self.devices[id]?.repairSector else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let result = self.performWrite(id, sector: sector, kind: .repair)
            self.publish()
            DispatchQueue.main.async { completion(result) }
        }
    }

    private func writeProfile(_ id: String, sector: Int, kind: WriteKind, completion: @escaping (String?) -> Void) {
        work.async { [weak self] in
            guard let self else { return }
            let result = self.performWrite(id, sector: sector, kind: kind)
            self.publish()
            DispatchQueue.main.async { completion(result) }
        }
    }

    private func performWrite(_ id: String, sector: Int, kind: WriteKind) -> String? {
        var isRepair = false
        if case .repair = kind { isRepair = true }
        guard var s = devices[id], let backups,
              isRepair ? s.link == .online && s.onboardMode == 1 && (1..<0x100).contains(sector) && s.sectorSize >= 0x50
                       : s.canEditButtons,
              let receiver = receivers.first(where: { receiverKey($0) == s.receiver }) else {
            return Lang.t("裝置沒有連著，或目前的設定檔不能改", "The device isn't connected or this profile can't be changed")
        }
        if !isRepair, s.activeProfile != sector { return OtherDevicesHIDPP.message(.profileChanged) }
        gate.begin()
        let device = s.backupKey, snapshot = s, slot = s.slot, stage = s.stageIndex
        let mode: OtherWriteMode
        switch kind {
        case .patch(let patch): mode = .patch { patch($0, snapshot) }
        case .restoreOriginal: mode = .restore(backups.loadImage(backups.originalURL(device: device, sector: sector), size: s.sectorSize))
        case .repair: mode = .repair(backups.loadImage(backups.repairURL(device: device, sector: sector), size: s.sectorSize))
        }
        let io = OtherProfileIO(
            activeSector: { [unowned self] in
                self.call(receiver, id, slot, 0x8100, OtherDevicesProtocol.onboardActiveProfile, userAction: true)
                    .flatMap { OtherDevicesProtocol.resolvedActiveProfile($0, wpid: snapshot.wpid, slots: snapshot.profileSlots) }
            },
            read: { [unowned self] in self.readSector(receiver, snapshot, $0) },
            command: { [unowned self] function, parameters in
                self.call(receiver, id, slot, 0x8100, function, parameters, userAction: true) != nil
            },
            backup: { backups.save($0, device: device, sector: sector) },
            reload: { [unowned self] in
                // 重新載入設定檔，再切回原本的段，兩步都要收到回覆才算套用。
                guard self.call(receiver, id, slot, 0x8100, OtherDevicesProtocol.onboardSetProfile,
                                OtherDevicesProtocol.setProfileParameters(sector: sector, slots: snapshot.profileSlots),
                                userAction: true) != nil else { return false }
                return stage < 0 || self.call(receiver, id, slot, 0x8100, OtherDevicesProtocol.onboardSetStage,
                                              [UInt8(stage)], userAction: true) != nil
            })
        let outcome = OtherProfileWriter.run(sector: sector, mode: mode, io: io)
        log("other device \(s.name) profile \(sector) write result=\(outcome.result)")
        if outcome.result == .failedNeedsRepair, let image = outcome.repairImage {
            let saved = backups.saveRepair(image, device: device, sector: sector)
            log("other device \(s.name) profile \(sector) repair image saved=\(saved)")
            if saved { s.repairSector = sector }
            devices[id] = s
        }
        if let target = outcome.target {
            if isRepair {
                backups.clearRepair(device: device, sector: sector)
                s.repairSector = nil
            }
            if s.activeProfile == sector {
                s.buttons = OtherDevicesProtocol.profileButtons(target, count: min(s.buttonCount, 12))
                if let stages = OtherDevicesProtocol.profileStages(target) { s.dpiStages = stages }
                if let d = OtherDevicesProtocol.defaultStage(target) { s.defaultStage = d }
                if !s.lights.isEmpty { s.lights = OtherDevicesProtocol.profileLights(target, zones: s.lights.count) }
                if OtherDevicesProtocol.reportRates.contains(Int(target[0])) { s.reportRateMs = Int(target[0]) }
            }
            refreshAfterSwitch(receiver, &s)
            devices[id] = s
            log("other device \(s.name) profile \(sector) buttons written: \(s.buttons.map { $0.bytes.map { String(format: "%02X", $0) }.joined() })")
        }
        return OtherDevicesHIDPP.message(outcome.result)
    }

    // 寫入結果的說明；nil 是成功。
    private static func message(_ result: OtherWriteResult) -> String? {
        switch result {
        case .written, .unchanged: return nil
        case .writtenNotApplied:
            return Lang.t("已寫入滑鼠，但還沒確認套用。切換一次設定檔就會生效", "Saved to the mouse, but not confirmed as applied. Switch profiles once to apply it")
        case .profileChanged:
            return Lang.t("滑鼠的設定檔已經切換，這次沒有寫入。請重新打開再改", "The mouse switched profiles, so nothing was written. Reopen it and try again")
        case .readFailed: return Lang.t("讀取設定檔失敗，沒有寫入", "Couldn't read the profile; nothing was written")
        case .backupFailed: return Lang.t("無法備份目前的設定檔，沒有寫入", "Couldn't back up the current profile; nothing was written")
        case .unexpectedContent: return Lang.t("設定檔內容不符預期，沒有寫入", "The profile looks unexpected; nothing was written")
        case .leftClickLocked: return Lang.t("這個內容會改掉左鍵，沒有寫入", "This would change the left button; nothing was written")
        case .noBackup: return Lang.t("找不到可用的備份", "No usable backup was found")
        case .failedUnchanged: return Lang.t("寫入失敗，設定檔沒有改變", "Writing failed; the profile wasn't changed")
        case .failedRolledBack: return Lang.t("寫入失敗，已改回原本的設定", "Writing failed; the previous settings were restored")
        case .failedNeedsRepair:
            return Lang.t("寫入沒有完成，設定檔可能不完整。滑鼠連回來後請按「修復設定檔」",
                          "Writing didn't finish and the profile may be incomplete. Once the mouse is back, click Repair profile")
        }
    }

    private func readSector(_ receiver: IOHIDDevice, _ s: OtherDeviceSnapshot, _ sector: Int) -> [UInt8]? {
        guard s.sectorSize >= 16 else { return nil }
        var data = [UInt8](repeating: 0, count: s.sectorSize)
        for offset in OtherDevicesProtocol.readOffsets(sectorSize: s.sectorSize) {
            guard let r = call(receiver, s.id, s.slot, 0x8100, OtherDevicesProtocol.onboardReadData,
                               OtherDevicesProtocol.readDataParameters(sector: sector, offset: offset), userAction: true) else { return nil }
            data.replaceSubrange(offset..<(offset + 16), with: r[4..<20])
        }
        return data
    }

    // 定時讀電量時順便更新 DPI、回報率與目前的段：事件漏收（例如 App 沒在跑時按過 DPI 鍵）也會補上。
    private func readSpeed(_ receiver: IOHIDDevice, _ id: String) {
        guard var s = devices[id] else { return }
        if let current = call(receiver, id, s.slot, 0x2201, 2, [0]) { s.dpi = OtherDevicesProtocol.currentDpi(current) }
        if let rate = call(receiver, id, s.slot, 0x8060, 1) { s.reportRateMs = Int(rate[4]) }
        if s.onboardMode == 1 { readOnboard(receiver, &s, directory: false) }
        devices[id] = s
    }

    // MARK: - 使用者按的切換（work 佇列）：不等滑鼠停下（是使用者自己要的，只有幾筆問答）

    func setStage(_ id: String, _ index: Int) {
        work.async { [weak self] in
            guard let self, var s = self.devices[id], s.canSwitchStage, s.dpiStages.indices.contains(index), s.dpiStages[index] > 0,
                  let receiver = self.receivers.first(where: { self.receiverKey($0) == s.receiver }) else { return }
            self.gate.begin()
            let ok = self.call(receiver, id, s.slot, 0x8100, OtherDevicesProtocol.onboardSetStage, [UInt8(index)], userAction: true) != nil
            self.refreshAfterSwitch(receiver, &s)
            self.devices[id] = s
            self.log("other device \(s.name) set stage \(index + 1) ok=\(ok): stage=\(s.stageIndex) dpi=\(s.dpi)")
            self.publish()
        }
    }

    func setProfile(_ id: String, _ sector: Int) {
        work.async { [weak self] in
            guard let self, var s = self.devices[id], s.link == .online, s.onboardMode == 1, s.profiles.contains(sector),
                  let receiver = self.receivers.first(where: { self.receiverKey($0) == s.receiver }) else { return }
            self.gate.begin()
            let ok = self.call(receiver, id, s.slot, 0x8100, OtherDevicesProtocol.onboardSetProfile,
                               OtherDevicesProtocol.setProfileParameters(sector: sector, slots: s.profileSlots),
                               userAction: true) != nil
            self.refreshAfterSwitch(receiver, &s)
            self.devices[id] = s
            self.log("other device \(s.name) set profile \(String(format: "%04X", sector)) ok=\(ok): profile=\(s.profileNumber ?? 0) stage=\(s.stageIndex) dpi=\(s.dpi)")
            self.publish()
        }
    }

    private func refreshAfterSwitch(_ receiver: IOHIDDevice, _ s: inout OtherDeviceSnapshot) {
        let id = s.id
        devices[id] = s
        Thread.sleep(forTimeInterval: 0.15)
        readOnboard(receiver, &s, directory: false, userAction: true)
        if let current = call(receiver, id, s.slot, 0x2201, 2, [0], userAction: true) { s.dpi = OtherDevicesProtocol.currentDpi(current) }
        s.lastSeen = Date()
    }

    // 依裝置支援的功能讀電量：0x1004 → 0x1000 → 0x1001（電壓換算）。
    @discardableResult
    private func readBattery(_ receiver: IOHIDDevice, _ id: String) -> Bool {
        guard var s = devices[id] else { return false }
        var ok = false
        if let reply = call(receiver, id, s.slot, 0x1004, 1), let b = OtherDevicesProtocol.unifiedBatteryInfo(reply) {
            s.batterySource = .percent
            s.batteryPercent = b.percent
            OtherDevicesHIDPP.applyCharge(&s, b.state, fast: false, slow: b.slow)
            ok = true
        } else if let reply = call(receiver, id, s.slot, 0x1000, 0), let b = OtherDevicesProtocol.batteryStatusInfo(reply) {
            s.batterySource = .percent
            s.batteryPercent = b.percent
            OtherDevicesHIDPP.applyCharge(&s, b.state, fast: false, slow: b.slow)
            ok = true
        } else if let reply = call(receiver, id, s.slot, 0x1001, 0) {
            ok = applyVoltage(&s, reply)
        }
        if ok {
            lastBattery[id] = Date()
            s.lastSeen = Date()
            s.batterySeq += 1
        }
        devices[id] = s
        return ok
    }

    private func applyVoltage(_ s: inout OtherDeviceSnapshot, _ bytes: [UInt8]) -> Bool {
        guard let v = OtherDevicesProtocol.voltageInfo(bytes) else { return false }
        // 接上或拔掉電源時電壓會跳一段，平均要重新開始。
        if v.state != s.chargeState { samples[s.id] = [] }
        var list = (samples[s.id] ?? []) + [v.mv]
        if list.count > 5 { list.removeFirst(list.count - 5) }
        samples[s.id] = list
        s.batterySource = .voltage
        s.millivolts = v.mv
        OtherDevicesHIDPP.applyCharge(&s, v.state, fast: v.fast, slow: v.slow)
        s.batteryPercent = v.state == .full ? 100 : OtherDevicesProtocol.percent(millivolts: OtherDevicesProtocol.smoothed(list))
        return true
    }

    static func applyCharge(_ s: inout OtherDeviceSnapshot, _ state: OtherChargeState, fast: Bool, slow: Bool) {
        s.chargeState = state
        s.charging = state == .charging
        s.full = state == .full
        s.fastCharge = fast
        s.slowCharge = slow
    }

    // MARK: - 收到的回報

    private func received(_ source: IOHIDDevice, _ bytes: [UInt8]) {
        lock.lock()
        if let wait = pending, CFEqual(wait.device, source) {
            let key = wait.key
            let reply = bytes.count > key.count && Array(bytes[1...key.count]) == key
            // 錯誤：HID++ 2.0 是 <dev> FF <feature> <function>、HID++ 1.0 是 <dev> 8F <sub> <register>。
            let error = bytes.count >= 6 && bytes[1] == key[0] && (bytes[2] == 0xFF || bytes[2] == 0x8F) &&
                bytes[3] == key[1] && bytes[4] == key[2]
            if reply || error {
                pendingReply = reply ? bytes : nil
                pendingError = error && !reply
                pending = nil
                pendingSemaphore?.signal()
                lock.unlock()
                return
            }
        }
        lock.unlock()
        // 接收器的連線通知（預設沒開；其他程式開了就會收到）：重新看那個槽位。
        if let notice = OtherDevicesProtocol.connectionNotice(bytes) {
            work.async { [weak self] in
                guard let self, !self.stopped else { return }
                self.log("other device slot \(notice.slot) connection notice connected=\(notice.connected)")
                let key = self.receiverKey(source)
                // 關機或斷線：馬上標成沒有回應，不必再問。
                if !notice.connected {
                    self.markNoAnswer(key + "#\(notice.slot)")
                    self.publish()
                    return
                }
                self.deviceCameBack(source, slot: notice.slot)
            }
            return
        }
        // 軟體 ID 為 0 的是裝置主動送出的事件：電量變化、重新連線（0x1D4B）。
        guard bytes[0] == 0x11, bytes[3] & 0x0F == 0, (1...6).contains(bytes[1]) else { return }
        work.async { [weak self] in
            guard let self, !self.stopped else { return }
            let id = self.receiverKey(source) + "#\(bytes[1])"
            guard var s = self.devices[id], let table = self.features[id] else { return }
            if let index = table[0x1D4B], index != 0, bytes[2] == index {
                self.log("other device \(s.name) reconnected")
                self.deviceCameBack(source, slot: s.slot)
            } else if let event = OtherDevicesProtocol.onboardEvent(bytes, featureIndex: table[0x8100] ?? 0) {
                // 按了 DPI 鍵或設定檔鍵：段直接更新；設定檔換了要重讀各段 DPI（等滑鼠停下）。
                s.lastSeen = Date()
                switch event {
                case .stageChanged(let index):
                    s.stageIndex = index
                    if let dpi = OtherDevicesProtocol.dpi(forStage: index, in: s.dpiStages) { s.dpi = dpi }
                    self.devices[id] = s
                    self.log("other device \(s.name) stage changed to \(index + 1) (\(s.dpi) DPI)")
                case .profileChanged:
                    self.devices[id] = s
                    self.log("other device \(s.name) profile changed")
                    self.whenIdle(giveUpAfter: 60, quick: true) {
                        guard var current = self.devices[id], current.link == .online,
                              let receiver = self.receivers.first(where: { self.receiverKey($0) == current.receiver }) else { return }
                        self.gate.begin()
                        current.dpiStages = []
                        current.buttons = []
                        self.readOnboard(receiver, &current, directory: false)
                        if let dpi = OtherDevicesProtocol.dpi(forStage: current.stageIndex, in: current.dpiStages) { current.dpi = dpi }
                        if !self.gate.interrupted { self.devices[id] = current }
                        self.publish()
                    }
                }
                self.publish()
            } else if let index = table[0x1001], index != 0, bytes[2] == index, self.applyVoltage(&s, bytes) {
                s.lastSeen = Date()
                s.batterySeq += 1
                self.devices[id] = s
                self.lastBattery[id] = Date()
                self.publish()
            } else if let index = table[0x1004], index != 0, bytes[2] == index, let b = OtherDevicesProtocol.unifiedBatteryInfo(bytes) {
                s.batteryPercent = b.percent
                OtherDevicesHIDPP.applyCharge(&s, b.state, fast: false, slow: b.slow)
                s.lastSeen = Date()
                s.batterySeq += 1
                self.devices[id] = s
                self.publish()
            }
        }
    }

    // MARK: - 傳輸（work 佇列）

    private func ping(_ receiver: IOHIDDevice, _ slot: Int) -> Bool {
        hidpp(receiver, slot, 0x00, 1, [0, 0, 0x5A], timeout: 1.5) != nil
    }

    private func findFeature(_ receiver: IOHIDDevice, _ id: String, _ slot: Int, _ feature: Int) -> UInt8? {
        if let cached = features[id]?[feature] { return cached == 0 ? nil : cached }
        guard let root = hidpp(receiver, slot, 0x00, 0, [UInt8(feature >> 8), UInt8(feature & 0xFF)], timeout: 1.2) else { return nil }
        features[id, default: [:]][feature] = root[4]
        return root[4] == 0 ? nil : root[4]
    }

    private func call(_ receiver: IOHIDDevice, _ id: String, _ slot: Int, _ feature: Int, _ function: UInt8,
                      _ parameters: [UInt8] = [], userAction: Bool = false) -> [UInt8]? {
        guard let index = findFeature(receiver, id, slot, feature) else { return nil }
        return hidpp(receiver, slot, index, function, parameters, timeout: 1.0, userAction: userAction)
    }

    private func hidpp(_ receiver: IOHIDDevice, _ slot: Int, _ feature: UInt8, _ function: UInt8, _ parameters: [UInt8],
                       timeout: Double, userAction: Bool = false) -> [UInt8]? {
        var packet = [UInt8](repeating: 0, count: 20)
        packet[0] = 0x11
        packet[1] = UInt8(slot)
        packet[2] = feature
        let requestId = requestIds.take(now: Date().timeIntervalSince1970)
        packet[3] = (function << 4) | requestId
        for (i, byte) in parameters.enumerated() where i + 4 < packet.count { packet[i + 4] = byte }
        let outcome = send(receiver, packet, key: Array(packet[1...3]), timeout: timeout, userAction: userAction)
        if case .timeout = outcome { requestIds.timedOut(requestId, now: Date().timeIntervalSince1970) }
        guard case .reply(let reply) = outcome, reply.count >= 16 else { return nil }
        return reply
    }

    // HID++ 1.0 接收器暫存器讀取（短封包送出，回覆可能是長封包）；key 多比對子暫存器。
    // 暫存器由接收器自己回答、不經無線，不影響游標，不用等滑鼠停下。
    private func register(_ receiver: IOHIDDevice, _ packet: [UInt8]) -> OtherRegisterOutcome {
        send(receiver, packet, key: Array(packet[1...4]), timeout: 1.0, userAction: true)
    }

    // 每一筆送出前都重看滑鼠（gate）：動了最多等 3 秒，還在動就中斷這一批（回傳 timeout，
    // 呼叫端看 gate.interrupted 分辨，不會把裝置當成沒回應或空槽）。
    // userAction：使用者按的切換，不等滑鼠停下（點按鈕或選單時滑鼠本來就在動）。
    private func send(_ receiver: IOHIDDevice, _ packet: [UInt8], key: [UInt8], timeout: Double,
                      userAction: Bool = false) -> OtherRegisterOutcome {
        guard userAction || gate.allow(idle: { mouseIdle(idleNeeded) }, wait: { Thread.sleep(forTimeInterval: $0) }) else { return .timeout }
        sent += 1
        let semaphore = DispatchSemaphore(value: 0)
        lock.lock()
        pending = (receiver, key)
        pendingReply = nil
        pendingError = false
        pendingSemaphore = semaphore
        lock.unlock()
        if IOHIDDeviceSetReport(receiver, kIOHIDReportTypeOutput, CFIndex(packet[0]), packet, packet.count) == kIOReturnSuccess {
            _ = semaphore.wait(timeout: .now() + timeout)
        }
        lock.lock()
        let reply = pendingReply
        let error = pendingError
        pending = nil
        pendingReply = nil
        pendingError = false
        pendingSemaphore = nil
        lock.unlock()
        if let reply { return .reply(reply) }
        if error { return .error }
        timeouts += 1
        return .timeout
    }

    private func log(_ text: String) {
        DispatchQueue.main.async { [weak self] in self?.onLog?("Others " + text) }
    }

    private func publish() {
        let list = devices.values.sorted { ($0.receiver, $0.slot) < ($1.receiver, $1.slot) }
        DispatchQueue.main.async { [weak self] in self?.onChange?(list) }
    }
}
