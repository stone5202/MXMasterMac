import SwiftUI

// 「按鈕」頁的滑鼠示意圖：自繪的俯視輪廓，加上對應清單列的編號標記。
// 設計座標沿用 Windows 版（296×372，內容位移 36,24）。標記位置是示意，未逐一對照實體校正。
struct MouseDiagram: View {
    @Binding var highlight: Int?

    private struct Spot: Identifiable {
        let rows: [Int]
        let target: CGPoint
        let badge: CGPoint
        var id: Int { rows[0] }
        var label: String { rows.map { "\($0 + 1)" }.joined(separator: "·") }
    }

    // 列順序同 MouseInput.allCases：0 中鍵、1 手勢鍵、2/3 側鍵、4/5 拇指滾輪、6 Actions Ring。
    private static let spots: [Spot] = [
        Spot(rows: [0], target: CGPoint(x: 144, y: 78), badge: CGPoint(x: 246, y: 78)),
        Spot(rows: [1], target: CGPoint(x: 62, y: 125), badge: CGPoint(x: -14, y: 112)),
        Spot(rows: [4, 5], target: CGPoint(x: 66, y: 152), badge: CGPoint(x: -10, y: 143)),
        Spot(rows: [2], target: CGPoint(x: 68, y: 192), badge: CGPoint(x: -14, y: 246)),
        Spot(rows: [3], target: CGPoint(x: 70, y: 207), badge: CGPoint(x: -14, y: 276)),
        Spot(rows: [6], target: CGPoint(x: 40, y: 184), badge: CGPoint(x: 40, y: 184)),
    ]

    private static let design = CGSize(width: 296, height: 372)
    private static let offset = CGPoint(x: 36, y: 24)

    var body: some View {
        GeometryReader { geometry in
            let fit = min(geometry.size.width / Self.design.width, geometry.size.height / Self.design.height)
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    context.scaleBy(x: fit, y: fit)
                    context.translateBy(x: Self.offset.x, y: Self.offset.y)
                    Self.drawMouse(&context)
                    for spot in Self.spots where spot.badge != spot.target {
                        var leader = Path()
                        let edge = spot.badge.x + (spot.target.x > spot.badge.x ? 11 : -11)
                        leader.move(to: CGPoint(x: edge, y: spot.badge.y))
                        leader.addLine(to: spot.target)
                        context.stroke(leader, with: .color(Color.accentColor.opacity(0.65)), lineWidth: 1.1)
                        context.fill(Path(ellipseIn: CGRect(x: spot.target.x - 2.6, y: spot.target.y - 2.6, width: 5.2, height: 5.2)),
                                     with: .color(.accentColor))
                    }
                }
                ForEach(Self.spots) { spot in
                    let active = highlight.map { spot.rows.contains($0) } ?? false
                    Text(spot.label)
                        .font(.system(size: 11 * fit, weight: .bold, design: .rounded))
                        .foregroundStyle(active ? Color.white : Color.accentColor)
                        .frame(width: (spot.rows.count > 1 ? 36 : 22) * fit, height: 22 * fit)
                        .background(Capsule().fill(active ? Color.accentColor : Color(nsColor: .controlBackgroundColor)))
                        .overlay(Capsule().strokeBorder(Color.accentColor, lineWidth: 1.6 * fit))
                        .position(x: (spot.badge.x + Self.offset.x) * fit, y: (spot.badge.y + Self.offset.y) * fit)
                        .onHover { inside in
                            if inside { highlight = spot.rows[0] } else if active { highlight = nil }
                        }
                }
            }
        }
        .aspectRatio(Self.design.width / Self.design.height, contentMode: .fit)
    }

    // MARK: - 繪製

    private static func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> Color {
        Color(.sRGB, red: r / 255, green: g / 255, blue: b / 255, opacity: a)
    }

    // 通過所有點的平滑曲線（cardinal spline），closed 表示頭尾相接。
    private static func curve(_ points: [CGPoint], tension: CGFloat, closed: Bool) -> Path {
        var path = Path()
        let count = points.count
        guard count > 1 else { return path }
        func point(_ index: Int) -> CGPoint {
            closed ? points[(index + count) % count] : points[min(max(index, 0), count - 1)]
        }
        func tangent(_ index: Int) -> CGPoint {
            let next = point(index + 1), previous = point(index - 1)
            return CGPoint(x: tension * (next.x - previous.x), y: tension * (next.y - previous.y))
        }
        path.move(to: points[0])
        for index in 0..<(closed ? count : count - 1) {
            let from = point(index), to = point(index + 1)
            let t0 = tangent(index), t1 = tangent(index + 1)
            path.addCurve(to: to,
                          control1: CGPoint(x: from.x + t0.x / 3, y: from.y + t0.y / 3),
                          control2: CGPoint(x: to.x - t1.x / 3, y: to.y - t1.y / 3))
        }
        if closed { path.closeSubpath() }
        return path
    }

    private static func points(_ values: [CGFloat]) -> [CGPoint] {
        stride(from: 0, to: values.count - 1, by: 2).map { CGPoint(x: values[$0], y: values[$0 + 1]) }
    }

    private static func drawMouse(_ context: inout GraphicsContext) {
        let seam = rgb(24, 26, 32, 0.6)
        let slot = rgb(26, 28, 34)
        let part = rgb(104, 108, 120)
        let steel = Gradient(colors: [rgb(232, 234, 240), rgb(150, 154, 166), rgb(214, 217, 224)])
        let ridge = rgb(40, 44, 56, 0.43)

        // 外殼：前緣方正、左側筆直，拇指托在下方向外展開。
        let shell = curve(points([67, 24, 73, 12, 100, 9, 135, 15, 170, 23, 197, 38, 206, 56, 212, 110,
                                  220, 180, 218, 250, 200, 300, 170, 320, 140, 325, 110, 316, 86, 294, 68, 276,
                                  45, 275, 20, 260, 6, 233, 5, 208, 16, 168, 31, 141, 50, 133, 63, 130,
                                  65, 90, 66, 50]), tension: 0.35, closed: true)
        context.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(0.28), radius: 12, x: 0, y: 8))
            layer.fill(shell, with: .linearGradient(Gradient(colors: [rgb(96, 99, 108), rgb(38, 40, 46)]),
                                                    startPoint: CGPoint(x: 30, y: 0), endPoint: CGPoint(x: 200, y: 334)))
        }

        // 拇指托與它的波紋。
        let rest = curve(points([23, 168, 35, 146, 60, 140, 68, 200, 70, 268, 50, 270, 26, 257, 12, 231, 11, 208]),
                         tension: 0.3, closed: true)
        context.fill(rest, with: .color(rgb(46, 48, 55)))
        context.drawLayer { layer in
            layer.clip(to: rest)
            var radius: CGFloat = 14
            while radius < 150 {
                layer.stroke(Path(ellipseIn: CGRect(x: 60 - radius, y: 162 - radius, width: radius * 2, height: radius * 2)),
                             with: .color(.white.opacity(0.10)), lineWidth: 1)
                radius += 9
            }
        }
        context.stroke(rest, with: .color(seam), lineWidth: 1.2)
        context.stroke(shell, with: .color(rgb(30, 32, 38)), lineWidth: 1.4)

        // 左右主鍵的分界，以及主鍵結束的那條線。
        var lines = Path()
        lines.move(to: CGPoint(x: 135, y: 16)); lines.addLine(to: CGPoint(x: 135, y: 50))
        lines.move(to: CGPoint(x: 135, y: 107)); lines.addLine(to: CGPoint(x: 135, y: 121))
        context.stroke(lines, with: .color(seam), lineWidth: 1.3)
        context.stroke(curve(points([66, 132, 96, 124, 140, 121, 213, 113]), tension: 0.4, closed: false),
                       with: .color(seam), lineWidth: 1.3)
        context.stroke(curve(points([207, 196, 211, 250, 199, 292]), tension: 0.5, closed: false),
                       with: .color(.white.opacity(0.17)), lineWidth: 1.1)

        // 滾輪、滾輪模式鍵、狀態燈。
        context.fill(Path(roundedRect: CGRect(x: 122, y: 51, width: 27, height: 55), cornerRadius: 5), with: .color(slot))
        context.fill(Path(roundedRect: CGRect(x: 127, y: 56, width: 17, height: 45), cornerRadius: 4),
                     with: .linearGradient(steel, startPoint: CGPoint(x: 127, y: 0), endPoint: CGPoint(x: 144, y: 0)))
        var ridges = Path()
        for y in stride(from: 61.0, to: 99.0, by: 4.0) {
            ridges.move(to: CGPoint(x: 128, y: y)); ridges.addLine(to: CGPoint(x: 143, y: y))
        }
        let mode = Path(roundedRect: CGRect(x: 127, y: 130, width: 17, height: 20), cornerRadius: 4)
        context.fill(mode, with: .color(part))
        context.stroke(mode, with: .color(seam), lineWidth: 1.3)
        context.fill(Path(ellipseIn: CGRect(x: 133.2, y: 158.5, width: 4, height: 4)), with: .color(rgb(70, 208, 146)))

        // 左側由前到後：手勢鍵、拇指滾輪、兩顆側鍵。
        context.fill(Path(roundedRect: CGRect(x: 60, y: 116, width: 8, height: 18), cornerRadius: 4), with: .color(part))
        context.fill(Path(roundedRect: CGRect(x: 63, y: 142, width: 14, height: 39), cornerRadius: 3.5),
                     with: .linearGradient(steel, startPoint: CGPoint(x: 63, y: 0), endPoint: CGPoint(x: 77, y: 0)))
        for y in stride(from: 146.0, to: 180.0, by: 4.0) {
            ridges.move(to: CGPoint(x: 64, y: y)); ridges.addLine(to: CGPoint(x: 76, y: y))
        }
        context.stroke(ridges, with: .color(ridge), lineWidth: 1)
        var divider = Path()
        divider.move(to: CGPoint(x: 63, y: 161.5)); divider.addLine(to: CGPoint(x: 77, y: 161.5))
        context.stroke(divider, with: .color(seam), lineWidth: 1.3)
        var forward = Path()
        forward.addLines(points([64, 185, 77, 185, 75, 199, 66, 199])); forward.closeSubpath()
        var back = Path()
        back.addLines(points([66.5, 201, 74.5, 201, 72, 216])); back.closeSubpath()
        context.fill(forward, with: .color(part))
        context.fill(back, with: .color(part))
    }
}
