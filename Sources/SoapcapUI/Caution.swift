import AppKit
import SwiftUI

extension ShapeStyle where Self == Color {
    /// Orange for words that warn. The system orange is fine on a dark
    /// window but only 2.3:1 on a light one, too faint to read as text, so
    /// light mode gets a deeper orange (about 5:1 on white). Symbols and
    /// borders can keep the system orange.
    static var caution: Color {
        Color(nsColor: NSColor(name: "caution") { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? .systemOrange
                : NSColor(srgbRed: 0.71, green: 0.33, blue: 0.04, alpha: 1)
        })
    }
}
