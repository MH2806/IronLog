import SwiftUI

enum Palette {
    static let bg = Color(red: 0.071, green: 0.075, blue: 0.094)
    static let card = Color(red: 0.125, green: 0.133, blue: 0.157)
    static let cardHi = Color(red: 0.19, green: 0.2, blue: 0.235)
    static let stroke = Color.white.opacity(0.07)
    static let text2 = Color.white.opacity(0.58)
    static let text3 = Color.white.opacity(0.38)
    static let blue = Color(red: 0.30, green: 0.55, blue: 1.0)
    static let blueSoft = Color(red: 0.30, green: 0.55, blue: 1.0).opacity(0.16)
    static let green = Color(red: 0.19, green: 0.80, blue: 0.54)
    static let orange = Color(red: 1.0, green: 0.54, blue: 0.24)
    static let purple = Color(red: 0.64, green: 0.40, blue: 1.0)
    static let red = Color(red: 0.95, green: 0.33, blue: 0.36)
    static let yellow = Color(red: 1.0, green: 0.78, blue: 0.25)
    static let muscleBase = Color(red: 0.22, green: 0.235, blue: 0.28)
}

// MARK: - Containers

struct CardStyle: ViewModifier {
    var padding: CGFloat = 18
    var radius: CGFloat = 24
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
    }
}

extension View {
    func card(padding: CGFloat = 18, radius: CGFloat = 24) -> some View { modifier(CardStyle(padding: padding, radius: radius)) }

    /// Standard dark scrolling screen background.
    func screenBackground() -> some View {
        background(Palette.bg.ignoresSafeArea())
    }
}

struct ScreenHeader<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 36, weight: .bold))
                if let subtitle { Text(subtitle).font(.subheadline.weight(.medium)).foregroundStyle(Palette.text2) }
            }
            Spacer()
            trailing()
        }
        .padding(.top, 8)
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = { EmptyView() }
    }
}

struct SquareIconButton: View {
    let icon: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.title3.weight(.semibold)).foregroundStyle(Palette.blue)
                .frame(width: 52, height: 52)
                .background(Palette.blueSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Palette.blue.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct SectionTitle: View {
    let title: String
    var action: String? = nil
    var onTap: (() -> Void)? = nil
    var body: some View {
        HStack {
            Text(title.uppercased()).font(.footnote.weight(.semibold)).tracking(3).foregroundStyle(Palette.text2)
            Spacer()
            if let action {
                Button { onTap?() } label: {
                    HStack(spacing: 2) { Text(action); Image(systemName: "chevron.right").font(.caption.bold()) }
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.blue)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 10)
    }
}

/// Pill-shaped segmented control, like the top tabs in Stronger.
struct PillTabs<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selection: T
    var body: some View {
        HStack(spacing: 4) {
            ForEach(options.indices, id: \.self) { i in
                let isOn = options[i].0 == selection
                Button {
                    withAnimation(.snappy(duration: 0.25)) { selection = options[i].0 }
                } label: {
                    Text(options[i].1).font(.subheadline.weight(.semibold))
                        .foregroundStyle(isOn ? .white : Palette.text2)
                        .frame(maxWidth: .infinity).padding(.vertical, 11)
                        .background {
                            if isOn {
                                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.cardHi)
                                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
    }
}

/// Horizontal row of selectable chips.
struct ChipBar<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selection: T
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(options.indices, id: \.self) { i in
                    Chip(text: options[i].1, selected: options[i].0 == selection) { selection = options[i].0 }
                }
            }
        }
    }
}

struct Chip: View {
    let text: String
    var selected = false
    var action: () -> Void = {}
    var body: some View {
        Button(action: action) {
            Text(text).font(.subheadline.weight(.semibold))
                .foregroundStyle(selected ? Palette.blue : Palette.text2)
                .padding(.horizontal, 16).padding(.vertical, 9)
                .background(selected ? Palette.blueSoft : Palette.card, in: Capsule())
                .overlay(Capsule().stroke(selected ? Palette.blue.opacity(0.7) : Palette.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct Tag: View {
    let text: String
    var color: Color = Palette.blue
    var body: some View {
        Text(text).font(.caption.weight(.bold)).tracking(1).foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

struct PillBadge: View {
    let icon: String
    let text: String
    var color: Color = Palette.blue
    var body: some View {
        Label(text, systemImage: icon).font(.caption.weight(.bold)).foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(color.opacity(0.16), in: Capsule())
    }
}

// MARK: - Data viz

struct RingGauge<Center: View>: View {
    let progress: Double
    var color: Color = Palette.green
    var lineWidth: CGFloat = 8
    @ViewBuilder var center: () -> Center
    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.18), lineWidth: lineWidth)
            Circle().trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            center()
        }
    }
}

struct ProgressLine: View {
    let fraction: Double
    var color: Color = Palette.green
    var height: CGFloat = 8
    var marker: Double? = nil
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule().fill(color).frame(width: max(height, g.size.width * min(max(fraction, 0), 1)))
                if let marker {
                    RoundedRectangle(cornerRadius: 1).fill(Color.white.opacity(0.7))
                        .frame(width: 3, height: height + 8)
                        .offset(x: g.size.width * min(max(marker, 0), 1) - 1.5)
                }
            }
        }
        .frame(height: height)
    }
}

struct Sparkline: View {
    let values: [Double]
    var color: Color = Palette.blue
    var body: some View {
        GeometryReader { g in
            let pts = points(in: g.size)
            if pts.count > 1 {
                ZStack {
                    Path { p in
                        p.move(to: CGPoint(x: pts[0].x, y: g.size.height))
                        for pt in pts { p.addLine(to: pt) }
                        p.addLine(to: CGPoint(x: pts.last!.x, y: g.size.height))
                        p.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [color.opacity(0.35), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                    Path { p in
                        p.move(to: pts[0])
                        for pt in pts.dropFirst() { p.addLine(to: pt) }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    Circle().fill(color).frame(width: 7, height: 7).position(pts.last!)
                }
            }
        }
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard values.count > 1, let lo = values.min(), let hi = values.max() else { return [] }
        let span = max(hi - lo, 0.0001)
        return values.enumerated().map { i, v in
            CGPoint(x: size.width * CGFloat(i) / CGFloat(values.count - 1),
                    y: 4 + (size.height - 8) * CGFloat(1 - (v - lo) / span))
        }
    }
}

struct IconTile: View {
    let icon: String
    var color: Color = Palette.blue
    var size: CGFloat = 52
    var body: some View {
        Image(systemName: icon).font(.system(size: size * 0.4, weight: .semibold)).foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
    }
}

struct StatCard: View {
    let icon: String
    var color: Color = Palette.blue
    let value: String
    let label: String
    var delta: String? = nil
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            IconTile(icon: icon, color: color, size: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.title2.bold()).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                Text(label).font(.subheadline.weight(.medium)).foregroundStyle(Palette.text2)
                if let delta {
                    Label(delta, systemImage: "arrow.up").font(.caption.weight(.semibold)).foregroundStyle(Palette.green)
                }
            }
            Spacer(minLength: 0)
        }
        .card(padding: 14, radius: 22)
    }
}

extension Double {
    /// 524200 → "524.2K"
    var compact: String {
        switch abs(self) {
        case 1_000_000...: return (self / 1_000_000).formatted(.number.precision(.fractionLength(0...1))) + "M"
        case 10_000...: return (self / 1_000).formatted(.number.precision(.fractionLength(0...1))) + "K"
        default: return Int(self).formatted()
        }
    }
}

extension Date {
    var relativeDay: String {
        let cal = Calendar.current
        if cal.isDateInToday(self) { return "Today" }
        if cal.isDateInYesterday(self) { return "Yesterday" }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: self), to: cal.startOfDay(for: .now)).day ?? 0
        if days < 7 { return "\(days)d ago" }
        return formatted(.dateTime.day().month(.abbreviated))
    }
}
