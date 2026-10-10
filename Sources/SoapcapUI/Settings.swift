import SoapcapCapture
import SoapcapNote
import SwiftUI

/// The choices that outlast a session, kept in the app's user defaults.
struct SessionSettings {
    enum Key {
        static let micLabel = "micLabel"
        static let systemLabel = "systemLabel"
        static let language = "language"
        static let format = "format"
        static let deidentify = "deidentify"
        static let noteModel = "noteModel"
        static let ollamaHost = "ollamaHost"
        static let sessionType = "sessionType"
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
    private func text(_ key: String) -> String {
        (defaults.string(forKey: key) ?? "").trimmingCharacters(in: .whitespaces)
    }

    /// The model that drafts notes: `bonsai`, or a model pulled into Ollama.
    var noteModel: String { text(Key.noteModel).isEmpty ? ModelCatalog.defaultModel : text(Key.noteModel) }

    /// Where Ollama is. Anything but this Mac sends the transcript over the network.
    var ollamaHost: URL {
        guard let url = URL(string: text(Key.ollamaHost)), url.scheme?.hasPrefix("http") == true, url.host() != nil else {
            return OllamaBackend.defaultHost
        }
        return url
    }

    /// The second half of the note's first line, e.g. "53 minutes, telehealth".
    var sessionType: String { text(Key.sessionType).isEmpty ? "telehealth" : text(Key.sessionType) }
}

struct SettingsView: View {
    @AppStorage(SessionSettings.Key.micLabel) private var micLabel = ""
    @AppStorage(SessionSettings.Key.systemLabel) private var systemLabel = ""
    @AppStorage(SessionSettings.Key.language) private var language = ""
    @AppStorage(SessionSettings.Key.noteModel) private var noteModel = ""
    @AppStorage(SessionSettings.Key.ollamaHost) private var ollamaHost = ""
    @AppStorage(SessionSettings.Key.sessionType) private var sessionType = ""
    @State private var languages: [Locale] = []
    @State private var models: [String] = []
    @ObservedObject var setup = ModelSetup.shared

    private var settings: SessionSettings { SessionSettings() }

    /// The installed models, plus the chosen one even if it has since gone.
    private var choices: [String] {
        let chosen = settings.noteModel
        return models.contains(chosen) ? models : [chosen] + models
    }

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
            Section {
                Picker("Draft with", selection: Binding(get: { settings.noteModel }, set: { noteModel = $0 })) {
                    ForEach(choices, id: \.self) { Text($0 == ModelCatalog.bonsai ? "Bonsai" : $0).tag($0) }
                }
                TextField("Session type", text: $sessionType, prompt: Text("telehealth"))
            } header: {
                Text("Note")
            } footer: {
                Text(ModelCatalog.description(of: settings.noteModel)
                     ?? "Not tested with these prompts; proofread its notes closely.")
                    .foregroundStyle(.secondary)
            }
            Section {
                switch setup.state {
                case .ready:
                    Label("The model is installed.", systemImage: "checkmark.circle.fill")
                case .working(let file, let fraction):
                    ProgressView(value: fraction) { Text(file.isEmpty ? "Setting up…" : "Getting \(file)…") }
                case .missing, .failed:
                    if case .failed(let why) = setup.state { Text(why).foregroundStyle(.orange) }
                    Text(setup.canCopyFromSoapcap
                         ? "soapcap's copy of the model is on this Mac. It will be copied; nothing is downloaded."
                         : "Needs OpenMed's PII model, a one-time 130 MB download from huggingface.co. This is the only time Soapcap uses the network, and nothing from a session is sent.")
                        .fixedSize(horizontal: false, vertical: true)
                    Button(setup.canCopyFromSoapcap ? "Set up" : "Download model") { setup.install() }
                }
            } header: {
                Text("De-identification")
            } footer: {
                Text("Replaces names, phone numbers, dates and similar details with tokens like [FIRST_NAME_1]. Best effort: the model misses things, so read the result before sharing it.")
                    .foregroundStyle(.secondary)
            }
            Section {
                TextField("Ollama address", text: $ollamaHost, prompt: Text(OllamaBackend.defaultHost.absoluteString))
            } header: {
                Text("Advanced")
            } footer: {
                if !OllamaBackend.isLocal(settings.ollamaHost) {
                    Text("This is not this Mac: transcripts will be sent to that machine over the network.")
                        .foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .task { languages = await Readiness.supportedLanguages() }
        .task(id: ollamaHost) { models = await ModelCatalog.installed(host: settings.ollamaHost) }
    }
}

#Preview("Settings") { SettingsView() }
