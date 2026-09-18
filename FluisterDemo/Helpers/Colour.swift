import SwiftUI

#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

extension Color {

    /// Same hue & saturation; brightness flipped for dark mode.
    static func adaptedForDarkMode(hue: Double, saturation: Double, brightness: Double, alpha: Double) -> Self {
#if canImport(UIKit)
        Self(uiColor: UIColor { traits in
            UIColor(
                hue: hue, 
                saturation: saturation, 
                brightness: traits.userInterfaceStyle == .dark 
                    ? 1 - brightness 
                    : brightness,
                alpha: alpha
            )
        })
#elseif canImport(AppKit)
        Self(nsColor: NSColor(name: nil) { appearance in
            UIColor(
                hue: hue, 
                saturation: saturation, 
                brightness: appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? 1 - brightness 
                    : brightness,
                alpha: alpha
            )
        })
#else
        Self(hue: hue, saturation: saturation, brightness: brightness, alpha: alpha)
#endif
    }
    static func pastel(for index: Int, of count: Int, baseHue: Double = 0, alpha: Double = 1) -> Self {
        adaptedForDarkMode(
            hue: (baseHue + Double(index) / Double(count)).truncatingRemainder(dividingBy: 1),
            saturation: 0.8,
            brightness: 0.2,
            alpha: alpha
        )
    }

    static let agent = Color(hue: 0.714, saturation: 0.538, brightness: 0.520)

    static func speaker(for index: Int, of count: Int = 1) -> Color {
        .pastel(for: abs(index), of: max(1,count))
    }
}