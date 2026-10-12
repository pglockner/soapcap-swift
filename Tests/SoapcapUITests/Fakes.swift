import SoapcapCapture
import SoapcapCore
import SoapcapDeidentify
import SoapcapNote
import XCTest
@testable import SoapcapUI

/// Settings kept in memory. A suite of the real kind leaves a file in
/// ~/Library/Preferences for every test run: macOS writes it back even
/// after it has been removed.
final class MemoryDefaults: UserDefaults {
    private var values: [String: Any] = [:]
    override func object(forKey key: String) -> Any? { values[key] }
    override func set(_ value: Any?, forKey key: String) { values[key] = value }
    override func removeObject(forKey key: String) { values[key] = nil }
}

/// Scripted capture: returns `segments` on stop and records what it was asked to do.
final class FakeCapture: Capturing {
    let live: AsyncStream<LiveLine>
    private let continuation: AsyncStream<LiveLine>.Continuation
    var segments: [Segment]
    var startError: Error?
    var calls: [String] = []
    var started = (mic: "", system: "", locale: "")

    init(_ segments: [Segment] = [], startError: Error? = nil) {
        (live, continuation) = AsyncStream.makeStream(of: LiveLine.self)
        self.segments = segments
        self.startError = startError
    }

    func start(micLabel: String, systemLabel: String, locale: Locale) async throws {
        calls.append("start")
        started = (micLabel, systemLabel, locale.identifier)
        if let startError { throw startError }
    }
    func pause() { calls.append("pause") }
    func resume() { calls.append("resume") }
    func stop() async -> [Segment] { calls.append("stop"); continuation.finish(); return segments }
    func hear(_ line: LiveLine) { continuation.yield(line) }
}

/// Scripted drafting: returns a note naming the format, and records what it was asked.
@MainActor final class FakeDrafter: Drafting {
    var warnings: [String] = []
    var error: Error?
    /// The note to hand back; a one-section note naming the format when nil.
    var text: String?
    var asked: [(format: NoteFormat, transcript: String, minutes: Int, systemLabel: String)] = []
    var releases = 0
    /// How long the model takes to go, in nanoseconds.
    var releaseDelay: UInt64 = 0
    /// "draft" as each draft starts and "released" as each release ends.
    var events: [String] = []

    func draft(format: NoteFormat, transcript: String, minutes: Int, systemLabel: String,
               progress: @escaping @Sendable (DraftProgress) -> Void) async throws -> DraftedNote {
        asked.append((format, transcript, minutes, systemLabel))
        events.append("draft")
        progress(DraftProgress(title: "Drafting…", tokens: 7))
        try? await Task.sleep(nanoseconds: 150_000_000)
        if let error { throw error }
        return DraftedNote(text: text ?? "SUBJECTIVE:\nformat \(format.rawValue)\nNote about Bob", warnings: warnings)
    }

    func release() async {
        releases += 1
        try? await Task.sleep(nanoseconds: releaseDelay)
        events.append("released")
    }
}

let hello = [Segment(speaker: "Therapist", start: 0, end: 1, id: 1, text: "hi Bob"),
             Segment(speaker: "Client", start: 2, end: 3, id: 1, text: "hello")]

/// Scripted de-identifying: replaces "Bob", and records what kind of text it was given.
@MainActor final class FakeDeidentifier: Deidentifying {
    var isReady = true
    var error: Error?
    var kinds: [LabeledText.Kind] = []

    func deidentify(_ text: String, kind: LabeledText.Kind) async throws -> Deidentified {
        kinds.append(kind)
        if let error { throw error }
        return Deidentified(text: text.replacingOccurrences(of: "Bob", with: "[FIRST_NAME_1]"), summary: "1 identifying detail replaced (first name)")
    }
}

/// Polls (suspending, so the main run loop and timers keep running).
@MainActor func waitFor(_ what: String, timeout: TimeInterval = 10,
                        file: StaticString = #filePath, line: UInt = #line,
                        _ condition: () -> Bool) async {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        if Date() > deadline { XCTFail("timed out waiting for \(what)", file: file, line: line); return }
        try? await Task.sleep(nanoseconds: 100_000_000)
    }
}
