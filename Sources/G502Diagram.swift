import SwiftUI

// 「其他裝置」頁的 G502 LIGHTSPEED 示意圖：和 Windows 版同一張自繪向量圖（座標照 OtherMouseDiagram），
// 不用羅技的圖片與標誌；按鍵位置依 G502 LIGHTSPEED 設定指南的編號圖。
// 編號＝設定檔裡的順序＋1：1 左鍵、2 右鍵、3 滾輪按下、4 G4、5 G5、6 G6、7 G7、8 G8、9 G9、10 右撥、11 左撥。
struct G502Diagram: View {
    @Binding var highlight: Int?
    var count = 11

    private struct Spot {
        let index: Int
        let target: CGPoint
        let badge: CGPoint
    }

    private static let design = CGSize(width: 200, height: 256)
    private static let badgeRadius: CGFloat = 9.5

    private static let spots: [Spot] = [
        Spot(index: 0, target: CGPoint(x: 80, y: 56), badge: CGPoint(x: 13, y: 30)),
        Spot(index: 7, target: CGPoint(x: 60.5, y: 68), badge: CGPoint(x: 13, y: 54)),
        Spot(index: 10, target: CGPoint(x: 99.5, y: 76), badge: CGPoint(x: 13, y: 78)),
        Spot(index: 6, target: CGPoint(x: 60, y: 91), badge: CGPoint(x: 13, y: 102)),
        Spot(index: 5, target: CGPoint(x: 52, y: 103), badge: CGPoint(x: 13, y: 126)),
        Spot(index: 4, target: CGPoint(x: 57, y: 130), badge: CGPoint(x: 13, y: 150)),
        Spot(index: 3, target: CGPoint(x: 62, y: 158), badge: CGPoint(x: 13, y: 174)),
        Spot(index: 1, target: CGPoint(x: 136, y: 62), badge: CGPoint(x: 187, y: 40)),
        Spot(index: 9, target: CGPoint(x: 117.5, y: 76), badge: CGPoint(x: 187, y: 74)),
        Spot(index: 2, target: CGPoint(x: 108.5, y: 92), badge: CGPoint(x: 187, y: 104)),
        Spot(index: 8, target: CGPoint(x: 110.5, y: 130), badge: CGPoint(x: 187, y: 134)),
    ]

    var body: some View {
        GeometryReader { geometry in
            let fit = min(geometry.size.width / Self.design.width, geometry.size.height / Self.design.height)
            let origin = CGPoint(x: (geometry.size.width - Self.design.width * fit) / 2,
                                 y: (geometry.size.height - Self.design.height * fit) / 2)
            let spots = Self.spots.filter { $0.index < count }
            Canvas { context, _ in
                context.translateBy(x: origin.x, y: origin.y)
                context.scaleBy(x: fit, y: fit)
                Self.drawMouse(&context, highlight: highlight)
                Self.drawBadges(&context, spots: spots, highlight: highlight)
            }
            // 滑過編號圈，右邊清單的同一顆鍵一起亮。
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    let x = (point.x - origin.x) / fit, y = (point.y - origin.y) / fit
                    let reach = (Self.badgeRadius + 2) * (Self.badgeRadius + 2)
                    let hit = spots.first { pow($0.badge.x - x, 2) + pow($0.badge.y - y, 2) <= reach }?.index
                    if highlight != hit { highlight = hit }
                case .ended:
                    if highlight != nil { highlight = nil }
                }
            }
        }
        .aspectRatio(Self.design.width / Self.design.height, contentMode: .fit)
    }

    // MARK: - 繪製

    private static func rgb(_ r: Double, _ g: Double, _ b: Double, alpha: Double = 255) -> Color {
        Color(.sRGB, red: r / 255, green: g / 255, blue: b / 255, opacity: alpha / 255)
    }

    private static func polygon(_ values: [CGFloat]) -> Path {
        var path = Path()
        path.addLines(stride(from: 0, to: values.count - 1, by: 2).map { CGPoint(x: values[$0], y: values[$0 + 1]) })
        path.closeSubpath()
        return path
    }

    // 同 GDI+ 的 LinearGradientBrush：角度順時針，漸層線剛好涵蓋整個矩形。
    private static func gradient(_ rect: CGRect, angle: Double, _ from: Color, _ to: Color) -> GraphicsContext.Shading {
        let radians = angle * .pi / 180
        let dx = cos(radians), dy = sin(radians)
        let half = (abs(rect.width * dx) + abs(rect.height * dy)) / 2
        return .linearGradient(Gradient(colors: [from, to]),
                               startPoint: CGPoint(x: rect.midX - dx * half, y: rect.midY - dy * half),
                               endPoint: CGPoint(x: rect.midX + dx * half, y: rect.midY + dy * half))
    }

    private static func outline() -> Path {
        func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
        var p = Path()
        p.move(to: at(97, 30))
        p.addLine(to: at(96, 47))
        p.addLine(to: at(118, 47))
        p.addLine(to: at(115, 24))
        p.addCurve(to: at(146, 44), control1: at(128, 32), control2: at(140, 38))
        p.addCurve(to: at(158, 94), control1: at(152, 52), control2: at(155, 72))
        p.addCurve(to: at(159, 140), control1: at(159, 112), control2: at(158, 128))
        p.addCurve(to: at(163.5, 184), control1: at(160, 155), control2: at(163, 170))
        p.addCurve(to: at(137, 237), control1: at(164, 200), control2: at(152, 224))
        p.addCurve(to: at(116, 247.4), control1: at(130, 243), control2: at(122, 246))
        p.addLine(to: at(108.5, 245))
        p.addLine(to: at(101.3, 248.7))
        p.addCurve(to: at(74, 235), control1: at(92, 247), control2: at(81, 241))
        p.addLine(to: at(38.3, 181.5))
        p.addCurve(to: at(34, 172), control1: at(35, 178), control2: at(34, 176))
        p.addCurve(to: at(36.2, 136), control1: at(33, 158), control2: at(34, 146))
        p.addCurve(to: at(48.8, 121.4), control1: at(38, 130), control2: at(44, 126))
        p.addLine(to: at(50.5, 111))
        p.addLine(to: at(47.8, 104))
        p.addLine(to: at(50.9, 88))
        p.addLine(to: at(65.6, 48))
        p.closeSubpath()
        return p
    }

    private static func drawMouse(_ context: inout GraphicsContext, highlight: Int?) {
        func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
        let accent = Color.accentColor
        let round = StrokeStyle(lineWidth: 1, lineJoin: .round)

        // 主鍵：柔和漸層，對應的按鍵被選到時染色。
        func mainPlate(_ values: [CGFloat], _ index: Int, _ c: inout GraphicsContext) {
            let plate = polygon(values)
            c.fill(plate, with: gradient(CGRect(x: 45, y: 20, width: 115, height: 125), angle: 80, rgb(92, 97, 108), rgb(58, 62, 71)))
            if highlight == index { c.fill(plate, with: .color(accent.opacity(165.0 / 255))) }
            c.stroke(plate, with: .color(rgb(24, 26, 32)), style: StrokeStyle(lineWidth: 0.9, lineJoin: .round))
        }

        func sidePlate(_ values: [CGFloat], _ index: Int, _ c: inout GraphicsContext) {
            let plate = polygon(values)
            c.fill(plate, with: .color(highlight == index ? accent : rgb(120, 126, 138)))
            c.stroke(plate, with: .color(rgb(24, 26, 32)), style: StrokeStyle(lineWidth: 0.7, lineJoin: .round))
        }

        func key(_ rect: CGRect, _ radius: CGFloat, _ index: Int, _ normal: Color, _ c: inout GraphicsContext) {
            let shape = Path(roundedRect: rect, cornerRadius: radius)
            c.fill(shape, with: .color(index >= 0 && highlight == index ? accent : normal))
            c.stroke(shape, with: .color(rgb(138, 145, 158)), lineWidth: 0.7)
        }

        let body = outline()
        context.fill(body.offsetBy(dx: 1, dy: 3.5), with: .color(rgb(20, 26, 38, alpha: 38)))
        context.fill(body, with: gradient(CGRect(x: 30, y: 20, width: 136, height: 232), angle: 72, rgb(64, 68, 78), rgb(36, 38, 45)))

        // 手掌區：拇指側較亮的一塊，用弧形接縫分開。
        context.drawLayer { layer in
            layer.clip(to: body)
            var palm = Path()
            palm.move(to: at(61, 178))
            palm.addCurve(to: at(106, 207), control1: at(72, 196), control2: at(92, 200))
            palm.addCurve(to: at(102, 250), control1: at(108, 222), control2: at(105, 238))
            palm.addLine(to: at(60, 250))
            palm.addLine(to: at(28, 180))
            palm.closeSubpath()
            layer.fill(palm, with: .color(.white.opacity(20.0 / 255)))
        }
        var seam = Path()
        seam.move(to: at(61, 178))
        seam.addCurve(to: at(106, 207), control1: at(72, 196), control2: at(92, 200))
        seam.addCurve(to: at(102, 248), control1: at(108, 222), control2: at(105, 238))
        seam.move(to: at(150, 141))
        seam.addCurve(to: at(158, 186), control1: at(148, 154), control2: at(148, 168))
        context.stroke(seam, with: .color(rgb(22, 24, 30)), lineWidth: 1)

        // 左右主鍵與中間的溝槽。
        mainPlate([97, 31, 96.6, 47.5, 101.3, 137, 72, 150, 65.8, 86, 66.3, 50.5], 0, &context)
        mainPlate([115.5, 26, 118.3, 47.5, 119.6, 140, 149.6, 139.5, 155.5, 95, 151, 62, 144.5, 46], 1, &context)
        context.fill(polygon([96.8, 47.5, 118, 47.5, 119.4, 140, 101.5, 137.5]), with: .color(rgb(27, 29, 35)))

        // 左緣的側鍵，由前到後：G8、G7、狙擊 G6、G5、G4。
        sidePlate([65.4, 50, 65.4, 85, 52.5, 87], 7, &context)
        sidePlate([52, 89, 65.6, 87, 67, 94, 54, 97], 6, &context)
        sidePlate([49.2, 99, 54, 98.4, 55, 108, 51, 110], 5, &context)
        sidePlate([51.6, 112, 57, 111.5, 63.5, 146, 56.5, 147], 4, &context)
        sidePlate([57, 149.5, 64, 148.5, 67, 165, 61, 167.5], 3, &context)
        context.stroke(body, with: .color(rgb(112, 118, 130)), style: round)

        // 滾輪、左右撥、不能設定的滾輪模式鍵，以及後面的 G9。
        context.fill(Path(roundedRect: CGRect(x: 101.5, y: 61, width: 14, height: 43), cornerRadius: 5), with: .color(rgb(14, 15, 19)))
        key(CGRect(x: 103, y: 63.5, width: 11, height: 38), 4.5, 2, rgb(166, 172, 182), &context)
        var ticks = Path()
        for y in stride(from: CGFloat(67), to: 99, by: 3.6) {
            ticks.move(to: at(104.5, y))
            ticks.addLine(to: at(112.5, y))
        }
        context.stroke(ticks, with: .color(rgb(34, 37, 44, alpha: highlight == 2 ? 160 : 120)), lineWidth: 0.9)
        context.fill(polygon([100.8, 71.5, 100.8, 80.5, 98, 76]), with: .color(highlight == 10 ? accent : rgb(176, 182, 194)))
        context.fill(polygon([116.2, 71.5, 116.2, 80.5, 118.8, 76]), with: .color(highlight == 9 ? accent : rgb(176, 182, 194)))
        key(CGRect(x: 103.6, y: 107, width: 13, height: 11), 2.5, -1, rgb(48, 51, 59), &context)
        key(CGRect(x: 104, y: 122.5, width: 13, height: 14.5), 2.5, 8, rgb(92, 97, 108), &context)
    }

    private static func drawBadges(_ context: inout GraphicsContext, spots: [Spot], highlight: Int?) {
        let accent = Color.accentColor
        for spot in spots {
            let on = spot.index == highlight
            var line = Path()
            line.move(to: spot.badge)
            line.addLine(to: spot.target)
            context.stroke(line, with: .color(on ? accent : accent.opacity(150.0 / 255)), lineWidth: on ? 1.4 : 0.8)
            context.fill(Path(ellipseIn: CGRect(x: spot.target.x - 1.7, y: spot.target.y - 1.7, width: 3.4, height: 3.4)),
                         with: .color(on ? accent : rgb(120, 175, 255)))
            let circle = Path(ellipseIn: CGRect(x: spot.badge.x - badgeRadius, y: spot.badge.y - badgeRadius,
                                                width: badgeRadius * 2, height: badgeRadius * 2))
            context.fill(circle, with: .color(on ? accent : .white))
            context.stroke(circle, with: .color(accent), lineWidth: 1.2)
            context.draw(Text(verbatim: "\(spot.index + 1)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(on ? .white : accent),
                         at: spot.badge)
        }
    }
}
