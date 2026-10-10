// Records for a few seconds and prints what was heard. A development aid for
// checking capture without the window: `swift run CaptureProbe [seconds] [pause]`.
// With `pause`, the middle third of the time is paused.
import Foundation
import SoapcapCapture
import SoapcapCore

let seconds = CommandLine.arguments.dropFirst().compactMap(Double.init).first ?? 10
let pauses = CommandLine.arguments.contains("pause")
func say(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }

let session = CaptureSession()
do { try await session.start() } catch {
    say("could not start: \(error.localizedDescription)")
    exit(1)
}
let printer = Task { for await line in session.live { say("  \(line.isFinal ? "=" : "~") \(line.speaker): \(line.text)") } }
say("recording for \(Int(seconds))s…")
if pauses {
    try await Task.sleep(for: .seconds(seconds / 3))
    session.pause(); say("paused")
    try await Task.sleep(for: .seconds(seconds / 3))
    session.resume(); say("resumed")
    try await Task.sleep(for: .seconds(seconds / 3))
} else {
    try await Task.sleep(for: .seconds(seconds))
}
let segments = await session.stop()
await printer.value
say("\(segments.count) segment(s), last ends at \(segments.map(\.end).max() ?? 0)s")
print(Transcript.render(segments, mic: "Therapist", system: "Client"))
