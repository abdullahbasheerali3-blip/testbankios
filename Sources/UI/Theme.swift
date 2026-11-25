import SwiftUI

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}

/// Brand palette. Navy -> royal blue hero gradient with teal + amber accents.
enum Brand {
    static let navy = Color(hex: 0x071A3F)
    static let navyMid = Color(hex: 0x0E2F7A)
    static let royal = Color(hex: 0x1B4FD8)
    static let sky = Color(hex: 0x4C8DFF)
    static let teal = Color(hex: 0x12B5A6)
    static let amber = Color(hex: 0xFFB020)
    static let rose = Color(hex: 0xE5484D)
    static let violet = Color(hex: 0x7C5CFF)
    static let mint = Color(hex: 0x16A36B)

    static let hero = LinearGradient(colors: [navy, navyMid, royal], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let heroVertical = LinearGradient(colors: [navy, navyMid, royal], startPoint: .top, endPoint: .bottom)
}

/// Material-3-style light colour scheme from the Android app.
enum Theme {
    static let primary = Brand.royal
    static let primaryContainer = Color(hex: 0xE3EBFF)
    static let onPrimaryContainer = Color(hex: 0x0A2463)
    static let secondary = Brand.teal
    static let secondaryContainer = Color(hex: 0xD5F5F1)
    static let tertiary = Brand.mint
    static let tertiaryContainer = Color(hex: 0xDDF5E9)
    static let onTertiaryContainer = Color(hex: 0x053B25)
    static let error = Color(hex: 0xD92D3A)
    static let errorContainer = Color(hex: 0xFFE4E6)
    static let onErrorContainer = Color(hex: 0x5C0A12)
    static let surface = Color.white
    static let onSurface = Color(hex: 0x0F172A)
    static let onSurfaceVariant = Color(hex: 0x5B6678)
    static let surfaceLow = Color(hex: 0xF7F9FD)
    static let surfaceContainer = Color(hex: 0xF1F4FA)
    static let surfaceHigh = Color(hex: 0xEAEFF8)
    static let background = Color(hex: 0xF3F6FC)
    static let outline = Color(hex: 0xC3CCDB)
    static let outlineVariant = Color(hex: 0xE3E8F1)
}

/// Typography scale from the Android theme (sizes in points).
enum AppFont {
    static let displayMedium = Font.system(size: 44, weight: .bold)
    static let displaySmall = Font.system(size: 34, weight: .bold)
    static let headlineLarge = Font.system(size: 30, weight: .bold)
    static let headlineMedium = Font.system(size: 26, weight: .bold)
    static let headlineSmall = Font.system(size: 22, weight: .bold)
    static let titleLarge = Font.system(size: 20, weight: .bold)
    static let titleMedium = Font.system(size: 16, weight: .semibold)
    static let titleSmall = Font.system(size: 14, weight: .semibold)
    static let bodyLarge = Font.system(size: 16)
    static let bodyMedium = Font.system(size: 14)
    static let bodySmall = Font.system(size: 12)
    static let labelLarge = Font.system(size: 15, weight: .semibold)
    static let labelMedium = Font.system(size: 12, weight: .medium)
    static let labelSmall = Font.system(size: 11, weight: .semibold)
}

func statusColor(_ status: String) -> Color {
    switch status.lowercased() {
    case "active", "approved", "completed", "submitted", "received": return Color(hex: 0x16A36B)
    case "frozen", "blocked", "declined", "rejected", "cancelled", "canceled", "failed": return Color(hex: 0xD92D3A)
    default: return Color(hex: 0xB7791F)
    }
}
