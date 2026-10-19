import AppKit
import CoreText
import DeckConfig
import ImageIO
import UniformTypeIdentifiers

/// Everything that determines how one key looks.
public struct KeyAppearance: Equatable, Sendable {
    public var background: HexColor
    public var icon: Icon?
    public var label: String?
    public var pressed: Bool
    public var error: Bool

    public init(background: HexColor = .black, icon: Icon? = nil, label: String? = nil, pressed: Bool = false, error: Bool = false) {
        self.background = background
        self.icon = icon
        self.label = label
        self.pressed = pressed
        self.error = error
    }

    public static let blank = KeyAppearance()
}

public struct RenderedKey: Sendable {
    /// JPEG, flipped for the device.
    public var jpeg: Data
    /// Problems found while rendering, such as a missing icon.
    public var problems: [String]
}

public enum KeyRenderer {
    public static let size = 72
    static let padding: CGFloat = 4
    static let maxFontSize: CGFloat = 14
    static let minFontSize: CGFloat = 9
    static let labelAreaHeight: CGFloat = 24

    /// Renders and encodes a key for the device.
    public static func render(_ appearance: KeyAppearance) -> RenderedKey {
        let (image, problems) = renderUpright(appearance)
        return RenderedKey(jpeg: encodeJPEG(flipped(image)), problems: problems)
    }

    /// The key as the user sees it on the device, for on-screen previews.
    public static func preview(_ appearance: KeyAppearance) -> CGImage {
        renderUpright(appearance).0
    }

    /// The key image as the user sees it, before the device flip.
    static func renderUpright(_ appearance: KeyAppearance) -> (CGImage, [String]) {
        let context = makeContext()
        let bounds = CGRect(x: 0, y: 0, width: size, height: size)
        var problems: [String] = []

        let background = appearance.background
        context.setFillColor(CGColor(srgbRed: CGFloat(background.red) / 255, green: CGFloat(background.green) / 255,
                                     blue: CGFloat(background.blue) / 255, alpha: 1))
        context.fill(bounds)

        let label = appearance.label.flatMap { $0.isEmpty ? nil : $0 }
        let iconRect: CGRect = label == nil
            ? bounds.insetBy(dx: 12, dy: 12)
            : CGRect(x: 14, y: labelAreaHeight + 2, width: CGFloat(size) - 28, height: CGFloat(size) - labelAreaHeight - 8)

        if let icon = appearance.icon {
            if let image = loadIcon(icon, pointSize: iconRect.height) {
                context.draw(image, in: aspectFit(CGSize(width: image.width, height: image.height), in: iconRect))
            } else {
                problems.append(missingIconMessage(icon))
                drawPlaceholder(in: iconRect, context: context)
            }
        }

        if let label {
            let area = appearance.icon == nil
                ? bounds.insetBy(dx: padding, dy: padding)
                : CGRect(x: padding, y: 2, width: CGFloat(size) - 2 * padding, height: labelAreaHeight)
            drawLabel(label, in: area, context: context)
        }

        if appearance.error {
            context.setFillColor(CGColor(srgbRed: 0.9, green: 0.1, blue: 0.1, alpha: 1))
            context.fillEllipse(in: CGRect(x: CGFloat(size) - 13, y: CGFloat(size) - 13, width: 10, height: 10))
        }

        if appearance.pressed {
            context.setFillColor(CGColor(gray: 0, alpha: 0.4))
            context.fill(bounds)
        }

        return (context.makeImage()!, problems)
    }

    // MARK: - Icons

    static func loadIcon(_ icon: Icon, pointSize: CGFloat) -> CGImage? {
        switch icon {
        case let .file(path):
            guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        case let .symbol(name):
            let configuration = NSImage.SymbolConfiguration(pointSize: pointSize * 0.8, weight: .regular)
                .applying(.init(paletteColors: [.white]))
            guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration) else { return nil }
            var rect = CGRect(origin: .zero, size: symbol.size)
            return symbol.cgImage(forProposedRect: &rect, context: nil, hints: [.ctm: AffineTransform(scale: 2)])
        }
    }

    static func missingIconMessage(_ icon: Icon) -> String {
        switch icon {
        case let .file(path): "icon file not found or unreadable: \(path)"
        case let .symbol(name): "unknown SF Symbol: \(name)"
        }
    }

    /// A dashed outline with a question mark.
    static func drawPlaceholder(in rect: CGRect, context: CGContext) {
        let square = aspectFit(CGSize(width: 1, height: 1), in: rect).insetBy(dx: 4, dy: 4)
        context.saveGState()
        context.setStrokeColor(CGColor(gray: 0.6, alpha: 1))
        context.setLineWidth(2)
        context.setLineDash(phase: 0, lengths: [4, 3])
        context.stroke(square)
        context.restoreGState()
        drawLabel("?", in: square, context: context, color: CGColor(gray: 0.6, alpha: 1))
    }

    static func aspectFit(_ size: CGSize, in rect: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return rect }
        let scale = min(rect.width / size.width, rect.height / size.height)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(x: rect.midX - fitted.width / 2, y: rect.midY - fitted.height / 2, width: fitted.width, height: fitted.height)
    }

    // MARK: - Labels

    /// Draws text centered in `area`: shrinks from 14 to 9 pt, wraps to two lines, then truncates.
    static func drawLabel(_ text: String, in area: CGRect, context: CGContext, color: CGColor = CGColor(gray: 1, alpha: 1)) {
        let lines = layoutLabel(text, width: area.width, height: area.height, color: color)
        let lineHeight = lines.first.map { lineMetrics($0).height } ?? 0
        let total = lineHeight * CGFloat(lines.count)
        var baselineTop = area.midY + total / 2
        for line in lines {
            let metrics = lineMetrics(line)
            let width = CTLineGetTypographicBounds(line, nil, nil, nil)
            context.textPosition = CGPoint(x: area.midX - width / 2, y: baselineTop - metrics.ascent)
            CTLineDraw(line, context)
            baselineTop -= lineHeight
        }
    }

    /// Lines to draw for a label; never more than two, each no wider than `width`.
    static func layoutLabel(_ text: String, width: CGFloat, height: CGFloat, color: CGColor = CGColor(gray: 1, alpha: 1)) -> [CTLine] {
        var size = maxFontSize
        while true {
            let attributed = attributedLabel(text, size: size, color: color)
            let lines = wrap(attributed, width: width)
            let lineHeight = lines.first.map { lineMetrics($0).height } ?? 0
            if lines.count <= 2, lineHeight * CGFloat(lines.count) <= height, lines.allSatisfy({ lineWidth($0) <= width }) {
                return lines
            }
            if size <= minFontSize {
                return truncate(attributed, lines: lines, width: width, maxLines: max(1, min(2, Int(height / max(lineHeight, 1)))))
            }
            size -= 1
        }
    }

    private static func attributedLabel(_ text: String, size: CGFloat, color: CGColor) -> NSAttributedString {
        let font = NSFont.systemFont(ofSize: size, weight: .semibold)
        return NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ])
    }

    private static func wrap(_ attributed: NSAttributedString, width: CGFloat) -> [CTLine] {
        let typesetter = CTTypesetterCreateWithAttributedString(attributed)
        var lines: [CTLine] = []
        var start = 0
        while start < attributed.length {
            let count = CTTypesetterSuggestLineBreak(typesetter, start, width)
            guard count > 0 else { break }
            lines.append(CTTypesetterCreateLine(typesetter, CFRange(location: start, length: count)))
            start += count
        }
        return lines
    }

    private static func truncate(_ attributed: NSAttributedString, lines: [CTLine], width: CGFloat, maxLines: Int) -> [CTLine] {
        var kept = Array(lines.prefix(maxLines - 1))
        let usedLength = kept.reduce(0) { $0 + CTLineGetStringRange($1).length }
        let rest = attributed.attributedSubstring(from: NSRange(location: usedLength, length: attributed.length - usedLength))
        let restLine = CTLineCreateWithAttributedString(rest)
        let ellipsisAttributes = attributed.attributes(at: 0, effectiveRange: nil)
        let ellipsis = CTLineCreateWithAttributedString(NSAttributedString(string: "\u{2026}", attributes: ellipsisAttributes))
        kept.append(CTLineCreateTruncatedLine(restLine, Double(width), .end, ellipsis) ?? ellipsis)
        return kept
    }

    static func lineWidth(_ line: CTLine) -> CGFloat {
        CTLineGetTypographicBounds(line, nil, nil, nil) - CTLineGetTrailingWhitespaceWidth(line)
    }

    private static func lineMetrics(_ line: CTLine) -> (ascent: CGFloat, height: CGFloat) {
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        return (ascent, ascent + descent + leading)
    }

    // MARK: - Output

    static func makeContext() -> CGContext {
        CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    }

    /// Rotates 180 degrees (both axes flipped), as the device expects.
    static func flipped(_ image: CGImage) -> CGImage {
        let context = makeContext()
        context.translateBy(x: CGFloat(size), y: CGFloat(size))
        context.scaleBy(x: -1, y: -1)
        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        return context.makeImage()!
    }

    static func encodeJPEG(_ image: CGImage) -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        CGImageDestinationFinalize(destination)
        return data as Data
    }
}
