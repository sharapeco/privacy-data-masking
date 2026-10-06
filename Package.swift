// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "pdmask",
    platforms: [
        .macOS(.v26)   // FoundationModels / @Generable / LanguageModelSession require macOS 26
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0")
    ],
    targets: [
        .target(name: "PDMaskCore"),
        .executableTarget(
            name: "pdmask",
            dependencies: [
                "PDMaskCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .testTarget(
            name: "PDMaskCoreTests",
            dependencies: ["PDMaskCore"]
        )
    ]
)
