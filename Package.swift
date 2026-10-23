// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Brimtune",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Auto-updates for apps distributed outside the App Store.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        .executableTarget(
            name: "Brimtune",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/Brimtune",
            linkerSettings: [
                .linkedFramework("IOBluetooth"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("EventKit"),
                .linkedFramework("Accelerate"),
            ]
        )
    ]
)
