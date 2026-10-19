// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StreamDeck",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "StreamDeckApp", targets: ["StreamDeckApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0"),
    ],
    targets: [
        .target(name: "DeckHID"),
        .target(name: "DeckConfig", dependencies: ["Yams"]),
        .target(name: "DeckRender", dependencies: ["DeckConfig"]),
        .target(name: "DeckEngine", dependencies: ["DeckHID", "DeckConfig", "DeckRender"]),
        .executableTarget(name: "StreamDeckApp", dependencies: ["DeckEngine", "DeckHID", "DeckConfig", "DeckRender"]),
        .testTarget(name: "DeckHIDTests", dependencies: ["DeckHID"]),
        .testTarget(name: "DeckConfigTests", dependencies: ["DeckConfig"]),
        .testTarget(name: "DeckRenderTests", dependencies: ["DeckRender"]),
        .testTarget(name: "DeckEngineTests", dependencies: ["DeckEngine"]),
        .testTarget(name: "StreamDeckAppTests", dependencies: ["StreamDeckApp", "DeckConfig"]),
    ]
)
