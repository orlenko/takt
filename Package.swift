// swift-tools-version: 6.0
import PackageDescription

let swiftSettings: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "takt",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "TaktCore",
            swiftSettings: swiftSettings
        ),
        .target(
            name: "TaktAudio",
            dependencies: ["TaktCore"],
            resources: [.copy("Resources/TAKT-1")],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "TaktMIDI",
            dependencies: ["TaktCore"],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "TaktUI",
            dependencies: ["TaktCore", "TaktAudio", "TaktMIDI"],
            swiftSettings: swiftSettings
        ),
        .executableTarget(
            name: "takt",
            dependencies: ["TaktUI"],
            swiftSettings: swiftSettings
        ),
        .executableTarget(
            name: "takt-render-kit",
            dependencies: ["TaktCore"],
            swiftSettings: swiftSettings
        ),
        .executableTarget(
            name: "takt-bounce",
            dependencies: ["TaktCore", "TaktAudio"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "TaktCoreTests",
            dependencies: ["TaktCore"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "TaktAudioTests",
            dependencies: ["TaktAudio"],
            swiftSettings: swiftSettings
        ),
    ]
)
