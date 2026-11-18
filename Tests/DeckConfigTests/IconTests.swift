import Foundation
import Testing
import DeckConfig

private let directory = URL(fileURLWithPath: "/Users/test/.config/streamdeck")

@Test func symbolIcon() {
    #expect(Icon(configValue: "sf:lightbulb.fill", relativeTo: directory) == .symbol("lightbulb.fill"))
}

@Test func materialSymbolIcon() {
    #expect(Icon(configValue: "ms:play_arrow", relativeTo: directory) == .material(name: "play_arrow", filled: false))
}

@Test func filledMaterialSymbolIcon() {
    #expect(Icon(configValue: "ms:lightbulb.fill", relativeTo: directory) == .material(name: "lightbulb", filled: true))
}

@Test func emptyMaterialSymbolNameIsPassedToRenderer() {
    #expect(Icon(configValue: "ms:", relativeTo: directory) == .material(name: "", filled: false))
}

@Test func tildeIconExpandsToHome() {
    #expect(Icon(configValue: "~/x.png", relativeTo: directory) == .file(NSHomeDirectory() + "/x.png"))
}

@Test func absoluteIconIsKept() {
    #expect(Icon(configValue: "/abs.png", relativeTo: directory) == .file("/abs.png"))
}

@Test func relativeIconResolvesAgainstDirectory() {
    #expect(Icon(configValue: "icons/x.png", relativeTo: directory) == .file("/Users/test/.config/streamdeck/icons/x.png"))
}

@Test func resolvePathHandlesTildeAbsoluteAndRelative() {
    #expect(resolvePath("~/x.png", relativeTo: directory) == NSHomeDirectory() + "/x.png")
    #expect(resolvePath("/abs.png", relativeTo: directory) == "/abs.png")
    #expect(resolvePath("art/x.png", relativeTo: directory) == "/Users/test/.config/streamdeck/art/x.png")
}
