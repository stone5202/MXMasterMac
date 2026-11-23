import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private let model = AppModel()
    private var statusItem: NSStatusItem?
    private var window: NSWindow?
    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 只執行一份：已經有一份在跑就把它叫到前面，自己結束。
        if let bundleID = Bundle.main.bundleIdentifier {
            let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            if let other = others.first {
                other.activate()
                NSApp.terminate(nil)
                return
            }
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "computermouse.fill", accessibilityDescription: "MX Master Mac")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item

        ActionRunner.openSettings = { [weak self] in self?.showSettings() }
        model.start()
        // 被 kill 時也要解除改道，否則專用鍵會停在沒人接收的狀態。
        for number in [SIGTERM, SIGINT] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }
            source.resume()
            signalSources.append(source)
        }

        let firstRun = !FileManager.default.fileExists(atPath: Config.fileURL.path)
        if firstRun || !model.trusted || CommandLine.arguments.contains("--show") { showSettings() }
        if !model.trusted { model.requestAccessibility() }
        HIDPP.requestInputMonitoring()
        if firstRun { model.config.save() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.shutdown()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let status = NSMenuItem(title: model.enabled ? model.statusText : Lang.t("已暫停", "Paused"), action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        if !model.batteryText.isEmpty {
            let battery = NSMenuItem(title: Lang.t("電量 ", "Battery ") + model.batteryText, action: nil, keyEquivalent: "")
            battery.isEnabled = false
            menu.addItem(battery)
        }
        // 「其他裝置」頁連著的裝置（例如 G502），各一行。
        for other in model.otherDevices where other.link == .online && other.batteryPercent >= 0 {
            let line = NSMenuItem(title: OthersPage.shortName(other) + " " + OthersPage.batteryText(other), action: nil, keyEquivalent: "")
            line.isEnabled = false
            menu.addItem(line)
        }
        // 可切段的裝置（例如 G502 內建設定檔模式）：子選單切指標速度段與設定檔，不用開設定視窗。
        for other in model.otherDevices where other.canSwitchStage {
            let sub = NSMenu()
            for (index, dpi) in other.dpiStages.enumerated() where dpi > 0 {
                let stage = NSMenuItem(title: "\(dpi) DPI", action: #selector(pickOtherStage(_:)), keyEquivalent: "")
                stage.target = self
                stage.representedObject = [other.id, index] as [Any]
                stage.state = other.stageIndex == index ? .on : .off
                sub.addItem(stage)
            }
            if other.profiles.count > 1 {
                sub.addItem(.separator())
                for (number, sector) in other.profiles.enumerated() {
                    let profile = NSMenuItem(title: Lang.t("設定檔 \(number + 1)", "Profile \(number + 1)"),
                                             action: #selector(pickOtherProfile(_:)), keyEquivalent: "")
                    profile.target = self
                    profile.representedObject = [other.id, sector] as [Any]
                    profile.state = other.activeProfile == sector ? .on : .off
                    sub.addItem(profile)
                }
            }
            let title = Lang.t("\(OthersPage.shortName(other)) 指標速度", "\(OthersPage.shortName(other)) pointer speed")
            let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            holder.submenu = sub
            menu.addItem(holder)
        }
        menu.addItem(.separator())
        menu.addItem(item(Lang.t("開啟設定…", "Open settings…"), #selector(showSettings), ","))
        menu.addItem(item(model.enabled ? Lang.t("暫停", "Pause") : Lang.t("啟用", "Resume"), #selector(toggleEnabled), ""))
        // 打勾表示 MX Flow 開著；與設定視窗「MX Flow」頁的開關是同一個設定。
        let flow = item("MX Flow", #selector(toggleFlow), "")
        flow.state = model.config.edgeSwitch.enabled ? .on : .off
        menu.addItem(flow)
        menu.addItem(.separator())
        menu.addItem(item(Lang.t("結束", "Quit"), #selector(quit), "q"))
    }

    @objc private func pickOtherStage(_ sender: NSMenuItem) {
        guard let pair = sender.representedObject as? [Any], let id = pair[0] as? String, let index = pair[1] as? Int else { return }
        model.setOtherStage(id, index)
    }

    @objc private func pickOtherProfile(_ sender: NSMenuItem) {
        guard let pair = sender.representedObject as? [Any], let id = pair[0] as? String, let sector = pair[1] as? Int else { return }
        model.setOtherProfile(id, sector)
    }

    private func item(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func showSettings() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(model: model))
            // 視窗大小由這裡決定，不讓 SwiftUI 依安全區域自行加高。
            hosting.sizingOptions = []
            let created = NSWindow(contentViewController: hosting)
            created.title = "MX Master Mac"
            created.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            created.titlebarAppearsTransparent = true
            created.titleVisibility = .hidden
            created.isMovableByWindowBackground = true
            created.isReleasedWhenClosed = false
            created.delegate = self
            created.setContentSize(NSSize(width: 1000, height: 690))
            created.center()
            window = created
        }
        model.refreshDevice()
        model.refreshOthers()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    @objc private func toggleEnabled() { model.setEnabled(!model.enabled) }
    @objc private func toggleFlow() { model.config.edgeSwitch.enabled.toggle() }
    @objc private func quit() { NSApp.terminate(nil) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
