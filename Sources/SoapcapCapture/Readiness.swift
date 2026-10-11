import AVFoundation
import CoreGraphics
import SoapcapCore
import Speech

/// Whether this app can capture and transcribe, read from macOS without recording anything.
public enum Readiness {
    static func pane(_ name: String) -> URL {
        URL(string: "x-apple.systempreferences:com.apple.preference.security?\(name)")!
    }

    /// The pane where the call-audio permission is turned on.
    public static let callAudioPane = pane("Privacy_ScreenCapture")

    /// True when the app may use the microphone and hear the call.
    public static var hasPermissions: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized && CGPreflightScreenCaptureAccess()
    }

    /// Has macOS put its question about the microphone.
    public static func askForMicrophone() async { _ = await AVCaptureDevice.requestAccess(for: .audio) }

    /// Has macOS list this app under Screen & System Audio Recording, asking
    /// about it the first time. The grant counts once the app is reopened.
    public static func askForCallAudio() { _ = CGRequestScreenCaptureAccess() }

    public static func checks(locale: Locale = Locale(identifier: Locale.current.identifier)) async -> [Check] {
        [microphone(AVCaptureDevice.authorizationStatus(for: .audio)),
         callAudio(granted: CGPreflightScreenCaptureAccess())] + (await speech(locale: locale))
    }

    static func microphone(_ status: AVAuthorizationStatus) -> Check {
        switch status {
        case .authorized:
            return Check("Microphone", .ok, "Soapcap can hear your side.")
        case .notDetermined:
            return Check("Microphone", .warning, "Needed to hear your side. macOS will ask whether Soapcap may use the microphone; choose Allow.",
                         fix: Check.Fix(label: "Allow the microphone", action: .askForMicrophone))
        default:
            return Check("Microphone", .failed, "Turn on Soapcap under Microphone, then reopen Soapcap.",
                         fix: Check.Fix(label: "Open Microphone settings", url: pane("Privacy_Microphone")))
        }
    }

    static func callAudio(granted: Bool) -> Check {
        granted
            ? Check("Call audio", .ok, "Soapcap can hear what the Mac is playing.")
            : Check("Call audio", .failed,
                    "Needed to hear the other side. macOS files this under Screen & System Audio Recording; no picture is taken.\n1. If macOS asks, choose Open System Settings, not Deny.\n2. Turn Soapcap on in the list. macOS wants Touch ID or your password for that.\n3. Choose Quit & Reopen.\nIf Soapcap is already on in the list, remove it and add it again.",
                    fix: Check.Fix(label: "Allow call audio", action: .askForCallAudio))
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
