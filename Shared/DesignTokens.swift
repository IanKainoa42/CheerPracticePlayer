import SwiftUI

// MARK: - Color Palette

enum PPColors {
    static let background = Color.black
    static let card = Color(white: 0.10)
    static let cardBorder = Color(white: 0.16)
    static let accentYellow = Color(red: 1.0, green: 0.92, blue: 0.23)     // #FFEB3B
    static let accentOrange = Color(red: 1.0, green: 0.42, blue: 0.21)     // #FF6B35
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.6)
    static let textTertiary = Color.white.opacity(0.35)
    static let destructive = Color(red: 1.0, green: 0.27, blue: 0.27)
    static let success = Color(red: 0.30, green: 0.85, blue: 0.40)
    static let cardHighlight = Color(white: 0.14)

    /// Per-block accent palette in a red → orange → yellow gradient (12 stops).
    /// Used to color-code rep pips, queue rows, and timeline overlays so coaches can
    /// distinguish sections at a glance. Cycles by index — stable for a given session layout.
    static let blockPalette: [Color] = [
        Color(red: 0.90, green: 0.22, blue: 0.21),  // #E53935 red
        Color(red: 0.96, green: 0.32, blue: 0.12),  // #F4511E deep orange
        Color(red: 1.00, green: 0.42, blue: 0.21),  // #FF6B35 orange
        Color(red: 0.98, green: 0.55, blue: 0.00),  // #FB8C00 dark orange
        Color(red: 1.00, green: 0.60, blue: 0.00),  // #FF9800 orange
        Color(red: 1.00, green: 0.65, blue: 0.15),  // #FFA726 light orange
        Color(red: 1.00, green: 0.70, blue: 0.00),  // #FFB300 amber
        Color(red: 1.00, green: 0.76, blue: 0.03),  // #FFC107 amber
        Color(red: 1.00, green: 0.79, blue: 0.16),  // #FFCA28 light amber
        Color(red: 1.00, green: 0.84, blue: 0.31),  // #FFD54F gold
        Color(red: 1.00, green: 0.92, blue: 0.23),  // #FFEB3B yellow
        Color(red: 1.00, green: 0.95, blue: 0.46),  // #FFF176 light yellow
    ]

    static func blockColor(at index: Int) -> Color {
        let palette = blockPalette
        guard !palette.isEmpty else { return accentYellow }
        return palette[((index % palette.count) + palette.count) % palette.count]
    }
}

// MARK: - Typography

enum PPFonts {
    static func hero(_ size: CGFloat = 34) -> Font {
        .system(size: size, weight: .black, design: .default)
    }

    static func title(_ size: CGFloat = 22) -> Font {
        .system(size: size, weight: .bold)
    }

    static func headline(_ size: CGFloat = 17) -> Font {
        .system(size: size, weight: .semibold)
    }

    static func body(_ size: CGFloat = 16) -> Font {
        .system(size: size, weight: .regular)
    }

    static func mono(_ size: CGFloat = 13) -> Font {
        .system(size: size, weight: .medium, design: .monospaced)
    }

    static func monoLarge(_ size: CGFloat = 28) -> Font {
        .system(size: size, weight: .bold, design: .monospaced)
    }

    static func caption(_ size: CGFloat = 12) -> Font {
        .system(size: size, weight: .medium)
    }
}

// MARK: - Card Modifier

struct PPCardStyle: ViewModifier {
    var filled: Bool = true
    var highlighted: Bool = false

    func body(content: Content) -> some View {
        content
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(highlighted ? PPColors.cardHighlight : (filled ? PPColors.card : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(PPColors.cardBorder, lineWidth: 1)
            )
    }
}

extension View {
    func ppCard(filled: Bool = true, highlighted: Bool = false) -> some View {
        modifier(PPCardStyle(filled: filled, highlighted: highlighted))
    }
}

// MARK: - Pill Tag

struct PPPill: View {
    let text: String
    var color: Color = PPColors.accentYellow
    var textColor: Color = .black

    var body: some View {
        Text(text.uppercased())
            .font(PPFonts.caption(11))
            .fontWeight(.bold)
            .tracking(0.5)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(color))
            .foregroundStyle(textColor)
    }
}

// MARK: - Primary CTA Button

struct PPPrimaryButton: View {
    let title: String
    let icon: String?
    let action: () -> Void

    init(_ title: String, icon: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .bold))
                }
                Text(title.uppercased())
                    .font(PPFonts.headline(16))
                    .tracking(1.2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(PPColors.accentYellow)
            .foregroundStyle(.black)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .medium), trigger: UUID())
    }
}

// MARK: - Section Header

struct PPSectionHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(PPFonts.caption(12))
                .tracking(1.5)
                .foregroundStyle(PPColors.textTertiary)

            if let subtitle {
                Text(subtitle)
                    .font(PPFonts.body(14))
                    .foregroundStyle(PPColors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Metric Card

struct PPMetricCard: View {
    let label: String
    let value: String
    var icon: String? = nil
    var accentColor: Color = PPColors.accentYellow

    var body: some View {
        VStack(spacing: 8) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(accentColor)
            }

            Text(value)
                .font(PPFonts.monoLarge())
                .foregroundStyle(PPColors.textPrimary)

            Text(label.uppercased())
                .font(PPFonts.caption(11))
                .tracking(1.0)
                .foregroundStyle(PPColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .ppCard()
    }
}

// MARK: - Diagnostic Row

struct PPDiagnosticRow: View {
    let icon: String
    let label: String
    var value: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(PPColors.textTertiary)
                    .frame(width: 20)

                Text(label)
                    .font(PPFonts.mono(13))
                    .foregroundStyle(PPColors.textSecondary)

                Spacer()

                if let value {
                    Text(value)
                        .font(PPFonts.mono(13))
                        .foregroundStyle(PPColors.textTertiary)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(PPColors.textTertiary)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Step Progress

struct PPStepProgress: View {
    let steps: [String]
    let activeIndex: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                if index > 0 {
                    Rectangle()
                        .fill(index <= activeIndex ? PPColors.accentYellow : PPColors.cardBorder)
                        .frame(height: 2)
                        .frame(maxWidth: .infinity)
                }

                VStack(spacing: 6) {
                    Circle()
                        .fill(index <= activeIndex ? PPColors.accentYellow : PPColors.cardBorder)
                        .frame(width: 10, height: 10)
                        .overlay {
                            if index < activeIndex {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 6, weight: .black))
                                    .foregroundStyle(.black)
                            }
                        }

                    Text(step)
                        .font(PPFonts.caption(10))
                        .tracking(0.5)
                        .foregroundStyle(index <= activeIndex ? PPColors.textPrimary : PPColors.textTertiary)
                }
            }
        }
        .padding(.horizontal, 8)
    }
}
