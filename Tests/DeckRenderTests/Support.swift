import DeckEngine
import Foundation
@testable import DeckRender

typealias RGB = (r: Int, g: Int, b: Int)

extension RGBAImage {
    func rgb(_ x: Int, _ y: Int) -> RGB {
        let p = self[x, y]
        return (Int(p.r), Int(p.g), Int(p.b))
    }

    var allRGB: [RGB] {
        (0 ..< height).flatMap { y in (0 ..< width).map { rgb($0, y) } }
    }

    static func solid(width: Int, height: Int, _ fill: (Int, Int) -> (UInt8, UInt8, UInt8)) -> RGBAImage {
        var bytes: [UInt8] = []
        for y in 0 ..< height {
            for x in 0 ..< width {
                let (r, g, b) = fill(x, y)
                bytes += [r, g, b, 255]
            }
        }
        return RGBAImage(width: width, height: height, pixels: bytes)
    }

    /// Writes a PNG to a temporary file and returns its path.
    func writePNG() -> String {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("image-\(UUID().uuidString).png")
        try! png().write(to: url)
        return url.path
    }
}

func isClose(_ pixel: RGB, _ r: Int, _ g: Int, _ b: Int, tolerance: Int = 24) -> Bool {
    abs(pixel.r - r) <= tolerance && abs(pixel.g - g) <= tolerance && abs(pixel.b - b) <= tolerance
}

func decodeJPEG(_ data: Data) -> RGBAImage {
    RGBAImage(encoded: data)!
}
