import AppKit
import IOKit

enum TapEvent: String {
    case middleDown, middleUp, backDown, backUp, forwardDown, forwardUp
    case wheelLeft, wheelRight
    case leftDown, leftUp, rightDown, rightUp
}

// 一般按鍵與水平滾輪用系統的事件攔截（需要「輔助使用」權限）。攔截掛在主執行緒，
// handler 回傳 true 表示吃掉這個事件。
// 來源滑鼠：事件欄位 87 是送出事件的 HID 服務的 IORegistry ID（2026-11-23 實測：MX Master 4 藍牙與 G502 的 C539 接收器不同），
// 查得到是 Lightspeed 接收器的，就不套 MX Master 4 的按鍵對應（舊版 G502 的中鍵／側鍵也會被改掉）。
final class EventTap {
    var handler: ((TapEvent) -> Bool)?
    // Lightspeed 裝置（例如 G502）的第 6 鍵起：(接收器識別, 鍵號 1 起算, 按下) → 回傳 true 吃掉。設定檔把某顆鍵設成「交給 App」時用。
    var extraHandler: ((String, Int, Bool) -> Bool)?
    // 系統因為逾時或受保護輸入停用過攔截：這段期間的放開事件可能漏掉。
    var onDisabled: (() -> Void)?
    // 正在處理的事件來自哪個 HID 服務（handler 裡分辨左右鍵的放開是不是同一隻滑鼠）。
    private(set) var currentSource: UInt64 = 0
    private var lightspeedSources: [UInt64: String] = [:]   // 來源 → 接收器識別；空字串表示不是 Lightspeed
    private static let senderField = CGEventField(rawValue: 87)
    private var port: CFMachPort?
    private var source: CFRunLoopSource?

    var installed: Bool { port != nil }

    @discardableResult
    func install() -> Bool {
        if port != nil { return true }
        let types: [CGEventType] = [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
                                    .otherMouseDown, .otherMouseUp, .scrollWheel]
        var mask: CGEventMask = 0
        for type in types { mask |= CGEventMask(1) << CGEventMask(type.rawValue) }
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: mask, callback: { _, type, event, context in
            let tap = Unmanaged<EventTap>.fromOpaque(context!).takeUnretainedValue()
            return tap.handle(type, event)
        }, userInfo: context) else { return false }
        self.port = port
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        return true
    }

    func remove() {
        if let port { CGEvent.tapEnable(tap: port, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        port = nil
        source = nil
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        // 系統在攔截處理太慢或使用者輸入受保護內容時會停用攔截，要自己開回來。
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            onDisabled?()
            return Unmanaged.passUnretained(event)
        }
        if type == .otherMouseDown || type == .otherMouseUp, let receiver = lightspeedReceiver(event) {
            let number = Int(event.getIntegerValueField(.mouseEventButtonNumber)) + 1
            if number >= 6, let extraHandler, extraHandler(receiver, number, type == .otherMouseDown) { return nil }
            return Unmanaged.passUnretained(event)
        }
        // Lightspeed 滑鼠的水平捲動（G502 滾輪左右撥）照原樣放行，不套 MX Master 4 拇指滾輪的對應，也不會震到它。
        if type == .scrollWheel, lightspeedReceiver(event) != nil { return Unmanaged.passUnretained(event) }
        guard let kind = classify(type, event), let handler else { return Unmanaged.passUnretained(event) }
        currentSource = EventTap.senderField.map { UInt64(bitPattern: event.getIntegerValueField($0)) } ?? 0
        return handler(kind) ? nil : Unmanaged.passUnretained(event)
    }

    // 事件來自哪一支 Lightspeed 接收器（查一次就記住；查不到當成不是，維持舊行為）。識別格式同 OtherDevicesHIDPP.receiverKey。
    private func lightspeedReceiver(_ event: CGEvent) -> String? {
        guard let field = EventTap.senderField else { return nil }
        let id = UInt64(bitPattern: event.getIntegerValueField(field))
        guard id != 0 else { return nil }
        if let known = lightspeedSources[id] { return known.isEmpty ? nil : known }
        var result = ""
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IORegistryEntryIDMatching(id))
        if service != 0 {
            func number(_ key: String) -> Int? {
                IORegistryEntrySearchCFProperty(service, kIOServicePlane, key as CFString, kCFAllocatorDefault,
                                                IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)) as? Int
            }
            let product = number("ProductID") ?? 0
            if number("VendorID") == OtherDevicesProtocol.vendor, OtherDevicesProtocol.lightspeedReceivers.contains(product) {
                result = String(format: "%04X@%08X", product, number("LocationID") ?? 0)
            }
            IOObjectRelease(service)
        }
        if lightspeedSources.count > 64 { lightspeedSources.removeAll() }
        lightspeedSources[id] = result
        return result.isEmpty ? nil : result
    }

    private func classify(_ type: CGEventType, _ event: CGEvent) -> TapEvent? {
        switch type {
        case .leftMouseDown: return .leftDown
        case .leftMouseUp: return .leftUp
        case .rightMouseDown: return .rightDown
        case .rightMouseUp: return .rightUp
        case .otherMouseDown, .otherMouseUp:
            let down = type == .otherMouseDown
            switch event.getIntegerValueField(.mouseEventButtonNumber) {
            case 2: return down ? .middleDown : .middleUp
            case 3: return down ? .backDown : .backUp
            case 4: return down ? .forwardDown : .forwardUp
            default: return nil
            }
        case .scrollWheel:
            // 觸控式軌跡板與巧控滑鼠送的是連續捲動，不能當成拇指滾輪。
            if event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0 { return nil }
            let horizontal = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
            let vertical = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
            if horizontal == 0 || vertical != 0 { return nil }
            return horizontal > 0 ? .wheelLeft : .wheelRight
        default: return nil
        }
    }
}
