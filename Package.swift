// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FrenchLive",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "FrenchLive", targets: ["FrenchLive"]),
    ],
    targets: [
        .executableTarget(
            name: "FrenchLive",
            dependencies: ["FrenchLiveCore"],
            path: "Sources/FrenchLive"
        ),
        .target(
            name: "FrenchLiveCore",
            path: "Sources/FrenchLiveCore",
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("Speech"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Translation"),
                .linkedFramework("_Translation_SwiftUI"),
            ]
        ),
        .testTarget(
            name: "FrenchLiveTests",
            dependencies: ["FrenchLiveCore"],
            path: "Tests/FrenchLiveTests",
            swiftSettings: [
                .unsafeFlags(["-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"]),
            ],
            linkerSettings: [
                .unsafeFlags(["-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"]),
            ]
        ),
    ]
)
