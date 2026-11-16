// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AppleLens",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "AppleLensCore",
            targets: ["AppleLensCore"]
        ),
        .executable(
            name: "AppleLensApp",
            targets: ["AppleLensApp"]
        ),
        .executable(
            name: "applelens",
            targets: ["applelens-cli"]
        )
    ],
    dependencies: [
        // Zero external dependencies (pure Swift + Darwin / Security / Network / SystemConfiguration)
    ],
    targets: [
        .target(
            name: "AppleLensCore",
            dependencies: [],
            path: "Sources/AppleLensCore",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .executableTarget(
            name: "AppleLensApp",
            dependencies: ["AppleLensCore"],
            path: "Sources/AppleLensApp",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .executableTarget(
            name: "applelens-cli",
            dependencies: ["AppleLensCore"],
            path: "Sources/applelens-cli",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "AppleLensCoreTests",
            dependencies: ["AppleLensCore"],
            path: "Tests/AppleLensCoreTests",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
