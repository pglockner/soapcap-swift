import CryptoKit
import Foundation

/// A file that is fetched once from a fixed address and must match a
/// pinned checksum.
public struct PinnedFile: Equatable, Sendable {
    public let name: String
    public let url: URL
    public let sha256: String
    /// Its size, known in advance so that room and time can be told first.
    public let bytes: Int64

    public init(name: String, url: URL, sha256: String, bytes: Int64) {
        self.name = name
        self.url = url
        self.sha256 = sha256
        self.bytes = bytes
    }
}

public enum FetchError: Error, LocalizedError, Equatable {
    case download(file: String, detail: String)
    case checksum(file: String)
    case noRoom(file: String, needBytes: Int64, freeBytes: Int64)

    public var errorDescription: String? {
        switch self {
        case .download(let file, let detail): "Couldn't download \(file): \(detail)"
        case .checksum(let file): "\(file) doesn't match the tested file's checksum, so it was discarded. The file upstream may have changed."
        case .noRoom(let file, let need, let free):
            "\(file) needs \(ByteCount.text(need)) of disk and this Mac has \(ByteCount.text(free)) free."
        }
    }
}

/// How a fetch is going.
public struct FetchProgress: Equatable, Sendable {
    /// Fetched so far, counting what an earlier attempt left behind.
    public var bytes: Int64
    public var total: Int64
    /// Measured over this attempt; 0 until there is something to measure.
    public var bytesPerSecond: Double
    /// True once everything has arrived and the checksum is being worked out.
    public var isVerifying: Bool

    public init(bytes: Int64, total: Int64, bytesPerSecond: Double = 0, isVerifying: Bool = false) {
        self.bytes = bytes
        self.total = total
        self.bytesPerSecond = bytesPerSecond
        self.isVerifying = isVerifying
    }

    public var fraction: Double { total > 0 ? min(1, Double(bytes) / Double(total)) : 0 }
    public var secondsLeft: Double? { bytesPerSecond > 0 ? Double(max(0, total - bytes)) / bytesPerSecond : nil }

    /// "2.1 of 5.9 GB, 24 MB a second, about 3 minutes left"
    public var summary: String {
        if isVerifying { return "Checking the download…" }
        var text = "\(ByteCount.text(bytes)) of \(ByteCount.text(total))"
        guard bytesPerSecond > 0, let secondsLeft else { return text }
        text += ", \(ByteCount.text(Int64(bytesPerSecond))) a second"
        let minutes = Int((secondsLeft / 60).rounded(.up))
        text += minutes <= 1 ? ", under a minute left" : ", about \(minutes) minutes left"
        return text
    }
}

/// Sizes the way Finder shows them: "5.9 GB", "130 MB".
public enum ByteCount {
    public static func text(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_000_000_000
        if gb >= 1 { return String(format: gb >= 10 ? "%.0f GB" : "%.1f GB", gb) }
        return String(format: "%.0f MB", Double(bytes) / 1_000_000)
    }
}

/// Fetches a pinned file to a place on disk. A fetch that is interrupted
/// leaves `<name>.part` beside the target and the next one carries on from
/// there. Nothing is put in place until the whole file matches its checksum.
public struct Fetcher: Sendable {
    /// What the requests are made with; tests put a stub here.
    public var configuration: URLSessionConfiguration
    /// Room on the disk that will hold the file.
    public var freeBytes: @Sendable (URL) -> Int64? = Fetcher.freeBytes

    public init(configuration: URLSessionConfiguration = .default) { self.configuration = configuration }

    public static func part(of target: URL) -> URL { target.appendingPathExtension("part") }

    public func fetch(_ file: PinnedFile, to target: URL,
                      progress: @escaping @Sendable (FetchProgress) -> Void = { _ in }) async throws {
        let fm = FileManager.default
        let part = Self.part(of: target)
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)

        var have = Self.size(of: part)
        if have > file.bytes { try? fm.removeItem(at: part); have = 0 }
        if let free = freeBytes(target.deletingLastPathComponent()), free < file.bytes - have {
            throw FetchError.noRoom(file: file.name, needBytes: file.bytes - have, freeBytes: free)
        }
        if have < file.bytes {
            if have == 0 { fm.createFile(atPath: part.path, contents: nil) }
            do { try await receive(file, into: part, from: have, progress: progress) } catch {
                if Self.size(of: part) == 0 { try? fm.removeItem(at: part) }     // nothing worth carrying on from
                throw error
            }
        }

        progress(FetchProgress(bytes: file.bytes, total: file.bytes, isVerifying: true))
        guard try Self.sha256(of: part) == file.sha256 else {
            try? fm.removeItem(at: part)
            throw FetchError.checksum(file: file.name)
        }
        try? fm.removeItem(at: target)
        try fm.moveItem(at: part, to: target)
    }

    /// Appends what the server sends to `part`, asking only for what is missing.
    private func receive(_ file: PinnedFile, into part: URL, from have: Int64,
                         progress: @escaping @Sendable (FetchProgress) -> Void) async throws {
        var request = URLRequest(url: file.url)
        if have > 0 { request.setValue("bytes=\(have)-", forHTTPHeaderField: "Range") }
        let receiver = try Receiver(file: file, part: part, have: have, progress: progress)
        let session = URLSession(configuration: configuration, delegate: receiver, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let task = session.dataTask(with: request)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
                receiver.done = done
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }

    public static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    public static func size(of url: URL) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value ?? 0
    }

    /// Room on the disk that holds `directory`, as the Finder would count it.
    public static func freeBytes(_ directory: URL) -> Int64? {
        var existing = directory
        while !FileManager.default.fileExists(atPath: existing.path), existing.path != "/" { existing.deleteLastPathComponent() }
        return try? existing.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage
    }
}

/// Writes a download to disk as it arrives and says how far it has got.
private final class Receiver: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    var done: CheckedContinuation<Void, Error>?
    private let file: PinnedFile
    private let part: URL
    private let handle: FileHandle
    private let progress: @Sendable (FetchProgress) -> Void
    private let started = Date()
    private var bytes: Int64
    private var arrived: Int64 = 0
    private var lastReport = Date.distantPast
    private var failure: Error?

    init(file: PinnedFile, part: URL, have: Int64, progress: @escaping @Sendable (FetchProgress) -> Void) throws {
        self.file = file
        self.part = part
        self.progress = progress
        bytes = have
        handle = try FileHandle(forWritingTo: part)
        try handle.seekToEnd()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        switch (response as? HTTPURLResponse)?.statusCode ?? 200 {
        case 206:
            break
        case 200:
            // The whole file is coming, whatever was asked for: start again.
            if bytes > 0 { try? handle.truncate(atOffset: 0); bytes = 0 }
        case let status:
            failure = FetchError.download(file: file.name, detail: "the server answered \(status)")
            return completionHandler(.cancel)
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        do { try handle.write(contentsOf: data) } catch {
            failure = FetchError.download(file: file.name, detail: error.localizedDescription)
            return dataTask.cancel()
        }
        bytes += Int64(data.count)
        arrived += Int64(data.count)
        guard Date().timeIntervalSince(lastReport) >= 0.25 else { return }
        lastReport = Date()
        let elapsed = Date().timeIntervalSince(started)
        progress(FetchProgress(bytes: bytes, total: file.bytes, bytesPerSecond: elapsed > 1 ? Double(arrived) / elapsed : 0))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        try? handle.close()
        if let failure {
            done?.resume(throwing: failure)
        } else if let error {
            done?.resume(throwing: (error as? URLError)?.code == .cancelled
                ? CancellationError() : FetchError.download(file: file.name, detail: error.localizedDescription))
        } else if bytes < file.bytes {
            done?.resume(throwing: FetchError.download(file: file.name, detail: "the connection closed early"))
        } else {
            done?.resume()
        }
        done = nil
    }
}
