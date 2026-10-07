import SwiftUI

/// iOS-only SwiftUI APIs with a macOS stand-in, so the shared views keep compiling for macOS
/// while iOS keeps exactly the iOS behaviour.

extension ToolbarItemPlacement {
    /// `.topBarLeading` on iOS; the navigation area on macOS.
    static var barLeading: ToolbarItemPlacement {
        #if os(iOS)
        .topBarLeading
        #else
        .navigation
        #endif
    }

    /// `.topBarTrailing` on iOS; the system's default spot on macOS.
    static var barTrailing: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .automatic
        #endif
    }
}

extension Color {
    /// `secondarySystemBackground` on iOS; the control background on macOS.
    static var secondaryBackground: Color {
        #if os(iOS)
        Color(.secondarySystemBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }
}
