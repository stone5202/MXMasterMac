import AppKit
import SwiftUI

// Offline renderer. Never calls AppModel.start(), HIDPP.start(), KeyboardHIDPP.start(),
// or a device operation. Their candidate/device lists remain empty throughout rendering.
@main struct FeaturePreview {
    @MainActor static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let model = AppModel()
        var mouse = DeviceSnapshot()
        mouse.transport = "BLE"; mouse.batteryPercent = 75; mouse.firmware = "23.1"
        mouse.dpi = 1000; mouse.dpiMin = 200; mouse.dpiMax = 8000; mouse.dpiStep = 50
        mouse.smartShiftPresent = true; mouse.wheelMode = 2; mouse.smartShift = 12
        mouse.wheelInvertPresent = true; mouse.ratchetTorque = 65; mouse.thumbInverted = false; mouse.hiresResolution = true
        model.snapshot = mouse
        var kb = KeyboardSnapshot()
        kb.name = "MX Mechanical Mini"; kb.batteryPercent = 60; kb.firmware = "RBK 72.03.B0014"
        kb.backlightPresent = true; kb.backlightEnabled = true; kb.backlightMode = 3
        kb.backlightAuto = true; kb.backlightManual = true; kb.backlightLevel = 4; kb.backlightLevels = 8
        kb.backlightDelays = [30,60,120]; kb.disabledKeysMask = 255; kb.disabledKeys = 1
        kb.platforms = [.init(id: 0,name: "macOS"),.init(id: 1,name: "Windows")]; kb.currentPlatform = 0
        kb.fnPresent = true; kb.hosts = (0..<3).map { HostEntry(index:$0,name:["MacBook Pro","Office PC","Logitech Bolt receiver"][$0],paired:true,bus:4) }; kb.currentHost = 0
        model.keyboardSnapshot = kb
        let destination = CommandLine.arguments[1]
        for language in ["zh-Hant", "en"] {
            Lang.load(language)
            for page in [2,5] {
                let body = VStack(alignment:.leading, spacing:14) {
                    Text(page == 2 ? Page.device.title : Page.keyboard.title).font(.system(size:22,weight:.bold))
                    if page == 2 { DevicePage(model:model,page:.constant(.device)) }
                    else { KeyboardPage(model:model,page:.constant(.keyboard)) }
                }.padding(26).frame(width:760).background(Color(nsColor:.windowBackgroundColor))
                let hosting = NSHostingView(rootView:body)
                let size = hosting.fittingSize
                let window = NSWindow(contentRect:NSRect(origin:NSPoint(x:-10000,y:-10000),size:size),
                                      styleMask:.borderless,backing:.buffered,defer:false)
                window.contentView = hosting
                hosting.frame = NSRect(origin:.zero,size:size)
                hosting.layoutSubtreeIfNeeded()
                RunLoop.current.run(until:Date().addingTimeInterval(0.1))
                guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in:hosting.bounds) else { fatalError("bitmap failed") }
                hosting.cacheDisplay(in:hosting.bounds,to:bitmap)
                guard let data = bitmap.representation(using:.png,properties:[:]) else { fatalError("render failed") }
                let path = "\(destination)/mac-\(page)-\(language).png"
                try data.write(to:URL(fileURLWithPath:path))
                print("Rendered \(path) \(bitmap.pixelsWide)x\(bitmap.pixelsHigh)")
            }
        }
    }
}
