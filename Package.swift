// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StreamDeck",
    platforms: [.macOS(.v14)],
    products: [],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.2.2"),
    ],
    targets: [
        // Portable: builds and tests on macOS and Linux.
        .target(name: "DeckSupport"),
        .target(name: "CStb"),
        .target(name: "DeckHID"),
        .target(name: "DeckConfig", dependencies: ["Yams"]),
        .target(name: "DeckEngine", dependencies: ["DeckSupport", "DeckHID", "DeckConfig"]),
        .target(name: "DeckRender", dependencies: ["CStb", "DeckConfig", "DeckEngine"]),
        .testTarget(name: "DeckSupportTests", dependencies: ["DeckSupport"]),
        .testTarget(name: "DeckHIDTests", dependencies: ["DeckHID"]),
        .testTarget(name: "DeckConfigTests", dependencies: ["DeckConfig", "DeckSupport"]),
        .testTarget(name: "DeckEngineTests", dependencies: ["DeckEngine", "DeckSupport"]),
        .testTarget(name: "DeckRenderTests", dependencies: ["DeckRender", "DeckEngine", "CStb"]),
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
    .executableTarget(name: "streamdeckd", dependencies: ["DeckPlatformLinux", "DeckEngine", "DeckHID", "DeckConfig", "DeckRender"]),
    .testTarget(name: "DeckPlatformLinuxTests", dependencies: ["DeckPlatformLinux", "CLinux", "DeckEngine", "DeckHID", "DeckConfig", "DeckSupport"],
                resources: [.copy("Fixtures")]),
])
#endif
