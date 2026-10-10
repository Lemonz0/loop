// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LiquidGlassMessaging",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "LiquidGlassMessaging",
            targets: ["LiquidGlassMessaging"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "LiquidGlassMessaging",
            path: ".",
            exclude: ["Package.swift"],
            sources: [
                "App",
                "DesignSystem",
                "Models",
                "Networking",
                "MediaPipeline",
                "Calling",
                "Views"
            ]
        ),
    ]
)
