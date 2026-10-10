import Foundation

/// One line of a readiness report: something the app needs, and whether it has it.
public struct Check: Equatable, Sendable, Identifiable {
    public enum Status: Equatable, Sendable { case ok, warning, failed }

    /// Where to go to put it right, e.g. a pane of System Settings.
    public struct Fix: Equatable, Sendable {
        public var label: String
        public var url: URL

        public init(label: String, url: URL) {
            self.label = label
            self.url = url
        }
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
