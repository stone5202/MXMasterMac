import AppKit
import Combine
import ServiceManagement

// 全部的執行期狀態與輸入處理邏輯；只在主執行緒使用。
final class AppModel: ObservableObject {
    static let version = "1.1.1"

    @Published var config: Config { didSet { configChanged() } }
    @Published var status: DeviceStatus = .searching
    @Published var snapshot: DeviceSnapshot?
    @Published var enabled = true
    @Published var trusted = AXIsProcessTrusted()
    @Published var tapInstalled = false
    @Published var logLines: [String] = []
    @Published var logging = false
    @Published var deviceMessage = ""
    @Published var launchAtLogin = false
    @Published var optionsPlusRunning = HIDPP.optionsPlusRunning

    let hidpp = HIDPP()
    private let tap = EventTap()
    private let ring = RingOverlay()
    private let hud = GestureHUD()
    private var timers: [Timer] = []

    // 圓環與手勢的進行狀態
    private var swallowLeftUp = false
    private var swallowRightUp = false
    private var swallowedButtons = Set<String>()
    private var gestureActive = false
    private var gestureStart = NSPoint.zero
    private var gestureDirection = -1          // 0 上、1 右、2 下、3 左
    private var gestureMoved = false
    private var gestureTimer: Timer?
    private var lastWheelAction = Date.distantPast
    private var buttonState: [Int: Bool] = [:]

    init() {
        config = Config.load()
        Lang.load(config.language)
        ring.slots = config.ring
        ring.clickMode = config.ringClick
        ring.bubbles = config.ringStyle == "bubble"
        ring.scale = CGFloat(config.ringScaleFactor)
        ring.bubbleScale = CGFloat(config.bubbleScaleFactor)
        ring.opacity = CGFloat(config.ringOpacity)
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func start() {
        hidpp.onLog = { [weak self] in self?.log($0) }
        hidpp.onStatus = { [weak self] in self?.status = $0 }
        hidpp.onButton = { [weak self] cid, down in self?.vendorButton(cid, down) }
        hidpp.onReady = { [weak self] in self?.deviceReady() }
        hidpp.onBattery = { [weak self] percent, charging in
            self?.snapshot?.batteryPercent = percent
            self?.snapshot?.charging = charging
        }
        if CommandLine.arguments.contains("--log") { setLogging(true) }
        hidpp.start()

        tap.handler = { [weak self] in self?.tapEvent($0) ?? false }
        installTapIfPossible()
        // 權限是使用者到「系統設定」裡開的，只能定時看有沒有開。
        timers.append(Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.installTapIfPossible()
        })
        timers.append(Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            self?.hidpp.recheck()
            self?.refreshDevice()
        })
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil,
                                                          queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self?.hidpp.recheck() }
        }
    }

    func shutdown() {
        tap.remove()
        hidpp.shutdown()
    }

    // MARK: - 設定

    private func configChanged() {
        config.save()
        ring.slots = config.ring
        ring.clickMode = config.ringClick
        ring.bubbles = config.ringStyle == "bubble"
        ring.scale = CGFloat(config.ringScaleFactor)
        ring.bubbleScale = CGFloat(config.bubbleScaleFactor)
        ring.opacity = CGFloat(config.ringOpacity)
    }

    func mapping(_ input: MouseInput) -> ActionBinding { config.binding(for: input) }

    func setMapping(_ input: MouseInput, _ binding: ActionBinding) {
        config.mappings[input.rawValue] = binding
    }

    func setEnabled(_ value: Bool) {
        guard enabled != value else { return }
        enabled = value
        if !value {
            cancelRing()
            cancelGesture()
        }
        hidpp.setEnabled(value)
    }

    func setLaunchAtLogin(_ value: Bool) {
        do {
            if value { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            log("launch at login: \(error.localizedDescription)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func openInputMonitoringSettings() {
        HIDPP.requestInputMonitoring()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func installTapIfPossible() {
        let now = AXIsProcessTrusted()
        if now != trusted { trusted = now }
        let running = HIDPP.optionsPlusRunning
        if running != optionsPlusRunning {
            optionsPlusRunning = running
            log("Options+ " + (running ? "started" : "stopped"))
            // Options+ 結束時可能留下它的滾輪設定、或順手清掉改道；等它收尾後檢查並補回。
            if !running {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                    self?.hidpp.recheck()
                    self?.deviceReady()
                }
            }
        }
        if now && !tap.installed {
            let ok = tap.install()
            log(ok ? "event tap installed" : "event tap could not be created")
        }
        if tapInstalled != tap.installed { tapInstalled = tap.installed }
    }

    // MARK: - 裝置

    private func deviceReady() {
        buttonState.removeAll()
        hidpp.restore(config.device) { [weak self] snapshot, results in
            guard let self else { return }
            if let snapshot { self.snapshot = snapshot }
            for line in snapshot?.raw ?? [] { self.log("Device " + line) }
            for line in results { self.log("Device " + line) }
            if results.contains(where: { $0.hasSuffix("verified=false") }) {
                self.deviceMessage = Lang.t("部分儲存的裝置設定重新套用失敗", "Some saved device settings could not be re-applied")
            } else if !results.isEmpty {
                self.deviceMessage = Lang.t("已重新套用儲存的裝置設定", "Saved device settings re-applied")
            }
        }
    }

    func refreshDevice() {
        hidpp.readDevice { [weak self] snapshot in
            if let snapshot { self?.snapshot = snapshot }
        }
    }

    // 套用一項裝置設定；滑鼠回讀確認後才寫進設定檔。
    func applyDevice(_ name: String, _ operation: @escaping (HIDPP) -> Bool, save: @escaping (inout DeviceSettings) -> Void) {
        deviceMessage = Lang.t("套用中…", "Applying…")
        hidpp.write(operation) { [weak self] ok in
            guard let self else { return }
            self.log("Device set \(name) verified=\(ok)")
            if ok {
                save(&self.config.device)
                self.deviceMessage = name + Lang.t("：已套用", ": applied")
            } else {
                self.deviceMessage = name + Lang.t("：滑鼠沒有確認，未套用", ": not confirmed by the mouse")
            }
            self.refreshDevice()
        }
    }

    // MARK: - 專用按鍵（HID++）

    private func vendorButton(_ cid: Int, _ down: Bool) {
        // 同一次按下可能以不同格式重複送達；狀態沒變就不處理。
        if buttonState[cid] == down { return }
        buttonState[cid] = down
        let name = cid == 0x00C3 ? "GestureButton" : "ActionRingButton"
        log("Decoded \(name) " + (down ? "Down" : "Up"))
        guard enabled else { return }

        if cid == 0x00C3 {
            if config.gestureMode {
                if down { beginGesture() } else if gestureActive { finishGesture() }
            } else if down {
                runMapped(.gesture)
            }
            return
        }

        if config.ringMode {
            if ring.visible && ring.clickMode {
                // 點選模式：圓環開著時放開不做事，再按一次取消。
                if down { cancelRing() }
            } else if down {
                ring.clickMode = config.ringClick
                ring.show(at: NSEvent.mouseLocation)
                log("ActionRing opened" + (ring.clickMode ? " click-mode" : ""))
            } else if ring.visible {
                let selected = ring.selectedBinding
                ring.hide()
                let sent = selected.map { ActionRunner.run($0) } ?? false
                log("ActionRing selected=\(selected?.action.rawValue ?? "None") sent=\(sent)")
            }
        } else if down {
            runMapped(.actionRing)
        }
    }

    private func runMapped(_ input: MouseInput) {
        let binding = mapping(input)
        let sent = ActionRunner.run(binding)
        log("Mapped \(input.rawValue) selected=\(binding.action.rawValue) sent=\(sent)")
    }

    private func cancelRing() {
        guard ring.visible else { return }
        ring.hide()
        log("ActionRing cancelled")
    }

    // MARK: - 拇指四向手勢

    private func beginGesture() {
        gestureActive = true
        gestureStart = NSEvent.mouseLocation
        gestureDirection = -1
        gestureMoved = false
        hud.show(at: gestureStart, text: Lang.t("往四個方向滑動", "Swipe in a direction"))
        gestureTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.trackGesture() }
        RunLoop.main.add(timer, forMode: .common)
        gestureTimer = timer
    }

    private func trackGesture() {
        let location = NSEvent.mouseLocation
        let dx = location.x - gestureStart.x, dy = location.y - gestureStart.y
        if abs(dx) > 8 || abs(dy) > 8 { gestureMoved = true }
        // 方向一旦鎖定就不再變，避免放開前游標回彈改變結果。
        guard gestureDirection < 0, max(abs(dx), abs(dy)) >= 65 else { return }
        if abs(dx) >= abs(dy) * 1.35 {
            gestureDirection = dx > 0 ? 1 : 3
        } else if abs(dy) >= abs(dx) * 1.35 {
            gestureDirection = dy > 0 ? 0 : 2
        } else {
            return
        }
        hud.update(config.gestures[gestureDirection].title)
    }

    private func finishGesture() {
        gestureActive = false
        gestureTimer?.invalidate()
        gestureTimer = nil
        hud.hide()
        if gestureDirection >= 0 {
            let binding = config.gestures[gestureDirection]
            let sent = ActionRunner.run(binding)
            log("Gesture direction=\(gestureDirection) selected=\(binding.action.rawValue) sent=\(sent)")
        } else if gestureMoved {
            log("Gesture direction=Ambiguous")
        } else {
            runMapped(.gesture)
        }
    }

    private func cancelGesture() {
        guard gestureActive else { return }
        gestureActive = false
        gestureTimer?.invalidate()
        gestureTimer = nil
        hud.hide()
    }

    // MARK: - 一般按鍵與水平滾輪（事件攔截）

    private func tapEvent(_ event: TapEvent) -> Bool {
        guard enabled else { return false }
        switch event {
        case .leftDown:
            guard ring.visible && ring.clickMode else { return false }
            let index = ring.slotUnderCursor()
            let selected = ring.selectedBinding
            ring.hide()
            swallowLeftUp = true
            if index >= 0, let selected {
                // 等這次點擊結束後再送鍵，免得動作落在圓環底下的視窗之前。
                DispatchQueue.main.async { [weak self] in
                    let sent = ActionRunner.run(selected)
                    self?.log("ActionRing clicked=\(selected.action.rawValue) sent=\(sent)")
                }
            } else {
                log("ActionRing cancelled")
            }
            return true
        case .leftUp:
            if swallowLeftUp { swallowLeftUp = false; return true }
            return false
        case .rightDown:
            guard ring.visible && ring.clickMode else { return false }
            cancelRing()
            swallowRightUp = true
            return true
        case .rightUp:
            if swallowRightUp { swallowRightUp = false; return true }
            return false
        case .middleDown: return buttonDown(.middle, event)
        case .backDown: return buttonDown(.back, event)
        case .forwardDown: return buttonDown(.forward, event)
        case .middleUp: return buttonUp(.middle)
        case .backUp: return buttonUp(.back)
        case .forwardUp: return buttonUp(.forward)
        case .wheelLeft: return wheel(.wheelLeft)
        case .wheelRight: return wheel(.wheelRight)
        }
    }

    private func buttonDown(_ input: MouseInput, _ event: TapEvent) -> Bool {
        let binding = mapping(input)
        if logging { log("Tap \(event.rawValue)") }
        if binding.isPassThrough { return false }
        swallowedButtons.insert(input.rawValue)
        DispatchQueue.main.async { [weak self] in
            let sent = ActionRunner.run(binding)
            self?.log("Mapped \(input.rawValue) selected=\(binding.action.rawValue) sent=\(sent)")
        }
        return true
    }

    // 按下被吃掉的話，對應的放開也要吃掉，否則 App 會收到落單的放開事件。
    private func buttonUp(_ input: MouseInput) -> Bool {
        swallowedButtons.remove(input.rawValue) != nil
    }

    private func wheel(_ input: MouseInput) -> Bool {
        let binding = mapping(input)
        if binding.isPassThrough { return false }
        // 滾輪轉一下會送出一串事件，間隔內只執行一次。
        if Date().timeIntervalSince(lastWheelAction) >= 0.30 {
            lastWheelAction = Date()
            DispatchQueue.main.async { [weak self] in
                let sent = ActionRunner.run(binding)
                self?.log("Mapped \(input.rawValue) selected=\(binding.action.rawValue) sent=\(sent)")
            }
        }
        return true
    }

    // MARK: - 工程記錄

    func setLogging(_ value: Bool) {
        logging = value
        if value {
            try? FileManager.default.createDirectory(at: Config.directory, withIntermediateDirectories: true)
            try? "MX Master Mac diagnostic capture\n".write(to: Config.logURL, atomically: true, encoding: .utf8)
        }
    }

    func clearLog() { logLines.removeAll() }

    func log(_ text: String) {
        let formatter = AppModel.timeFormatter
        let line = formatter.string(from: Date()) + " " + text
        logLines.append(line)
        if logLines.count > 300 { logLines.removeFirst(logLines.count - 300) }
        guard logging, let data = (line + "\n").data(using: .utf8),
              let handle = try? FileHandle(forWritingTo: Config.logURL) else { return }
        handle.seekToEndOfFile()
        handle.write(data)
        try? handle.close()
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    // MARK: - 顯示用文字

    var statusText: String {
        switch status {
        case .searching: return Lang.t("正在尋找 MX Master 4…", "Looking for MX Master 4…")
        case .ready(let transport):
            let name = transport == "BOLT" ? "Logi Bolt" : "Bluetooth"
            return Lang.t("滑鼠已就緒（\(name)），專用按鍵已啟用", "Mouse ready (\(name)); special buttons enabled")
        case .notFound: return Lang.t("沒有偵測到 MX Master 4", "MX Master 4 not detected")
        case .needsInputMonitoring:
            return Lang.t("需要「輸入監控」權限才能與滑鼠通訊", "Input Monitoring permission is needed to talk to the mouse")
        case .problem(let text): return text
        }
    }

    var batteryText: String {
        guard let snapshot, snapshot.batteryPercent >= 0 else { return "" }
        return "\(snapshot.batteryPercent)%" + (snapshot.charging ? Lang.t("（充電中）", " (charging)") : "")
    }
}
