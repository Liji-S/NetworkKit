// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NetworkKit",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(name: "NetworkKit", targets: ["NetworkKit"]),
        .library(name: "NetworkKitTesting", targets: ["NetworkKitTesting"])
    ],
    targets: [
        .target(name: "NetworkKit"),
        .target(
            name: "NetworkKitTesting",
            dependencies: ["NetworkKit"]
        ),
        .testTarget(
            name: "NetworkKitTests",
            dependencies: ["NetworkKit", "NetworkKitTesting"]
        )
    ],
    swiftLanguageModes: [.v6]
)
