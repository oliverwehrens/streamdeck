import Foundation
import Testing
import DeckConfig

private let directory = URL(fileURLWithPath: "/Users/test/.config/streamdeck")

@Test func symbolIcon() {
    #expect(Icon(configValue: "sf:lightbulb.fill", relativeTo: directory) == .symbol("lightbulb.fill"))
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
