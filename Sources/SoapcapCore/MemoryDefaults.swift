import Foundation

/// Settings kept in memory, for tests and previews. A suite of the real
/// kind leaves a file in ~/Library/Preferences, and macOS writes it back
/// even after it has been removed.
public final class MemoryDefaults: UserDefaults {
    private var values: [String: Any] = [:]
    public override func object(forKey key: String) -> Any? { values[key] }
    public override func set(_ value: Any?, forKey key: String) { values[key] = value }
    public override func removeObject(forKey key: String) { values[key] = nil }
}
