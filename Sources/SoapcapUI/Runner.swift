import Foundation

/// Drives the soapcap CLI as child processes. Nothing here touches disk.
enum Runner {
    /// SOAPCAP_BIN overrides; otherwise the installed `soapcap` (install.sh
    /// symlinks it into Homebrew's bin), resolved to the real script so the
    /// soapcap checkout it lives in can be found.
    static var bin: URL {
        if let p = ProcessInfo.processInfo.environment["SOAPCAP_BIN"] { return URL(fileURLWithPath: p) }
        let candidates = ["/opt/homebrew/bin/soapcap", "/usr/local/bin/soapcap"]
        let found = candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? candidates[0]
        return URL(fileURLWithPath: found).resolvingSymlinksInPath()
    }

    /// soapcap's de-identify helper, where its tools/deidentify/install.sh puts it.
    static var deidentifyAvailable: Bool {
        let env = ProcessInfo.processInfo.environment
        let dir = env["SOAPCAP_DEIDENTIFY_DIR"]
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".local/share/soapcap/deidentify").path
        let path = env["SOAPCAP_DEIDENTIFY_BIN"] ?? dir + "/soapcap-deidentify-helper"
        return FileManager.default.isExecutableFile(atPath: path)
    }

    /// GUI apps get a minimal PATH; soapcap needs Homebrew's jq, ollama, etc.
    static func makeProcess(_ args: [String]) -> Process {
        let p = Process()
        p.executableURL = bin
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
        p.environment = env
        return p
    }

    private static func drain(_ p: Process, out: Pipe, err: Pipe) -> (String, String) {
        var o = Data(), e = Data()
        let g = DispatchGroup()
        g.enter(); DispatchQueue.global().async { o = out.fileHandleForReading.readDataToEndOfFile(); g.leave() }
        g.enter(); DispatchQueue.global().async { e = err.fileHandleForReading.readDataToEndOfFile(); g.leave() }
        p.waitUntilExit()
        g.wait()
        return (String(decoding: o, as: UTF8.self), String(decoding: e, as: UTF8.self))
    }

    /// Runs `soapcap <args>` with `input` on stdin.
    static func pipe(_ args: [String], input: String) async -> (out: String, err: String, status: Int32) {
        await withCheckedContinuation { cont in
            DispatchQueue.global().async {
                let p = makeProcess(args)
                let i = Pipe(), o = Pipe(), e = Pipe()
                p.standardInput = i; p.standardOutput = o; p.standardError = e
                do { try p.run() } catch {
                    cont.resume(returning: ("", "could not run \(bin.path): \(error)", 127)); return
                }
                i.fileHandleForWriting.write(Data(input.utf8))
                try? i.fileHandleForWriting.close()
                let (out, err) = drain(p, out: o, err: e)
                cont.resume(returning: (out, err.trimmingCharacters(in: .whitespacesAndNewlines), p.terminationStatus))
            }
        }
    }
}
