import AppKit
import SwiftUI

/// Light-mode colour tokens.
/// The app forces .preferredColorScheme(.light), so we use explicit sRGB
/// values for full predictability — NSColor semantics like
/// underPageBackgroundColor render as a medium gray (#969696) in macOS
/// Aqua light mode, which is unsuitable for a sidebar surface.
enum AGTheme {
    /// Page / window background — cool off-white (#F3F3F7)
    static let canvas     = Color(red: 0.953, green: 0.953, blue: 0.969)
    /// Sidebar / secondary surface — near-white with subtle cool tint (#F8F8FC)
    static let sidebar    = Color(red: 0.973, green: 0.973, blue: 0.988)
    /// Card / panel surface — pure white
    static let card       = Color.white
    /// Subtle divider / stroke (#E0E0EA)
    static let border     = Color(red: 0.878, green: 0.878, blue: 0.918)
    /// Brand accent — rich indigo-purple (#6B54DE)
    static let accent     = Color(red: 0.420, green: 0.330, blue: 0.871)
    /// Pale accent tint for chips, badge backgrounds
    static let accentSoft = Color(red: 0.420, green: 0.330, blue: 0.871).opacity(0.08)
}
