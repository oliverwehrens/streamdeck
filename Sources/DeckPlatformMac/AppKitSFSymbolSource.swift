import AppKit
import DeckRender

/// Rasterizes SF Symbols with AppKit for the shared `KeyRenderer`.
public struct AppKitSFSymbolSource: SFSymbolSource {
    public init() {}

    public func image(named name: String, pointSize: Double) -> RGBAImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize * 0.8, weight: .regular)
            .applying(.init(paletteColors: [.white]))
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else { return nil }
        var rect = CGRect(origin: .zero, size: symbol.size)
        guard let image = symbol.cgImage(forProposedRect: &rect, context: nil, hints: [.ctm: AffineTransform(scale: 2)]) else {
            return nil
        }
        return RGBAImage(cgImage: image)
    }
}

extension RGBAImage {
    /// The pixels of a Core Graphics image, in sRGB.
    public init(cgImage image: CGImage) {
        let width = image.width, height = image.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &buffer, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        // Core Graphics only draws premultiplied; RGBAImage holds straight alpha.
        for i in stride(from: 0, to: buffer.count, by: 4) {
            let alpha = Int(buffer[i + 3])
            guard alpha > 0, alpha < 255 else { continue }
            for c in 0 ..< 3 {
                buffer[i + c] = UInt8(min(255, (Int(buffer[i + c]) * 255 + alpha / 2) / alpha))
            }
        }
        self.init(width: width, height: height, pixels: buffer)
    }

    /// A Core Graphics image of these pixels, for on-screen previews.
    public var cgImage: CGImage {
        CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                provider: CGDataProvider(data: Data(pixels) as CFData)!,
                decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
    }
}
