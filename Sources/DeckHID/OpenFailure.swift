import AppKit
import IOKit

public enum OpenFailure {
    public static let elgatoBundleID = "com.elgato.StreamDeck"

    public static func elgatoAppIsRunning() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: elgatoBundleID).isEmpty
    }

    /// User-facing message for a device that matched but could not be opened.
    public static func message(code: Int32, elgatoRunning: Bool) -> String {
        if elgatoRunning {
            return "Cannot open the Stream Deck because the Elgato Stream Deck app is using it. Quit the Elgato app."
        }
        let reason = switch code {
        case kIOReturnExclusiveAccess: "another app has exclusive access"
        case kIOReturnNotPermitted, kIOReturnNotPrivileged: "macOS denied access"
        default: String(format: "IOKit error 0x%08x", UInt32(bitPattern: code))
        }
        return "Cannot open the Stream Deck: \(reason)."
    }
}
