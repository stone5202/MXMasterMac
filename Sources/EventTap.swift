import AppKit

enum TapEvent: String {
    case middleDown, middleUp, backDown, backUp, forwardDown, forwardUp
    case wheelLeft, wheelRight
    case leftDown, leftUp, rightDown, rightUp
}

// 一般按鍵與水平滾輪用系統的事件攔截（需要「輔助使用」權限）。攔截掛在主執行緒，
// handler 回傳 true 表示吃掉這個事件。事件攔截分不出來源是哪一隻滑鼠。
final class EventTap {
    var handler: ((TapEvent) -> Bool)?
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
            return Unmanaged.passUnretained(event)
        }
        guard let kind = classify(type, event), let handler else { return Unmanaged.passUnretained(event) }
        return handler(kind) ? nil : Unmanaged.passUnretained(event)
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
