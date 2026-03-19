import SwiftUI

enum Palette {
    static let ferrariRed = Color(red: 0.80, green: 0.07, blue: 0.13)
    static let ferrariShadow = Color(red: 0.39, green: 0.03, blue: 0.08)
    static let redGlow = Color(red: 0.96, green: 0.32, blue: 0.22)
    static let accentRed = Color(red: 1.00, green: 0.23, blue: 0.19)
    static let ink = Color(red: 0.12, green: 0.08, blue: 0.08)
    static let cocoa = Color(red: 0.34, green: 0.23, blue: 0.21)
    static let ivory = Color(red: 0.98, green: 0.94, blue: 0.89)
    static let workspace = Color(red: 0.96, green: 0.96, blue: 0.97)
    static let panel = Color.white
    static let panelAlt = Color(red: 0.97, green: 0.98, blue: 0.99)
    static let pill = Color(red: 0.94, green: 0.95, blue: 0.97)
    static let surfaceBorder = Color.black.opacity(0.08)
    static let hoverBackground = Color(red: 0.95, green: 0.96, blue: 0.98)
    static let success = Color(red: 0.09, green: 0.64, blue: 0.29)
    static let successBackground = Color(red: 0.90, green: 0.97, blue: 0.92)
    static let danger = Color(red: 0.69, green: 0.20, blue: 0.13)
    static let dangerBackground = Color(red: 0.99, green: 0.92, blue: 0.91)
}

enum Layout {
    static let maxContentWidth: CGFloat = 1_320
    static let screenPadding: CGFloat = 16
    static let sectionPadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 14
    static let innerSpacing: CGFloat = 12
    static let insetPadding: CGFloat = 14
    static let cardCorner: CGFloat = 14
    static let innerCorner: CGFloat = 14
    static let sidePanelWidth: CGFloat = 260
}

struct SectionCard<Content: View>: View {
    let content: Content
    let padding: CGFloat

    init(padding: CGFloat = Layout.sectionPadding, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(Palette.panel, in: RoundedRectangle(cornerRadius: Layout.cardCorner, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Layout.cardCorner, style: .continuous)
                    .stroke(Palette.surfaceBorder, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.05), radius: 18, y: 8)
    }
}

struct InsetPanel<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Layout.insetPadding)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: Layout.innerCorner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Layout.innerCorner, style: .continuous)
                .stroke(Palette.surfaceBorder, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.04), radius: 12, y: 6)
    }
}

struct BrandedTextField: View {
    @Binding var text: String
    let placeholder: String
    let width: CGFloat?
    let fontSize: CGFloat
    let fontWeight: Font.Weight
    let compact: Bool

    init(
        text: Binding<String>,
        placeholder: String,
        width: CGFloat? = nil,
        fontSize: CGFloat,
        fontWeight: Font.Weight,
        compact: Bool = false
    ) {
        self._text = text
        self.placeholder = placeholder
        self.width = width
        self.fontSize = fontSize
        self.fontWeight = fontWeight
        self.compact = compact
    }

    var body: some View {
        let resolvedFontSize = compact ? max(16, fontSize - 4) : fontSize

        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: resolvedFontSize, weight: fontWeight, design: .rounded))
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, compact ? 14 : 13)
            .frame(width: width, height: compact ? 46 : 44, alignment: .leading)
            .background(Color.white.opacity(0.97), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Palette.surfaceBorder, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.03), radius: compact ? 10 : 8, y: compact ? 4 : 3)
    }
}

struct SummaryCard: View {
    let title: String
    let value: String
    let tint: Color
    let isProminent: Bool
    let compact: Bool

    init(title: String, value: String, tint: Color, isProminent: Bool = false, compact: Bool = false) {
        self.title = title
        self.value = value
        self.tint = tint
        self.isProminent = isProminent
        self.compact = compact
    }

    var body: some View {
        let titleFontSize: CGFloat = compact ? 12 : 13
        let valueFontSize: CGFloat = compact ? (isProminent ? 28 : 20) : (isProminent ? 32 : 23)
        let paddingValue: CGFloat = compact ? (isProminent ? 15 : 13) : (isProminent ? 18 : 16)

        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: titleFontSize, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.cocoa)

            Text(value)
                .font(.system(size: valueFontSize, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(paddingValue)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isProminent ? tint.opacity(0.18) : Palette.surfaceBorder, lineWidth: isProminent ? 1.5 : 1)
        }
        .shadow(color: .black.opacity(0.05), radius: isProminent ? 18 : 14, y: isProminent ? 8 : 6)
    }
}

struct StatPill: View {
    let title: String
    let value: String
    let foreground: Color
    let background: Color
    let compact: Bool

    init(
        title: String,
        value: String,
        foreground: Color = Palette.ink,
        background: Color = Palette.pill,
        compact: Bool = false
    ) {
        self.title = title
        self.value = value
        self.foreground = foreground
        self.background = background
        self.compact = compact
    }

    var body: some View {
        let titleFontSize: CGFloat = compact ? 10 : 11
        let valueFontSize: CGFloat = compact ? 14 : 15

        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: titleFontSize, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.cocoa)
            Text(value)
                .font(.system(size: valueFontSize, weight: .bold, design: .rounded))
                .foregroundStyle(foreground)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(background, in: Capsule())
        .overlay {
            Capsule()
                .stroke(Palette.surfaceBorder.opacity(0.5), lineWidth: 0.8)
        }
    }
}

struct DetailRow: View {
    let title: String
    let subtitle: String
    let value: String
    let tint: Color
    let compact: Bool

    init(title: String, subtitle: String, value: String, tint: Color, compact: Bool = false) {
        self.title = title
        self.subtitle = subtitle
        self.value = value
        self.tint = tint
        self.compact = compact
    }

    var body: some View {
        let titleFontSize: CGFloat = compact ? 13 : 14
        let subtitleFontSize: CGFloat = compact ? 11 : 12
        let valueFontSize: CGFloat = compact ? 17 : 19
        let minHeight: CGFloat = compact ? 76 : 96

        VStack(alignment: .leading, spacing: 7) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: titleFontSize, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.ink)
                Text(subtitle)
                    .font(.system(size: subtitleFontSize, weight: .medium, design: .rounded))
                    .foregroundStyle(Palette.cocoa)
            }

            Text(value)
                .font(.system(size: valueFontSize, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
        .padding(compact ? 12 : 14)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: Layout.innerCorner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Layout.innerCorner, style: .continuous)
                .stroke(Palette.surfaceBorder, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.05), radius: compact ? 14 : 18, y: compact ? 6 : 8)
    }
}

struct ComparisonBarRow: View {
    let title: String
    let minutes: Double
    let tint: Color
    let scaleMinutes: Double
    let minutesLabel: String
    let compact: Bool

    init(
        title: String,
        minutes: Double,
        tint: Color,
        scaleMinutes: Double,
        minutesLabel: String,
        compact: Bool = false
    ) {
        self.title = title
        self.minutes = minutes
        self.tint = tint
        self.scaleMinutes = scaleMinutes
        self.minutesLabel = minutesLabel
        self.compact = compact
    }

    var body: some View {
        let labelFontSize: CGFloat = compact ? 11 : 12
        let barHeight: CGFloat = compact ? 8 : 10

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: labelFontSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.cocoa)

                Spacer()

                Text(minutesLabel)
                    .font(.system(size: labelFontSize, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.ink)
            }

            GeometryReader { proxy in
                let fillRatio = min(1, minutes / max(1, scaleMinutes))

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Palette.pill)

                    Capsule()
                        .fill(tint)
                        .frame(width: max(14, proxy.size.width * CGFloat(fillRatio)))
                }
            }
            .frame(height: barHeight)
        }
    }
}

struct ResultChip: View {
    let delta: Double?
    let formatter: (Double) -> String

    var body: some View {
        let style = Self.style(for: delta, formatter: formatter)

        return Text(style.text)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(style.foreground)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(style.background, in: Capsule())
    }

    private static func style(
        for delta: Double?,
        formatter: (Double) -> String
    ) -> (text: String, foreground: Color, background: Color) {
        guard let delta else {
            return ("Enter numbers", Palette.cocoa, Palette.pill)
        }

        if delta > 0.01 {
            return ("Saves \(formatter(delta))", Palette.success, Palette.successBackground)
        }

        if delta < -0.01 {
            return ("Loses \(formatter(abs(delta)))", Palette.danger, Palette.dangerBackground)
        }

        return ("Neutral", Palette.cocoa, Palette.pill)
    }
}

struct RouteOptionRow: View {
    let title: String
    let duration: String
    let distance: String
    let isSelected: Bool
    let isHovered: Bool
    let compact: Bool

    init(title: String, duration: String, distance: String, isSelected: Bool, isHovered: Bool, compact: Bool = false) {
        self.title = title
        self.duration = duration
        self.distance = distance
        self.isSelected = isSelected
        self.isHovered = isHovered
        self.compact = compact
    }

    var body: some View {
        let titleWidth: CGFloat = compact ? 62 : 70
        let durationWidth: CGFloat = compact ? 64 : 72
        let titleFontSize: CGFloat = compact ? 11 : 12
        let durationFontSize: CGFloat = compact ? 14 : 15
        let distanceFontSize: CGFloat = compact ? 12 : 13
        let rowHeight: CGFloat = compact ? 40 : 42

        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: titleFontSize, weight: .bold, design: .rounded))
                .foregroundStyle(Palette.ink)
                .frame(width: titleWidth, alignment: .leading)

            Text(duration)
                .font(.system(size: durationFontSize, weight: .bold, design: .rounded))
                .foregroundStyle(Palette.ink)
                .frame(width: durationWidth, alignment: .leading)

            Text(distance)
                .font(.system(size: distanceFontSize, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.cocoa)
                .frame(maxWidth: .infinity, alignment: .trailing)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.success)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: rowHeight)
        .padding(.horizontal, 12)
        .background(
            isSelected ? Palette.successBackground : ((isHovered && !isSelected) ? Palette.hoverBackground : Palette.panel),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? Palette.success : Palette.surfaceBorder, lineWidth: isSelected ? 1.6 : 1)
        }
    }
}
