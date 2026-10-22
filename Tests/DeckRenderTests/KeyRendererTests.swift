import CoreText
import DeckConfig
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import DeckRender

/// RGBA pixels of an image, addressed with y = 0 at the top.
struct Pixels {
    let bytes: [UInt8]
    let width: Int

    init(_ image: CGImage) {
        width = image.width
        var buffer = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(data: &buffer, width: image.width, height: image.height, bitsPerComponent: 8,
                                bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        bytes = buffer
    }

    init(jpeg: Data) {
        let source = CGImageSourceCreateWithData(jpeg as CFData, nil)!
        self.init(CGImageSourceCreateImageAtIndex(source, 0, nil)!)
    }

    subscript(x: Int, y: Int) -> (r: Int, g: Int, b: Int) {
        let i = (y * width + x) * 4
        return (Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2]))
    }
}

func isClose(_ pixel: (r: Int, g: Int, b: Int), _ r: Int, _ g: Int, _ b: Int, tolerance: Int = 24) -> Bool {
    abs(pixel.r - r) <= tolerance && abs(pixel.g - g) <= tolerance && abs(pixel.b - b) <= tolerance
}

@Test func outputIsJPEGOfKeySize() {
    let jpeg = KeyRenderer.render(.blank).jpeg
    let source = CGImageSourceCreateWithData(jpeg as CFData, nil)!
    #expect(CGImageSourceGetType(source) as String? == UTType.jpeg.identifier)
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
    #expect(image.width == 72 && image.height == 72)
}

@Test func blankKeyIsBlack() {
    let pixels = Pixels(jpeg: KeyRenderer.render(.blank).jpeg)
    #expect(isClose(pixels[36, 36], 0, 0, 0))
}

@Test func backgroundColor() {
    let pixels = Pixels(jpeg: KeyRenderer.render(KeyAppearance(background: HexColor(hex: "#1E90FF")!)).jpeg)
    #expect(isClose(pixels[10, 10], 0x1E, 0x90, 0xFF))
}

@Test func deviceImageIsRotated180() {
    // The error dot sits top-right as the user sees it; on the wire it must be bottom-left.
    let appearance = KeyAppearance(error: true)
    let upright = Pixels(KeyRenderer.renderUpright(appearance).0)
    let device = Pixels(jpeg: KeyRenderer.render(appearance).jpeg)
    #expect(isClose(upright[64, 8], 230, 25, 25))
    #expect(isClose(upright[8, 64], 0, 0, 0))
    #expect(isClose(device[8, 64], 230, 25, 25, tolerance: 40))
    #expect(isClose(device[64, 8], 0, 0, 0))
}

@Test func nonSquareIconKeepsAspectRatio() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("wide-\(UUID().uuidString).png")
    let context = CGContext(data: nil, width: 200, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 200, height: 100))
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    #expect(CGImageDestinationFinalize(destination))

    let (image, problems) = KeyRenderer.renderUpright(KeyAppearance(icon: .file(url.path)))
    let pixels = Pixels(image)
    #expect(problems.isEmpty)
    // Icon-only area is 12...60 square; a 2:1 image fits as 48x24, vertically centered (y 24...48).
    #expect(isClose(pixels[14, 36], 0, 255, 0))
    #expect(isClose(pixels[58, 36], 0, 255, 0))
    #expect(isClose(pixels[36, 20], 0, 0, 0))
    #expect(isClose(pixels[36, 52], 0, 0, 0))
}

@Test func symbolIconDraws() {
    let (image, problems) = KeyRenderer.renderUpright(KeyAppearance(icon: .symbol("square.fill")))
    #expect(problems.isEmpty)
    #expect(isClose(Pixels(image)[36, 36], 255, 255, 255))
}

@Test func labelOnlyIsCentered() {
    let pixels = Pixels(KeyRenderer.renderUpright(KeyAppearance(label: "WWW")).0)
    let lit = (0 ..< 72).flatMap { y in (0 ..< 72).map { (x: $0, y: y) } }.filter { pixels[$0.x, $0.y].r > 128 }
    #expect(!lit.isEmpty)
    let midY = Double(lit.map(\.y).min()! + lit.map(\.y).max()!) / 2
    let midX = Double(lit.map(\.x).min()! + lit.map(\.x).max()!) / 2
    #expect(abs(midY - 36) <= 3)
    #expect(abs(midX - 36) <= 3)
}

@Test func longLabelStaysInsideKey() throws {
    let width = CGFloat(72 - 8)
    let lines = KeyRenderer.layoutLabel("Deploy production environment", width: width, height: KeyRenderer.labelAreaHeight)
    #expect(lines.count <= 2)
    #expect(lines.allSatisfy { KeyRenderer.lineWidth($0) <= width + 0.5 })
    let last = try #require(lines.last)
    let glyphRuns = CTLineGetGlyphRuns(last) as! [CTRun]
    #expect(!glyphRuns.isEmpty)

    let veryLong = KeyRenderer.layoutLabel(String(repeating: "Supercalifragilistic ", count: 4), width: width, height: 64)
    #expect(veryLong.count == 2)
    #expect(veryLong.allSatisfy { KeyRenderer.lineWidth($0) <= width + 0.5 })
}

@Test func shortLabelUsesLargestFont() {
    let lines = KeyRenderer.layoutLabel("Play", width: 64, height: KeyRenderer.labelAreaHeight)
    #expect(lines.count == 1)
    let runs = CTLineGetGlyphRuns(lines[0]) as! [CTRun]
    let attributes = CTRunGetAttributes(runs[0]) as NSDictionary
    let font = attributes[kCTFontAttributeName] as! CTFont
    #expect(CTFontGetSize(font) == KeyRenderer.maxFontSize)
}

@Test func pressedKeyIsDarker() {
    let normal = Pixels(KeyRenderer.renderUpright(KeyAppearance(background: HexColor(red: 200, green: 200, blue: 200))).0)
    let pressed = Pixels(KeyRenderer.renderUpright(KeyAppearance(background: HexColor(red: 200, green: 200, blue: 200), pressed: true)).0)
    #expect(pressed[10, 10].r < normal[10, 10].r - 50)
}

@Test func missingIconFileShowsPlaceholderAndIsReported() {
    let path = "/nonexistent/icons/missing.png"
    let (image, problems) = KeyRenderer.renderUpright(KeyAppearance(icon: .file(path), label: "Zoom"))
    #expect(problems == ["icon file not found or unreadable: \(path)"])
    // The dashed placeholder outline is gray, not the black background.
    let pixels = Pixels(image)
    let gray = (0 ..< 72).flatMap { y in (0 ..< 72).map { pixels[$0, y] } }.filter { isClose($0, 153, 153, 153, tolerance: 20) }
    #expect(gray.count > 30)
}

@Test func unknownSymbolIsReported() {
    let problems = KeyRenderer.render(KeyAppearance(icon: .symbol("no.such.symbol.xyz"))).problems
    #expect(problems == ["unknown SF Symbol: no.such.symbol.xyz"])
}

// MARK: - Full-key image

/// Writes a PNG drawn by `draw` (y-up coordinates) and returns its path.
private func writePNG(width: Int, height: Int, _ draw: (CGContext) -> Void) -> String {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("image-\(UUID().uuidString).png")
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    draw(context)
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
    return url.path
}

private func fill(_ context: CGContext, _ rect: CGRect, red: CGFloat, green: CGFloat, blue: CGFloat) {
    context.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
    context.fill(rect)
}

@Test func squareImageCoversWholeKey() {
    let path = writePNG(width: 144, height: 144) { fill($0, CGRect(x: 0, y: 0, width: 144, height: 144), red: 1, green: 0, blue: 0) }
    let (image, problems) = KeyRenderer.renderUpright(KeyAppearance(image: path))
    let pixels = Pixels(image)
    #expect(problems.isEmpty)
    for (x, y) in [(0, 0), (71, 0), (0, 71), (71, 71), (36, 36)] {
        #expect(isClose(pixels[x, y], 255, 0, 0))
    }
}

@Test func wideImageIsCroppedAtCenter() {
    let path = writePNG(width: 200, height: 100) { context in
        fill(context, CGRect(x: 0, y: 0, width: 100, height: 100), red: 1, green: 0, blue: 0)
        fill(context, CGRect(x: 100, y: 0, width: 100, height: 100), red: 0, green: 0, blue: 1)
    }
    let pixels = Pixels(KeyRenderer.renderUpright(KeyAppearance(image: path)).0)
    // Scaled to 144x72 and centered: the left half shows red, the right half blue, no border.
    #expect(isClose(pixels[0, 0], 255, 0, 0))
    #expect(isClose(pixels[30, 71], 255, 0, 0))
    #expect(isClose(pixels[42, 0], 0, 0, 255))
    #expect(isClose(pixels[71, 71], 0, 0, 255))
}

@Test func labelHasShadowOnlyOnImage() {
    let white = HexColor(red: 255, green: 255, blue: 255)
    let path = writePNG(width: 72, height: 72) { fill($0, CGRect(x: 0, y: 0, width: 72, height: 72), red: 1, green: 1, blue: 1) }
    func darkest(_ appearance: KeyAppearance) -> Int {
        let pixels = Pixels(KeyRenderer.renderUpright(appearance).0)
        return (0 ..< 72).flatMap { y in (0 ..< 72).map { pixels[$0, y].r } }.min()!
    }
    // White label on white: invisible without a shadow, visible with one.
    #expect(darkest(KeyAppearance(background: white, label: "WWW")) > 240)
    #expect(darkest(KeyAppearance(image: path, label: "WWW")) < 160)
}

@Test func missingImageIsSkippedAndReported() {
    let path = "/nonexistent/art/missing.png"
    let (image, problems) = KeyRenderer.renderUpright(KeyAppearance(background: HexColor(red: 0, green: 0, blue: 255), image: path, label: "Cat"))
    #expect(problems == ["image file not found or unreadable: \(path)"])
    let pixels = Pixels(image)
    let all = (0 ..< 72).flatMap { y in (0 ..< 72).map { pixels[$0, y] } }
    #expect(isClose(pixels[2, 2], 0, 0, 255))
    #expect(all.contains { $0.r > 200 && $0.g > 200 })  // label drawn
    #expect(!all.contains { isClose($0, 153, 153, 153, tolerance: 20) })  // no placeholder
}
