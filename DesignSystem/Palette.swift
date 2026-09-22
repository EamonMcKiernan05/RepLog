import SwiftUI

// Design tokens sampled from the RepCount reference screenshots (plan §5).
// Dark-first; light mode uses system backgrounds with the same accent.
enum Palette {
    /// Page background — pure black in dark, system background in light.
    static var bg: Color {
        Color(uiColor: .systemBackground)
    }

    /// Grouped cards / sheets. #1C1C1D in dark (≈ systemGray6).
    static var card: Color {
        Color(uiColor: UIColor.systemGray6)
    }

    /// Slightly raised control fill (buttons, search fields, segmented).
    static var control: Color {
        Color(uiColor: UIColor.systemGray5)
    }

    /// Teal accent ≈ #58C5D1 — selected tab, actions, timer ring, PRs.
    static let accent = Color(red: 0x58 / 255, green: 0xC5 / 255, blue: 0xD1 / 255)

    static var textPrimary: Color { .primary }
    static var textSecondary: Color { .secondary }
    static var destructive: Color { .red }
    static var success: Color { .green }

    /// Hairline separators inside cards.
    static var separator: Color {
        Color(uiColor: UIColor.separator)
    }
}

enum Typography {
    /// Monospaced digits so weight/rep/timer columns don't jitter.
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static let largeTitle = Font.largeTitle.weight(.heavy)
    static let title = Font.title2.weight(.bold)
    static let value = Font.body.weight(.bold)
    static let label = Font.caption
    static let duration = Font.subheadline
}

extension View {
    /// Inset-grouped card styling used across the app.
    func replogCard() -> some View {
        self
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(.horizontal, 16)
    }
}
