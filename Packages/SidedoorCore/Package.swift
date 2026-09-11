// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SidedoorCore",
    platforms: [
        .iOS(.v26),
        .macOS(.v13)   // host floor for `swift test`: enables async URLSession + modern Foundation APIs
    ],
    products: [
        .library(name: "SidedoorCore", targets: ["SidedoorCore"])
    ],
    targets: [
        .target(
            name: "SidedoorCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "SidedoorCoreTests",
            dependencies: ["SidedoorCore"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
