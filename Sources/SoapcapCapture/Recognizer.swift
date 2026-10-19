import Foundation
import Speech

public enum CaptureError: Error, LocalizedError, Equatable {
    case recognitionUnavailable
    case unsupportedLocale(String)
    case noAudioFormat
    /// macOS refused the Microphone permission.
    case microphoneDenied
    /// The permission is there, but no microphone could be started: none
    /// is connected, or the one there wouldn't start.
    case noMicrophone
    case callAudioDenied
    /// Core Audio would not set up listening to the Mac's output.
    case callAudioFailed(String)

    public var errorDescription: String? {
        switch self {
        case .recognitionUnavailable: "On-device speech recognition is not available on this Mac."
        case .unsupportedLocale(let id): "Speech recognition does not support the language \"\(id)\"."
        case .noAudioFormat: "No audio format is available for speech recognition."
        case .microphoneDenied:
            "Soapcap isn't allowed to use the microphone. Turn on Soapcap in System Settings > Privacy & Security > Microphone, then quit and reopen Soapcap."
        case .noMicrophone:
            "Soapcap can't find a working microphone. Connect one, such as a headset or AirPods, and start again."
        case .callAudioDenied:
            "Soapcap can't hear the call. Turn on Soapcap in System Settings > Privacy & Security > Screen & System Audio Recording, under System Audio Recording Only, then start again."
        case .callAudioFailed(let why):
            "Soapcap couldn't start listening to what the Mac is playing (\(why))."
        }
    }
}

/// Builds on-device transcribers and makes sure their language model is installed.
enum Recognizer {
    /// `live` adds in-progress (volatile) results, for showing text as it is heard.
    static func transcriber(locale: Locale, live: Bool) async throws -> SpeechTranscriber {
        guard SpeechTranscriber.isAvailable else { throw CaptureError.recognitionUnavailable }
        let wanted = locale.identifier(.bcp47)
        guard await SpeechTranscriber.supportedLocales.contains(where: { $0.identifier(.bcp47) == wanted }) else {
            throw CaptureError.unsupportedLocale(wanted)
        }
        return SpeechTranscriber(locale: locale, transcriptionOptions: [],
                                 reportingOptions: live ? [.volatileResults] : [],
                                 attributeOptions: [.audioTimeRange])
    }

    /// Reserves the locale and downloads its model if this Mac doesn't have it yet.
    static func prepare(_ modules: [any SpeechModule], locale: Locale) async throws {
        let wanted = locale.identifier(.bcp47)
        for reserved in await AssetInventory.reservedLocales where reserved.identifier(.bcp47) != wanted {
            await AssetInventory.release(reservedLocale: reserved)
        }
        try await AssetInventory.reserve(locale: locale)
        guard !(await SpeechTranscriber.installedLocales).contains(where: { $0.identifier(.bcp47) == wanted }) else { return }
        try await AssetInventory.assetInstallationRequest(supporting: modules)?.downloadAndInstall()
    }
}
