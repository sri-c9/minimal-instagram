// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "IGCore",
    platforms: [
        .iOS(.v26),
        .macOS(.v13)   // host floor for `swift test`: enables async URLSession + modern Foundation APIs
    ],
    products: [
        .library(name: "IGCore", targets: ["IGCore"])
    ],
    targets: [
        .target(
            name: "IGCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "IGCoreTests",
            dependencies: ["IGCore"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
