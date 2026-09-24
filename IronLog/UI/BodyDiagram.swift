import SwiftUI

// MARK: - Body diagram (IronLog's own line-art, 100 × 220 units per figure)

enum BodySide { case front, back }

private struct Region {
    let muscle: String?          // nil = silhouette
    let points: [CGPoint]
    let smooth: Bool
}

private func pts(_ a: [(CGFloat, CGFloat)]) -> [CGPoint] { a.map { CGPoint(x: $0.0, y: $0.1) } }
private func mirrored(_ p: [CGPoint]) -> [CGPoint] { p.map { CGPoint(x: 100 - $0.x, y: $0.y) }.reversed() }
private func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> [CGPoint] {
    (0..<16).map { i in
        let a = CGFloat(i) / 16 * 2 * .pi
        return CGPoint(x: cx + rx * cos(a), y: cy + ry * sin(a))
    }
}

private enum Anatomy {
    static func pair(_ muscle: String?, _ p: [(CGFloat, CGFloat)], smooth: Bool = true) -> [Region] {
        let l = pts(p)
        return [Region(muscle: muscle, points: l, smooth: smooth), Region(muscle: muscle, points: mirrored(l), smooth: smooth)]
    }

    static let silhouette: [Region] = {
        let parts: [[Region]] = [
            [
            Region(muscle: nil, points: ellipse(50, 12, 8.5, 10.5), smooth: true),
            Region(muscle: nil, points: pts([(45, 20), (55, 20), (56, 31), (44, 31)]), smooth: false),
        ],
            pair(nil, [(50, 30), (43, 30), (35, 33), (29, 38), (30, 47), (33, 56), (34, 70), (35, 86), (35, 98), (38, 104), (50, 106)]),
            pair(nil, [(29, 37), (24, 40), (21, 50), (20, 62), (18, 76), (15, 90), (13, 104), (12, 113), (15, 121), (19, 121),
                     (21, 112), (24, 98), (27, 86), (29, 74), (31, 62), (32, 50)]),
            pair(nil, [(35, 100), (33, 114), (32, 130), (33, 146), (36, 158), (35, 168), (34, 184), (36, 200), (35, 210), (47, 212),
                     (46, 200), (47, 184), (47, 168), (46, 158), (48, 142), (50, 124), (50, 106)]),
        ]
        return parts.flatMap { $0 }
    }()

    static let forearms = pair("forearms", [(21, 79), (18, 89), (15, 101), (16, 110), (20, 108), (24, 96), (27, 84), (25, 78)])

    static let front: [Region] = {
        let parts: [[Region]] = [
            silhouette,
            pair("traps", [(45, 29), (47, 33), (38, 35), (41, 31)]),
            pair("shoulders", [(37, 34), (30, 37), (25, 44), (25, 54), (29, 52), (32, 45), (38, 39)]),
            pair("chest", [(49.5, 37), (39, 37), (33, 44), (33, 52), (38, 57), (45, 58), (49.5, 56)]),
            pair("biceps", [(25, 55), (22, 63), (21, 72), (24, 77), (28, 73), (30, 64), (30, 56)]),
            forearms,
            pair("abs", [(42, 60), (36, 62), (35, 74), (36.5, 88), (41, 96), (42.5, 86)]),
            pair("abs", [(43.5, 60), (49.5, 60), (49.5, 68), (43.5, 68)], smooth: false),
            pair("abs", [(43.5, 69.5), (49.5, 69.5), (49.5, 77.5), (43.5, 77.5)], smooth: false),
            pair("abs", [(43.5, 79), (49.5, 79), (49.5, 87), (43.5, 87)], smooth: false),
            pair("abs", [(43.5, 88.5), (49.5, 88.5), (49.5, 101), (45.5, 97)], smooth: false),
            pair("quadriceps", [(49, 108), (41, 106), (35, 112), (34, 128), (35, 144), (39, 154), (44, 152), (47, 136), (49.5, 118)]),
            pair("calves", [(37, 164), (35, 176), (37, 194), (41, 198), (44, 192), (45, 176), (44, 164)]),
        ]
        return parts.flatMap { $0 }
    }()

    static let back: [Region] = {
        let parts: [[Region]] = [
            silhouette,
            pair("traps", [(50, 23), (46, 27), (36, 33), (41, 37), (46, 46), (50, 64)]),
            pair("shoulders", [(36, 33.5), (29, 37), (25, 45), (26, 52), (31, 47), (37, 40)]),
            pair("lats", [(40, 40), (34, 48), (34, 62), (37, 78), (43, 88), (48, 76), (46, 56), (44, 46)]),
            pair("back", [(49.5, 66), (47, 80), (45, 92), (46, 100), (49.5, 101)]),
            pair("triceps", [(25, 53), (22, 62), (21, 73), (24, 78), (29, 71), (31, 59), (30, 52)]),
            forearms,
            pair("glutes", [(49.5, 101), (41, 101), (36, 108), (36, 120), (41, 125), (49.5, 122)]),
            pair("hamstrings", [(49, 126), (41, 126), (35, 131), (35, 146), (38, 156), (43, 156), (47, 142)]),
            pair("calves", [(36, 160), (34, 171), (36, 187), (41, 193), (45, 187), (46, 172), (44, 161)]),
        ]
        return parts.flatMap { $0 }
    }()
}

private struct RegionShape: Shape {
    let points: [CGPoint]
    let smooth: Bool

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width / 100, rect.height / 220)
        let ox = rect.minX + (rect.width - 100 * s) / 2, oy = rect.minY + (rect.height - 220 * s) / 2
        let p = points.map { CGPoint(x: ox + $0.x * s, y: oy + $0.y * s) }
        var path = Path()
        guard p.count > 2 else { return path }
        path.move(to: p[0])
        if !smooth {
            for q in p.dropFirst() { path.addLine(to: q) }
        } else {
            let n = p.count
            for i in 0..<n {
                let p0 = p[(i - 1 + n) % n], p1 = p[i], p2 = p[(i + 1) % n], p3 = p[(i + 2) % n]
                let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
                let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
                path.addCurve(to: p2, control1: c1, control2: c2)
            }
        }
        path.closeSubpath()
        return path
    }
}

/// One figure. `color` returns the fill for a muscle, or nil for the default.
struct BodyFigure: View {
    let side: BodySide
    var lineWidth: CGFloat = 0.9
    let color: (String) -> Color?

    var body: some View {
        let regions = side == .front ? Anatomy.front : Anatomy.back
        ZStack {
            ForEach(regions.indices, id: \.self) { i in
                let r = regions[i]
                let shape = RegionShape(points: r.points, smooth: r.smooth)
                let fill: Color = r.muscle.flatMap(color) ?? (r.muscle == nil ? Color(white: 0.13) : Palette.muscleBase)
                shape.fill(fill)
                shape.stroke(Color.white.opacity(r.muscle == nil ? 0.85 : 0.55), lineWidth: lineWidth)
            }
        }
        .aspectRatio(100.0 / 220.0, contentMode: .fit)
    }
}

/// Front and back side by side.
struct BodyDiagram: View {
    var spacing: CGFloat = 18
    var lineWidth: CGFloat = 0.9
    let color: (String) -> Color?
    var body: some View {
        HStack(spacing: spacing) {
            BodyFigure(side: .front, lineWidth: lineWidth, color: color)
            BodyFigure(side: .back, lineWidth: lineWidth, color: color)
        }
    }
}

/// Small single-figure tile highlighting one muscle (used for filters).
struct MuscleTile: View {
    let muscle: String
    var selected = false
    var body: some View {
        VStack(spacing: 4) {
            BodyFigure(side: MuscleName.isBack(muscle) ? .back : .front, lineWidth: 0.5) {
                $0 == muscle ? Palette.blue : nil
            }
            .frame(height: 64)
            Text(MuscleName.display(muscle)).font(.caption2.weight(.semibold)).foregroundStyle(selected ? Palette.blue : Palette.text2)
                .lineLimit(1)
        }
        .frame(width: 70, height: 96)
        .background(selected ? Palette.blueSoft : Palette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(selected ? Palette.blue : Palette.stroke, lineWidth: 1))
    }
}

// MARK: - Rank badge

struct Hexagon: Shape {
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY), r = min(rect.width, rect.height) / 2
        var p = Path()
        for i in 0..<6 {
            let a = CGFloat(i) * .pi / 3 - .pi / 2
            let pt = CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

extension StrengthLevel {
    var color: Color { Theme.color(self) }
    var icon: String {
        switch self {
        case .beginner: return "leaf.fill"
        case .novice: return "flame.fill"
        case .intermediate: return "diamond.fill"
        case .advanced: return "triangle.fill"
        case .elite: return "hexagon.fill"
        case .worldClass: return "crown.fill"
        }
    }
    var shortName: String { self == .worldClass ? "World" : name }
}

struct RankBadge: View {
    let level: StrengthLevel
    var tier: Int = 1
    var size: CGFloat = 60
    var dimmed = false
    var glow = false

    var body: some View {
        let c = level.color
        ZStack {
            if glow { Circle().fill(c.opacity(0.35)).frame(width: size * 1.6).blur(radius: size * 0.35) }
            if level >= .advanced {
                HStack(spacing: size * 0.62) {
                    Image(systemName: "chevron.left").font(.system(size: size * 0.32, weight: .black)).foregroundStyle(c.opacity(0.8))
                    Image(systemName: "chevron.right").font(.system(size: size * 0.32, weight: .black)).foregroundStyle(c.opacity(0.8))
                }
            }
            Hexagon().fill(LinearGradient(colors: [c.opacity(0.95), c.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                .frame(width: size, height: size)
            Hexagon().fill(LinearGradient(colors: [Color.white.opacity(0.35), c.opacity(0.6)], startPoint: .top, endPoint: .bottom))
                .frame(width: size * 0.7, height: size * 0.7)
            Hexagon().stroke(Color.white.opacity(0.35), lineWidth: max(1, size * 0.025)).frame(width: size * 0.7, height: size * 0.7)
            VStack(spacing: size * 0.02) {
                Image(systemName: level.icon).font(.system(size: size * 0.2, weight: .bold)).foregroundStyle(.white)
                HStack(spacing: size * 0.02) {
                    ForEach(0..<max(1, min(3, tier)), id: \.self) { _ in
                        Image(systemName: "chevron.up").font(.system(size: size * 0.09, weight: .heavy)).foregroundStyle(.white.opacity(0.9))
                    }
                }
            }
        }
        .frame(width: size * 1.3, height: size * 1.1)
        .saturation(dimmed ? 0.15 : 1)
        .opacity(dimmed ? 0.55 : 1)
    }
}
