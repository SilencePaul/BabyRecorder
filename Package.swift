// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BabyRecorder",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "BabyRecorder", targets: ["BabyRecorder"])
    ],
    targets: [
        .executableTarget(
            name: "BabyRecorder",
            path: "Sources/BabyRecorder",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("SwiftUI")
            ]
        ),
        .testTarget(
            name: "BabyRecorderTests",
            dependencies: ["BabyRecorder"],
            path: "Tests/BabyRecorderTests"
        )
    ]
)
