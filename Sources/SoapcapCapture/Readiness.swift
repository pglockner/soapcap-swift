import AVFoundation
import CoreGraphics
import SoapcapCore
import Speech

/// Whether this app can capture and transcribe, read from macOS without recording anything.
public enum Readiness {
    static func privacy(_ pane: String, _ label: String) -> Check.Fix {
        Check.Fix(label: label,
                  url: URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
    }

    public static func checks(locale: Locale = Locale(identifier: Locale.current.identifier)) async -> [Check] {
        [microphone(AVCaptureDevice.authorizationStatus(for: .audio)),
         callAudio(granted: CGPreflightScreenCaptureAccess())] + (await speech(locale: locale))
    }

    static func microphone(_ status: AVAuthorizationStatus) -> Check {
        let fix = privacy("Privacy_Microphone", "Open Microphone settings")
        switch status {
        case .authorized:
            return Check("Microphone", .ok, "Soapcap can hear your side.")
        case .notDetermined:
            return Check("Microphone", .warning, "Not asked yet. macOS will ask the first time you start recording.")
        default:
            return Check("Microphone", .failed, "Turn on Soapcap under Microphone, then quit and reopen Soapcap.", fix: fix)
        }
    }

    static func callAudio(granted: Bool) -> Check {
        granted
            ? Check("Call audio", .ok, "Soapcap can hear what the Mac is playing.")
            : Check("Call audio", .failed,
                    "Turn on Soapcap under Screen & System Audio Recording, then quit and reopen Soapcap. If it is already on, remove it from the list and add it again.",
                    fix: privacy("Privacy_ScreenCapture", "Open Screen Recording settings"))
    }

    static func speech(locale: Locale) async -> [Check] {
        let title = "Speech recognition"
        let wanted = locale.identifier(.bcp47)
        guard SpeechTranscriber.isAvailable else {
            return [Check(title, .failed, "On-device speech recognition is not available on this Mac.")]
        }
        guard await SpeechTranscriber.supportedLocales.contains(where: { $0.identifier(.bcp47) == wanted }) else {
            return [Check(title, .failed, "The language \(wanted) is not supported. Choose another in Settings.")]
        }
        guard await SpeechTranscriber.installedLocales.contains(where: { $0.identifier(.bcp47) == wanted }) else {
            return [Check(title, .warning, "The \(wanted) model is not installed yet. It downloads the first time you record.")]
        }
        return [Check(title, .ok, "Ready for \(wanted), on this Mac only.")]
    }

    /// Languages the on-device recognizer can transcribe, by name.
    public static func supportedLanguages() async -> [Locale] {
        await SpeechTranscriber.supportedLocales.sorted {
            let name = { (l: Locale) in Locale.current.localizedString(forIdentifier: l.identifier) ?? l.identifier }
            return name($0) < name($1)
        }
    }
}
