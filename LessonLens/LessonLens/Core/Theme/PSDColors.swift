import SwiftUI

// MARK: - PSD Brand Colors

/// Peninsula School District brand color palette
/// Based on PNW nature-inspired branding guide
extension Color {
    // MARK: Primary Palette

    /// Pacific #25424C - Deep teal, used for headings
    static let psdPacific = Color(hex: 0x25424C)

    /// Sea Glass #6CA18A - Medium green, decorative only (fails WCAG on white)
    static let psdSeaGlass = Color(hex: 0x6CA18A)

    /// Darkened Sea Glass #4A7A64 - WCAG AA compliant accent for interactive elements
    static let psdSeaGlassAccessible = Color(hex: 0x4A7A64)

    /// Ocean #2D5F7A - Deep blue
    static let psdOcean = Color(hex: 0x2D5F7A)

    /// Whulge #346780 - Teal-blue, used for next steps and processing states
    static let psdWhulge = Color(hex: 0x346780)

    // MARK: Secondary Palette

    /// Meadow #5D9068 - Muted green, used for strengths/success
    static let psdMeadow = Color(hex: 0x5D9068)

    /// Sea Foam #E8F0E8 - Light green tint
    static let psdSeaFoam = Color(hex: 0xE8F0E8)

    /// Skylight #FFFAEC - Warm off-white, page backgrounds
    static let psdSkylight = Color(hex: 0xFFFAEC)

    /// Driftwood #D7CDBE - Warm tan
    static let psdDriftwood = Color(hex: 0xD7CDBE)

    // MARK: Appearance-Adaptive Initializer

    /// Resolves to `light` or `dark` based on the current macOS appearance
    init(light: Color, dark: Color) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(dark)
                : NSColor(light)
        })
    }

    // MARK: Hex Initializer

    init(hex: UInt, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: alpha
        )
    }
}
