import SoapcapCore
import XCTest
@testable import SoapcapCapture

/// Speaks a sentence into a file with `say`, then checks the transcription,
/// and that it agrees with `yap` (the tool this replaces) when yap is installed.
final class FileTranscriberTests: XCTestCase {
    private let spoken = "Thanks for meeting with me today. I wanted to talk about what happened at work last week, because it has been on my mind."
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("soapcap-capture-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private func run(_ tool: String, _ args: [String]) throws -> Data {
        let p = Process(), out = Pipe()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        try p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return data
    }

    private func speak() throws -> URL {
        let file = dir.appendingPathComponent("spoken.aiff")
        _ = try run("/usr/bin/say", ["-o", file.path, spoken])
        return file
    }

    private func words(_ segments: [Segment]) -> [String] {
        segments.flatMap { $0.text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init) }
    }

    func testTranscribesSpeechIntoOrderedTimedSegments() async throws {
        let segments = try await FileTranscriber.segments(of: try speak(), locale: Locale(identifier: "en-US"))
        XCTAssertFalse(segments.isEmpty)
        XCTAssertTrue(words(segments).contains("work"), "heard: \(segments.map(\.text))")
        XCTAssertEqual(segments.map(\.id), Array(1...segments.count))
        XCTAssertTrue(segments.allSatisfy { $0.end >= $0.start })
        XCTAssertEqual(segments.map(\.start), segments.map(\.start).sorted())
    }

    func testAgreesWithYap() async throws {
        let yap = "/opt/homebrew/bin/yap"
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: yap), "yap is not installed")
        let file = try speak()
        let theirs = try Segment.decode(yapJSON: try run(yap, ["transcribe", "--json", "--locale", "en-US", file.path]))
        let ours = try await FileTranscriber.segments(of: file, locale: Locale(identifier: "en-US"))
        XCTAssertEqual(words(ours), words(theirs))
        XCTAssertEqual(ours.map(\.text), theirs.map(\.text))
        XCTAssertEqual(ours.first?.start ?? -1, theirs.first?.start ?? -2, accuracy: 0.05)
        XCTAssertEqual(ours.last?.end ?? -1, theirs.last?.end ?? -2, accuracy: 0.05)
    }
}
