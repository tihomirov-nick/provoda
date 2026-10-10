// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Provoda",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Provoda", targets: ["Provoda"]),
    ],
    targets: [
        // Localization and the interface language (InterfaceLanguage.swift is the family's shared file)
        .target(
            name: "ProvodaCore",
            path: "Sources/ProvodaCore"
        ),
        // The menu bar app: the icon, its menu and panel, Settings, updates, sounds
        .executableTarget(
            name: "Provoda",
            dependencies: ["ProvodaCore"],
            path: "Sources/Provoda"
        ),
        .testTarget(
            name: "ProvodaTests",
            dependencies: ["Provoda", "ProvodaCore"],
            path: "Tests/ProvodaTests"
        ),
    ]
)
