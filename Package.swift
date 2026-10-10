// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "soapcap-swift",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Soapcap", targets: ["Soapcap"]),
        .library(name: "SoapcapUI", targets: ["SoapcapUI"]),
    ],
    targets: [
        // Pure logic with no UI, processes or frameworks beyond Foundation.
        .target(name: "SoapcapCore", path: "Sources/SoapcapCore"),
        // The window and session flow. A library so Xcode can render its previews.
        .target(name: "SoapcapUI", dependencies: ["SoapcapCore"], path: "Sources/SoapcapUI",
                swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "Soapcap", dependencies: ["SoapcapUI"], path: "Sources/Soapcap"),
        .testTarget(name: "SoapcapCoreTests", dependencies: ["SoapcapCore"], path: "Tests/SoapcapCoreTests"),
        .testTarget(name: "SoapcapUITests", dependencies: ["SoapcapUI"], path: "Tests/SoapcapUITests",
                    swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
