// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "soapcap-swift",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Soapcap", targets: ["Soapcap"]),
        .library(name: "SoapcapUI", targets: ["SoapcapUI"]),
    ],
    dependencies: [
        // OpenMed's on-device PII model runtime. Pinned to the version soapcap tested.
        .package(url: "https://github.com/maziyarpanahi/openmed.git", exact: "2.5.0"),
    ],
    targets: [
        // Pure logic with no UI, processes or frameworks beyond Foundation.
        .target(name: "SoapcapCore", path: "Sources/SoapcapCore"),
        // Audio capture and on-device transcription, producing SoapcapCore segments.
        .target(name: "SoapcapCapture", dependencies: ["SoapcapCore"], path: "Sources/SoapcapCapture",
                swiftSettings: [.swiftLanguageMode(.v5)]),
        // Note drafting: prompts, the model backends, and the checks on what comes back.
        .target(name: "SoapcapNote", dependencies: ["SoapcapCore"], path: "Sources/SoapcapNote",
                resources: [.copy("Resources/prompts")]),
        // De-identifying: the text rules around a detector, with no model of its own.
        .target(name: "SoapcapDeidentify", path: "Sources/SoapcapDeidentify"),
        // The model behind de-identifying. The only target that pulls in OpenMedKit.
        .target(name: "SoapcapPII", dependencies: ["SoapcapDeidentify", .product(name: "OpenMedKit", package: "openmed")],
                path: "Sources/SoapcapPII"),
        .executableTarget(name: "DeidentifyProbe", dependencies: ["SoapcapPII"], path: "Sources/DeidentifyProbe"),
        .executableTarget(name: "NoteProbe", dependencies: ["SoapcapNote"], path: "Sources/NoteProbe"),
        .executableTarget(name: "CaptureProbe", dependencies: ["SoapcapCapture"], path: "Sources/CaptureProbe"),
        // The window and session flow. A library so Xcode can render its previews.
        .target(name: "SoapcapUI", dependencies: ["SoapcapCore", "SoapcapCapture", "SoapcapNote"], path: "Sources/SoapcapUI",
                swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "Soapcap", dependencies: ["SoapcapUI"], path: "Sources/Soapcap"),
        .testTarget(name: "SoapcapCoreTests", dependencies: ["SoapcapCore"], path: "Tests/SoapcapCoreTests"),
        .testTarget(name: "SoapcapCaptureTests", dependencies: ["SoapcapCapture"], path: "Tests/SoapcapCaptureTests",
                    swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "SoapcapNoteTests", dependencies: ["SoapcapNote"], path: "Tests/SoapcapNoteTests"),
        .testTarget(name: "SoapcapDeidentifyTests", dependencies: ["SoapcapDeidentify"], path: "Tests/SoapcapDeidentifyTests"),
        .testTarget(name: "SoapcapUITests", dependencies: ["SoapcapUI"], path: "Tests/SoapcapUITests",
                    swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
