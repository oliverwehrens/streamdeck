// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StreamDeck",
    platforms: [.macOS(.v14)],
    products: [],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.2.2"),
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
        // Already dependencies of Hummingbird; named so DeckWeb can import them directly.
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.80.0"),
        .package(url: "https://github.com/apple/swift-http-types.git", from: "1.0.0"),
    ],
    targets: [
        // Portable: builds and tests on macOS and Linux.
        .target(name: "DeckSupport"),
        .target(name: "CStb"),
        .target(name: "DeckHID"),
        .target(name: "DeckConfig", dependencies: ["Yams"]),
        .target(name: "DeckEngine", dependencies: ["DeckSupport", "DeckHID", "DeckConfig"]),
        .target(name: "DeckRender", dependencies: ["CStb", "DeckConfig", "DeckEngine"]),
        .target(name: "DeckEditor", dependencies: ["DeckConfig"]),
        .target(name: "CWebAssets"),
        .target(name: "DeckWeb", dependencies: [
            "DeckSupport", "DeckHID", "DeckConfig", "DeckEngine", "DeckRender", "DeckEditor", "CStb", "CWebAssets",
            .product(name: "Hummingbird", package: "hummingbird"),
            .product(name: "Logging", package: "swift-log"),
            .product(name: "NIOCore", package: "swift-nio"),
            .product(name: "HTTPTypes", package: "swift-http-types"),
        ]),
        .testTarget(name: "DeckSupportTests", dependencies: ["DeckSupport"]),
        .testTarget(name: "DeckHIDTests", dependencies: ["DeckHID"]),
        .testTarget(name: "DeckConfigTests", dependencies: ["DeckConfig", "DeckSupport"]),
        .testTarget(name: "DeckEngineTests", dependencies: ["DeckEngine", "DeckSupport"]),
        .testTarget(name: "DeckRenderTests", dependencies: ["DeckRender", "DeckEngine", "CStb"]),
        .testTarget(name: "DeckEditorTests", dependencies: ["DeckEditor", "DeckConfig"]),
        .testTarget(name: "DeckWebTests", dependencies: [
            "DeckWeb", "DeckEditor", "DeckEngine", "DeckConfig", "DeckHID", "DeckSupport",
            .product(name: "HummingbirdTesting", package: "hummingbird"),
        ]),
    ],
    cLanguageStandard: .c2x
)

#if os(macOS)
// macOS only: IOKit, CGEvent and SF Symbol platform code, and the menu-bar app.
package.products.append(.executable(name: "StreamDeckApp", targets: ["StreamDeckApp"]))
package.targets.append(contentsOf: [
    .target(name: "DeckPlatformMac", dependencies: ["DeckHID", "DeckConfig", "DeckEngine", "DeckRender"]),
    .executableTarget(name: "StreamDeckApp", dependencies: ["DeckEngine", "DeckHID", "DeckConfig", "DeckRender", "DeckPlatformMac"]),
    .testTarget(name: "DeckPlatformMacTests", dependencies: ["DeckPlatformMac", "DeckEngine", "DeckConfig", "DeckRender"]),
    .testTarget(name: "StreamDeckAppTests", dependencies: ["StreamDeckApp", "DeckConfig", "DeckEngine"]),
])
#endif

#if os(Linux)
// Linux only: hidraw and uinput platform code, and the headless daemon.
package.products.append(.executable(name: "streamdeckd", targets: ["streamdeckd"]))
package.targets.append(contentsOf: [
    .target(name: "CLinux"),
    .target(name: "DeckPlatformLinux", dependencies: ["CLinux", "DeckSupport", "DeckHID", "DeckConfig", "DeckEngine"]),
    .executableTarget(name: "streamdeckd", dependencies: ["DeckPlatformLinux", "DeckEngine", "DeckHID", "DeckConfig", "DeckRender", "DeckWeb"]),
    .testTarget(name: "DeckPlatformLinuxTests", dependencies: ["DeckPlatformLinux", "CLinux", "DeckEngine", "DeckHID", "DeckConfig", "DeckSupport"],
                resources: [.copy("Fixtures")]),
])
#endif
