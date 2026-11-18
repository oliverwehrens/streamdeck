import Foundation
import Testing
@testable import DeckRender

@Test func solidFillReadsBackExactly() {
    var canvas = Canvas(width: 72, height: 72)
    canvas.fill(canvas.bounds, Color(red: 30 / 255, green: 144 / 255, blue: 1))
    let image = canvas.image()
    #expect(image.allRGB.allSatisfy { $0 == (30, 144, 255) })
    #expect(image[0, 0].a == 255)
}

@Test func rotationMovesTopLeftToBottomRight() {
    let image = RGBAImage.solid(width: 72, height: 72) { x, y in x == 0 && y == 0 ? (255, 0, 0) : (0, 0, 0) }
    let rotated = image.rotated180()
    #expect(rotated.rgb(71, 71) == (255, 0, 0))
    #expect(rotated.rgb(0, 0) == (0, 0, 0))
}

@Test func downscaledCheckerboardAveragesToGray() {
    let checkerboard = RGBAImage.solid(width: 144, height: 144) { x, y in (x + y) % 2 == 0 ? (255, 255, 255) : (0, 0, 0) }
    var canvas = Canvas(width: 72, height: 72)
    canvas.draw(checkerboard, in: canvas.bounds)
    #expect(canvas.image().allRGB.allSatisfy { isClose($0, 128, 128, 128, tolerance: 2) })
}

@Test func jpegDecodesBackToKeySize() {
    var canvas = Canvas(width: 72, height: 72)
    canvas.fill(canvas.bounds, Color(red: 1, green: 0, blue: 0))
    let jpeg = canvas.image().jpeg()
    #expect(jpeg.prefix(3) == Data([0xFF, 0xD8, 0xFF]))
    let decoded = decodeJPEG(jpeg)
    #expect(decoded.width == 72 && decoded.height == 72)
    #expect(isClose(decoded.rgb(36, 36), 255, 0, 0))
}

@Test func pngRoundTrips() {
    let image = RGBAImage.solid(width: 3, height: 2) { x, y in (UInt8(x * 80), UInt8(y * 200), 7) }
    #expect(RGBAImage(encoded: image.png()) == image)
}

@Test func garbageDoesNotDecode() {
    #expect(RGBAImage(encoded: Data("not an image".utf8)) == nil)
    #expect(RGBAImage(contentsOfFile: "/nonexistent.png") == nil)
}

@Test func ellipseIsAntialiased() {
    var canvas = Canvas(width: 20, height: 20)
    canvas.fill(canvas.bounds, .black)
    canvas.fillEllipse(Rect(x: 5, y: 5, width: 10, height: 10), .white)
    let image = canvas.image()
    #expect(image.rgb(10, 10) == (255, 255, 255))
    #expect(image.rgb(1, 1) == (0, 0, 0))
    // Some edge pixel is partly covered.
    #expect(image.allRGB.contains { $0.r > 20 && $0.r < 235 })
}
