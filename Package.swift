// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "soapcap-swift",
    platforms: [.macOS(.v26)],
    targets: [
        // Pure logic with no UI, processes or frameworks beyond Foundation.
        .target(name: "SoapcapCore", path: "Sources/SoapcapCore"),
        .executableTarget(name: "Soapcap", dependencies: ["SoapcapCore"], path: "Sources/Soapcap",
                          swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "SoapcapCoreTests", dependencies: ["SoapcapCore"], path: "Tests/SoapcapCoreTests"),
        .testTarget(name: "SoapcapTests", dependencies: ["Soapcap"], path: "Tests/SoapcapTests",
                    swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
