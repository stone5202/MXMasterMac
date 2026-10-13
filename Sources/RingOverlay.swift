import AppKit

// 八方向圓環的繪製。第 0 格在正上方，順時針排列。
final class RingView: NSView {
    static let side: CGFloat = 392
    static let outerRadius: CGFloat = 170
    static let innerRadius: CGFloat = 56
    static let popOut: CGFloat = 8
    static let centerRadius: CGFloat = 50

    var slots: [ActionBinding] = Config.defaultRing { didSet { needsDisplay = true } }
    var selected = -1 { didSet { if oldValue != selected { needsDisplay = true } } }
    var clickMode = false { didSet { needsDisplay = true } }
    var showNumbers = false { didSet { needsDisplay = true } }
    var bubbles = false { didSet { needsDisplay = true } }      // 泡泡樣式：每格一個圓形圖示
    var bubbleScale: CGFloat = 1 { didSet { needsDisplay = true } }   // 泡泡圓圈的大小倍率

    override var isFlipped: Bool { false }
    override var isOpaque: Bool { false }

    // 以圓心為原點、y 向上的座標，回傳格子編號；-1 是中心，-2 是圓環外。
    static func slot(dx: CGFloat, dy: CGFloat, scale: CGFloat = 1) -> Int {
        let distance = (dx * dx + dy * dy).squareRoot()
        if distance < centerRadius * scale { return -1 }
        if distance > (outerRadius + popOut) * scale { return -2 }
        return direction(dx: dx, dy: dy)
    }

    static func direction(dx: CGFloat, dy: CGFloat) -> Int {
        let angle = atan2(dx, dy)                       // 0 = 上，順時針為正
        let index = Int((angle / (.pi / 4)).rounded())
        return ((index % 8) + 8) % 8
    }

    override func draw(_ dirtyRect: NSRect) {
        let scale = min(bounds.width, bounds.height) / RingView.side
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let accent = NSColor.controlAccentColor
        if bubbles {
            drawBubbles(scale: scale, center: center, accent: accent)
            return
        }

        // 外圈：一道半透明的淺色邊框，讓圓環在任何背景上都有輪廓。
        let rimOuter = (RingView.outerRadius + 13) * scale, rimInner = (RingView.outerRadius + 4) * scale
        let rim = NSBezierPath()
        rim.appendOval(in: NSRect(x: center.x - rimOuter, y: center.y - rimOuter, width: rimOuter * 2, height: rimOuter * 2))
        rim.appendOval(in: NSRect(x: center.x - rimInner, y: center.y - rimInner, width: rimInner * 2, height: rimInner * 2))
        rim.windingRule = .evenOdd
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
        shadow.shadowBlurRadius = 5 * scale
        shadow.shadowOffset = NSSize(width: 0, height: -1.5 * scale)
        shadow.set()
        NSColor(white: 0.80, alpha: 0.55).setFill()
        rim.fill()
        NSGraphicsContext.restoreGraphicsState()

        let normal = NSGradient(starting: NSColor(calibratedRed: 0.20, green: 0.21, blue: 0.25, alpha: 0.96),
                                ending: NSColor(calibratedRed: 0.11, green: 0.12, blue: 0.15, alpha: 0.96))
        let chosen = NSGradient(starting: accent.blended(withFraction: 0.22, of: .white) ?? accent,
                                ending: accent.blended(withFraction: 0.18, of: .black) ?? accent)

        for index in 0..<8 {
            let isSelected = index == selected
            let middle = 90.0 - Double(index) * 45.0
            let start = CGFloat(middle - 21.2)
            let end = CGFloat(middle + 21.2)
            let push = isSelected ? RingView.popOut * scale : 0
            let radians = CGFloat(middle) * .pi / 180
            let origin = NSPoint(x: center.x + cos(radians) * push, y: center.y + sin(radians) * push)

            let path = NSBezierPath()
            path.appendArc(withCenter: origin, radius: RingView.outerRadius * scale, startAngle: start, endAngle: end)
            path.appendArc(withCenter: origin, radius: RingView.innerRadius * scale, startAngle: end, endAngle: start, clockwise: true)
            path.close()
            (isSelected ? chosen : normal)?.draw(in: path, angle: -90)
            NSColor(white: 1, alpha: isSelected ? 0.30 : 0.07).setStroke()
            path.lineWidth = 1
            path.stroke()

            let labelRadius = (RingView.outerRadius + RingView.innerRadius) / 2 * scale
            let point = NSPoint(x: origin.x + cos(radians) * labelRadius, y: origin.y + sin(radians) * labelRadius)
            let binding = index < slots.count ? slots[index] : ActionBinding(.passThrough)
            drawSlot(binding, at: point, scale: scale, number: showNumbers ? index + 1 : nil)
        }

        // 中心：顯示目前選到的動作或操作提示。
        let radius = RingView.centerRadius * scale
        let circle = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        NSGradient(starting: NSColor(calibratedRed: 0.13, green: 0.14, blue: 0.17, alpha: 0.97),
                   ending: NSColor(calibratedRed: 0.07, green: 0.08, blue: 0.10, alpha: 0.97))?.draw(in: circle, angle: -90)
        NSColor(white: 1, alpha: 0.14).setStroke()
        circle.lineWidth = 1.2
        circle.stroke()

        var text: String
        if selected >= 0 && selected < slots.count {
            text = slots[selected].title
        } else if showNumbers {
            text = ""
        } else {
            text = clickMode ? Lang.t("點選功能", "Click a slice") : Lang.t("移動選擇", "Move to choose")
        }
        if slots.indices.contains(selected), slots[selected].isPassThrough { text = Lang.t("未設定", "Not set") }
        drawText(text, in: NSRect(x: center.x - radius + 6, y: center.y - radius + 6, width: radius * 2 - 12, height: radius * 2 - 12),
                 size: 12 * scale, weight: .semibold, vertical: true)
    }

    // 泡泡樣式：八個圓形圖示圍成一圈，只有游標指到的那一個會在中央顯示名稱。
    private func drawBubbles(scale: CGFloat, center: NSPoint, accent: NSColor) {
        let normal = NSGradient(starting: NSColor(calibratedRed: 0.22, green: 0.23, blue: 0.27, alpha: 0.96),
                                ending: NSColor(calibratedRed: 0.11, green: 0.12, blue: 0.15, alpha: 0.96))
        let chosen = NSGradient(starting: accent.blended(withFraction: 0.22, of: .white) ?? accent,
                                ending: accent.blended(withFraction: 0.18, of: .black) ?? accent)
        let bubble = 39 * bubbleScale
        // 圓圈變大時把軌道往外推，讓相鄰兩個之間至少留一點空隙。
        let orbit = max(126, (bubble * 2 + 8) * 8 / (2 * .pi)) * scale
        for index in 0..<8 {
            let isSelected = index == selected
            let radians = CGFloat(90.0 - Double(index) * 45.0) * .pi / 180
            let point = NSPoint(x: center.x + cos(radians) * orbit, y: center.y + sin(radians) * orbit)
            let radius = (isSelected ? bubble + 5 : bubble) * scale
            let rect = NSRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
            let circle = NSBezierPath(ovalIn: rect)

            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
            shadow.shadowBlurRadius = 7 * scale
            shadow.shadowOffset = NSSize(width: 0, height: -2 * scale)
            shadow.set()
            NSColor(white: 0.12, alpha: 0.9).setFill()
            circle.fill()
            NSGraphicsContext.restoreGraphicsState()
            (isSelected ? chosen : normal)?.draw(in: circle, angle: -90)
            NSColor(white: 1, alpha: isSelected ? 0.45 : 0.22).setStroke()
            circle.lineWidth = 1.4 * scale
            circle.stroke()

            let binding = index < slots.count ? slots[index] : ActionBinding(.passThrough)
            let color = NSColor(white: 1, alpha: binding.isPassThrough ? 0.35 : 1)
            let configuration = NSImage.SymbolConfiguration(pointSize: (isSelected ? 29 : 25) * bubbleScale * scale, weight: .medium)
                .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
            if let image = NSImage(systemSymbolName: ActionCatalog.symbol(binding.action), accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration) {
                let size = image.size
                image.draw(in: NSRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height))
            }
            if showNumbers {
                let badge = NSRect(x: rect.maxX - 17 * scale, y: rect.maxY - 17 * scale, width: 19 * scale, height: 19 * scale)
                NSColor.controlAccentColor.setFill()
                NSBezierPath(ovalIn: badge).fill()
                NSColor.white.setStroke()
                let ring = NSBezierPath(ovalIn: badge)
                ring.lineWidth = 1.2 * scale
                ring.stroke()
                drawText("\(index + 1)", in: badge.insetBy(dx: 0, dy: 1.5 * scale), size: 10.5 * scale, weight: .bold, vertical: true)
            }
        }

        if slots.indices.contains(selected) {
            // 中央的名稱標籤，寬度跟著文字走。
            let title = slots[selected].isPassThrough ? Lang.t("未設定", "Not set") : slots[selected].title
            let font = NSFont.systemFont(ofSize: 14 * scale, weight: .semibold)
            let width = min((title as NSString).size(withAttributes: [.font: font]).width + 30 * scale, 150 * scale)
            let pill = NSRect(x: center.x - width / 2, y: center.y - 17 * scale, width: width, height: 34 * scale)
            NSColor(calibratedRed: 0.08, green: 0.09, blue: 0.11, alpha: 0.94).setFill()
            NSBezierPath(roundedRect: pill, xRadius: 17 * scale, yRadius: 17 * scale).fill()
            drawText(title, in: pill.insetBy(dx: 10 * scale, dy: 8 * scale), size: 14 * scale, weight: .semibold, vertical: false)
        } else if !showNumbers {
            // 沒選到東西時，中央留一個小圓點標示取消的位置。
            let radius = 9 * scale
            let dot = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            NSColor(white: 0.1, alpha: 0.75).setFill()
            dot.fill()
            NSColor(white: 1, alpha: 0.5).setStroke()
            dot.lineWidth = 1.4 * scale
            dot.stroke()
        }
    }

    private func drawSlot(_ binding: ActionBinding, at point: NSPoint, scale: CGFloat, number: Int?) {
        let dimmed = binding.isPassThrough
        let color = NSColor(white: 1, alpha: dimmed ? 0.35 : 1)
        let configuration = NSImage.SymbolConfiguration(pointSize: 21 * scale, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        if let image = NSImage(systemSymbolName: ActionCatalog.symbol(binding.action), accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) {
            let size = image.size
            image.draw(in: NSRect(x: point.x - size.width / 2, y: point.y - size.height / 2 + 9 * scale,
                                  width: size.width, height: size.height))
        }
        let title = dimmed ? Lang.t("未設定", "Not set") : binding.title
        drawText(title, in: NSRect(x: point.x - 46 * scale, y: point.y - 26 * scale, width: 92 * scale, height: 16 * scale),
                 size: 10.5 * scale, weight: .regular, vertical: false, color: color)

        if let number {
            let badge = NSRect(x: point.x - 9 * scale, y: point.y + 27 * scale, width: 18 * scale, height: 18 * scale)
            NSColor.controlAccentColor.setFill()
            NSBezierPath(ovalIn: badge).fill()
            drawText("\(number)", in: badge.insetBy(dx: 0, dy: 1.5 * scale), size: 10.5 * scale, weight: .bold, vertical: true)
        }
    }

    private func drawText(_ text: String, in rect: NSRect, size: CGFloat, weight: NSFont.Weight, vertical: Bool,
                          color: NSColor = .white) {
        if text.isEmpty { return }
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = vertical ? .byWordWrapping : .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
            .paragraphStyle: style,
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        var target = rect
        if vertical {
            let needed = string.boundingRect(with: rect.size, options: [.usesLineFragmentOrigin]).height
            let height = min(needed, rect.height)
            target = NSRect(x: rect.minX, y: rect.midY - height / 2, width: rect.width, height: height)
        }
        string.draw(with: target, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }
}

// 浮在所有視窗上方、不搶焦點、不接收點擊的圓環面板。
final class RingOverlay {
    private let panel: NSPanel
    private let view = RingView(frame: NSRect(x: 0, y: 0, width: RingView.side, height: RingView.side))
    private var timer: Timer?
    private(set) var center = NSPoint.zero
    private(set) var visible = false

    var slots: [ActionBinding] {
        get { view.slots }
        set { view.slots = newValue }
    }
    var clickMode: Bool {
        get { view.clickMode }
        set { view.clickMode = newValue }
    }
    var bubbles: Bool {
        get { view.bubbles }
        set { view.bubbles = newValue }
    }
    var scale: CGFloat = 1          // 圓環大小倍率
    var bubbleScale: CGFloat {
        get { view.bubbleScale }
        set { view.bubbleScale = newValue }
    }
    var opacity: CGFloat = 1        // 圓環不透明度

    init() {
        panel = NSPanel(contentRect: view.frame, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = view
    }

    func show(at point: NSPoint) {
        var origin = point
        // 點選模式要讓八格都點得到，所以把圓環留在游標所在的螢幕範圍內。
        if clickMode, let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) {
            let margin = (RingView.outerRadius + RingView.popOut + 4) * scale
            let area = screen.visibleFrame
            origin.x = min(max(point.x, area.minX + margin), area.maxX - margin)
            origin.y = min(max(point.y, area.minY + margin), area.maxY - margin)
        }
        center = origin
        view.selected = -1
        let side = RingView.side * scale
        panel.setFrame(NSRect(x: origin.x - side / 2, y: origin.y - side / 2, width: side, height: side), display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.06
            panel.animator().alphaValue = opacity
        }
        visible = true
        timer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.track() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func hide() {
        timer?.invalidate()
        timer = nil
        visible = false
        panel.orderOut(nil)
    }

    // 目前游標所在的格子；-1 中心、-2 圓環外。
    func slotUnderCursor() -> Int {
        let location = NSEvent.mouseLocation
        let dx = location.x - center.x, dy = location.y - center.y
        if clickMode { return RingView.slot(dx: dx, dy: dy, scale: scale) }
        // 按住模式沒有外緣限制：移得再遠都算該方向。
        let distance = (dx * dx + dy * dy).squareRoot()
        return distance < RingView.centerRadius * scale ? -1 : RingView.direction(dx: dx, dy: dy)
    }

    var selectedBinding: ActionBinding? {
        let index = slotUnderCursor()
        return index >= 0 && index < view.slots.count ? view.slots[index] : nil
    }

    private func track() {
        let index = slotUnderCursor()
        view.selected = index >= 0 ? index : -1
    }
}

// 拇指手勢進行中顯示的小提示。
final class GestureHUD {
    private let panel: NSPanel
    private let label = NSTextField(labelWithString: "")

    init() {
        let frame = NSRect(x: 0, y: 0, width: 190, height: 44)
        panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .popUpMenu
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let background = NSVisualEffectView(frame: frame)
        background.material = .hudWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        background.layer?.masksToBounds = true
        label.frame = NSRect(x: 8, y: 12, width: frame.width - 16, height: 20)
        label.alignment = .center
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        background.addSubview(label)
        panel.contentView = background
    }

    func show(at point: NSPoint, text: String) {
        label.stringValue = text
        panel.setFrameOrigin(NSPoint(x: point.x - panel.frame.width / 2, y: point.y + 28))
        panel.orderFrontRegardless()
    }

    func update(_ text: String) { label.stringValue = text }
    func hide() { panel.orderOut(nil) }
}
