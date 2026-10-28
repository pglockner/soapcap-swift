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

    /// The model that drafts notes, one of `NoteModel.all`. Chosen in
    /// Settings, or beside Draft note and Regenerate.
    var noteModel: String { Self.noteModel(stored: defaults.string(forKey: Key.noteModel) ?? "") }

    /// What a stored choice of model means: that model, or else the default
    /// one. A name left from a model the app no longer offers counts as none.
    static func noteModel(stored: String) -> String {
        NoteModel.named(stored.trimmingCharacters(in: .whitespaces))?.id ?? ModelCatalog.defaultModel
    }

    /// The second half of the note's first line, e.g. "53 minutes, telehealth".
    var sessionType: String { text(Key.sessionType).isEmpty ? "telehealth" : text(Key.sessionType) }
}

struct SettingsView: View {
    @AppStorage(SessionSettings.Key.micLabel) private var micLabel = ""
    @AppStorage(SessionSettings.Key.systemLabel) private var systemLabel = ""
    @AppStorage(SessionSettings.Key.language) private var language = ""
    @AppStorage(SessionSettings.Key.noteModel) private var noteModel = ""
    @AppStorage(SessionSettings.Key.sessionType) private var sessionType = ""
    @AppStorage(SessionSettings.Key.deidentify) private var deidentify = true
    @State private var languages: [Locale] = []
    /// The note models on this Mac.
    @State private var models: [String] = []
    /// Trying the chosen note model on the sample session.
    let test: ModelTest
    @ObservedObject var setup = ModelSetup.shared
    /// One for each note model, in `NoteModel.all`'s order.
    var downloads = ModelDownload.all
    /// Ends a draft and frees the note model, before the app is uninstalled.
    var stop: () async -> Void = {}

    /// The chosen model, read from the setting this view holds and not from
    /// the stored settings: a window is drawn again only for a setting its
    /// body has read, and otherwise the picker went on showing the model it had.
    private var chosenModel: String { SessionSettings.noteModel(stored: noteModel) }

    /// The installed models, plus the chosen one even if it has since gone.
    private var choices: [String] {
        models.contains(chosenModel) ? models : [chosenModel] + models
    }

    /// Where soapcap's installer put Bonsai. Looked at only to say why it
    /// isn't used; the app never reads it.
    private static var soapcapsBonsai: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".local/share/soapcap/bonsai/\(NoteModel.bonsai.weights.name)")
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
                // checks screen.
                if models.contains(chosenModel) {
                    ModelTestView(test: test, model: chosenModel)
                } else {
                    Text("\(ModelCatalog.displayName(of: chosenModel)) can be tested once it is downloaded below.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Note")
            }
            ForEach(Array(zip(NoteModel.all, downloads)), id: \.0.id) { model, download in
                Section {
                    if model == .bonsai, !models.contains(model.id), FileManager.default.fileExists(atPath: Self.soapcapsBonsai.path) {
                        Text("The copy of Bonsai that soapcap installed isn't used: Soapcap only runs model files it downloaded and checked itself.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ModelDownloadRow(name: model.displayName, needGB: model.memoryNeedGB, download: download)
                } header: {
                    Text(model.id == ModelCatalog.defaultModel ? "\(model.displayName) (default)" : model.displayName)
                } footer: {
                    Text(model.description).foregroundStyle(.secondary)
                }
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
                    if case .failed(let why) = setup.state { Text(why).foregroundStyle(.caution) }
                    Text("Needs OpenMed's PII model, a one-time 130 MB download from huggingface.co. Nothing from a session is sent.")
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Download model") { setup.install() }
                }
            } header: {
                Text("De-identification")
            } footer: {
                Text("Replaces names, phone numbers, dates and similar details with tokens like [FIRST_NAME_1]. Best effort: the model misses things, so read the result before sharing it.")
                    .foregroundStyle(.secondary)
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
        .onReceive(ModelDownload.changes) { models = ModelCatalog.installed() }
    }
}

#Preview("Settings") { SettingsView(test: SessionModel().modelTest) }
