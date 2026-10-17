import Foundation

/// A change of one key's physical state.
public struct KeyEvent: Equatable, Sendable {
    public enum Edge: Sendable { case down, up }

    public let key: Int
    public let edge: Edge

    public init(key: Int, edge: Edge) {
        self.key = key
        self.edge = edge
    }
}

/// Encodes and decodes Stream Deck Original V2 reports. See docs/protocol.md.
public enum ReportCodec {
    public static let keyCount = 15
    public static let imageReportSize = 1024
    public static let imageHeaderSize = 8
    public static let featureReportSize = 32

    static let inputReportID: UInt8 = 0x01
    static let inputHeaderSize = 4

    /// Extracts key states from an input report buffer (report ID at byte 0).
    /// Returns nil for reports that are not key-state reports.
    public static func keyStates(fromInputReport bytes: [UInt8]) -> [Bool]? {
        guard bytes.count >= inputHeaderSize + keyCount, bytes[0] == inputReportID else { return nil }
        return bytes[inputHeaderSize ..< inputHeaderSize + keyCount].map { $0 != 0 }
    }

    /// Key events needed to get from `old` to `new`, in key order.
    public static func events(from old: [Bool], to new: [Bool]) -> [KeyEvent] {
        zip(old, new).enumerated().compactMap { key, pair in
            switch pair {
            case (false, true): KeyEvent(key: key, edge: .down)
            case (true, false): KeyEvent(key: key, edge: .up)
            default: nil
            }
        }
    }

    /// Splits a JPEG into 1024-byte output reports for one key.
    public static func imageReports(key: Int, jpeg: Data) -> [[UInt8]] {
        precondition((0 ..< keyCount).contains(key), "key index out of range")
        let payloadSize = imageReportSize - imageHeaderSize
        let bytes = [UInt8](jpeg)
        let pageCount = max(1, (bytes.count + payloadSize - 1) / payloadSize)
        return (0 ..< pageCount).map { page in
            let start = page * payloadSize
            let chunk = bytes[start ..< min(start + payloadSize, bytes.count)]
            var report = [UInt8](repeating: 0, count: imageReportSize)
            report[0] = 0x02
            report[1] = 0x07
            report[2] = UInt8(key)
            report[3] = page == pageCount - 1 ? 1 : 0
            report[4] = UInt8(chunk.count & 0xff)
            report[5] = UInt8(chunk.count >> 8)
            report[6] = UInt8(page & 0xff)
            report[7] = UInt8(page >> 8)
            report.replaceSubrange(imageHeaderSize ..< imageHeaderSize + chunk.count, with: chunk)
            return report
        }
    }

    /// Feature report setting brightness; the value is clamped to 0...100.
    public static func brightnessReport(percent: Int) -> [UInt8] {
        feature([0x03, 0x08, UInt8(min(100, max(0, percent)))])
    }

    public static func resetReport() -> [UInt8] {
        feature([0x03, 0x02])
    }

    /// Parses a NUL-terminated ASCII string from a get-feature response.
    public static func string(fromFeatureReport bytes: [UInt8], offset: Int) -> String {
        guard bytes.count > offset else { return "" }
        let text = bytes[offset...].prefix { $0 != 0 }
        return String(decoding: text, as: UTF8.self)
    }

    public static let firmwareReportID: UInt8 = 0x05
    public static let firmwareOffset = 6
    public static let serialReportID: UInt8 = 0x06
    public static let serialOffset = 2

    private static func feature(_ prefix: [UInt8]) -> [UInt8] {
        prefix + [UInt8](repeating: 0, count: featureReportSize - prefix.count)
    }
}
