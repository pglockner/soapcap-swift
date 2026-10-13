import SwiftUI
import UniformTypeIdentifiers

/// A de-identified transcript as a text file. It is the one thing the app
/// ever writes to disk, and only when asked: its owner chooses Save
/// transcript and says where it goes.
struct TranscriptFile: FileDocument {
    static let readableContentTypes: [UTType] = [.plainText]
    /// The name the save panel offers. Nothing about the session is in it.
    static let name = "Transcript"

    var text: String

    /// `about` is the session in a few words, as on a note's first line
    /// ("53 minutes, telehealth"). The transcript is laid out by its minutes
    /// when each line's time is known, and otherwise goes in as it is.
    init(transcript: String, times: [Int], pauses: [SessionPause], about: String) {
        let body = MinuteIndex(text: transcript, times: times, pauses: pauses)?.plainText ?? transcript
        text = """
            Transcript, \(about)
            De-identified by Soapcap, which is best effort: read it through before sharing it.

            \(body)

            """
    }

    init(configuration: ReadConfiguration) throws {
        text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
