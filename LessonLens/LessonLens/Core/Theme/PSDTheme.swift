import SwiftUI

/// Semantic color and style mappings for PSD branding
enum PSDTheme {

    // MARK: - Interactive Colors

    /// Primary accent for buttons, links, interactive elements.
    /// Light: darkened Sea Glass (WCAG AA on white). Dark: Sea Glass (readable on dark backgrounds).
    static let accent = Color(light: .psdSeaGlassAccessible, dark: .psdSeaGlass)

    /// Decorative accent — non-interactive use only (e.g., illustrations, dividers)
    static let accentDecorative = Color.psdSeaGlass

    // MARK: - Text Colors

    /// Heading text color (light mode only; dark mode uses .primary)
    static func headingText(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.primary : Color.psdPacific
    }

    // MARK: - Background Colors

    /// Page-level background (Skylight in light mode, system window background in dark mode)
    static let pageBackground = Color(light: .psdSkylight, dark: Color(nsColor: .windowBackgroundColor))

    /// Bottom stop of the login gradient (Sea Foam in light mode, system window background in dark mode)
    static let pageBackgroundGradientEnd = Color(light: .psdSeaFoam, dark: Color(nsColor: .windowBackgroundColor))

    /// Card background for PDF export (light bg context)
    static let pdfCardBackground = Color.psdSeaFoam

    // MARK: - Semantic Feedback Colors

    /// Strengths sections
    static let strength = Color.psdMeadow

    /// Growth areas — kept orange for UX urgency signaling
    static let growth = Color.orange

    /// Next steps / informational
    static let nextSteps = Color.psdWhulge

    /// Processing / in-progress states
    static let processing = Color.psdWhulge

    /// Success / complete states
    static let success = Color.psdMeadow

    /// Recording indicator — kept red (functional, not branded)
    static let recording = Color.red

    /// Error / failure — kept red (functional)
    static let error = Color.red

    // MARK: - Media Type Colors

    /// Audio badge color
    static let audio = Color.psdOcean

    /// Video badge color
    static let video = Color.psdWhulge

    // MARK: - Info Banner

    /// Info banner background
    static let infoBanner = Color.psdOcean.opacity(0.1)

    /// Info banner accent
    static let infoBannerAccent = Color.psdOcean

    // MARK: - Rating Scale

    /// Rating color for 1-5 scale: red, orange, Driftwood, Meadow, Whulge
    static func ratingColor(_ rating: Int) -> Color {
        switch rating {
        case 1: return .red
        case 2: return .orange
        case 3: return .psdDriftwood
        case 4: return .psdMeadow
        case 5: return .psdWhulge
        default: return .gray
        }
    }

    /// Whether a rating level needs a border to be visible against the page background
    static func ratingNeedsBorder(_ rating: Int) -> Bool {
        rating == 3
    }
}
