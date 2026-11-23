import AppKit
import Combine
import ServiceManagement
import UserNotifications

// 全部的執行期狀態與輸入處理邏輯；只在主執行緒使用。
final class AppModel: ObservableObject {
    static let version = "2.5"

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
    @Published var keyboardSnapshot: KeyboardSnapshot?     // nil：沒有連上 Logitech 鍵盤
    @Published var keyboardMessage = ""
    @Published var receiver = BoltReceiverSnapshot()       // Logi Bolt 接收器（配對頁）
    @Published var receiverMessage = ""
    // Lightspeed／Unifying／Nano 接收器上的其他羅技裝置（「其他裝置」頁）。
    @Published var otherDevices: [OtherDeviceSnapshot] = [] {
        didSet {
            let resolved = OtherDevicesProtocol.resolveSelection(otherDevices, current: selectedOtherID)
            if resolved != selectedOtherID { selectedOtherID = resolved }
        }
    }
    @Published var selectedOtherID: String?               // 多台時，「其他裝置」頁正在看哪一台
    var selectedOther: OtherDeviceSnapshot? {
        let id = OtherDevicesProtocol.resolveSelection(otherDevices, current: selectedOtherID)
        return otherDevices.first { $0.id == id }
    }

    let hidpp = HIDPP()
    let keyboard = KeyboardHIDPP()
    let bolt = BoltReceiver()
    let others = OtherDevicesHIDPP()
    // 電池歷史（本機檔案）；示範模式用假資料、不寫檔。
    let history = BatteryHistoryStore(demo: UserDefaults.standard.integer(forKey: "demoOthers") > 0)
    private var historyTimer: Timer?
    private var mouseFull = FullChargeState()
    private var keyboardFull = FullChargeState()
    private var keyboardLowNotified = false
    private var otherFull: [String: FullChargeState] = [:]
    private let tap = EventTap()
    private let ring = RingOverlay()
    private let hud = GestureHUD()
    private let modeHUD = ModeHUD()
    private var timers: [Timer] = []

    // 圓環與手勢的進行狀態
    private var swallowLeft = SwallowedRelease()
    private var swallowRight = SwallowedRelease()
    private var swallowedButtons: [String: MappedAction] = [:]   // 按下時被吃掉的鍵與當時的動作
    private var otherPresses = PressLedger<String, ActionBinding>()  // G502 等交給 App 的鍵：每次按下的處理方式
    private var ringHold = HoldOwner()         // 按住開著圓環的是哪顆鍵
    private var gestureActive = false
    private var gestureHold = HoldOwner()      // 正按著的那顆鍵；只有它放開才結束手勢
    private var gestureQuiet = false           // 從其他滑鼠按的：不震 MX Master 4
    private var gestureGeneration = 0          // 取消手勢時加一：已排程但還沒執行的動作作廢
    private var gestureStart = NSPoint.zero
    private var gestureTracker = GestureTracker()
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
    private var precisionSeq = 0               // 每次切換加一；寫入完成時編號已變就不再處理那次的結果
    private var precisionRestorePending = false   // 已關閉精準模式，但正常速度還沒確認寫回

    // 低電量：每次電量降到門檻以下只通知一次；充電或回到門檻之上（多 3%）後才會再通知。
    private var lowBatteryNotified = false
    private var otherLowBattery: [String: OtherLowBatteryState] = [:]   // 其他裝置各自的低電量狀態（含 WPID 與讀取序號）
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
            // 由 G502 等其他滑鼠叫出的圓環不震動（震動只能送到 MX Master 4，會震到另一隻手上的滑鼠）。
            guard let self, self.config.ringHaptic, !self.ringQuiet else { return }
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
        hidpp.onBattery = { [weak self] percent, charging, full in
            self?.snapshot?.batteryPercent = percent
            self?.snapshot?.charging = charging
            self?.snapshot?.full = full
            self?.batteryChanged()
        }
        keyboard.onLog = { [weak self] in self?.log($0) }
        keyboard.onChange = { [weak self] snapshot in
            var snapshot = snapshot
            // 啟動參數 -demoHosts YES：截圖時鍵盤頻道上的電腦名稱也換成示範名稱（Bolt 接收器的名稱照舊）。
            if UserDefaults.standard.bool(forKey: "demoHosts"), var kb = snapshot {
                let names = ["MacBook Pro", "Office PC", "Office PC"]
                for i in kb.hosts.indices where kb.hosts[i].name != "Logitech Bolt receiver" {
                    kb.hosts[i].name = i < names.count ? names[i] : ""
                }
                snapshot = kb
            }
            self?.keyboardSnapshot = snapshot
            self?.keyboardBatteryChanged()
        }
        bolt.onLog = { [weak self] in self?.log($0) }
        bolt.onChange = { [weak self] in self?.receiver = $0 }
        others.onLog = { [weak self] in self?.log($0) }
        others.onChange = { [weak self] list in
            self?.otherDevices = list
            self?.migrateOtherActions()
            self?.otherBatteryChanged()
        }
        if CommandLine.arguments.contains("--log") { setLogging(true) }
        hidpp.start()
        keyboard.start()
        // 啟動參數 -demoReceiver N：截圖或檢查版面用的假接收器（1 一般、2 搜尋中、3 鍵盤驗證碼、4 滑鼠驗證碼、5 成功、6 失敗）。
        let demoReceiver = UserDefaults.standard.integer(forKey: "demoReceiver")
        if demoReceiver > 0 { receiver = AppModel.demoReceiver(demoReceiver) } else { bolt.start() }
        // 啟動參數 -demoOthers N：截圖或檢查版面用的假裝置（1 一台連著的 G502、2 再加一台沒回應的、3 G502＋M331＋G903、4 八台）。
        let demoOthers = UserDefaults.standard.integer(forKey: "demoOthers")
        if demoOthers > 0 {
            otherDevices = AppModel.demoOthers(demoOthers)
            // -demoOtherTab N：截圖時直接選第 N 台（從 0 算）。
            let tab = UserDefaults.standard.integer(forKey: "demoOtherTab")
            if otherDevices.indices.contains(tab) { selectedOtherID = otherDevices[tab].id }
        } else {
            others.start()
        }
        // 每 10 分鐘把連著的裝置的電量記進歷史（有變化時各自的回呼也會記，記錄規則會略過太密的）。
        let timer = Timer(timeInterval: BatteryHistoryLogic.interval, repeats: true) { [weak self] _ in self?.recordHistory() }
        RunLoop.main.add(timer, forMode: .common)
        historyTimer = timer

        tap.handler = { [weak self] in self?.tapEvent($0) ?? false }
        tap.extraHandler = { [weak self] receiver, number, down in self?.otherAppButton(receiver, number, down) ?? false }
        tap.onDisabled = { [weak self] in DispatchQueue.main.async { self?.cancelHeldInteractions() } }
        installTapIfPossible()
        // 權限是使用者到「系統設定」裡開的，只能定時看有沒有開。
        timers.append(Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.installTapIfPossible()
        })
        timers.append(Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            self?.hidpp.recheck()
            self?.refreshDevice()
            self?.keyboard.refresh()
        })
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil,
                                                          queue: .main) { [weak self] _ in
            self?.sleeping = false
            self?.lastWake = Date()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                self?.hidpp.recheck()
                self?.keyboard.refresh()
                self?.others.refresh()
            }
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
        // 精準模式開著、或關閉後速度還沒確認寫回就結束的話，先把速度寫回去。
        if precisionActive || precisionRestorePending, precisionNormalDpi > 0 {
            let dpi = precisionNormalDpi
            hidpp.performNow { _ = $0.setDpi(dpi) }
        }
        for monitor in moveMonitors { NSEvent.removeMonitor(monitor) }
        moveMonitors.removeAll()
        tap.remove()
        keyboard.stop()
        bolt.stop()
        others.stop()
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
        // 暫停期間不處理滑鼠事件，按著的鍵放開了也不知道；暫停與恢復時都把按住狀態清掉，
        // 免得恢復後 MX Flow 還以為切換按鍵按著，或吃掉一次沒有對應按下的放開。
        deferredInput = nil
        heldInputs.removeAll()
        buttonState.removeAll()
        swallowedButtons.removeAll()
        swallowLeft.clear()
        swallowRight.clear()
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
        precisionRestorePending = false
        precisionSeq += 1
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

    func refreshOthers(full: Bool = false) { others.refresh(full: full) }
    // 其他裝置的切段／切設定檔（等同按滑鼠上的 DPI 鍵與設定檔鍵）。示範模式只改畫面。
    func setOtherStage(_ id: String, _ index: Int) {
        if UserDefaults.standard.integer(forKey: "demoOthers") > 0, let i = otherDevices.firstIndex(where: { $0.id == id }) {
            otherDevices[i].stageIndex = index
            otherDevices[i].dpi = otherDevices[i].dpiStages[index]
            return
        }
        others.setStage(id, index)
    }
    func setOtherProfile(_ id: String, _ sector: Int) {
        if UserDefaults.standard.integer(forKey: "demoOthers") > 0, let i = otherDevices.firstIndex(where: { $0.id == id }) {
            otherDevices[i].activeProfile = sector
            return
        }
        others.setProfile(id, sector)
    }

    func refreshDevice() {
        hidpp.readDevice { [weak self] snapshot in
            guard let snapshot else { return }
            self?.snapshot = snapshot
            self?.batteryChanged()
        }
    }

    // 設定頁改了指標速度：那就是新的正常速度，精準模式結束。
    // 精準模式開著時改速度，若寫入失敗就把原本的正常速度補寫回去，免得停在精準速度。
    func applyDpi(_ value: Int) {
        let restoreDpi = precisionActive || precisionRestorePending ? precisionNormalDpi : 0
        precisionActive = false
        precisionHeldBy = nil
        precisionRestorePending = false
        precisionSeq += 1
        let seq = precisionSeq
        applyDevice("DPI \(value)", { $0.setDpi(value) }, save: { $0.dpi = value }, done: { [weak self] ok in
            guard let self, !ok, restoreDpi > 0, seq == self.precisionSeq else { return }
            self.precisionRestorePending = true
            self.writePrecisionDpi(restoreDpi, on: false, seq: seq, quiet: true, retry: true)
        })
    }

    // 套用一項裝置設定；滑鼠回讀確認後才寫進設定檔。
    func applyDevice(_ name: String, _ operation: @escaping (HIDPP) -> Bool, save: @escaping (inout DeviceSettings) -> Void, done: ((Bool) -> Void)? = nil) {
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
            done?(ok)
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
            // 滑鼠確定切走了才帶鍵盤，免得只有鍵盤離開。
            if sent { self?.switchKeyboard(withMouseChannel: host) }
        }
    }

    // MARK: - 鍵盤

    // 滑鼠切到 channel 時，鍵盤要切到哪個頻道；nil 表示不帶鍵盤。
    func keyboardChannel(forMouse channel: Int) -> Int? {
        if let chosen = config.keyboard.channels[String(channel)] { return chosen < 0 ? nil : chosen }
        return autoKeyboardChannel(forMouse: channel)
    }

    // 自動對應：鍵盤上有同名（同名多個時再比連線方式）的頻道就用它，否則用同一個頻道號。
    // Bolt 配對的頻道在鍵盤上常記成「Logitech Bolt receiver」，名稱對不起來，所以要退回頻道號。
    func autoKeyboardChannel(forMouse channel: Int) -> Int? {
        guard let kb = keyboardSnapshot, !kb.hosts.isEmpty else { return channel }
        let mouseHost = hosts.first { $0.index == channel }
        if let name = mouseHost?.name, !name.isEmpty {
            var same = kb.hosts.filter { $0.paired && $0.name == name }
            if same.count > 1, let bus = mouseHost?.bus { same = same.filter { $0.bus == bus } }
            if same.count == 1 { return same[0].index }
        }
        guard let host = kb.hosts.first(where: { $0.index == channel }), host.paired else { return nil }
        return host.index
    }

    func setKeyboardChannel(forMouse channel: Int, _ value: Int?) {
        config.keyboard.channels[String(channel)] = value
    }

    func keyboardHostTitle(_ index: Int) -> String {
        let name = keyboardSnapshot?.hosts.first { $0.index == index }?.name ?? ""
        let channel = Lang.t("頻道 \(index + 1)", "Channel \(index + 1)")
        return name.isEmpty ? channel : channel + " · " + name
    }

    private func switchKeyboard(withMouseChannel channel: Int) {
        guard config.keyboard.followSwitch, let kb = keyboardSnapshot else { return }
        guard let target = keyboardChannel(forMouse: channel) else {
            log("Keyboard stays (mouse channel \(channel) has no keyboard channel)")
            return
        }
        guard target != kb.currentHost else { return }
        keyboard.changeHost(target) { [weak self] sent in
            self?.log("Keyboard switch host -> \(target) sent=\(sent)")
        }
    }

    func refreshKeyboard() { keyboard.refresh() }

    // MARK: - Logi Bolt 接收器

    func refreshReceiver() { bolt.refresh() }
    func startPairing() { receiverMessage = ""; bolt.startPairing() }
    func cancelPairing() { bolt.cancelPairing() }
    func dismissPairingResult() { bolt.dismissResult() }

    func unpair(_ slot: BoltSlot) {
        receiverMessage = Lang.t("解除配對中…", "Unpairing…")
        bolt.unpair(slot) { [weak self] result in
            guard let self else { return }
            let name = slot.name.isEmpty ? Lang.t("槽位 \(slot.slot)", "slot \(slot.slot)") : slot.name
            switch result {
            case .done: self.receiverMessage = Lang.t("已解除「\(name)」的配對", "Unpaired \(name)")
            case .changed: self.receiverMessage = Lang.t("槽位 \(slot.slot) 的裝置已經變了，沒有解除；請看過清單再試",
                                                         "Slot \(slot.slot) holds a different device now; nothing was unpaired. Check the list and try again")
            case .failed: self.receiverMessage = Lang.t("接收器沒有確認，「\(name)」仍然配對著", "The receiver did not confirm; \(name) is still paired")
            }
        }
    }

    private static func demoOthers(_ kind: Int) -> [OtherDeviceSnapshot] {
        var g502 = OtherDeviceSnapshot(receiver: "C539@00000000", slot: 1, name: "G502 LIGHTSPEED Wireless Gaming Mouse", kind: 3,
                                       wpid: "407F")
        g502.batterySource = .voltage
        g502.millivolts = 4016
        g502.batteryPercent = OtherDevicesProtocol.percent(millivolts: 4016)
        g502.firmware = "MPM 17.00.B0008"
        g502.dpi = 3200
        g502.dpiMin = 100
        g502.dpiMax = 25600
        g502.reportRateMs = 1
        g502.onboardMode = 1
        g502.profileCount = 5
        g502.profiles = [1, 2, 3, 4, 5]
        g502.activeProfile = 1
        g502.dpiStages = [450, 800, 1600, 3200, 6400]
        g502.stageIndex = 3
        g502.lastSeen = Date().addingTimeInterval(-120)
        g502.lights = [.cycle(period: 5000, brightness: 100), .cycle(period: 5000, brightness: 100)]
        g502.defaultStage = 3
        g502.buttonCount = 11
        g502.sectorSize = 255
        g502.buttons = [.mouse(1), .mouse(2), .mouse(3), .mouse(4), .mouse(5), .function(7), .function(4), .function(3),
                        .function(0x0C), .function(2), .function(1)]
        g502.onboardFormatOK = true
        guard kind >= 2 else { return [g502] }
        var other = OtherDeviceSnapshot(receiver: "C547@00000000", slot: 1, name: "PRO X", kind: 3, wpid: "40A9")
        other.link = .noAnswer
        guard kind >= 3 else { return [g502, other] }
        var m331 = OtherDeviceSnapshot(receiver: "C52F@00000000", slot: 1, name: "Wireless Mouse B330/M330/M331", kind: 3, wpid: "4057")
        m331.batterySource = .percent
        m331.batteryPercent = 70
        m331.firmware = "RQM 75.10.B0002"
        m331.lastSeen = Date()
        var g903 = g502
        g903.receiver = "C539@00000001"
        g903.name = "G903 LIGHTSPEED Wireless Gaming Mouse"
        g903.wpid = "4087"
        g903.batterySource = .percent
        g903.batteryPercent = 64
        guard kind >= 4 else { return [g502, m331, g903] }
        let more: [(String, String, String)] = [("C547@00000000", "PRO X SUPERLIGHT", "4093"), ("C53A@00000000", "G305", "4074"),
                                                 ("C52B@00000000", "MX Vertical", "407B"), ("C532@00000000", "M720 Triathlon", "405E"),
                                                 ("C52B@00000001", "Wireless Touchpad", "4011")]
        return [g502, m331, g903] + more.map { item in
            var device = OtherDeviceSnapshot(receiver: item.0, slot: 1, name: item.1, kind: 3, wpid: item.2)
            device.batterySource = .percent
            device.batteryPercent = 55
            device.lastSeen = Date()
            return device
        }
    }

    private static func demoReceiver(_ kind: Int) -> BoltReceiverSnapshot {
        var demo = BoltReceiverSnapshot(present: true, slots: [
            BoltSlot(slot: 1, kind: 2, wpid: "B042", serial: "00000000", name: "MX Master 4"),
            BoltSlot(slot: 2, kind: 1, wpid: "B367", serial: "00000000", name: "MX MCHNCL M"),
        ])
        switch kind {
        case 2: demo.phase = .searching
        case 3: demo.phase = .passkey(code: "482913", name: "MX Keys S", keyboard: true)
        case 4: demo.phase = .passkey(code: "000613", name: "MX Anywhere 3S", keyboard: false)
        case 5: demo.phase = .succeeded(slot: 3, name: "MX Keys S")
            demo.slots.append(BoltSlot(slot: 3, kind: 1, wpid: "B378", serial: "00000000", name: "MX Keys S"))
        case 6: demo.phase = .failed(.notFound)
        default: break
        }
        return demo
    }

    // 套用一項鍵盤設定；鍵盤回讀確認才顯示已套用。設定存在鍵盤裡，不寫進設定檔。
    func applyKeyboard(_ name: String, _ operation: @escaping (KeyboardHIDPP) -> Bool) {
        keyboardMessage = Lang.t("套用中…", "Applying…")
        keyboard.write(operation) { [weak self] ok in
            guard let self else { return }
            self.log("Keyboard set \(name) verified=\(ok)")
            self.keyboardMessage = name + (ok ? Lang.t("：已套用", ": applied") : Lang.t("：鍵盤沒有確認，未套用", ": not confirmed by the keyboard"))
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
              !ring.visible || ringHold.owner == key?.rawValue, !gestureActive || gestureHold.owner == key?.rawValue,
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
        swallowLeft.clear()
        swallowRight.clear()
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
            let owner = MouseInput.gesture.rawValue
            if !down, gestureHold.owner == owner {
                finishGesture()
            } else if config.gestureMode {
                if down { beginGesture(owner: owner) }
            } else {
                clickMapped(.gesture, down)
            }
            return
        }

        if config.ringMode {
            ringPress(down, owner: MouseInput.actionRing.rawValue)
        } else {
            clickMapped(.actionRing, down)
        }
    }

    // 按住叫出圓環、放開執行（「點選」設定開著時：放開不做事，點一下選取，再按一次取消）。
    // MX Master 4 的 Action Ring 鍵，以及設成「叫出 Action Ring」的其他按鍵（含 G502 交給 App 的鍵）共用。
    private var ringQuiet = false

    // owner：按下的是哪顆鍵，只有它放開才結束；別顆鍵按住開著時不重開，也不改震動來源。
    private func ringPress(_ down: Bool, owner: String, quiet: Bool = false) {
        if ring.visible && ring.clickMode {
            if down { cancelRing() }
        } else if down {
            guard !ring.visible else { return }
            ringHold.takeOver(owner)
            ringQuiet = quiet
            ring.clickMode = config.ringClick
            ring.show(at: NSEvent.mouseLocation)
            log("ActionRing opened" + (ring.clickMode ? " click-mode" : ""))
        } else if ring.visible, ringHold.release(owner) {
            let selected = ring.selectedBinding, quiet = ringQuiet
            ring.hide()
            // 可能開 App 或網址：不要在事件攔截裡同步執行。
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let sent = selected.map { self.runAction($0, fromOtherMouse: quiet) } ?? false
                self.log("ActionRing selected=\(selected?.action.rawValue ?? "None") sent=\(sent)")
            }
        }
    }

    // 系統停用過事件攔截：放開事件可能漏了，按住型的圓環與手勢先收起來，不要卡在畫面上（點選模式的圓環不受影響）。
    private func cancelHeldInteractions() {
        if ring.visible && !ring.clickMode { cancelRing() }
        cancelGesture()
    }

    // 專用鍵當一般按鍵用：按下就執行。被選為切換按鍵時改在放開時執行，切換了就不執行。
    private func clickMapped(_ input: MouseInput, _ down: Bool) {
        if gestureHold.owner == input.rawValue || mapping(input).action == .gestureHold {
            holdGesture(input.rawValue, down: down)
            return
        }
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

    private func runMapped(_ input: MouseInput, fromOtherMouse: Bool = false) {
        let binding = mapping(input)
        let sent = runAction(binding, fromOtherMouse: fromOtherMouse)
        log("Mapped \(input.rawValue) selected=\(binding.action.rawValue) sent=\(sent)")
    }

    // 動作來自其他滑鼠（例如 G502）時，從動作叫出的圓環滑過不震 MX Master 4。ActionRunner 會同步呼叫 runMouseAction，執行期間用這個旗標帶過去。
    // 精準模式、滾動模式、切換頻道改的是 MX Master 4 本身，不管從哪隻滑鼠觸發都照常震動（使用者 2026-11-23 指定）。
    private var actionFromOtherMouse = false

    private func runAction(_ binding: ActionBinding, fromOtherMouse: Bool) -> Bool {
        let previous = actionFromOtherMouse
        actionFromOtherMouse = fromOtherMouse
        defer { actionFromOtherMouse = previous }
        return ActionRunner.run(binding)
    }

    private func cancelRing() {
        guard ring.visible else { return }
        ringHold.cancel()
        ring.hide()
        log("ActionRing cancelled")
    }

    // MARK: - 拇指四向手勢

    // 設成「手勢鍵」的其他按鍵（含 G502 交給 App 的鍵）：按住開始、放開結束。圓環開著時不開始。
    private func holdGesture(_ owner: String, down: Bool, quiet: Bool = false) {
        if down {
            if !ring.visible { beginGesture(owner: owner, quiet: quiet) }
        } else if gestureHold.owner == owner {
            finishGesture()
        }
    }

    // 新的按下會接手進行中的手勢，避免另一顆鍵的放開事件遺失（例如滑鼠斷線）時卡住。
    private func beginGesture(owner: String, quiet: Bool = false) {
        gestureHold.takeOver(owner)
        gestureQuiet = quiet
        gestureActive = true
        gestureStart = NSEvent.mouseLocation
        gestureTracker.reset()
        hud.show(at: gestureStart, text: Lang.t("往四個方向滑動", "Swipe in a direction"))
        gestureTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.trackGesture() }
        RunLoop.main.add(timer, forMode: .common)
        gestureTimer = timer
    }

    private func trackGesture() {
        let location = NSEvent.mouseLocation
        let dx = location.x - gestureStart.x, dy = location.y - gestureStart.y
        guard gestureTracker.sample(dx: dx, dy: dy, factor: config.gestureDistanceFactor) else { return }
        hud.update(config.gestures[gestureTracker.direction].title)
        if config.gestureHaptic && !gestureQuiet { playHaptic(config.gestureHapticWave) }
    }

    private func finishGesture() {
        let owner = gestureHold.owner ?? ""
        gestureHold.cancel()
        gestureActive = false
        gestureTimer?.invalidate()
        gestureTimer = nil
        hud.hide()
        // 放開當下補取一次位置；要執行的動作現在就決定，之後改設定也不影響這一次。
        let location = NSEvent.mouseLocation
        let end = gestureTracker.end(dx: location.x - gestureStart.x, dy: location.y - gestureStart.y,
                                     factor: config.gestureDistanceFactor)
        let quiet = gestureQuiet, generation = gestureGeneration
        let binding: ActionBinding?
        switch end {
        case .direction(let direction): binding = config.gestures[direction]
        case .ambiguous: binding = nil
        case .tap: binding = mapping(.gesture)
        }
        // 可能在事件攔截裡被呼叫：等這次放開處理完再執行，別拖慢攔截，動作也不會排在放開事件之前。
        DispatchQueue.main.async { [weak self] in
            // 排程後暫停或切換頻道：這次手勢作廢。
            guard let self, generation == self.gestureGeneration else { return }
            guard let binding else {
                self.log("Gesture owner=\(owner) direction=Ambiguous")
                return
            }
            let sent = self.runAction(binding, fromOtherMouse: quiet)
            if case .direction(let direction) = end {
                self.log("Gesture owner=\(owner) direction=\(direction) selected=\(binding.action.rawValue) sent=\(sent)")
            } else {
                self.log("Mapped GestureButton owner=\(owner) selected=\(binding.action.rawValue) sent=\(sent)")
            }
        }
    }

    private func cancelGesture() {
        gestureGeneration &+= 1
        guard gestureActive else { return }
        gestureHold.cancel()
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
            swallowLeft.arm(tap.currentSource)
            if index >= 0, let selected {
                let quiet = ringQuiet
                // 等這次點擊結束後再送鍵，免得動作落在圓環底下的視窗之前。
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    let sent = self.runAction(selected, fromOtherMouse: quiet)
                    self.log("ActionRing clicked=\(selected.action.rawValue) sent=\(sent)")
                }
            } else {
                log("ActionRing cancelled")
            }
            return true
        case .leftUp:
            return swallowLeft.consume(tap.currentSource)
        case .rightDown:
            guard ring.visible && ring.clickMode else { return false }
            cancelRing()
            swallowRight.arm(tap.currentSource)
            return true
        case .rightUp:
            return swallowRight.consume(tap.currentSource)
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
        swallowedButtons[input.rawValue] = binding.action
        if binding.action == .precisionHold {
            holdPrecision(input, true)
            return true
        }
        // 圓環與手勢的畫面更新移出事件攔截，按下與放開照順序排在主佇列上。
        if binding.action == .showActionRing {
            DispatchQueue.main.async { [weak self] in self?.ringPress(true, owner: input.rawValue) }
            return true
        }
        if binding.action == .gestureHold {
            DispatchQueue.main.async { [weak self] in self?.holdGesture(input.rawValue, down: true) }
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
        // 照按下當時的動作收尾：按住時改了設定也一樣。
        let action = swallowedButtons.removeValue(forKey: input.rawValue)
        if action == .showActionRing {
            DispatchQueue.main.async { [weak self] in self?.ringPress(false, owner: input.rawValue) }
        } else if action == .gestureHold {
            DispatchQueue.main.async { [weak self] in self?.holdGesture(input.rawValue, down: false) }
        }
        if deferredInput == input {
            deferredInput = nil
            DispatchQueue.main.async { [weak self] in self?.runMapped(input) }
        }
        return action != nil
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
        case .showActionRing:
            // 從手勢、拇指滾輪這類「按一下」的地方叫出：沒有放開可言，用點選模式（點一下選取）。圓環裡選到它就不做事。
            guard !ring.visible else { return false }
            let quiet = actionFromOtherMouse
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.ringHold.cancel()
                self.ringQuiet = quiet
                self.ring.clickMode = true
                self.ring.show(at: NSEvent.mouseLocation)
                self.log("ActionRing opened click-mode (from action)")
            }
            return true
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
    // 切換提示等滑鼠回讀確認後才顯示；寫入失敗時重試一次，仍失敗就提示。
    @discardableResult
    func setPrecision(_ on: Bool, quiet: Bool = false) -> Bool {
        guard on != precisionActive else { return true }
        precisionSeq += 1
        let seq = precisionSeq
        if on {
            guard case .ready = status, let snapshot, snapshot.dpi > 0 else { return false }
            let normal = config.device.dpi ?? snapshot.dpi
            // 存下正常速度：程式中途結束時，下次啟動或重新連線會把它寫回去。
            if config.device.dpi == nil { config.device.dpi = normal }
            let low = snapshot.dpiMax > 0 ? min(max(config.precisionDpi, snapshot.dpiMin), snapshot.dpiMax) : config.precisionDpi
            precisionNormalDpi = normal
            precisionActive = true
            precisionRestorePending = false
            writePrecisionDpi(low, on: true, seq: seq, quiet: quiet, retry: true)
        } else {
            precisionActive = false
            precisionHeldBy = nil
            precisionRestorePending = true
            writePrecisionDpi(precisionNormalDpi, on: false, seq: seq, quiet: quiet, retry: true)
        }
        if !quiet { playModeHaptic() }
        return true
    }

    private func writePrecisionDpi(_ dpi: Int, on: Bool, seq: Int, quiet: Bool, retry: Bool) {
        hidpp.write({ $0.setDpi(dpi) }) { [weak self] ok in
            guard let self else { return }
            self.log("Precision \(on ? "on" : "off") DPI \(dpi) verified=\(ok)" + (retry ? "" : " (retry)"))
            // 之後又切換過、重新連線或手動改了速度：這次的結果不算數。
            guard seq == self.precisionSeq else { return }
            if ok {
                if on {
                    if !quiet { self.showModeHUD("scope", Lang.t("精準模式", "Precision mode"), "\(dpi) DPI") }
                } else {
                    self.precisionRestorePending = false
                    if !quiet { self.showModeHUD("cursorarrow.motionlines", Lang.t("指標速度已恢復", "Pointer speed restored"), "\(dpi) DPI") }
                }
            } else if retry {
                self.writePrecisionDpi(dpi, on: on, seq: seq, quiet: quiet, retry: false)
            } else if on {
                // 沒確認到降速：精準模式當作沒開。回讀逾時時速度可能其實已經降了，
                // 所以標成待寫回並安靜補寫正常速度，成功才清掉。
                self.precisionActive = false
                self.precisionHeldBy = nil
                self.precisionRestorePending = true
                self.writePrecisionDpi(self.precisionNormalDpi, on: false, seq: seq, quiet: true, retry: true)
                if !quiet { self.modeHUD.show(symbol: "exclamationmark.triangle", title: Lang.t("精準模式未能開啟", "Precision mode failed"), detail: Lang.t("無法寫入滑鼠速度", "Couldn't set the mouse speed")) }
            } else {
                // 速度沒寫回：保留待寫回的狀態，結束程式時再寫一次；重新連線時也會套回儲存的速度。
                if !quiet { self.modeHUD.show(symbol: "exclamationmark.triangle", title: Lang.t("指標速度未能恢復", "Pointer speed not restored"), detail: Lang.t("重新連線後會套用 \(dpi) DPI", "\(dpi) DPI is applied on reconnect")) }
            }
        }
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
        return !snapshot.charging && snapshot.batteryPercent <= mouseLowLevel
    }

    private func playHaptic(_ wave: Int) {
        guard !hapticsPaused else { return }
        hidpp.playHaptic(UInt8(clamping: wave))
    }

    // 電量有更新時呼叫（滑鼠主動通知或讀取裝置）。
    private func batteryChanged() {
        guard let snapshot, snapshot.batteryPercent >= 0 else { return }
        let percent = snapshot.batteryPercent
        let alert = batteryAlert(BatteryDeviceKey.mouse)
        history.record(BatteryDeviceKey.mouse, name: "MX Master 4", percent: percent, charging: snapshot.charging || snapshot.full)
        let full = BatteryAlerts.fullStep(mouseFull, charging: snapshot.charging, full: snapshot.full, percent: percent,
                                          alertOn: config.lowBatteryAlert && alert.full)
        mouseFull = full.state
        if full.notify { postFull("MX Master 4") }
        if snapshot.charging || percent > alert.threshold + 3 {
            lowBatteryNotified = false
            return
        }
        // 提醒關著時不標成已通知：之後打開提醒，這次放電還會通知一次。
        guard percent <= alert.threshold, !lowBatteryNotified, config.lowBatteryAlert, alert.low else { return }
        lowBatteryNotified = true
        log("Battery low: \(percent)% (threshold \(alert.threshold)%)" + (hapticsPaused ? "; haptics paused" : ""))
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
        if let percent = snapshot?.batteryPercent, percent > mouseLowLevel + 3 { lowBatteryNotified = false }
        batteryChanged()
        keyboardBatteryChanged()
        otherBatteryChanged()
    }

    // 其他裝置的清單更新時呼叫。電壓換算的百分比會跳動，連續兩次「新讀到的」電量在門檻以下才通知；
    // 同一筆快取重複發布不算（batterySeq 沒變），同一個槽位換了裝置（WPID 不同）從頭算。
    private func otherBatteryChanged() {
        for device in otherDevices where device.link == .online && device.batteryPercent >= 0 {
            let key = BatteryDeviceKey.other(wpid: device.wpid)
            let alert = batteryAlert(key)
            let name = device.name.isEmpty ? Lang.t("其他裝置", "Other device") : device.name
            let plugged = device.charging || device.full || device.chargeState == .pluggedNotCharging
            history.record(key, name: name, percent: device.batteryPercent, charging: plugged)
            let full = BatteryAlerts.fullStep(otherFull[device.id] ?? FullChargeState(), charging: device.charging, full: device.full,
                                              percent: device.batteryPercent, alertOn: config.lowBatteryAlert && alert.full)
            otherFull[device.id] = full.state
            if full.notify { postFull(OthersPage.shortName(device)) }
            let step = OtherDevicesProtocol.lowBatteryStep(previous: otherLowBattery[device.id], wpid: device.wpid,
                                                           seq: device.batterySeq, percent: device.batteryPercent,
                                                           charging: plugged,
                                                           threshold: alert.threshold,
                                                           alertOn: config.lowBatteryAlert && alert.low)
            otherLowBattery[device.id] = step.state
            guard step.notify else { continue }
            let estimate = device.batterySource == .voltage ? Lang.t("約 ", "about ") : ""
            log("Other device battery low: \(name) \(device.batteryPercent)% (threshold \(alert.threshold)%)")
            let title = Lang.t("\(name) 電量低", "\(name) battery low")
            let body = Lang.t("剩\(estimate)\(device.batteryPercent)%，請盡快充電。", "\(estimate.isEmpty ? "" : "About ")\(device.batteryPercent)% left. Charge it soon.")
            notifier.post(title: title, body: body, identifier: "lowBattery-" + device.id) { [weak self] delivered in
                if !delivered { self?.modeHUD.show(symbol: "battery.25percent", title: title, detail: "\(device.batteryPercent)%") }
                self?.log("Other device battery notification delivered=\(delivered)")
            }
        }
    }

    // MARK: 其他裝置的按鍵（2026-11-23）：寫入設定檔、「交給 App」的動作

    @Published var otherButtonBusy: Set<String> = []
    @Published var otherButtonMessage: [String: String] = [:]

    // sector：使用者改的是哪個設定檔；滑鼠已經切走就不寫。
    func setOtherButton(_ id: String, sector: Int, index: Int, _ assignment: OtherButtonAssignment) {
        writeOtherButtons(id, sector: sector, [index: assignment], restore: false)
    }

    func restoreOtherButtons(_ id: String, sector: Int) { writeOtherButtons(id, sector: sector, [:], restore: true) }

    func repairOtherProfile(_ id: String) {
        guard !otherButtonBusy.contains(id) else { return }
        otherButtonBusy.insert(id)
        otherButtonMessage[id] = nil
        others.repairProfile(id) { [weak self] error in
            self?.otherButtonBusy.remove(id)
            self?.otherButtonMessage[id] = error ?? Lang.t("設定檔已修復", "Profile repaired")
            self?.log("Other profile repair result=\(error ?? "ok")")
        }
    }

    func setOtherReportRate(_ id: String, sector: Int, ms: Int) {
        guard !otherButtonBusy.contains(id) else { return }
        otherButtonBusy.insert(id)
        otherButtonMessage[id] = nil
        others.writeReportRate(id, sector: sector, ms: ms) { [weak self] error in
            self?.otherButtonBusy.remove(id)
            self?.otherButtonMessage[id] = error ?? Lang.t("回報率已寫入滑鼠", "Report rate saved to the mouse")
            self?.log("Other report rate write result=\(error ?? "ok") ms=\(ms)")
        }
    }

    func setOtherLights(_ id: String, sector: Int, _ lights: [Int: OtherLightEffect]) {
        guard !otherButtonBusy.contains(id) else { return }
        otherButtonBusy.insert(id)
        otherButtonMessage[id] = nil
        others.writeLights(id, sector: sector, lights) { [weak self] error in
            self?.otherButtonBusy.remove(id)
            self?.otherButtonMessage[id] = error ?? Lang.t("燈光已寫入滑鼠", "Lighting saved to the mouse")
            self?.log("Other lights write result=\(error ?? "ok") \(lights.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value.bytes.map { String(format: "%02X", $0) }.joined())" })")
        }
    }

    func setOtherStages(_ id: String, sector: Int, _ stages: [Int], defaultIndex: Int?) {
        guard !otherButtonBusy.contains(id) else { return }
        otherButtonBusy.insert(id)
        otherButtonMessage[id] = nil
        others.writeStages(id, sector: sector, stages, defaultIndex: defaultIndex) { [weak self] error in
            self?.otherButtonBusy.remove(id)
            self?.otherButtonMessage[id] = error ?? Lang.t("指標速度已寫入滑鼠", "Pointer speeds saved to the mouse")
            self?.log("Other stages write result=\(error ?? "ok") stages=\(stages) default=\(defaultIndex ?? -1)")
        }
    }

    func hasOriginalButtons(_ d: OtherDeviceSnapshot) -> Bool {
        guard let url = OtherDevicesHIDPP.originalBackup(d) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    private func writeOtherButtons(_ id: String, sector: Int, _ changes: [Int: OtherButtonAssignment], restore: Bool) {
        guard !otherButtonBusy.contains(id) else { return }
        otherButtonBusy.insert(id)
        otherButtonMessage[id] = nil
        others.writeButtons(id, sector: sector, changes, restoreOriginal: restore) { [weak self] error in
            self?.otherButtonBusy.remove(id)
            self?.otherButtonMessage[id] = error ?? (restore ? Lang.t("已還原原本的設定檔", "Original profile restored")
                                                            : Lang.t("已寫入滑鼠", "Saved to the mouse"))
            self?.log("Other buttons write \(restore ? "restore" : "change") result=\(error ?? "ok")")
        }
    }

    // 有按鍵設成「手勢鍵」時，就算拇指手勢鍵的四向手勢關著，方向設定也要能改。
    var gestureHoldInUse: Bool {
        config.otherAppActions.values.contains { $0.action == .gestureHold } ||
            MouseInput.allCases.contains { $0.canHoldGesture && mapping($0).action == .gestureHold }
    }

    // 「交給 App」的動作分裝置、分設定檔存；舊版只存鍵號的設定在搬過去之前照舊讀得到。
    func otherAction(_ d: OtherDeviceSnapshot, number: Int) -> ActionBinding {
        config.otherAppActions[OtherDevicesProtocol.appActionKey(d, number: number)]
            ?? config.otherAppActions["\(number)"] ?? ActionBinding(.passThrough)
    }

    func setOtherAction(_ d: OtherDeviceSnapshot, number: Int, _ binding: ActionBinding) {
        config.otherAppActions[OtherDevicesProtocol.appActionKey(d, number: number)] = binding
    }

    private func migrateOtherActions() {
        for d in otherDevices where d.link == .online {
            if let moved = OtherDevicesProtocol.migratedAppActions(config.otherAppActions, device: d) {
                config.otherAppActions = moved
            }
        }
    }

    // 「交給 App」的鍵（第 6 鍵起）：按下時決定吃掉或放行並記下來，放開沿用同一筆（按住時改設定也不會多吃或漏吃）。
    // 這裡在事件攔截裡，動作與畫面更新都排到主佇列之後才做。
    private func otherAppButton(_ receiver: String, _ number: Int, _ down: Bool) -> Bool {
        let owner = "\(receiver):\(number)"
        guard down else {
            guard case .swallowed(let binding)? = otherPresses.up(owner) else { return false }
            DispatchQueue.main.async { [weak self] in
                if binding.action == .showActionRing {
                    self?.ringPress(false, owner: owner)
                } else if binding.action == .gestureHold {
                    self?.holdGesture(owner, down: false)
                }
            }
            return true
        }
        guard enabled,
              let device = OtherDevicesProtocol.device(forAppButton: number, receiver: receiver, in: otherDevices),
              case let binding = otherAction(device, number: number), !binding.isPassThrough else {
            otherPresses.down(owner, .passed)
            return false
        }
        otherPresses.down(owner, .swallowed(binding))
        DispatchQueue.main.async { [weak self] in
            guard let self, self.enabled else { return }
            switch binding.action {
            case .showActionRing: self.ringPress(true, owner: owner, quiet: true)
            case .gestureHold: self.holdGesture(owner, down: true, quiet: true)
            default:
                let sent = self.runAction(binding, fromOtherMouse: true)
                self.log("Other button \(number) selected=\(binding.action.rawValue) sent=\(sent)")
            }
        }
        return true
    }

    // MARK: 逐台提醒（2026-11-23）

    // 實際用的門檻與開關；其他裝置沒有逐台設定時，低電量提醒沿用舊的「其他裝置的低電量提醒」開關。
    func batteryAlert(_ key: String) -> (threshold: Int, low: Bool, full: Bool) {
        BatteryAlerts.effective(config.deviceAlerts, key: key, defaultLow: key.hasPrefix("other-") ? config.otherDevicesAlert : true,
                                globalThreshold: config.lowBatteryLevel)
    }

    var mouseLowLevel: Int { batteryAlert(BatteryDeviceKey.mouse).threshold }

    func setBatteryAlert(_ key: String, _ alert: DeviceBatteryAlert) {
        config.deviceAlerts[key] = alert
        batterySettingsChanged()
    }

    // 鍵盤只回報百分比：讀到一次在門檻以下就通知（同 MX Master 4）。
    private func keyboardBatteryChanged() {
        guard let kb = keyboardSnapshot, kb.batteryPercent >= 0 else { return }
        let alert = batteryAlert(BatteryDeviceKey.keyboard)
        let name = kb.name.isEmpty ? Lang.t("鍵盤", "Keyboard") : kb.name
        history.record(BatteryDeviceKey.keyboard, name: name, percent: kb.batteryPercent, charging: kb.charging || kb.full)
        let full = BatteryAlerts.fullStep(keyboardFull, charging: kb.charging, full: kb.full, percent: kb.batteryPercent,
                                          alertOn: config.lowBatteryAlert && alert.full)
        keyboardFull = full.state
        if full.notify { postFull(name) }
        let low = BatteryAlerts.lowStep(notified: keyboardLowNotified, percent: kb.batteryPercent, charging: kb.charging,
                                        threshold: alert.threshold, alertOn: config.lowBatteryAlert && alert.low)
        keyboardLowNotified = low.notified
        guard low.notify else { return }
        log("Keyboard battery low: \(name) \(kb.batteryPercent)% (threshold \(alert.threshold)%)")
        let title = Lang.t("\(name) 電量低", "\(name) battery low")
        notifier.post(title: title, body: Lang.t("剩 \(kb.batteryPercent)%，請盡快充電。", "\(kb.batteryPercent)% left. Charge it soon."),
                      identifier: "lowBattery-keyboard") { [weak self] delivered in
            if !delivered { self?.modeHUD.show(symbol: "battery.25percent", title: title, detail: "\(kb.batteryPercent)%") }
            self?.log("Keyboard battery notification delivered=\(delivered)")
        }
    }

    private func postFull(_ name: String) {
        log("Battery full: \(name)")
        let title = Lang.t("\(name) 已充飽", "\(name) is fully charged")
        notifier.post(title: title, body: Lang.t("可以拔掉充電線了。", "You can unplug the charging cable."),
                      identifier: "fullBattery-" + name) { [weak self] delivered in
            if !delivered { self?.modeHUD.show(symbol: "battery.100percent.bolt", title: title, detail: "100%") }
            self?.log("Battery full notification delivered=\(delivered)")
        }
    }

    // 定時記錄：沒有變化的裝置也每 10 分鐘記一筆，圖上斷開的地方才代表真的沒資料。
    private func recordHistory() {
        // MX Master 4 切到別台電腦時 snapshot 還留著舊值：要真的連著才記。
        var mouseReady = false
        if case .ready = status { mouseReady = true }
        if let s = snapshot, let percent = BatteryHistoryLogic.liveReading(connected: mouseReady, percent: s.batteryPercent) {
            history.record(BatteryDeviceKey.mouse, name: "MX Master 4", percent: percent, charging: s.charging || s.full)
        }
        if let kb = keyboardSnapshot, kb.batteryPercent >= 0 {
            history.record(BatteryDeviceKey.keyboard, name: kb.name, percent: kb.batteryPercent, charging: kb.charging || kb.full)
        }
        for d in otherDevices where d.link == .online && d.batteryPercent >= 0 {
            history.record(BatteryDeviceKey.other(wpid: d.wpid), name: d.name, percent: d.batteryPercent,
                           charging: d.charging || d.full || d.chargeState == .pluggedNotCharging)
        }
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

    // identifier：同一個識別碼的通知會互相取代，不同裝置、低電量與充飽要分開。
    func post(title: String, body: String, identifier: String = "lowBattery", completion: @escaping (Bool) -> Void) {
        guard let center else { return completion(false) }
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return DispatchQueue.main.async { completion(false) } }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
            center.add(request) { error in DispatchQueue.main.async { completion(error == nil) } }
        }
    }

    // 設定視窗在前景時也顯示橫幅。
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
