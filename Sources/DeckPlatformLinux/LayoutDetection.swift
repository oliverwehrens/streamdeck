import Foundation

/// Finds the XKB layout keystrokes are typed on. The first source that names one wins:
/// gamescope's environment (it applies that keymap in Game Mode), our own environment,
/// `localectl`'s `00-keyboard.conf`, `vconsole.conf`, then `us`.
public struct LayoutDetection: Sendable {
    public var procRoot: String
    public var etcRoot: String
    public var environment: [String: String]
    public var uid: uid_t

    public init(procRoot: String = "/proc", etcRoot: String = "/etc",
                environment: [String: String] = ProcessInfo.processInfo.environment, uid: uid_t = getuid()) {
        self.procRoot = procRoot
        self.etcRoot = etcRoot
        self.environment = environment
        self.uid = uid
    }

    public func current() -> XKBLayout.Selection {
        detect()?.selection ?? XKBLayout.Selection(layout: "us")
    }

    /// The layout and the source it came from, for logging.
    public func detect() -> (selection: XKBLayout.Selection, source: String)? {
        if let selection = gamescopeEnvironment() { return (selection, "gamescope environment") }
        if let selection = Self.selection(layout: environment["XKB_DEFAULT_LAYOUT"], variant: environment["XKB_DEFAULT_VARIANT"]) {
            return (selection, "XKB_DEFAULT_LAYOUT")
        }
        if let selection = xorgKeyboardConf() { return (selection, "\(etcRoot)/X11/xorg.conf.d/00-keyboard.conf") }
        if let selection = vconsoleConf() { return (selection, "\(etcRoot)/vconsole.conf") }
        return nil
    }

    /// First entry of comma lists (`de,us`); an empty layout means none.
    static func selection(layout: String?, variant: String?) -> XKBLayout.Selection? {
        guard let layout = layout?.split(separator: ",", omittingEmptySubsequences: false).first
            .map({ $0.trimmingCharacters(in: .whitespaces) }), !layout.isEmpty else { return nil }
        let variant = variant?.split(separator: ",", omittingEmptySubsequences: false).first
            .map { $0.trimmingCharacters(in: .whitespaces) }
        return XKBLayout.Selection(layout: layout, variant: (variant?.isEmpty ?? true) ? nil : variant)
    }

    func gamescopeEnvironment() -> XKBLayout.Selection? {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: procRoot) else { return nil }
        for pid in entries where pid.allSatisfy(\.isNumber) {
            let directory = "\(procRoot)/\(pid)"
            guard let comm = try? String(contentsOfFile: directory + "/comm", encoding: .utf8),
                  comm.hasPrefix("gamescope"),
                  Self.ownerUID(status: (try? String(contentsOfFile: directory + "/status", encoding: .utf8)) ?? "") == uid,
                  let environ = FileManager.default.contents(atPath: directory + "/environ")
            else { continue }
            let variables = Self.parseEnviron(environ)
            if let selection = Self.selection(layout: variables["XKB_DEFAULT_LAYOUT"], variant: variables["XKB_DEFAULT_VARIANT"]) {
                return selection
            }
        }
        return nil
    }

    /// The real UID from `/proc/<pid>/status` (`Uid:\treal\teffective\t...`).
    static func ownerUID(status: String) -> uid_t? {
        for line in status.split(separator: "\n") where line.hasPrefix("Uid:") {
            return line.split(whereSeparator: \.isWhitespace).dropFirst().first.flatMap { uid_t($0) }
        }
        return nil
    }

    static func parseEnviron(_ data: Data) -> [String: String] {
        var variables: [String: String] = [:]
        for entry in data.split(separator: 0) {
            let text = String(decoding: entry, as: UTF8.self)
            guard let equals = text.firstIndex(of: "=") else { continue }
            variables[String(text[..<equals])] = String(text[text.index(after: equals)...])
        }
        return variables
    }

    func xorgKeyboardConf() -> XKBLayout.Selection? {
        guard let text = try? String(contentsOfFile: "\(etcRoot)/X11/xorg.conf.d/00-keyboard.conf", encoding: .utf8) else { return nil }
        var options: [String: String] = [:]
        let pattern = try! NSRegularExpression(pattern: #"Option\s+"(\w+)"\s+"([^"]*)""#)
        let nsText = text as NSString
        for match in pattern.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
            options[nsText.substring(with: match.range(at: 1)).lowercased()] = nsText.substring(with: match.range(at: 2))
        }
        return Self.selection(layout: options["xkblayout"], variant: options["xkbvariant"])
    }

    func vconsoleConf() -> XKBLayout.Selection? {
        guard let text = try? String(contentsOfFile: "\(etcRoot)/vconsole.conf", encoding: .utf8) else { return nil }
        var values: [String: String] = [:]
        for line in text.split(separator: "\n") {
            guard let equals = line.firstIndex(of: "=") else { continue }
            let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            values[String(line[..<equals]).trimmingCharacters(in: .whitespaces)] = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
        return Self.selection(layout: values["XKBLAYOUT"], variant: values["XKBVARIANT"])
    }
}
