import DeckConfig
import DeckEngine
import Foundation

/// Draws SF Symbols, which only exist on macOS. The platform passes one to `KeyRenderer`.
public protocol SFSymbolSource: Sendable {
    /// The symbol in white, rasterized for a box `pointSize` high, or nil if there's no such symbol.
    func image(named name: String, pointSize: Double) -> RGBAImage?
}

/// Draws keys the same way on every platform: the engine's `KeyRendering` port and the editor previews.
public struct KeyRenderer: KeyRendering {
    public static let size = 72
    static let padding = 4.0
    static let labelAreaHeight = 24.0

    private let sfSymbols: (any SFSymbolSource)?

    /// Without `sfSymbols`, `sf:` icons draw a placeholder and report a problem.
    public init(sfSymbols: (any SFSymbolSource)? = nil) {
        self.sfSymbols = sfSymbols
    }

    /// Encoded for the device: JPEG, rotated 180 degrees.
    public func render(_ appearance: KeyAppearance) -> RenderedKey {
        let (image, problems) = renderUpright(appearance)
        return RenderedKey(jpeg: image.rotated180().jpeg(), problems: problems)
    }

    /// The key as the user sees it on the device, for on-screen previews.
    public func preview(_ appearance: KeyAppearance) -> RGBAImage {
        renderUpright(appearance).0
    }

    // MARK: - Layers

    func renderUpright(_ appearance: KeyAppearance) -> (RGBAImage, [String]) {
        var canvas = Canvas(width: Self.size, height: Self.size)
        let bounds = canvas.bounds
        var problems: [String] = []

        let background = appearance.background
        canvas.fill(bounds, Color(red: Float(background.red) / 255, green: Float(background.green) / 255,
                                  blue: Float(background.blue) / 255))

        var drewImage = false
        if let path = appearance.image {
            if let image = RGBAImage(contentsOfFile: path) {
                canvas.draw(image, in: bounds.aspectFill(width: Double(image.width), height: Double(image.height)))
                drewImage = true
            } else {
                problems.append("image file not found or unreadable: \(path)")
            }
        }

        let label = appearance.label.flatMap { $0.isEmpty ? nil : $0 }
        let size = Double(Self.size)
        let iconBox = label == nil
            ? bounds.insetBy(dx: 12, dy: 12)
            : Rect(x: 14, y: 6, width: size - 28, height: size - Self.labelAreaHeight - 8)

        if let icon = appearance.icon {
            if let problem = drawIcon(icon, in: iconBox, on: &canvas) {
                problems.append(problem)
                drawPlaceholder(in: iconBox, on: &canvas)
            }
        }

        if let label {
            let area = appearance.icon == nil
                ? bounds.insetBy(dx: Self.padding, dy: Self.padding)
                : Rect(x: Self.padding, y: size - 2 - Self.labelAreaHeight, width: size - 2 * Self.padding, height: Self.labelAreaHeight)
            drawLabel(label, in: area, on: &canvas, shadow: drewImage)
        }

        if appearance.error {
            canvas.fillEllipse(Rect(x: size - 13, y: 3, width: 10, height: 10), Color(red: 0.9, green: 0.1, blue: 0.1))
        }

        if appearance.pressed {
            canvas.fill(bounds, Color(gray: 0, alpha: 0.4))
        }

        return (canvas.image(), problems)
    }

    // MARK: - Icons

    /// Draws the icon, or returns the problem when it can't.
    private func drawIcon(_ icon: Icon, in box: Rect, on canvas: inout Canvas) -> String? {
        switch icon {
        case let .file(path):
            guard let image = RGBAImage(contentsOfFile: path) else { return "icon file not found or unreadable: \(path)" }
            canvas.draw(image, in: box.aspectFit(width: Double(image.width), height: Double(image.height)))
            return nil
        case let .material(name, filled):
            var mask = Mask(width: canvas.width, height: canvas.height)
            guard MaterialSymbols.draw(name, filled: filled, in: box, into: &mask) else {
                return "unknown Material Symbol: \(name)"
            }
            canvas.fill(mask, .white)
            return nil
        case let .symbol(name):
            guard let sfSymbols else {
                return "SF Symbols are only available on macOS: sf:\(name). Use an ms: icon instead."
            }
            guard let image = sfSymbols.image(named: name, pointSize: box.height) else { return "unknown SF Symbol: \(name)" }
            canvas.draw(image, in: box.aspectFit(width: Double(image.width), height: Double(image.height)))
            return nil
        }
    }

    /// A dashed gray outline with a question mark.
    private func drawPlaceholder(in box: Rect, on canvas: inout Canvas) {
        let side = min(box.width, box.height)
        let square = Rect(x: box.midX - side / 2, y: box.midY - side / 2, width: side, height: side).insetBy(dx: 4, dy: 4)
        let gray = Color(gray: 0.6)
        canvas.strokeDashedRect(square, lineWidth: 2, dash: (4, 3), gray)
        drawLabel("?", in: square, on: &canvas, color: gray)
    }

    // MARK: - Labels

    /// Draws text centered in `area`, laid out by `LabelLayout`.
    private func drawLabel(_ text: String, in area: Rect, on canvas: inout Canvas, color: Color = .white, shadow: Bool = false) {
        let mask = Self.labelMask(text, in: area, width: canvas.width, height: canvas.height)
        if shadow {
            // Keeps the label readable on bright images.
            canvas.fill(mask.blurred(radius: 1).shifted(dx: 0, dy: 1), Color(gray: 0, alpha: 0.8))
        }
        canvas.fill(mask, color)
    }

    static func labelMask(_ text: String, in area: Rect, width: Int, height: Int) -> Mask {
        let layout = LabelLayout(text, width: area.width, height: area.height)
        var mask = Mask(width: width, height: height)
        let top = area.midY - layout.lineHeight * Double(layout.lines.count) / 2
        for (index, line) in layout.lines.enumerated() {
            let baseline = top + Double(index) * layout.lineHeight + layout.ascent
            let left = area.midX - line.width / 2
            for glyph in line.glyphs {
                layout.font.draw(glyph.glyph, scale: layout.scale, x: left + glyph.x, y: baseline, into: &mask)
            }
        }
        return mask
    }
}

extension RGBAImage {
    /// Rotated 180 degrees (both axes flipped), as the device expects.
    func rotated180() -> RGBAImage {
        var bytes = [UInt8](repeating: 0, count: pixels.count)
        let count = width * height
        for i in 0 ..< count {
            let j = (count - 1 - i) * 4
            bytes[j ..< j + 4] = pixels[i * 4 ..< i * 4 + 4]
        }
        return RGBAImage(width: width, height: height, pixels: bytes)
    }
}
