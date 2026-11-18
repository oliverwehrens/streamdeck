import DeckConfig
import DeckEngine
import DeckRender
import Testing
@testable import DeckPlatformMac

@Test func knownSymbolIsWhite() throws {
    let image = try #require(AppKitSFSymbolSource().image(named: "square.fill", pointSize: 48))
    let center = image[image.width / 2, image.height / 2]
    #expect(center.r > 240 && center.g > 240 && center.b > 240 && center.a > 240)
}

@Test func unknownSymbolIsNil() {
    #expect(AppKitSFSymbolSource().image(named: "no.such.symbol.xyz", pointSize: 48) == nil)
}

@Test func rendererDrawsAndReportsSFSymbols() {
    let renderer = KeyRenderer(sfSymbols: AppKitSFSymbolSource())
    let drawn = renderer.preview(KeyAppearance(icon: .symbol("square.fill")))
    #expect(drawn[36, 36].r > 240)
    #expect(renderer.render(KeyAppearance(icon: .symbol("square.fill"))).problems.isEmpty)
    #expect(renderer.render(KeyAppearance(icon: .symbol("no.such.symbol.xyz"))).problems == ["unknown SF Symbol: no.such.symbol.xyz"])
}

@Test func cgImageRoundTrips() {
    var pixels: [UInt8] = []
    for i in 0 ..< 72 * 72 { pixels += [UInt8(i % 256), 40, 200, 255] }
    let image = RGBAImage(width: 72, height: 72, pixels: pixels)
    let cgImage = image.cgImage
    #expect(cgImage.width == 72 && cgImage.height == 72)
    let back = RGBAImage(cgImage: cgImage)
    #expect(back[0, 0] == image[0, 0])
    #expect(back[71, 71] == image[71, 71])
}
