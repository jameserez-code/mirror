// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Mirror",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Mirror",
            path: "Mirror",
            resources: [
                .copy("ui.html"),
                .copy("settings.html"),
                .copy("editor.html"),
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("WebKit"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Security"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Vision"),
                .linkedFramework("System"),
                .linkedFramework("Foundation"),
            ]
        )
    ]
)
