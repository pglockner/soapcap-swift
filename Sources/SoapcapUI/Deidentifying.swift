import Foundation
import SoapcapCore
import SoapcapDeidentify
import SoapcapPII

/// What the session needs from de-identifying; `ModelDeidentifying` in the
/// app, a scripted stand-in in tests.
@MainActor protocol Deidentifying: AnyObject {
    /// Whether the model is installed, so de-identifying can be offered.
    var isReady: Bool { get }
    /// Throws rather than hand back text it could not check.
    func deidentify(_ text: String, kind: LabeledText.Kind) async throws -> Deidentified
}

/// De-identifies with the on-device model, loaded on first use and kept.
@MainActor final class ModelDeidentifying: Deidentifying {
    private let detector = OpenMedDetector()

    var isReady: Bool { ModelFiles.isReady() }

    func deidentify(_ text: String, kind: LabeledText.Kind) async throws -> Deidentified {
        try await Deidentifier(detector: detector).deidentify(text, kind: kind)
    }
}

/// Installing the de-identification model, for Settings to show and start.
@MainActor final class ModelSetup: ObservableObject {
    enum State: Equatable {
        case missing, ready
        case working(file: String, fraction: Double)
        case failed(String)
    }

    static let shared = ModelSetup()

    @Published private(set) var state: State
    private let installer: ModelInstaller

    init(installer: ModelInstaller = ModelInstaller(), isReady: Bool = ModelFiles.isReady()) {
        self.installer = installer
        state = isReady ? .ready : .missing
    }

    /// True when soapcap's copy is on this Mac, so nothing needs downloading.
    var canCopyFromSoapcap: Bool { installer.canCopyFromSoapcap }

    func install() {
        if case .working = state { return }
        state = .working(file: "", fraction: 0)
        Task {
            do {
                try await installer.install { file, fraction in
                    Task { @MainActor in
                        if case .working = self.state { self.state = .working(file: file, fraction: fraction) }
                    }
                }
                state = .ready
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    /// For previews.
    func show(_ state: State) { self.state = state }

    /// The line on the checks screen.
    static func check(isReady: Bool = ModelFiles.isReady()) -> Check {
        isReady
            ? Check("De-identify", .ok, "The model is installed.")
            : Check("De-identify", .warning, "Optional and not set up. The model is a 130 MB download in Settings.",
                    fix: Check.Fix(label: "Open Settings", action: .showSettings))
    }
}
