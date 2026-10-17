import Foundation

public struct DeckConfig: Equatable, Sendable {
    public static let keyCount = 15
    public static let defaultBrightness = 70

    public var brightness: Int
    public var defaultPage: String
    public var pages: [String: Page]
    /// Application bundle ID to page name.
    public var appPages: [String: String]

    public init(brightness: Int = DeckConfig.defaultBrightness, defaultPage: String, pages: [String: Page], appPages: [String: String] = [:]) {
        self.brightness = brightness
        self.defaultPage = defaultPage
        self.pages = pages
        self.appPages = appPages
    }
}

public struct Page: Equatable, Sendable {
    public var keys: [Int: KeyDefinition]

    public init(keys: [Int: KeyDefinition]) {
        self.keys = keys
    }
}

public struct KeyDefinition: Equatable, Sendable {
    public var icon: Icon?
    public var label: String?
    public var background: HexColor?
    public var action: Action?
    public var dynamic: Dynamic?

    public init(icon: Icon? = nil, label: String? = nil, background: HexColor? = nil, action: Action? = nil, dynamic: Dynamic? = nil) {
        self.icon = icon
        self.label = label
        self.background = background
        self.action = action
        self.dynamic = dynamic
    }
}

public enum Icon: Equatable, Sendable {
    case symbol(String)
    /// Absolute path, already resolved against the config directory.
    case file(String)
}

public struct HexColor: Equatable, Sendable {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public static let black = HexColor(red: 0, green: 0, blue: 0)

    /// Parses `#RRGGBB`.
    public init?(hex: String) {
        guard hex.count == 7, hex.first == "#", let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        self.init(red: UInt8(value >> 16 & 0xff), green: UInt8(value >> 8 & 0xff), blue: UInt8(value & 0xff))
    }
}

public enum Action: Equatable, Sendable {
    case run(String)
    case open(String)
    case keys(KeyCombo)
    case media(MediaKey)
    case page(PageTarget)
}

public enum PageTarget: Equatable, Sendable {
    case named(String)
    case back
}

public enum MediaKey: String, CaseIterable, Sendable {
    case playpause, next, previous, volumeup, volumedown, mute, brightnessup, brightnessdown
}

public struct Dynamic: Equatable, Sendable {
    public static let minimumInterval: TimeInterval = 1

    public var run: String
    public var every: TimeInterval

    public init(run: String, every: TimeInterval) {
        self.run = run
        self.every = every
    }
}
