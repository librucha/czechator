// swift-tools-version: 6.0
import PackageDescription

// The menu bar app is macOS-only; on Linux only the core and the CLI are built.
#if os(macOS)
    let appProducts: [Product] = [
        .executable(name: "CzechatorApp", targets: ["CzechatorApp"])
    ]
    let appTargets: [Target] = [
        .executableTarget(name: "CzechatorApp", dependencies: ["CzechatorCore"]),
        .testTarget(name: "CzechatorAppTests", dependencies: ["CzechatorApp"]),
    ]
#else
    let appProducts: [Product] = []
    let appTargets: [Target] = []
#endif

let package = Package(
    name: "czechator",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CzechatorCore", targets: ["CzechatorCore"]),
        .executable(name: "czechator", targets: ["czechator"]),
    ] + appProducts,
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
        .package(url: "https://github.com/jpsim/Yams", from: "5.1.0"),
    ],
    targets: [
        .target(
            name: "CzechatorCore",
            dependencies: [.product(name: "Yams", package: "Yams")]
        ),
        .executableTarget(
            name: "czechator",
            dependencies: [
                "CzechatorCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(name: "CzechatorCoreTests", dependencies: ["CzechatorCore"]),
    ] + appTargets
)
