// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Nuntius",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Nuntius", targets: ["Nuntius"])
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.15.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.8.0")
    ],
    targets: [
        .executableTarget(
            name: "Nuntius",
            dependencies: [
                "WhisperKit",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/Nuntius",
            resources: [
                .process("Assets.xcassets")
            ]
        ),
        .testTarget(
            name: "NuntiusTests",
            dependencies: ["Nuntius"],
            path: "Tests/NuntiusTests"
        )
    ]
)
