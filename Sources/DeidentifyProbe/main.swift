// A quick check of de-identifying without the window:
//   swift run DeidentifyProbe FILE [note]
// prints FILE with identifying text replaced, and a one-line count on stderr.
// The model is read from the app's folder; SOAPCAP_DEIDENTIFY_MODEL overrides.
//   swift run DeidentifyProbe --install
// puts the model there first, as the app's Download button does.
import Foundation
import SoapcapDeidentify
import SoapcapPII

let args = CommandLine.arguments.dropFirst()
if args.first == "--install" {
    do {
        let source = try await ModelInstaller().install { file, fraction in
            FileHandle.standardError.write(Data("\r\(file) \(Int(fraction * 100))%   ".utf8))
        }
        print("\nmodel ready in \(ModelFiles.directory.path) (\(source == .soapcap ? "copied from soapcap" : "downloaded"))")
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("\ninstall failed: \(error.localizedDescription)\n".utf8))
        exit(1)
    }
}
guard let path = args.first, let text = try? String(contentsOfFile: path, encoding: .utf8) else {
    FileHandle.standardError.write(Data("usage: DeidentifyProbe FILE [note]\n".utf8))
    exit(64)
}
do {
    let kind: LabeledText.Kind = args.dropFirst().first == "note" ? .note : .transcript
    let result = try await Deidentifier(detector: OpenMedDetector()).deidentify(text, kind: kind)
    print(result.text, terminator: "")
    FileHandle.standardError.write(Data((result.summary + "\n").utf8))
} catch {
    FileHandle.standardError.write(Data("de-identify failed: \(error.localizedDescription)\n".utf8))
    exit(1)
}
