import CStb
import CWebAssets
import Foundation

/// Files served to the browser, all compiled into the binary. See design "Static assets".
struct WebAssets: Sendable {
    struct Asset: Sendable {
        let bytes: Data
        let contentType: String
        /// A hash of the bytes, quoted as an HTTP entity tag.
        let etag: String
    }

    let files: [String: Asset]

    static let shared = WebAssets()

    init() {
        var files: [String: Asset] = [:]
        var count = 0
        let table = UnsafeBufferPointer(start: deck_web_assets(&count), count: count)
        for entry in table {
            let path = String(cString: entry.path)
            files[path] = Self.asset(Data(bytes: entry.bytes, count: entry.size), path: path)
        }
        files["material-outlined.ttf"] = Self.asset(Self.data(deck_font_material_outlined), path: "material-outlined.ttf")
        files["material-filled.ttf"] = Self.asset(Self.data(deck_font_material_filled), path: "material-filled.ttf")
        self.files = files
    }

    /// Material Symbols names with their codepoints, from the codepoints file next to the fonts.
    static let symbols: [(name: String, codepoint: Int)] = {
        let text = String(decoding: data(deck_material_codepoints), as: UTF8.self)
        return text.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: " ")
            guard fields.count == 2, let value = Int(fields[1], radix: 16) else { return nil }
            return (String(fields[0]), value)
        }
    }()

    private static func data(_ accessor: (UnsafeMutablePointer<Int>?) -> UnsafePointer<UInt8>?) -> Data {
        var size = 0
        guard let bytes = accessor(&size) else { return Data() }
        return Data(bytes: bytes, count: size)
    }

    private static func asset(_ bytes: Data, path: String) -> Asset {
        Asset(bytes: bytes, contentType: contentType(path), etag: "\"\(SHA256.hex(bytes).prefix(16))\"")
    }

    static func contentType(_ path: String) -> String {
        switch path.split(separator: ".").last {
        case "html": "text/html; charset=utf-8"
        case "css": "text/css; charset=utf-8"
        case "js": "text/javascript; charset=utf-8"
        case "ttf": "font/ttf"
        case "json": "application/json"
        default: "application/octet-stream"
        }
    }
}
