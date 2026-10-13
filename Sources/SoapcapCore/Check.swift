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
            /// Has macOS ask to hear the call, and reports the answer.
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

    /// The titles of the two checks that are permissions from macOS.
    public static let permissions = ["Microphone", "Call audio"]
}

extension Sequence<Check> {
    /// Whether a permission is still to be given. Until both are, there is
    /// no session to be had.
    public var lackPermission: Bool {
        contains { Check.permissions.contains($0.title) && $0.status != .ok }
    }

    /// Whether something stands in the way of a session or its note: a
    /// permission still to give, or a check that failed. A warning alone
    /// (de-identifying not set up, memory short just now) does not.
    public var needAttention: Bool {
        lackPermission || contains { $0.status == .failed }
    }
}
