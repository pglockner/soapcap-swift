import Foundation
import SoapcapCapture
import SoapcapCore

/// What the session needs from audio capture; `CaptureSession` in the app,
/// a scripted stand-in in tests and previews.
protocol Capturing: AnyObject {
    var live: AsyncStream<LiveLine> { get }
    func start(micLabel: String, systemLabel: String, locale: Locale) async throws
    func pause()
    func resume()
    func stop() async -> [Segment]
}

extension CaptureSession: Capturing {}
