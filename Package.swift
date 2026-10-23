// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Brimtune",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Brimtune",
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
