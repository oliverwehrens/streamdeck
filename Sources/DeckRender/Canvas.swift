import Foundation

/// A rectangle in pixels, y = 0 at the top.
struct Rect: Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    var minX: Double { x }
    var minY: Double { y }
    var maxX: Double { x + width }
    var maxY: Double { y + height }
    var midX: Double { x + width / 2 }
    var midY: Double { y + height / 2 }

    func insetBy(dx: Double, dy: Double) -> Rect {
        Rect(x: x + dx, y: y + dy, width: width - 2 * dx, height: height - 2 * dy)
    }

    func offsetBy(dx: Double, dy: Double) -> Rect {
        Rect(x: x + dx, y: y + dy, width: width, height: height)
    }

    /// Scales `size` to fit inside, centered.
    func aspectFit(width w: Double, height h: Double) -> Rect {
        guard w > 0, h > 0 else { return self }
        return scaled(w, h, by: min(width / w, height / h))
    }

    /// Scales `size` to cover, centered; the overflow is clipped by the caller.
    func aspectFill(width w: Double, height h: Double) -> Rect {
        guard w > 0, h > 0 else { return self }
        return scaled(w, h, by: max(width / w, height / h))
    }

    private func scaled(_ w: Double, _ h: Double, by scale: Double) -> Rect {
        Rect(x: midX - w * scale / 2, y: midY - h * scale / 2, width: w * scale, height: h * scale)
    }
}

/// A color with straight alpha, components 0...1.
struct Color: Equatable {
    var red: Float
    var green: Float
    var blue: Float
    var alpha: Float = 1

    init(red: Float, green: Float, blue: Float, alpha: Float = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(gray: Float, alpha: Float = 1) {
        self.init(red: gray, green: gray, blue: gray, alpha: alpha)
    }

    static let white = Color(gray: 1)
    static let black = Color(gray: 0)
}

/// Coverage values 0...1 for an area the size of the canvas.
struct Mask {
    let width: Int
    let height: Int
    var values: [Float]

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        values = [Float](repeating: 0, count: width * height)
    }

    /// Adds coverage from an 8-bit bitmap placed with its top-left corner at (left, top), clamped to 1.
    mutating func add(_ bitmap: UnsafePointer<UInt8>, width w: Int, height h: Int, left: Int, top: Int, scale: Float = 1) {
        for row in 0 ..< h {
            let y = top + row
            guard y >= 0, y < height else { continue }
            for column in 0 ..< w {
                let x = left + column
                guard x >= 0, x < width else { continue }
                let value = Float(bitmap[row * w + column]) / 255 * scale
                values[y * width + x] = min(1, values[y * width + x] + value)
            }
        }
    }

    /// Moves the coverage by whole pixels; uncovered pixels become 0.
    func shifted(dx: Int, dy: Int) -> Mask {
        var result = Mask(width: width, height: height)
        for y in 0 ..< height {
            for x in 0 ..< width {
                let sx = x - dx, sy = y - dy
                guard sx >= 0, sx < width, sy >= 0, sy < height else { continue }
                result.values[y * width + x] = values[sy * width + sx]
            }
        }
        return result
    }

    /// Three box-blur passes of `radius` in each direction, close to a Gaussian.
    func blurred(radius: Int, passes: Int = 3) -> Mask {
        var result = self
        for _ in 0 ..< passes {
            result = result.boxBlur(radius: radius, horizontal: true).boxBlur(radius: radius, horizontal: false)
        }
        return result
    }

    private func boxBlur(radius: Int, horizontal: Bool) -> Mask {
        var result = Mask(width: width, height: height)
        let window = Float(2 * radius + 1)
        for y in 0 ..< height {
            for x in 0 ..< width {
                var sum: Float = 0
                for d in -radius ... radius {
                    let sx = horizontal ? x + d : x, sy = horizontal ? y : y + d
                    if sx >= 0, sx < width, sy >= 0, sy < height { sum += values[sy * width + sx] }
                }
                result.values[y * width + x] = sum / window
            }
        }
        return result
    }
}

/// A premultiplied RGBA float raster with y = 0 at the top.
struct Canvas {
    let width: Int
    let height: Int
    /// Premultiplied red, green, blue, alpha per pixel.
    private(set) var storage: [Float]

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        storage = [Float](repeating: 0, count: width * height * 4)
    }

    var bounds: Rect { Rect(x: 0, y: 0, width: Double(width), height: Double(height)) }

    /// Source-over with a straight-alpha color, scaled by `coverage`.
    private mutating func blend(_ x: Int, _ y: Int, _ color: Color, coverage: Float) {
        let a = color.alpha * coverage
        guard a > 0 else { return }
        let i = (y * width + x) * 4
        let keep = 1 - a
        storage[i] = color.red * a + storage[i] * keep
        storage[i + 1] = color.green * a + storage[i + 1] * keep
        storage[i + 2] = color.blue * a + storage[i + 2] * keep
        storage[i + 3] = a + storage[i + 3] * keep
    }

    /// Source-over with a premultiplied color.
    private mutating func blendPremultiplied(_ x: Int, _ y: Int, _ r: Float, _ g: Float, _ b: Float, _ a: Float) {
        guard a > 0 else { return }
        let i = (y * width + x) * 4
        let keep = 1 - a
        storage[i] = r + storage[i] * keep
        storage[i + 1] = g + storage[i + 1] * keep
        storage[i + 2] = b + storage[i + 2] * keep
        storage[i + 3] = a + storage[i + 3] * keep
    }

    /// Pixels touched by `rect`, clamped to the canvas.
    private func pixelRange(_ rect: Rect) -> (xs: Range<Int>, ys: Range<Int>)? {
        let x0 = max(0, Int(rect.minX.rounded(.down))), x1 = min(width, Int(rect.maxX.rounded(.up)))
        let y0 = max(0, Int(rect.minY.rounded(.down))), y1 = min(height, Int(rect.maxY.rounded(.up)))
        guard x0 < x1, y0 < y1 else { return nil }
        return (x0 ..< x1, y0 ..< y1)
    }

    /// Fills `rect`; partly covered edge pixels get partial coverage.
    mutating func fill(_ rect: Rect, _ color: Color) {
        guard let (xs, ys) = pixelRange(rect) else { return }
        for y in ys {
            let cy = Float(min(rect.maxY, Double(y + 1)) - max(rect.minY, Double(y)))
            for x in xs {
                let cx = Float(min(rect.maxX, Double(x + 1)) - max(rect.minX, Double(x)))
                blend(x, y, color, coverage: cx * cy)
            }
        }
    }

    /// Fills the ellipse inside `rect`, antialiased with 4x4 samples per pixel.
    mutating func fillEllipse(_ rect: Rect, _ color: Color) {
        guard let (xs, ys) = pixelRange(rect) else { return }
        let rx = rect.width / 2, ry = rect.height / 2
        for y in ys {
            for x in xs {
                var inside = 0
                for sy in 0 ..< 4 {
                    for sx in 0 ..< 4 {
                        let px = (Double(x) + (Double(sx) + 0.5) / 4 - rect.midX) / rx
                        let py = (Double(y) + (Double(sy) + 0.5) / 4 - rect.midY) / ry
                        if px * px + py * py <= 1 { inside += 1 }
                    }
                }
                blend(x, y, color, coverage: Float(inside) / 16)
            }
        }
    }

    /// Strokes the outline of `rect` with a centered line and a repeating on/off dash pattern.
    mutating func strokeDashedRect(_ rect: Rect, lineWidth: Double, dash: (on: Double, off: Double), _ color: Color) {
        let half = lineWidth / 2
        // Walk the perimeter clockwise from the top-left corner, as CoreGraphics does.
        let sides: [(start: (Double, Double), direction: (Double, Double), length: Double)] = [
            ((rect.minX, rect.minY), (1, 0), rect.width),
            ((rect.maxX, rect.minY), (0, 1), rect.height),
            ((rect.maxX, rect.maxY), (-1, 0), rect.width),
            ((rect.minX, rect.maxY), (0, -1), rect.height),
        ]
        let period = dash.on + dash.off
        var travelled = 0.0
        for side in sides {
            var along = 0.0
            while along < side.length {
                let phase = (travelled + along).truncatingRemainder(dividingBy: period)
                let isOn = phase < dash.on
                let step = min(side.length - along, isOn ? dash.on - phase : period - phase)
                if isOn {
                    let ax = side.start.0 + side.direction.0 * along, ay = side.start.1 + side.direction.1 * along
                    let bx = ax + side.direction.0 * step, by = ay + side.direction.1 * step
                    fill(Rect(x: min(ax, bx) - half, y: min(ay, by) - half,
                              width: abs(bx - ax) + lineWidth, height: abs(by - ay) + lineWidth), color)
                }
                along += step
            }
            travelled += side.length
        }
    }

    /// Paints `color` through `mask`.
    mutating func fill(_ mask: Mask, _ color: Color) {
        for y in 0 ..< min(height, mask.height) {
            for x in 0 ..< min(width, mask.width) {
                blend(x, y, color, coverage: mask.values[y * mask.width + x])
            }
        }
    }

    /// Draws `image` scaled into `rect`, clipped to the canvas. Upscaling samples bilinearly;
    /// downscaling averages every source pixel under the destination pixel.
    mutating func draw(_ image: RGBAImage, in rect: Rect) {
        guard image.width > 0, image.height > 0, rect.width > 0, rect.height > 0,
              let (xs, ys) = pixelRange(rect) else { return }
        let source = Premultiplied(image)
        let scaleX = rect.width / Double(image.width), scaleY = rect.height / Double(image.height)
        for y in ys {
            for x in xs {
                // The destination pixel's footprint inside `rect`, in source pixels.
                let left = max(Double(x), rect.minX), right = min(Double(x + 1), rect.maxX)
                let top = max(Double(y), rect.minY), bottom = min(Double(y + 1), rect.maxY)
                guard right > left, bottom > top else { continue }
                let coverage = Float((right - left) * (bottom - top))
                let sx0 = (left - rect.minX) / scaleX, sx1 = (right - rect.minX) / scaleX
                let sy0 = (top - rect.minY) / scaleY, sy1 = (bottom - rect.minY) / scaleY
                let pixel = (scaleX >= 1 && scaleY >= 1)
                    ? source.bilinear(x: (sx0 + sx1) / 2, y: (sy0 + sy1) / 2)
                    : source.average(x0: sx0, x1: sx1, y0: sy0, y1: sy1)
                blendPremultiplied(x, y, pixel.0 * coverage, pixel.1 * coverage, pixel.2 * coverage, pixel.3 * coverage)
            }
        }
    }

    /// The canvas as 8-bit RGBA with straight alpha.
    func image() -> RGBAImage {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for i in stride(from: 0, to: storage.count, by: 4) {
            let a = storage[i + 3]
            func byte(_ value: Float) -> UInt8 { UInt8(max(0, min(255, (value * 255).rounded()))) }
            if a > 0 {
                bytes[i] = byte(storage[i] / a)
                bytes[i + 1] = byte(storage[i + 1] / a)
                bytes[i + 2] = byte(storage[i + 2] / a)
            }
            bytes[i + 3] = byte(a)
        }
        return RGBAImage(width: width, height: height, pixels: bytes)
    }
}

/// An image's pixels as premultiplied floats, for resampling.
private struct Premultiplied {
    let width: Int
    let height: Int
    let values: [Float]

    init(_ image: RGBAImage) {
        width = image.width
        height = image.height
        var values = [Float](repeating: 0, count: image.pixels.count)
        for i in stride(from: 0, to: image.pixels.count, by: 4) {
            let a = Float(image.pixels[i + 3]) / 255
            values[i] = Float(image.pixels[i]) / 255 * a
            values[i + 1] = Float(image.pixels[i + 1]) / 255 * a
            values[i + 2] = Float(image.pixels[i + 2]) / 255 * a
            values[i + 3] = a
        }
        self.values = values
    }

    func pixel(_ x: Int, _ y: Int) -> (Float, Float, Float, Float) {
        let i = (min(max(y, 0), height - 1) * width + min(max(x, 0), width - 1)) * 4
        return (values[i], values[i + 1], values[i + 2], values[i + 3])
    }

    /// Bilinear sample at a point in pixel coordinates (pixel centers at +0.5); edges clamp.
    func bilinear(x: Double, y: Double) -> (Float, Float, Float, Float) {
        let fx = x - 0.5, fy = y - 0.5
        let x0 = Int(fx.rounded(.down)), y0 = Int(fy.rounded(.down))
        let tx = Float(fx - Double(x0)), ty = Float(fy - Double(y0))
        let a = pixel(x0, y0), b = pixel(x0 + 1, y0), c = pixel(x0, y0 + 1), d = pixel(x0 + 1, y0 + 1)
        func mix(_ p: Float, _ q: Float, _ r: Float, _ s: Float) -> Float {
            (p * (1 - tx) + q * tx) * (1 - ty) + (r * (1 - tx) + s * tx) * ty
        }
        return (mix(a.0, b.0, c.0, d.0), mix(a.1, b.1, c.1, d.1), mix(a.2, b.2, c.2, d.2), mix(a.3, b.3, c.3, d.3))
    }

    /// Area-weighted average over a box in pixel coordinates.
    func average(x0: Double, x1: Double, y0: Double, y1: Double) -> (Float, Float, Float, Float) {
        var sum: (Float, Float, Float, Float) = (0, 0, 0, 0)
        var total: Float = 0
        for y in max(0, Int(y0.rounded(.down))) ..< min(height, Int(y1.rounded(.up))) {
            let wy = Float(min(y1, Double(y + 1)) - max(y0, Double(y)))
            for x in max(0, Int(x0.rounded(.down))) ..< min(width, Int(x1.rounded(.up))) {
                let w = Float(min(x1, Double(x + 1)) - max(x0, Double(x))) * wy
                let p = pixel(x, y)
                sum = (sum.0 + p.0 * w, sum.1 + p.1 * w, sum.2 + p.2 * w, sum.3 + p.3 * w)
                total += w
            }
        }
        guard total > 0 else { return (0, 0, 0, 0) }
        return (sum.0 / total, sum.1 / total, sum.2 / total, sum.3 / total)
    }
}
