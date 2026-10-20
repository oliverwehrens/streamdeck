import DeckConfig
import Foundation

/// What a dynamic key's command set. A nil field keeps the key's configured value.
public struct DynamicOutput: Equatable, Sendable {
    public var label: String?
    public var icon: Icon?
    public var background: HexColor?

    public init(label: String? = nil, icon: Icon? = nil, background: HexColor? = nil) {
        self.label = label
        self.icon = icon
        self.background = background
    }

    public struct Rejected: Error, Equatable, Sendable {
        public var reason: String
    }

    /// Output starting with `{` is a JSON object; anything else is plain text whose first line is the label.
    public static func parse(_ stdout: String, configDirectory: URL) -> Result<DynamicOutput, Rejected> {
        guard stdout.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") else {
            let firstLine = stdout.split(separator: "\n", omittingEmptySubsequences: false).first ?? ""
            return .success(DynamicOutput(label: firstLine.trimmingCharacters(in: .whitespaces)))
        }
        guard let object = try? JSONSerialization.jsonObject(with: Data(stdout.utf8)) else {
            return .failure(Rejected(reason: "not valid JSON"))
        }
        guard let fields = object as? [String: Any] else {
            return .failure(Rejected(reason: "not a JSON object"))
        }

        var output = DynamicOutput()
        for name in ["label", "icon", "background"] {
            guard let value = fields[name] else { continue }
            guard let text = value as? String else {
                return .failure(Rejected(reason: "\(name) must be a string"))
            }
            switch name {
            case "label":
                output.label = text
            case "icon":
                output.icon = Icon(configValue: text, relativeTo: configDirectory)
            default:
                guard let color = HexColor(hex: text) else {
                    return .failure(Rejected(reason: "background '\(text)' must be #RRGGBB"))
                }
                output.background = color
            }
        }
        return .success(output)
    }
}
