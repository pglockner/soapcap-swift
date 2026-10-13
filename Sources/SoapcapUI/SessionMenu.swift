import AppKit
import SwiftUI

/// What the time in the menu bar opens: the way back to the window, and
/// pausing. Stopping is left to the window, where it is red.
struct SessionMenu: View {
    /// The id of the session's window.
    static let window = "session"

    @ObservedObject var m: SessionModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Show Soapcap") { show() }
        if m.phase == .paused {
            Button("Resume") { m.resume() }
        } else {
            Button("Pause") { m.pause() }
        }
    }

    /// Brings the session's window forward, or opens one if it was closed:
    /// the session belongs to the app, not to a window.
    private func show() {
        NSApp.activate()
        if let window = NSApp.windows.first(where: { $0.canBecomeMain && $0.isVisible }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: Self.window)
        }
    }
}
