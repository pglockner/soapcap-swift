import CryptoKit
import Foundation

public enum ModelInstallError: Error, LocalizedError, Equatable {
    case download(file: String, detail: String)
    case checksum(file: String)

    public var errorDescription: String? {
        switch self {
        case .download(let file, let detail): "Couldn't download \(file): \(detail)"
        case .checksum(let file): "\(file) doesn't match the tested model's checksum, so it was discarded. The file upstream may have changed."
        }
    }
}

/// Puts the model's files in place: from soapcap's copy when there is one,
/// otherwise by downloading. Every file is checked against its pinned
/// checksum, and nothing is moved into place unless all of them pass.
/// The download is the only time the app uses the network; it sends no session data.
public struct ModelInstaller: Sendable {
    public enum Source: Equatable, Sendable { case soapcap, download }

    var files = ModelFiles.pinned
    var directory = ModelFiles.directory
    var soapcapModels = ModelFiles.soapcapModels
    var session = URLSession.shared

    public init() {}

    /// Whether soapcap's copy can supply every file, so no download is needed.
    public var canCopyFromSoapcap: Bool {
        files.allSatisfy { FileManager.default.fileExists(atPath: $0.soapcapCopy(in: soapcapModels).path) }
    }

    /// `progress` gets the file being fetched and how far along it is (0 to 1).
    /// Returns `.download` if any file came from the network.
    @discardableResult
    public func install(progress: @escaping @Sendable (String, Double) -> Void = { _, _ in }) async throws -> Source {
        let fm = FileManager.default
        let staging = directory.deletingLastPathComponent().appending(path: ".\(directory.lastPathComponent)-\(UUID().uuidString)")
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        var source = Source.soapcap
        for file in files {
            let target = staging.appending(path: file.name)
            let copy = file.soapcapCopy(in: soapcapModels)
            if (try? Self.sha256(of: copy)) == file.sha256 {
                try fm.copyItem(at: copy.resolvingSymlinksInPath(), to: target)
                continue
            }
            source = .download
            try await download(file, to: target, progress: progress)
            guard try Self.sha256(of: target) == file.sha256 else { throw ModelInstallError.checksum(file: file.name) }
        }
        try? fm.removeItem(at: directory)
        try fm.moveItem(at: staging, to: directory)
        return source
    }

    private func download(_ file: ModelFile, to target: URL, progress: @escaping @Sendable (String, Double) -> Void) async throws {
        progress(file.name, 0)
        let watcher = ProgressWatcher { progress(file.name, $0) }
        let fetched: URL, response: URLResponse
        do {
            (fetched, response) = try await session.download(from: file.url, delegate: watcher)
        } catch {
            throw ModelInstallError.download(file: file.name, detail: error.localizedDescription)
        }
        defer { try? FileManager.default.removeItem(at: fetched) }
        if let status = (response as? HTTPURLResponse)?.statusCode, status != 200 {
            throw ModelInstallError.download(file: file.name, detail: "the server answered \(status)")
        }
        try FileManager.default.moveItem(at: fetched, to: target)
        progress(file.name, 1)
    }

    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// Relays a download's progress as it runs.
private final class ProgressWatcher: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let report: @Sendable (Double) -> Void
    private var observation: NSKeyValueObservation?

    init(report: @escaping @Sendable (Double) -> Void) { self.report = report }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        observation = task.progress.observe(\.fractionCompleted) { [report] progress, _ in report(progress.fractionCompleted) }
    }
}
