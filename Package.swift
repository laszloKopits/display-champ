// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DisplayChamp",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "DisplayChamp",
            path: "Sources/DisplayChamp",
            resources: [
                .copy("Resources/AppIcon.icns")
            ],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("AppKit"),
                .linkedFramework("AudioToolbox"),
            ]
        )
    ]
)
