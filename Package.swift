// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "BabyRecorder",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS("26.4.1")
    ],
    products: [
        .executable(name: "BabyRecorder", targets: ["BabyRecorder"])
    ],
    targets: [
        .executableTarget(
            name: "BabyRecorder",
            path: "Sources/BabyRecorder",
            resources: [
                .process("Resources")
            ],
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
