import Foundation

/// Location of the config file and creation of the starter config.
public enum ConfigFile {
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/streamdeck/config.yaml")
    }

    /// Writes the starter config if no file exists at `url`. Returns true if it wrote one.
    @discardableResult
    public static func createStarterIfMissing(at url: URL) throws -> Bool {
        guard !FileManager.default.fileExists(atPath: url.path) else { return false }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try starter.write(to: url, atomically: true, encoding: .utf8)
        return true
    }

    public static let starter = """
    # Stream Deck configuration. Saved changes apply within a second.
    # Keys are numbered 0-14, left to right, top to bottom:
    #    0  1  2  3  4
    #    5  6  7  8  9
    #   10 11 12 13 14
    # Full reference: docs/config.md in the project repository.

    brightness: 70
    default_page: home

    # Show a page automatically when an app comes to the front.
    # app_pages:
    #   com.apple.Safari: media

    pages:
      home:
        keys:
          0: { icon: sf:terminal, label: Terminal, action: { open: /System/Applications/Utilities/Terminal.app } }
          1: { icon: sf:safari, label: Web, action: { open: "https://www.apple.com" } }
          2: { icon: sf:magnifyingglass, label: Spotlight, action: { keys: cmd+space } }
          4: { icon: sf:music.note, label: Media, action: { page: media } }
          10: { label: Hello, background: "#2D6A4F", action: { run: "say hello" } }
          14: { dynamic: { run: "date +%H:%M", every: 10s } }

      media:
        keys:
          0: { icon: sf:backward.fill, action: { media: previous } }
          1: { icon: sf:playpause.fill, action: { media: playpause } }
          2: { icon: sf:forward.fill, action: { media: next } }
          5: { icon: sf:speaker.minus.fill, action: { media: volumedown } }
          6: { icon: sf:speaker.slash.fill, action: { media: mute } }
          7: { icon: sf:speaker.plus.fill, action: { media: volumeup } }
          14: { icon: sf:arrow.uturn.left, label: Back, action: { page: back } }

    """
}
