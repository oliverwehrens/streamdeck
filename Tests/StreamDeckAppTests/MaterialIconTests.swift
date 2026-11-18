import Testing
@testable import StreamDeckApp

@Test func parsesOutlinedAndFilled() {
    #expect(MaterialIcon(configValue: "ms:home") == MaterialIcon(name: "home", filled: false))
    #expect(MaterialIcon(configValue: "ms:home.fill") == MaterialIcon(name: "home", filled: true))
    #expect(MaterialIcon(configValue: "ms:") == MaterialIcon(name: "", filled: false))
    #expect(MaterialIcon(configValue: "sf:house") == nil)
    #expect(MaterialIcon(configValue: "icons/home.png") == nil)
}

@Test func writesConfigText() {
    #expect(MaterialIcon(name: "home", filled: true).configValue == "ms:home.fill")
    #expect(MaterialIcon(name: "play_arrow", filled: false).configValue == "ms:play_arrow")
    for text in ["ms:home", "ms:home.fill", "ms:"] {
        #expect(MaterialIcon(configValue: text)?.configValue == text)
    }
}
