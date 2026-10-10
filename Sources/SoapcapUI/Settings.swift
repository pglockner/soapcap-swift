import SoapcapCapture
import SwiftUI

/// The choices that outlast a session, kept in the app's user defaults.
struct SessionSettings {
    enum Key {
        static let micLabel = "micLabel"
        static let systemLabel = "systemLabel"
        static let language = "language"
        static let format = "format"
        static let deidentify = "deidentify"
    }

    var defaults: UserDefaults = .standard

    private func label(_ key: String, default fallback: String) -> String {
        let value = (defaults.string(forKey: key) ?? "").trimmingCharacters(in: .whitespaces)
        // A colon would break "Label: text" lines apart in the wrong place.
        return value.isEmpty || value.contains(":") ? fallback : value
    }

    /// Who the microphone is.
    var micLabel: String { label(Key.micLabel, default: "Therapist") }
    /// Who the call audio is.
    var systemLabel: String { label(Key.systemLabel, default: "Client") }

    /// The language to transcribe; the Mac's unless one was chosen.
    var locale: Locale {
        let id = defaults.string(forKey: Key.language) ?? ""
        return Locale(identifier: id.isEmpty ? Locale.current.identifier : id)
    }

    var format: String {
        get { defaults.string(forKey: Key.format).flatMap { SessionModel.formats.contains($0) ? $0 : nil } ?? "soap" }
        nonmutating set { defaults.set(newValue, forKey: Key.format) }
    }

    var deidentify: Bool {
        get { defaults.object(forKey: Key.deidentify) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Key.deidentify) }
    }
}

struct SettingsView: View {
    @AppStorage(SessionSettings.Key.micLabel) private var micLabel = ""
    @AppStorage(SessionSettings.Key.systemLabel) private var systemLabel = ""
    @AppStorage(SessionSettings.Key.language) private var language = ""
    @State private var languages: [Locale] = []

    var body: some View {
        Form {
            Section {
                TextField("Your microphone", text: $micLabel, prompt: Text("Therapist"))
                TextField("The call", text: $systemLabel, prompt: Text("Client"))
            } header: {
                Text("Speaker labels")
            } footer: {
                Text("Each transcript line starts with one of these.").foregroundStyle(.secondary)
            }
            Section("Language") {
                Picker("Transcribe in", selection: $language) {
                    Text("This Mac's language").tag("")
                    Divider()
                    ForEach(languages, id: \.identifier) { locale in
                        Text(Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier)
                            .tag(locale.identifier(.bcp47))
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .task { languages = await Readiness.supportedLanguages() }
    }
}

#Preview("Settings") { SettingsView() }
