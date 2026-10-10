import Foundation

/// The de-identification model's files on this Mac.
public enum ModelFiles {
    /// Where the app keeps them. SOAPCAP_DEIDENTIFY_MODEL overrides.
    public static var directory: URL {
        if let path = ProcessInfo.processInfo.environment["SOAPCAP_DEIDENTIFY_MODEL"] { return URL(fileURLWithPath: path) }
        return URL.applicationSupportDirectory.appending(path: "Soapcap/deidentify-model", directoryHint: .isDirectory)
    }
}
