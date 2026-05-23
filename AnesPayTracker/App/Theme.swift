import SwiftUI

// MARK: - App Theme

extension Color {
    /// Single accent color — a calm, high-contrast teal-blue.
    /// Passes WCAG AA on white and dark backgrounds.
    static let accent = Color("AccentColor")
}

extension Font {
    /// Round-number display font — large, bold, readable at a glance
    static func payDisplay(size: CGFloat = 40) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }
}

// MARK: - Dynamic Type Notes
// All text in this app uses SwiftUI's built-in Dynamic Type support.
// Use .font(.body), .font(.title3) etc — never hard-code font sizes
// except in PayDisplay contexts where we explicitly want large numerics.
// Minimum tap target enforced via .frame(minWidth: 44, minHeight: 44).
