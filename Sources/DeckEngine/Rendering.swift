import DeckConfig
import Foundation

/// Everything that determines how one key looks.
public struct KeyAppearance: Equatable, Sendable {
    public var background: HexColor
    public var icon: Icon?
    /// Absolute path of an image drawn across the whole key.
    public var image: String?
    public var label: String?
    public var pressed: Bool
    public var error: Bool

    public init(background: HexColor = .black, icon: Icon? = nil, image: String? = nil, label: String? = nil, pressed: Bool = false, error: Bool = false) {
        self.background = background
        self.icon = icon
        self.image = image
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

    public init(jpeg: Data, problems: [String] = []) {
        self.jpeg = jpeg
        self.problems = problems
    }
}

/// Turns a key's appearance into the image the device shows.
public protocol KeyRendering: Sendable {
    func render(_ appearance: KeyAppearance) -> RenderedKey
}
