import Foundation

/// Finds Stream Decks among the hidraw nodes, from sysfs. Pure apart from reading files, so tests use fixture trees.
public enum HidrawDevices {
    public static let vendorID = 0x0fd9
    public static let productID = 0x006d

    public struct Found: Equatable, Sendable {
        /// Device node, for example `/dev/hidraw3`.
        public var node: String
        /// `HID_UNIQ`, when the kernel knows it.
        public var serial: String?
    }

    public struct Uevent: Equatable, Sendable {
        public var bus: Int
        public var vendor: Int
        public var product: Int
        public var uniq: String?
    }

    /// Parses a hid device's `uevent` (`HID_ID=0003:00000FD9:0000006D`, `HID_UNIQ=...`).
    public static func parseUevent(_ text: String) -> Uevent? {
        var fields: [String: String] = [:]
        for line in text.split(separator: "\n") {
            guard let equals = line.firstIndex(of: "=") else { continue }
            fields[String(line[..<equals])] = String(line[line.index(after: equals)...])
        }
        guard let id = fields["HID_ID"] else { return nil }
        let parts = id.split(separator: ":").compactMap { Int($0, radix: 16) }
        guard parts.count == 3 else { return nil }
        let uniq = fields["HID_UNIQ"].flatMap { $0.isEmpty ? nil : $0 }
        return Uevent(bus: parts[0], vendor: parts[1], product: parts[2], uniq: uniq)
    }

    /// Stream Deck Original V2 nodes, sorted by name. `sysfsRoot` holds `class/hidraw`.
    public static func find(sysfsRoot: String = "/sys", devRoot: String = "/dev") -> [Found] {
        let classDirectory = sysfsRoot + "/class/hidraw"
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: classDirectory) else { return [] }
        return names.filter { $0.hasPrefix("hidraw") }.sorted { numericSuffix($0) < numericSuffix($1) }.compactMap { name in
            guard let text = try? String(contentsOfFile: "\(classDirectory)/\(name)/device/uevent", encoding: .utf8),
                  let event = parseUevent(text),
                  event.vendor == vendorID, event.product == productID
            else { return nil }
            return Found(node: "\(devRoot)/\(name)", serial: event.uniq)
        }
    }

    /// The message for a node that exists but cannot be opened.
    public static func openFailureMessage(node: String, errno code: Int32) -> String {
        switch code {
        case EACCES, EPERM:
            "Cannot open the Stream Deck at \(node): permission denied. Install the udev rules with scripts/install-linux.sh."
        case EBUSY:
            "Cannot open the Stream Deck at \(node): another program is using it."
        default:
            "Cannot open the Stream Deck at \(node): \(errorText(code))."
        }
    }

    private static func numericSuffix(_ name: String) -> Int {
        Int(name.dropFirst("hidraw".count)) ?? Int.max
    }
}
