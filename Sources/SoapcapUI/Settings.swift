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
        /// The last version whose beta notice was acknowledged.
        static let betaNoticeSeen = "betaNoticeSeen"
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

    /// Whether a transcript is de-identified as soon as the session stops,
    /// once the model is installed. Otherwise De-identify waits to be chosen.
    var deidentify: Bool {
        get { defaults.object(forKey: Key.deidentify) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Key.deidentify) }
    }

    private func text(_ key: String) -> String {
        (defaults.string(forKey: key) ?? "").trimmingCharacters(in: .whitespaces)
    }

    /// The model that drafts notes: `bonsai`, or a model pulled into Ollama.
    /// Chosen in Settings, or beside Draft note and Regenerate.
    var noteModel: String { Self.noteModel(stored: defaults.string(forKey: Key.noteModel) ?? "") }

    /// What a stored choice of model means: Bonsai, or else the default
    /// model. A name left from when any model in Ollama could be chosen
    /// counts as none.
    static func noteModel(stored: String) -> String {
        stored.trimmingCharacters(in: .whitespaces) == ModelCatalog.bonsai ? ModelCatalog.bonsai : ModelCatalog.defaultModel
    }

    /// Where Ollama is. Anything but this Mac sends the transcript over the network.
    var ollamaHost: URL { Self.ollamaHost(stored: text(Key.ollamaHost)) }

    /// What a stored address means: itself if it is a web address, and
    /// otherwise Ollama's usual place on this Mac.
    static func ollamaHost(stored: String) -> URL {
        let stored = stored.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: stored), url.scheme?.hasPrefix("http") == true, url.host() != nil else {
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
    @AppStorage(SessionSettings.Key.deidentify) private var deidentify = true
    @State private var languages: [Locale] = []
    @State private var models: [String] = []
    /// What Ollama has, so that a model it already holds isn't offered again.
    @State private var pulled: [String] = []
    /// Trying the chosen note model on the sample session.
    let test: ModelTest
    @ObservedObject var setup = ModelSetup.shared
    @ObservedObject var bonsai = ModelDownload.bonsai
    @ObservedObject var llama = ModelDownload.llama
    /// Ends a draft and frees the note model, before the app is uninstalled.
    var stop: () async -> Void = {}

    /// The chosen model and Ollama's address, read from the settings this
    /// view holds and not from the stored settings: a window is drawn again
    /// only for a setting its body has read, and otherwise the picker went
    /// on showing the model it had.
    private var chosenModel: String { SessionSettings.noteModel(stored: noteModel) }
    private var host: URL { SessionSettings.ollamaHost(stored: ollamaHost) }

    /// The installed models, plus the chosen one even if it has since gone.
    private var choices: [String] {
        models.contains(chosenModel) ? models : [chosenModel] + models
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
                Picker("Draft with", selection: Binding(get: { chosenModel }, set: { noteModel = $0 })) {
                    ForEach(choices, id: \.self) { Text(ModelCatalog.displayName(of: $0)).tag($0) }
                }
                TextField("Session type", text: $sessionType, prompt: Text("telehealth"))
                // A model still to be downloaded can't be tried, as on the
                // checks screen. Asked here, not read from `models`, which is
                // empty until the window has asked Ollama.
                if ModelCatalog.installed(pulled: pulled).contains(chosenModel) {
                    ModelTestView(test: test, model: chosenModel)
                } else {
                    Text("\(ModelCatalog.displayName(of: chosenModel)) can be tested once it is downloaded below.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Note")
            }
            Section {
                if OllamaBackend.has(ModelCatalog.defaultModel, in: pulled), llama.state == .missing {
                    Label("Ollama has \(ModelCatalog.defaultModel), and Soapcap drafts with that copy.", systemImage: "checkmark.circle.fill")
                } else {
                    ModelDownloadRow(name: ModelCatalog.defaultModel, needGB: ModelCatalog.defaultModelMemoryGB, download: llama)
                }
            } header: {
                Text(ModelCatalog.defaultModel)
            } footer: {
                Text(ModelCatalog.description(of: ModelCatalog.defaultModel) + " Built with Llama: Meta's Llama 3.1, under its Community License.")
                    .foregroundStyle(.secondary)
            }
            Section {
                ModelDownloadRow(name: BonsaiBackend.displayName, needGB: ModelCatalog.memoryNeedGB(of: ModelCatalog.bonsai), download: bonsai)
            } header: {
                Text(BonsaiBackend.displayName)
            } footer: {
                Text(ModelCatalog.description(of: ModelCatalog.bonsai)).foregroundStyle(.secondary)
            }
            Section {
                switch setup.state {
                case .ready:
                    Label("The model is installed.", systemImage: "checkmark.circle.fill")
                    Toggle("De-identify by default", isOn: $deidentify)
                    Text(deidentify ? "Each transcript is de-identified as the session stops, and so is its note."
                         : "A transcript keeps its names until you choose De-identify above it, and can't be saved until then.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                case .working(let file, let fraction):
                    ProgressView(value: fraction) { Text(file.isEmpty ? "Setting up…" : "Getting \(file)…") }
                case .missing, .failed:
                    if case .failed(let why) = setup.state { Text(why).foregroundStyle(.orange) }
                    Text(setup.canCopyFromSoapcap
                         ? "soapcap's copy of the model is on this Mac. It will be copied; nothing is downloaded."
                         : "Needs OpenMed's PII model, a one-time 130 MB download from huggingface.co. Nothing from a session is sent.")
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
                if !OllamaBackend.isLocal(host) {
                    Text("This is not this Mac: transcripts will be sent to that machine over the network.")
                        .foregroundStyle(.orange)
                }
            }
            Section {
                UninstallButton(stop: stop)
            } footer: {
                Text("Removes the models Soapcap downloaded, its settings and its permissions, then moves Soapcap to the Trash. It asks first.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        // A fixed height that scrolls: with nothing downloaded yet the
        // sections are taller than a laptop's screen.
        .frame(width: 440, height: 640)
        .task { languages = await Readiness.supportedLanguages() }
        // Asked again when a model arrives or goes, so the list above follows.
        .task(id: "\(ollamaHost) \(bonsai.isInstalled) \(llama.isInstalled)") {
            pulled = await ModelCatalog.pulled(host: host)
            models = ModelCatalog.installed(pulled: pulled)
        }
    }
}

#Preview("Settings") { SettingsView(test: SessionModel().modelTest) }
