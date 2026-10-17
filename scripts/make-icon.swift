// Renders the app icon as a 1024x1024 PNG.
// Usage: swift scripts/make-icon.swift <output.png>
// scripts/make-icon.sh turns the PNG into Resources/AppIcon.icns.

import AppKit

let size: CGFloat = 1024
let output = CommandLine.arguments.dropFirst().first ?? "AppIcon.png"

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}

func roundedRect(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func fillGradient(_ context: CGContext, path: CGPath, top: CGColor, bottom: CGColor, rect: CGRect) {
    context.saveGState()
    context.addPath(path)
    context.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [bottom, top] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: rect.midX, y: rect.minY), end: CGPoint(x: rect.midX, y: rect.maxY), options: [])
    context.restoreGState()
}

func drawSymbol(_ name: String, in rect: CGRect, context: CGContext) {
    let configuration = NSImage.SymbolConfiguration(pointSize: rect.height * 0.5, weight: .semibold)
        .applying(.init(paletteColors: [.white]))
    guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration) else { return }
    var proposed = CGRect(origin: .zero, size: symbol.size)
    guard let image = symbol.cgImage(forProposedRect: &proposed, context: nil, hints: [.ctm: AffineTransform(scale: 4)]) else { return }
    let scale = min(rect.width * 0.55 / symbol.size.width, rect.height * 0.55 / symbol.size.height)
    let fitted = CGSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
    context.draw(image, in: CGRect(x: rect.midX - fitted.width / 2, y: rect.midY - fitted.height / 2, width: fitted.width, height: fitted.height))
}

let context = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

// Background squircle on Apple's icon grid: 824 pt body centered in 1024 pt canvas.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = roundedRect(body, radius: 185)
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0x000000, alpha: 0.35))
context.addPath(bodyPath)
context.setFillColor(color(0x3A46D8))
context.fillPath()
context.restoreGState()
fillGradient(context, path: bodyPath, top: color(0x6E7BFF), bottom: color(0x2B2F9E), rect: body)

// Device: dark slab holding a 5x3 key grid.
let columns = 5, rows = 3
let padding: CGFloat = 40, gap: CGFloat = 20
let deviceWidth: CGFloat = 724
let key = (deviceWidth - 2 * padding - CGFloat(columns - 1) * gap) / CGFloat(columns)
let deviceHeight = 2 * padding + CGFloat(rows) * key + CGFloat(rows - 1) * gap
let device = CGRect(x: (size - deviceWidth) / 2, y: (size - deviceHeight) / 2 - 8, width: deviceWidth, height: deviceHeight)
let devicePath = roundedRect(device, radius: 64)
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -18), blur: 36, color: color(0x000000, alpha: 0.45))
context.addPath(devicePath)
context.setFillColor(color(0x1B1C22))
context.fillPath()
context.restoreGState()
fillGradient(context, path: devicePath, top: color(0x34363F), bottom: color(0x17181D), rect: device)

// Lit keys in a checkerboard; the rest stay dark.
let lit: [Int: (UInt32, String)] = [
    1: (0x0A84FF, "terminal.fill"),
    3: (0xFF9F0A, "play.fill"),
    5: (0x30D158, "mic.fill"),
    7: (0xFF375F, "heart.fill"),
    9: (0xFFD60A, "sun.max.fill"),
    11: (0xBF5AF2, "moon.fill"),
    13: (0x64D2FF, "speaker.wave.2.fill"),
]
for index in 0 ..< columns * rows {
    let column = index % columns, row = index / columns
    let rect = CGRect(x: device.minX + padding + CGFloat(column) * (key + gap),
                      y: device.maxY - padding - key - CGFloat(row) * (key + gap),
                      width: key, height: key)
    let path = roundedRect(rect, radius: 22)
    if let (hex, symbol) = lit[index] {
        fillGradient(context, path: path, top: color(hex), bottom: color(hex, alpha: 0.78), rect: rect)
        drawSymbol(symbol, in: rect, context: context)
    } else {
        fillGradient(context, path: path, top: color(0x2A2C33), bottom: color(0x0F1013), rect: rect)
    }
    // Thin top highlight gives the keys a glassy edge.
    context.saveGState()
    context.addPath(path)
    context.setStrokeColor(color(0xFFFFFF, alpha: 0.10))
    context.setLineWidth(2)
    context.strokePath()
    context.restoreGState()
}

let image = context.makeImage()!
let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: output) as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("cannot write \(output)") }
print("Wrote \(output)")
