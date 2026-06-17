import SwiftUI
import UIKit

/// Central design tokens. One place for colour, type, spacing and radius so the whole
/// app stays visually cohesive. Colours are built to adapt to light/dark automatically.
enum Theme {
    // MARK: Colour
    static let accent = Color(hex: 0x4F46E5)        // indigo — primary brand
    static let accentSoft = Color(hex: 0x6366F1)
    static let profit = Color(hex: 0x16A34A)        // green — gains
    static let loss = Color(hex: 0xDC2626)          // red — losses
    static let gold = Color(hex: 0xB8860B)          // money accents

    static let background = Color(.systemGroupedBackground)
    static let surface = Color(.secondarySystemGroupedBackground)
    static let surfaceRaised = Color(.tertiarySystemGroupedBackground)
    static let separator = Color(.separator)
    static let textPrimary = Color(.label)
    static let textSecondary = Color(.secondaryLabel)

    // MARK: Spacing
    static let spacing1: CGFloat = 4
    static let spacing2: CGFloat = 8
    static let spacing3: CGFloat = 12
    static let spacing4: CGFloat = 16
    static let spacing5: CGFloat = 24
    static let spacing6: CGFloat = 32

    // MARK: Radius
    static let radiusSmall: CGFloat = 8
    static let radiusMedium: CGFloat = 14
    static let radiusLarge: CGFloat = 22

    // MARK: Gradient
    static var brandGradient: LinearGradient {
        LinearGradient(colors: [accent, accentSoft],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

extension Font {
    static let screenTitle = Font.system(.largeTitle, design: .rounded).weight(.bold)
    static let cardTitle = Font.system(.headline, design: .rounded).weight(.semibold)
    static let stat = Font.system(.title2, design: .rounded).weight(.bold)
    static let mono = Font.system(.subheadline, design: .monospaced).weight(.medium)
}
