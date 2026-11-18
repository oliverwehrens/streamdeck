// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StreamDeck",
    platforms: [.macOS(.v14)],
    products: [],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0"),
    ],
    targets: [
        // Portable: builds and tests on macOS and Linux.
        .target(name: "DeckSupport"),
        .target(name: "DeckHID"),
        .target(name: "DeckConfig", dependencies: ["Yams"]),
        .target(name: "DeckEngine", dependencies: ["DeckSupport", "DeckHID", "DeckConfig"]),
        .testTarget(name: "DeckSupportTests", dependencies: ["DeckSupport"]),
        .testTarget(name: "DeckHIDTests", dependencies: ["DeckHID"]),
        .testTarget(name: "DeckConfigTests", dependencies: ["DeckConfig", "DeckSupport"]),
        .testTarget(name: "DeckEngineTests", dependencies: ["DeckEngine", "DeckSupport"]),
    ]
)

#if os(macOS)
// macOS only: AppKit rendering, IOKit and CGEvent platform code, and the menu-bar app.
package.products.append(.executable(name: "StreamDeckApp", targets: ["StreamDeckApp"]))
package.targets.append(contentsOf: [
    .target(name: "DeckRender", dependencies: ["DeckConfig", "DeckEngine"]),
    .target(name: "DeckPlatformMac", dependencies: ["DeckHID", "DeckConfig", "DeckEngine"]),
    .executableTarget(name: "StreamDeckApp", dependencies: ["DeckEngine", "DeckHID", "DeckConfig", "DeckRender", "DeckPlatformMac"]),
    .testTarget(name: "DeckRenderTests", dependencies: ["DeckRender", "DeckEngine"]),
    .testTarget(name: "DeckPlatformMacTests", dependencies: ["DeckPlatformMac", "DeckEngine", "DeckConfig"]),
    .testTarget(name: "StreamDeckAppTests", dependencies: ["StreamDeckApp", "DeckConfig", "DeckEngine"]),
])
#endif
