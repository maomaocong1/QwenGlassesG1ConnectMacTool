// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "QwenGlasses",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "IOBluetoothShim",
            path: "Sources/IOBluetoothShim",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("IOBluetooth"),
                .linkedFramework("AppKit"),
            ]
        ),
        .executableTarget(
            name: "QwenGlasses",
            dependencies: ["IOBluetoothShim"],
            path: "Sources/QwenGlasses",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("IOBluetooth"),
                .linkedFramework("CoreBluetooth"),
            ]
        ),
    ]
)
