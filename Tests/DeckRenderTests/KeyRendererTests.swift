import DeckConfig
import DeckEngine
import Foundation
import Testing
@testable import DeckRender

private let renderer = KeyRenderer()

private func upright(_ appearance: KeyAppearance) -> (RGBAImage, [String]) {
    renderer.renderUpright(appearance)
}

@Test func outputIsJPEGOfKeySize() {
    let jpeg = renderer.render(.blank).jpeg
    #expect(jpeg.prefix(3) == Data([0xFF, 0xD8, 0xFF]))
    let image = decodeJPEG(jpeg)
    #expect(image.width == 72 && image.height == 72)
}

@Test func blankKeyIsBlack() {
    #expect(isClose(decodeJPEG(renderer.render(.blank).jpeg).rgb(36, 36), 0, 0, 0))
}

@Test func backgroundColor() {
    let image = decodeJPEG(renderer.render(KeyAppearance(background: HexColor(hex: "#1E90FF")!)).jpeg)
    #expect(isClose(image.rgb(10, 10), 0x1E, 0x90, 0xFF))
}

@Test func deviceImageIsRotated180() {
    // The error dot sits top-right as the user sees it; on the wire it must be bottom-left.
    let appearance = KeyAppearance(error: true)
    let (image, _) = upright(appearance)
    let device = decodeJPEG(renderer.render(appearance).jpeg)
    #expect(isClose(image.rgb(64, 8), 230, 25, 25))
    #expect(isClose(image.rgb(8, 64), 0, 0, 0))
    #expect(isClose(device.rgb(8, 64), 230, 25, 25, tolerance: 40))
    #expect(isClose(device.rgb(64, 8), 0, 0, 0))
}

@Test func previewIsTheUprightImage() {
    let appearance = KeyAppearance(icon: .material(name: "home", filled: false), label: "Home", error: true)
    #expect(renderer.preview(appearance) == upright(appearance).0)
}

@Test func nonSquareIconKeepsAspectRatio() {
    let path = RGBAImage.solid(width: 200, height: 100) { _, _ in (0, 255, 0) }.writePNG()
    let (image, problems) = upright(KeyAppearance(icon: .file(path)))
    #expect(problems.isEmpty)
    // Icon-only area is 12...60 square; a 2:1 image fits as 48x24, vertically centered (y 24...48).
    #expect(isClose(image.rgb(14, 36), 0, 255, 0))
    #expect(isClose(image.rgb(58, 36), 0, 255, 0))
    #expect(isClose(image.rgb(36, 20), 0, 0, 0))
    #expect(isClose(image.rgb(36, 52), 0, 0, 0))
}

@Test func labelOnlyIsCentered() {
    let (image, _) = upright(KeyAppearance(label: "WWW"))
    let lit = (0 ..< 72).flatMap { y in (0 ..< 72).map { (x: $0, y: y) } }.filter { image.rgb($0.x, $0.y).r > 128 }
    #expect(!lit.isEmpty)
    let midY = Double(lit.map(\.y).min()! + lit.map(\.y).max()!) / 2
    let midX = Double(lit.map(\.x).min()! + lit.map(\.x).max()!) / 2
    #expect(abs(midY - 36) <= 3)
    #expect(abs(midX - 36) <= 3)
}

@Test func labelSitsBelowIcon() {
    let (image, _) = upright(KeyAppearance(icon: .material(name: "square", filled: true), label: "WWW"))
    let lit = (0 ..< 72).flatMap { y in (0 ..< 72).map { (x: $0, y: y) } }.filter { image.rgb($0.x, $0.y).r > 128 }
    // Icon box is y 6..46, label strip y 46..70.
    #expect(lit.contains { $0.y < 40 })
    #expect(lit.contains { $0.y > 50 })
    #expect(lit.allSatisfy { $0.y < 71 })
}

@Test func pressedKeyIsDarker() {
    let gray = HexColor(red: 200, green: 200, blue: 200)
    let normal = upright(KeyAppearance(background: gray)).0
    let pressed = upright(KeyAppearance(background: gray, pressed: true)).0
    #expect(pressed.rgb(10, 10).r < normal.rgb(10, 10).r - 50)
}

private func placeholderPixels(_ image: RGBAImage) -> Int {
    image.allRGB.filter { isClose($0, 153, 153, 153, tolerance: 20) }.count
}

@Test func missingIconFileShowsPlaceholderAndIsReported() {
    let path = "/nonexistent/icons/missing.png"
    let (image, problems) = upright(KeyAppearance(icon: .file(path), label: "Zoom"))
    #expect(problems == ["icon file not found or unreadable: \(path)"])
    #expect(placeholderPixels(image) > 30)
}

// MARK: - Material Symbols

@Test func knownMaterialSymbolNames() {
    #expect(MaterialSymbols.contains("home"))
    #expect(MaterialSymbols.contains("play_arrow"))
    #expect(!MaterialSymbols.contains("hoem"))
    #expect(!MaterialSymbols.contains(""))
}

private func whitePixels(_ image: RGBAImage) -> Int {
    image.allRGB.filter { $0.r > 200 && $0.g > 200 && $0.b > 200 }.count
}

@Test func materialSymbolDrawsWhiteInsideIconBox() {
    let (outlined, outlinedProblems) = upright(KeyAppearance(icon: .material(name: "square", filled: false)))
    let (filled, filledProblems) = upright(KeyAppearance(icon: .material(name: "square", filled: true)))
    #expect(outlinedProblems.isEmpty && filledProblems.isEmpty)
    #expect(whitePixels(outlined) > 50)
    #expect(whitePixels(filled) > whitePixels(outlined) * 2)
    #expect(isClose(filled.rgb(36, 36), 255, 255, 255))
    // Nothing outside the 12...60 icon box.
    for (x, y) in [(5, 5), (66, 66), (36, 4), (4, 36), (36, 67), (67, 36)] {
        #expect(isClose(filled.rgb(x, y), 0, 0, 0))
    }
}

@Test func unknownMaterialSymbolShowsPlaceholder() {
    let (image, problems) = upright(KeyAppearance(icon: .material(name: "no_such_symbol", filled: false)))
    #expect(problems == ["unknown Material Symbol: no_such_symbol"])
    #expect(placeholderPixels(image) > 30)
}

// MARK: - SF Symbols

@Test func sfSymbolWithoutSourceShowsPlaceholder() {
    let (image, problems) = upright(KeyAppearance(icon: .symbol("play.fill"), label: "Play"))
    #expect(problems == ["SF Symbols are only available on macOS: sf:play.fill. Use an ms: icon instead."])
    #expect(placeholderPixels(image) > 30)
    #expect(whitePixels(image) > 10)  // the label is still drawn
}

private struct FakeSFSymbols: SFSymbolSource {
    func image(named name: String, pointSize: Double) -> RGBAImage? {
        name == "square.fill" ? RGBAImage.solid(width: 10, height: 10) { _, _ in (255, 255, 255) } : nil
    }
}

@Test func sfSymbolSourceIsUsed() {
    let renderer = KeyRenderer(sfSymbols: FakeSFSymbols())
    let (image, problems) = renderer.renderUpright(KeyAppearance(icon: .symbol("square.fill")))
    #expect(problems.isEmpty)
    #expect(isClose(image.rgb(36, 36), 255, 255, 255))
    #expect(isClose(image.rgb(5, 5), 0, 0, 0))
    #expect(renderer.render(KeyAppearance(icon: .symbol("nope"))).problems == ["unknown SF Symbol: nope"])
}

// MARK: - Full-key image

@Test func squareImageCoversWholeKey() {
    let path = RGBAImage.solid(width: 144, height: 144) { _, _ in (255, 0, 0) }.writePNG()
    let (image, problems) = upright(KeyAppearance(image: path))
    #expect(problems.isEmpty)
    for (x, y) in [(0, 0), (71, 0), (0, 71), (71, 71), (36, 36)] {
        #expect(isClose(image.rgb(x, y), 255, 0, 0))
    }
}

@Test func wideImageIsCroppedAtCenter() {
    let path = RGBAImage.solid(width: 200, height: 100) { x, _ in x < 100 ? (255, 0, 0) : (0, 0, 255) }.writePNG()
    let (image, _) = upright(KeyAppearance(image: path))
    // Scaled to 144x72 and centered: the left half shows red, the right half blue, no border.
    #expect(isClose(image.rgb(0, 0), 255, 0, 0))
    #expect(isClose(image.rgb(30, 71), 255, 0, 0))
    #expect(isClose(image.rgb(42, 0), 0, 0, 255))
    #expect(isClose(image.rgb(71, 71), 0, 0, 255))
}

@Test func labelHasShadowOnlyOnImage() {
    let white = HexColor(red: 255, green: 255, blue: 255)
    let path = RGBAImage.solid(width: 72, height: 72) { _, _ in (255, 255, 255) }.writePNG()
    func darkest(_ appearance: KeyAppearance) -> Int {
        upright(appearance).0.allRGB.map(\.r).min()!
    }
    // White label on white: invisible without a shadow, visible with one.
    #expect(darkest(KeyAppearance(background: white, label: "WWW")) > 240)
    #expect(darkest(KeyAppearance(image: path, label: "WWW")) < 160)
}

@Test func missingImageIsSkippedAndReported() {
    let path = "/nonexistent/art/missing.png"
    let (image, problems) = upright(KeyAppearance(background: HexColor(red: 0, green: 0, blue: 255), image: path, label: "Cat"))
    #expect(problems == ["image file not found or unreadable: \(path)"])
    #expect(isClose(image.rgb(2, 2), 0, 0, 255))
    #expect(image.allRGB.contains { $0.r > 200 && $0.g > 200 })  // label drawn
    #expect(placeholderPixels(image) == 0)
}

// MARK: - Visual check

/// Writes sample keys as PNGs to $DECK_RENDER_DUMP for a person to look at. Does nothing otherwise.
@Test func dumpSamples() throws {
    guard let directory = ProcessInfo.processInfo.environment["DECK_RENDER_DUMP"] else { return }
    let art = RGBAImage.solid(width: 300, height: 200) { x, y in (UInt8(x * 255 / 300), UInt8(y * 255 / 200), 200) }.writePNG()
    let samples: [(String, KeyAppearance)] = [
        ("ms-play-label", KeyAppearance(icon: .material(name: "play_arrow", filled: true), label: "Play")),
        ("ms-home", KeyAppearance(icon: .material(name: "home", filled: false))),
        ("ms-lightbulb-fill", KeyAppearance(background: HexColor(hex: "#c08000")!, icon: .material(name: "lightbulb", filled: true), label: "on")),
        ("long-label", KeyAppearance(label: "Deploy production environment")),
        ("label-only", KeyAppearance(label: "Build")),
        ("image-label", KeyAppearance(icon: .material(name: "music_note", filled: true), image: art, label: "Album")),
        ("sf-on-linux", KeyAppearance(icon: .symbol("play.fill"), label: "Play")),
        ("emoji", KeyAppearance(label: "Party 🎉")),
        ("error-pressed", KeyAppearance(icon: .material(name: "terminal", filled: false), label: "Terminal", pressed: true, error: true)),
    ]
    for (name, appearance) in samples {
        let image = renderer.preview(appearance)
        try image.png().write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
    }
}
