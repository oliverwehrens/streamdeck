import CStb
import Foundation

/// An 8-bit RGBA image with straight (not premultiplied) alpha, rows top to bottom.
public struct RGBAImage: Equatable, Sendable {
    public let width: Int
    public let height: Int
    /// `width * height * 4` bytes: red, green, blue, alpha.
    public let pixels: [UInt8]

    public init(width: Int, height: Int, pixels: [UInt8]) {
        precondition(pixels.count == width * height * 4, "expected \(width * height * 4) bytes, got \(pixels.count)")
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// Decodes a PNG or JPEG, or returns nil.
    public init?(encoded data: Data) {
        guard !data.isEmpty, data.count <= Int(Int32.max) else { return nil }
        var width: Int32 = 0, height: Int32 = 0, components: Int32 = 0
        let decoded = data.withUnsafeBytes { buffer in
            stbi_load_from_memory(buffer.bindMemory(to: UInt8.self).baseAddress, Int32(buffer.count), &width, &height, &components, 4)
        }
        guard let decoded, width > 0, height > 0 else { return nil }
        defer { stbi_image_free(decoded) }
        self.init(width: Int(width), height: Int(height),
                  pixels: Array(UnsafeBufferPointer(start: decoded, count: Int(width) * Int(height) * 4)))
    }

    /// Reads and decodes a PNG or JPEG file, or returns nil.
    public init?(contentsOfFile path: String) {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        self.init(encoded: data)
    }

    /// The pixel at (x, y), with y = 0 at the top.
    public subscript(x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let i = (y * width + x) * 4
        return (pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3])
    }

    /// JPEG of the color channels; alpha is dropped.
    public func jpeg(quality: Int32 = 90) -> Data {
        var rgb = [UInt8]()
        rgb.reserveCapacity(width * height * 3)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            rgb.append(contentsOf: pixels[i ..< i + 3])
        }
        return Self.write { context, callback in
            stbi_write_jpg_to_func(callback, context, Int32(width), Int32(height), 3, rgb, quality)
        }
    }

    /// PNG with alpha.
    public func png() -> Data {
        Self.write { context, callback in
            stbi_write_png_to_func(callback, context, Int32(width), Int32(height), 4, pixels, width * 4)
        }
    }

    private final class Sink {
        var data = Data()
    }

    private static func write(_ body: (UnsafeMutableRawPointer, @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32) -> Void) -> Int32) -> Data {
        let sink = Sink()
        let callback: @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32) -> Void = { context, bytes, count in
            guard let context, let bytes, count > 0 else { return }
            Unmanaged<Sink>.fromOpaque(context).takeUnretainedValue().data.append(bytes.assumingMemoryBound(to: UInt8.self), count: Int(count))
        }
        let ok = withExtendedLifetime(sink) { body(Unmanaged.passUnretained(sink).toOpaque(), callback) }
        precondition(ok != 0, "stb_image_write failed")
        return sink.data
    }
}
