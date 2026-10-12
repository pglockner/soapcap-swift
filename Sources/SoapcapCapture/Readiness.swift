import AVFoundation
import SoapcapCore
import Speech

/// Whether this app can capture and transcribe, read from macOS without recording anything.
public enum Readiness {
    static func pane(_ name: String) -> URL {
        URL(string: "x-apple.systempreferences:com.apple.preference.security?\(name)")!
    }

    /// The pane where the call-audio permission is turned on.
    public static let callAudioPane = pane("Privacy_AudioCapture")

    /// True when the app may use the microphone and hear the call. Never
    /// makes macOS ask: a permission not asked for yet counts as missing.
    public static func hasPermissions() async -> Bool {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { return false }
        return await CallAudio.access() == .allowed
    }

    /// Has macOS put its question about the microphone.
    public static func askForMicrophone() async { _ = await AVCaptureDevice.requestAccess(for: .audio) }

    /// Has macOS put its question about system audio. The answer counts at once.
    public static func askForCallAudio() async { await CallAudio.ask() }

    public static func checks(locale: Locale = Locale(identifier: Locale.current.identifier)) async -> [Check] {
        [microphone(AVCaptureDevice.authorizationStatus(for: .audio)),
         callAudio(await CallAudio.access())] + (await speech(locale: locale))
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

    static func callAudio(_ access: CallAudioAccess) -> Check {
        switch access {
        case .allowed:
            return Check("Call audio", .ok, "Soapcap can hear what the Mac is playing.")
        case .notAsked:
            return Check("Call audio", .warning,
                         "Needed to hear the other side. macOS will ask whether Soapcap may record your system audio; choose Allow. Only sound is heard, never the screen, and none of it is kept.",
                         fix: Check.Fix(label: "Allow call audio", action: .askForCallAudio))
        case .refused:
            return Check("Call audio", .failed,
                         "Soapcap can't hear what the Mac is playing, so the other side of a call would be missing. Turn on Soapcap under System Audio Recording Only, then choose Check again.",
                         fix: Check.Fix(label: "Open System Audio settings", url: callAudioPane))
        }
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
