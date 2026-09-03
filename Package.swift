// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "GLKBCite",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "GLKBCiteCore", targets: ["GLKBCiteCore"]),
        .executable(name: "GLKBCiteMac", targets: ["GLKBCiteMac"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.5")
    ],
    targets: [
        .target(
            name: "GLKBCiteCore"
        ),
        .executableTarget(
            name: "GLKBCiteMac",
            dependencies: [
                "GLKBCiteCore",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            exclude: [
                "Resources"
            ]
        ),
        .testTarget(
            name: "GLKBCiteCoreTests",
            dependencies: ["GLKBCiteCore"],
            resources: [
                .process("Fixtures")
            ]
        ),
        .testTarget(
            name: "GLKBCiteMacTests",
            dependencies: ["GLKBCiteMac"]
        )
    ],
    swiftLanguageModes: [.v6]
)
