import Foundation

/// One line of a readiness report: something the app needs, and whether it has it.
public struct Check: Equatable, Sendable, Identifiable {
    public enum Status: Equatable, Sendable { case ok, warning, failed }

    /// A button that puts it right, or starts to.
    public struct Fix: Equatable, Sendable {
        public enum Action: Equatable, Sendable {
            /// Opens a pane of System Settings, or a web page.
            case open(URL)
            /// Has macOS ask for the microphone.
            case askForMicrophone
            /// Has macOS ask to hear the call, which it files under Screen Recording.
            case askForCallAudio
            /// Opens this app's own Settings window.
            case showSettings
        }

        public var label: String
        public var action: Action

        public init(label: String, action: Action) {
            self.label = label
            self.action = action
        }

        public init(label: String, url: URL) { self.init(label: label, action: .open(url)) }
    }

    public var title: String
    public var status: Status
    public var detail: String
    public var fix: Fix?
    public var id: String { title }

    public init(_ title: String, _ status: Status, _ detail: String, fix: Fix? = nil) {
        self.title = title
        self.status = status
        self.detail = detail
        self.fix = fix
    }
}
