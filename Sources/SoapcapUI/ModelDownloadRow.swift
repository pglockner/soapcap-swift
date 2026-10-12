import SoapcapCore
import SwiftUI

/// One downloadable model in Settings: what it costs before you get it,
/// how it is going, and a way to remove it.
struct ModelDownloadRow: View {
    let name: String
    /// Memory it takes while drafting, if known.
    let needGB: Double?
    @ObservedObject var download: ModelDownload
    var memoryGB: Double? = MemoryStatus.current()?.totalGB

    var body: some View {
        switch download.state {
        case .ready:
            HStack {
                Label("\(name) is on this Mac (\(ByteCount.text(download.file.bytes))).", systemImage: "checkmark.circle.fill")
                Spacer()
                Button("Remove") { download.remove() }
            }
        case .elsewhere:
            Label("Using the copy of \(name) that soapcap installed.", systemImage: "checkmark.circle.fill")
        case .working(let progress):
            ProgressView(value: progress.fraction) { Text(progress.summary) }
            Button("Stop") { download.stop() }
        case .missing, .failed:
            if case .failed(let why) = download.state { Text(why).foregroundStyle(.orange) }
            Text(cost).fixedSize(horizontal: false, vertical: true)
            if let short = shortOfDisk {
                Text(short).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            } else {
                Button(download.keptBytes > 0 ? "Carry on downloading" : "Download \(name)") { download.start() }
            }
        }
    }

    /// Size, time, disk and memory, said before anything is fetched.
    private var cost: String {
        let file = download.file
        let minutes = Int((Double(file.bytes) / 12_500_000 / 60).rounded(.up))
        var text = "\(name) is a \(ByteCount.text(file.bytes)) download from huggingface.co: about \(minutes) minutes on a 100 Mbit/s connection. Nothing from a session is sent."
        if download.keptBytes > 0 { text += " \(ByteCount.text(download.keptBytes)) is already here from an earlier try." }
        if let free = download.freeBytes { text += " This Mac has \(ByteCount.text(free)) of disk free." }
        if let needGB {
            // Rounded up: a need that is understated is the one that hurts.
            text += String(format: " It takes about %.0f GB of memory while drafting", needGB.rounded(.up))
            if let memoryGB, memoryGB < needGB * 1.5 {
                text += String(format: ", and this Mac has %.0f GB, so drafting with it will be very slow.", memoryGB)
            } else {
                text += "."
            }
        }
        return text
    }

    private var shortOfDisk: String? {
        guard let free = download.freeBytes, free < download.file.bytes - download.keptBytes else { return nil }
        return "There isn't room for it: free up \(ByteCount.text(download.file.bytes - download.keptBytes - free)) of disk first."
    }
}
