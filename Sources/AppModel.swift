import AppKit
import Combine
import ServiceManagement
import UserNotifications

// 全部的執行期狀態與輸入處理邏輯；只在主執行緒使用。
final class AppModel: ObservableObject {
    static let version = "2.2"

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
    @Published var hosts: [HostEntry] = []
    @Published var currentHost = -1
    @Published var displayCount = EdgeGeometry.displays().count
    @Published var precisionActive = false
    @Published var notificationStatus: UNAuthorizationStatus = .notDetermined

    let hidpp = HIDPP()
    private let tap = EventTap()
    private let ring = RingOverlay()
    private let hud = GestureHUD()
    private let modeHUD = ModeHUD()
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

    // 螢幕邊緣切換的進行狀態
    private var moveMonitors: [Any] = []
    private var displays = EdgeGeometry.displays()
    private var edgeCandidate: ScreenEdge?
    private var pushStart = Date.distantPast
    private var lastPush = Date.distantPast
    private var edgeCooldown = Date.distantPast
    private var lastArrival = Date.distantPast
    private var lastWake = Date.distantPast
    private var sleeping = false
    private var heldInputs = Set<String>()     // 目前按著的一般滑鼠按鍵（中鍵、側鍵）
    private var deferredInput: MouseInput?     // 被選為切換按鍵的按鍵：動作延到放開時才執行

    // 精準模式：開啟時把 DPI 暫時降到 config.precisionDpi，關閉時寫回原本的速度。
    private var precisionNormalDpi = 0
    private var precisionHeldBy: MouseInput?   // 由「按住」觸發時是哪顆鍵；放開它就恢復

    // 低電量：每次電量降到門檻以下只通知一次；充電或回到門檻之上（多 3%）後才會再通知。
    private var lowBatteryNotified = false
    private let notifier = BatteryNotifier()

    init() {
        config = Config.load()
        Lang.load(config.language)
        ring.slots = config.ring
        ring.clickMode = config.ringClick
        ring.bubbles = config.ringStyle == "bubble"
        ring.light = config.ringColor == "light"
        ring.scale = CGFloat(config.ringScaleFactor)
        ring.bubbleScale = CGFloat(config.bubbleScaleFactor)
        ring.opacity = CGFloat(config.ringOpacity)
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func start() {
        hidpp.onLog = { [weak self] in self?.log($0) }
        ring.onSlotEnter = { [weak self] _ in
            guard let self, self.config.ringHaptic else { return }
            self.playHaptic(self.config.ringHapticWave)
        }
        ActionRunner.mouseAction = { [weak self] action in self?.runMouseAction(action) ?? false }
        hidpp.onStatus = { [weak self] in self?.status = $0 }
        hidpp.onButton = { [weak self] cid, down in self?.vendorButton(cid, down) }
        hidpp.onReady = { [weak self] in
            self?.deviceReady()
            self?.refreshHosts()
        }
        hidpp.onArrival = { [weak self] in self?.mouseArrived() }
        hidpp.onBattery = { [weak self] percent, charging in
            self?.snapshot?.batteryPercent = percent
            self?.snapshot?.charging = charging
            self?.batteryChanged()
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
            self?.sleeping = false
            self?.lastWake = Date()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self?.hidpp.recheck() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil,
                                                          queue: .main) { [weak self] _ in self?.sleeping = true }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil,
                                               queue: .main) { [weak self] _ in
            guard let self else { return }
            self.displays = EdgeGeometry.displays()
            self.displayCount = self.displays.count
        }
        updateMoveMonitors()
    }

    func shutdown() {
        // 精準模式開著就結束的話，先把速度寫回去。
        if precisionActive, precisionNormalDpi > 0 {
            let dpi = precisionNormalDpi
            hidpp.performNow { _ = $0.setDpi(dpi) }
        }
        for monitor in moveMonitors { NSEvent.removeMonitor(monitor) }
        moveMonitors.removeAll()
        tap.remove()
        hidpp.shutdown()
    }

    // MARK: - 設定

    private func configChanged() {
        config.save()
        ring.slots = config.ring
        ring.clickMode = config.ringClick
        ring.bubbles = config.ringStyle == "bubble"
        ring.light = config.ringColor == "light"
        ring.scale = CGFloat(config.ringScaleFactor)
        ring.bubbleScale = CGFloat(config.bubbleScaleFactor)
        ring.opacity = CGFloat(config.ringOpacity)
        updateMoveMonitors()
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
            if precisionActive { setPrecision(false) }
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

    // 通知權限：「進階」頁的權限卡片用。還沒問過就跳系統詢問，拒絕過就開系統設定的通知頁。
    func refreshNotificationStatus() {
        notifier.status { [weak self] status in
            if self?.notificationStatus != status { self?.notificationStatus = status }
        }
    }

    func requestNotifications() {
        if notificationStatus == .notDetermined {
            notifier.request { [weak self] granted in
                self?.log("Notification permission granted=\(granted)")
                self?.refreshNotificationStatus()
            }
        } else if let id = Bundle.main.bundleIdentifier,
                  let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=" + id) {
            NSWorkspace.shared.open(url)
        }
    }

    private func installTapIfPossible() {
        refreshNotificationStatus()
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
        // 重新連線時會把儲存的速度寫回去，精準模式就此結束。
        precisionActive = false
        precisionHeldBy = nil
        hidpp.restore(config.device) { [weak self] snapshot, results in
            guard let self else { return }
            if let snapshot {
                self.snapshot = snapshot
                self.batteryChanged()
            }
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
            guard let snapshot else { return }
            self?.snapshot = snapshot
            self?.batteryChanged()
        }
    }

    // 設定頁改了指標速度：那就是新的正常速度，精準模式結束。
    func applyDpi(_ value: Int) {
        precisionActive = false
        precisionHeldBy = nil
        applyDevice("DPI \(value)", { $0.setDpi(value) }) { $0.dpi = value }
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

    // MARK: - MX Flow：螢幕邊緣切換電腦

    func refreshHosts() {
        hidpp.readHosts { [weak self] hosts, current in
            guard let self, !hosts.isEmpty else { return }
            var hosts = hosts
            // 啟動參數 -demoHosts YES：截圖時把頻道上的電腦名稱換成示範用的名稱。
            if UserDefaults.standard.bool(forKey: "demoHosts") {
                let names = ["MacBook Pro", "Office PC", "Office PC"]
                for i in hosts.indices { hosts[i].name = i < names.count ? names[i] : "" }
            }
            self.hosts = hosts
            self.currentHost = current
            ActionCatalog.hostNames = Dictionary(uniqueKeysWithValues: hosts.map { ($0.index, $0.name) })
        }
    }

    func hostTitle(_ index: Int) -> String {
        let name = hosts.first { $0.index == index }?.name ?? ""
        let channel = Lang.t("頻道 \(index + 1)", "Channel \(index + 1)")
        return name.isEmpty ? channel : channel + " · " + name
    }

    func setEdgeTarget(_ edge: ScreenEdge, _ host: Int?) {
        config.edgeSwitch.targets[edge.rawValue] = host
    }

    func switchHost(_ host: Int, reason: String) {
        edgeCooldown = Date().addingTimeInterval(3)
        resetEdge()
        // 滑鼠離開後，按著的鍵不會再送放開過來；把進行中的狀態清掉，也不執行延後的動作。
        deferredInput = nil
        heldInputs.removeAll()
        buttonState.removeAll()
        cancelRing()
        cancelGesture()
        log("Switch host -> \(host) (\(reason))")
        if precisionActive {
            // 滑鼠要離開了，速度先恢復，免得在另一台電腦上停在精準速度。
            setPrecision(false, quiet: true)
        }
        let haptic: UInt8? = config.flowHaptic && !hapticsPaused ? UInt8(clamping: config.flowHapticWave) : nil
        hidpp.changeHost(host, haptic: haptic) { [weak self] sent in
            self?.log("Switch host sent=\(sent)")
        }
    }

    // 只有功能開著且至少設定了一個邊緣時才監看游標移動。
    private func updateMoveMonitors() {
        let wanted = config.edgeSwitch.enabled && !config.edgeSwitch.targets.isEmpty
        if wanted && moveMonitors.isEmpty {
            // 按著中鍵或側鍵移動時，系統送的是 otherMouseDragged。
            let mask: NSEvent.EventTypeMask = [.mouseMoved, .otherMouseDragged]
            if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] in self?.mouseMoved($0) }) {
                moveMonitors.append(global)
            }
            if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
                self?.mouseMoved(event)
                return event
            }) {
                moveMonitors.append(local)
            }
        } else if !wanted && !moveMonitors.isEmpty {
            for monitor in moveMonitors { NSEvent.removeMonitor(monitor) }
            moveMonitors.removeAll()
            resetEdge()
        }
    }

    private func resetEdge() {
        edgeCandidate = nil
    }

    // 這顆按鍵是不是被選為「要按住才切換」的按鍵。
    private func isEdgeKey(_ input: MouseInput) -> Bool {
        config.edgeSwitch.enabled && config.edgeSwitch.modifierInput == input
    }

    private func edgeKeyHeld(_ settings: EdgeSwitchSettings) -> Bool {
        if let flag = settings.modifierFlag { return NSEvent.modifierFlags.contains(flag) }
        switch settings.modifierInput {
        case .none: return true
        case .gesture: return buttonState[0x00C3] == true
        case .actionRing: return buttonState[0x01A0] == true
        case .some(let input): return heldInputs.contains(input.rawValue)
        }
    }

    // 游標貼著設定好的外緣，而且持續往外推滿指定時間才切換；停在邊緣不動、沿著邊緣滑動、按著左右鍵拖曳都不算。
    private func mouseMoved(_ event: NSEvent) {
        let settings = config.edgeSwitch
        let key = settings.modifierInput
        // 圓環或手勢進行中不切；但切換按鍵就是那顆鍵時，按住它本來就會叫出圓環或手勢。
        guard enabled, settings.enabled, case .ready = status,
              !ring.visible || key == .actionRing, !gestureActive || key == .gesture,
              NSEvent.pressedMouseButtons & 0b11 == 0, let cg = event.cgEvent else { return resetEdge() }
        let now = Date()
        guard now >= edgeCooldown,
              let edge = EdgeGeometry.edge(at: cg.location, displays: displays),
              let target = settings.target(edge), target != currentHost else { return resetEdge() }
        guard edgeKeyHeld(settings) else { return resetEdge() }
        // 觸控式軌跡板或別的滑鼠推到邊緣時不切：收得到這隻滑鼠的輸入回報時，要求它剛剛才動過。
        if let age = hidpp.motionAge, age > 0.3 { return resetEdge() }

        let dx = cg.getDoubleValueField(.mouseEventDeltaX), dy = cg.getDoubleValueField(.mouseEventDeltaY)
        let outward: Double, along: Double
        switch edge {
        case .left: (outward, along) = (-dx, abs(dy))
        case .right: (outward, along) = (dx, abs(dy))
        case .top: (outward, along) = (-dy, abs(dx))
        case .bottom: (outward, along) = (dy, abs(dx))
        }
        guard outward > 0, outward >= along else { return }

        if edge != edgeCandidate || now.timeIntervalSince(lastPush) > 0.25 {
            edgeCandidate = edge
            pushStart = now
        }
        lastPush = now
        if now.timeIntervalSince(pushStart) >= settings.dwell {
            switchHost(target, reason: "edge " + edge.rawValue)
        }
    }

    // 滑鼠離開後又連回來：只設定了一個邊緣時，把游標移到那個邊緣（從那一側回來）。
    // 分不出是從哪一台切回來的，設定了多個邊緣就不移動；電腦剛喚醒時的重新連線也不移動。
    private func mouseArrived() {
        refreshHosts()
        // 用圓環點選切走時，放開事件送不到這台；回來時別再吃掉下一次放開。
        swallowLeftUp = false
        swallowRightUp = false
        swallowedButtons.removeAll()
        let settings = config.edgeSwitch
        let now = Date()
        guard enabled, settings.enabled, settings.placeCursor, !sleeping,
              now.timeIntervalSince(lastWake) > 60, now.timeIntervalSince(lastArrival) > 5 else { return }
        lastArrival = now
        let edges = ScreenEdge.allCases.filter { settings.target($0) != nil }
        guard edges.count == 1, let location = CGEvent(source: nil)?.location,
              let point = EdgeGeometry.arrivalPoint(for: edges[0], near: location, displays: displays) else { return }
        CGWarpMouseCursorPosition(point)
        CGAssociateMouseAndMouseCursorPosition(1)
        edgeCooldown = now.addingTimeInterval(1)
        log("Mouse arrived; cursor placed at \(edges[0].rawValue) edge")
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
            } else {
                clickMapped(.gesture, down)
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
        } else {
            clickMapped(.actionRing, down)
        }
    }

    // 專用鍵當一般按鍵用：按下就執行。被選為切換按鍵時改在放開時執行，切換了就不執行。
    private func clickMapped(_ input: MouseInput, _ down: Bool) {
        if mapping(input).action == .precisionHold {
            holdPrecision(input, down)
            return
        }
        if isEdgeKey(input) {
            if down {
                deferredInput = input
            } else if deferredInput == input {
                deferredInput = nil
                runMapped(input)
            }
        } else if down {
            runMapped(input)
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
        // 距離隨「手勢靈敏度」縮放；50% 時是原本的 8pt／65pt。
        let factor = config.gestureDistanceFactor
        if abs(dx) > 8 * factor || abs(dy) > 8 * factor { gestureMoved = true }
        // 方向一旦鎖定就不再變，避免放開前游標回彈改變結果。
        guard gestureDirection < 0, max(abs(dx), abs(dy)) >= 65 * factor else { return }
        if abs(dx) >= abs(dy) * 1.35 {
            gestureDirection = dx > 0 ? 1 : 3
        } else if abs(dy) >= abs(dx) * 1.35 {
            gestureDirection = dy > 0 ? 0 : 2
        } else {
            return
        }
        hud.update(config.gestures[gestureDirection].title)
        if config.gestureHaptic { playHaptic(config.gestureHapticWave) }
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
        heldInputs.insert(input.rawValue)
        let binding = mapping(input)
        if logging { log("Tap \(event.rawValue)") }
        if binding.isPassThrough { return false }
        swallowedButtons.insert(input.rawValue)
        if binding.action == .precisionHold {
            holdPrecision(input, true)
            return true
        }
        if isEdgeKey(input) {
            deferredInput = input
            return true
        }
        DispatchQueue.main.async { [weak self] in
            let sent = ActionRunner.run(binding)
            self?.log("Mapped \(input.rawValue) selected=\(binding.action.rawValue) sent=\(sent)")
        }
        return true
    }

    // 按下被吃掉的話，對應的放開也要吃掉，否則 App 會收到落單的放開事件。
    private func buttonUp(_ input: MouseInput) -> Bool {
        heldInputs.remove(input.rawValue)
        if precisionHeldBy == input { holdPrecision(input, false) }
        if deferredInput == input {
            deferredInput = nil
            DispatchQueue.main.async { [weak self] in self?.runMapped(input) }
        }
        return swallowedButtons.remove(input.rawValue) != nil
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

    // MARK: - 精準模式與滾動模式

    // 從選單動作執行（圓環、手勢、拇指滾輪或按鍵的一般執行）。
    private func runMouseAction(_ action: MappedAction) -> Bool {
        switch action {
        case .precisionHold, .precisionToggle:
            precisionHeldBy = nil
            return setPrecision(!precisionActive)
        case .wheelModeToggle:
            return toggleWheelMode()
        case .hostChannel1, .hostChannel2, .hostChannel3:
            return switchToChannel(action.hostChannel ?? 0)
        default:
            return false
        }
    }

    // 圓環、手勢或按鍵執行「切換到頻道 N」。已經在那個頻道或滑鼠沒就緒時不做事。
    private func switchToChannel(_ channel: Int) -> Bool {
        guard case .ready = status else { return false }
        if channel == currentHost {
            log("Switch host -> \(channel) skipped (already on this channel)")
            return false
        }
        if let host = hosts.first(where: { $0.index == channel }), !host.paired {
            log("Switch host -> \(channel) skipped (channel not paired)")
            return false
        }
        switchHost(channel, reason: "action")
        return true
    }

    private func holdPrecision(_ input: MouseInput, _ down: Bool) {
        if down {
            guard precisionHeldBy == nil else { return }
            if setPrecision(true) { precisionHeldBy = input }
            log("Precision hold \(input.rawValue) down active=\(precisionActive)")
        } else if precisionHeldBy == input {
            precisionHeldBy = nil
            setPrecision(false)
            log("Precision hold \(input.rawValue) up")
        }
    }

    // 狀態立刻改，寫入照順序排在 HID++ 佇列上；按一下馬上放開也會先降再升。
    @discardableResult
    func setPrecision(_ on: Bool, quiet: Bool = false) -> Bool {
        guard on != precisionActive else { return true }
        if on {
            guard case .ready = status, let snapshot, snapshot.dpi > 0 else { return false }
            let normal = config.device.dpi ?? snapshot.dpi
            // 存下正常速度：程式中途結束時，下次啟動或重新連線會把它寫回去。
            if config.device.dpi == nil { config.device.dpi = normal }
            let low = snapshot.dpiMax > 0 ? min(max(config.precisionDpi, snapshot.dpiMin), snapshot.dpiMax) : config.precisionDpi
            precisionNormalDpi = normal
            precisionActive = true
            hidpp.write({ $0.setDpi(low) }) { [weak self] ok in
                self?.log("Precision on DPI \(low) verified=\(ok)")
            }
            if !quiet {
                showModeHUD("scope", Lang.t("精準模式", "Precision mode"), "\(low) DPI")
                playModeHaptic()
            }
        } else {
            let normal = precisionNormalDpi
            precisionActive = false
            precisionHeldBy = nil
            hidpp.write({ $0.setDpi(normal) }) { [weak self] ok in
                self?.log("Precision off DPI \(normal) verified=\(ok)")
            }
            if !quiet {
                showModeHUD("cursorarrow.motionlines", Lang.t("指標速度已恢復", "Pointer speed restored"), "\(normal) DPI")
                playModeHaptic()
            }
        }
        return true
    }

    private func toggleWheelMode() -> Bool {
        guard case .ready = status else { return false }
        hidpp.perform({ $0.toggleWheelMode() }) { [weak self] result in
            guard let self else { return }
            guard let result else {
                self.log("Wheel mode toggle failed")
                return
            }
            self.log("Wheel mode -> \(result.mode) threshold=\(result.threshold)")
            self.config.device.wheelMode = result.mode
            self.config.device.smartShift = result.threshold
            self.snapshot?.wheelMode = result.mode
            if result.mode == 1 {
                self.showModeHUD("infinity", Lang.t("自由滾動", "Free spin"), Lang.t("滾輪無阻力", "No resistance"))
            } else {
                self.showModeHUD("dial.medium", Lang.t("段落滾動", "Ratchet"), Lang.t("一格一格", "Step by step"))
            }
            self.playModeHaptic()
        }
        return true
    }

    private func showModeHUD(_ symbol: String, _ title: String, _ detail: String) {
        if config.showModeHUD { modeHUD.show(symbol: symbol, title: title, detail: detail) }
    }

    private func playModeHaptic() {
        if config.modeHaptic { playHaptic(config.modeHapticWave) }
    }

    // MARK: - 觸覺回饋與電量

    // 低電量暫停震動：電量在門檻以下且沒有充電時，所有自動的震動都不送（「試震」按鈕不受影響）。
    var hapticsPaused: Bool {
        guard config.lowBatteryHapticPause, let snapshot, snapshot.batteryPercent >= 0 else { return false }
        return !snapshot.charging && snapshot.batteryPercent <= config.lowBatteryLevel
    }

    private func playHaptic(_ wave: Int) {
        guard !hapticsPaused else { return }
        hidpp.playHaptic(UInt8(clamping: wave))
    }

    // 電量有更新時呼叫（滑鼠主動通知或讀取裝置）。
    private func batteryChanged() {
        guard let snapshot, snapshot.batteryPercent >= 0 else { return }
        let percent = snapshot.batteryPercent
        if snapshot.charging || percent > config.lowBatteryLevel + 3 {
            lowBatteryNotified = false
            return
        }
        guard percent <= config.lowBatteryLevel, !lowBatteryNotified else { return }
        lowBatteryNotified = true
        log("Battery low: \(percent)% (threshold \(config.lowBatteryLevel)%)" + (hapticsPaused ? "; haptics paused" : ""))
        guard config.lowBatteryAlert else { return }
        let title = Lang.t("MX Master 4 電量低", "MX Master 4 battery low")
        let body = Lang.t("剩 \(percent)%，請盡快充電。", "\(percent)% left. Charge it soon.")
            + (hapticsPaused ? Lang.t("充電前震動會暫停。", " Haptics are paused until it charges.") : "")
        notifier.post(title: title, body: body) { [weak self] delivered in
            // 系統通知被關掉時，至少在螢幕下方提示一次。
            if !delivered { self?.modeHUD.show(symbol: "battery.25percent", title: title, detail: "\(percent)%") }
            self?.log("Battery low notification delivered=\(delivered)")
        }
    }

    // 「指標與滾輪」頁改了門檻或開關後，重新判斷一次（不會重複通知）。
    func batterySettingsChanged() {
        if let percent = snapshot?.batteryPercent, percent > config.lowBatteryLevel + 3 { lowBatteryNotified = false }
        batteryChanged()
    }

    // 「指標與滾輪」頁的觸發按鍵：哪一顆鍵目前設成「精準模式（按住）」。
    var precisionTrigger: MouseInput? {
        MouseInput.allCases.first { mapping($0).action == .precisionHold }
    }

    func setPrecisionTrigger(_ input: MouseInput?) {
        // 一次只留一顆；原本那顆回到預設動作。
        for other in MouseInput.allCases where other != input && mapping(other).action == .precisionHold {
            config.mappings[other.rawValue] = Config.defaultMappings[other] ?? ActionBinding(.passThrough)
        }
        if let input { config.mappings[input.rawValue] = ActionBinding(.precisionHold) }
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

// 低電量的系統通知。第一次要送時才請使用者允許；不允許或送不出去時回報 false。
final class BatteryNotifier: NSObject, UNUserNotificationCenterDelegate {
    private var center: UNUserNotificationCenter? {
        // 沒有 Bundle 的執行方式（例如直接跑執行檔）會讓 current() 當掉。
        Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
    }

    func status(_ completion: @escaping (UNAuthorizationStatus) -> Void) {
        guard let center else { return completion(.denied) }
        center.getNotificationSettings { settings in
            DispatchQueue.main.async { completion(settings.authorizationStatus) }
        }
    }

    func request(_ completion: @escaping (Bool) -> Void) {
        guard let center else { return completion(false) }
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    func post(title: String, body: String, completion: @escaping (Bool) -> Void) {
        guard let center else { return completion(false) }
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return DispatchQueue.main.async { completion(false) } }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let request = UNNotificationRequest(identifier: "lowBattery", content: content, trigger: nil)
            center.add(request) { error in DispatchQueue.main.async { completion(error == nil) } }
        }
    }

    // 設定視窗在前景時也顯示橫幅。
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
