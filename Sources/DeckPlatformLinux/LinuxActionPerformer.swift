import DeckConfig
import DeckEngine
import Foundation

/// Performs actions on Linux: shell commands, `steam`/`xdg-open`, and keys through uinput.
public struct LinuxActionPerformer: ActionPerformer {
    static let openPatience: TimeInterval = 10

    let commands: CommandRunner
    let keyboard: Result<UinputKeyboard, UinputError>
    let layout: any KeyboardLayout
    let launcher: any ProgramLauncher

    public init(commands: CommandRunner = ShellRunner(), keyboard: Result<UinputKeyboard, UinputError>,
                layout: any KeyboardLayout = XKBLayout(), launcher: any ProgramLauncher = ProcessLauncher()) {
        self.commands = commands
        self.keyboard = keyboard
        self.layout = layout
        self.launcher = launcher
    }

    public func perform(_ action: Action) async -> ActionResult {
        switch action {
        case let .run(command):
            return ActionResult(await commands.run(command, timeout: nil), command: command)
        case let .open(target):
            return await open(target)
        case let .keys(combo):
            return await send(combo)
        case let .media(key):
            return await press(modifiers: [], key: EvdevKeys.code(for: key), what: "media '\(key.rawValue)'")
        case .page:
            return .succeeded
        }
    }

    // MARK: - Keys

    enum Resolution: Equatable {
        case send(modifiers: [UInt16], key: UInt16)
        case failed(String)
    }

    /// Modifiers and key as evdev codes, or why the combo cannot be sent on Linux.
    static func resolve(_ combo: KeyCombo, layout: some KeyboardLayout) -> Resolution {
        if combo.modifiers.contains(.fn) {
            return .failed("keys '\(combo.text)': fn has no Linux equivalent")
        }
        let modifiers = EvdevKeys.modifierOrder.filter(combo.modifiers.contains).compactMap(EvdevKeys.code(for:))
        switch combo.key {
        case .named:
            guard let code = EvdevKeys.code(for: combo.key) else {
                return .failed("keys '\(combo.text)': no Linux key for '\(KeyCombo.name(of: combo.key))'")
            }
            return .send(modifiers: modifiers, key: code)
        case let .character(character):
            guard let code = layout.keyCode(typing: character) else {
                return .failed("keys '\(combo.text)': keyboard layout '\(layout.name)' has no key for '\(character)'")
            }
            return .send(modifiers: modifiers, key: code)
        }
    }

    private func send(_ combo: KeyCombo) async -> ActionResult {
        switch Self.resolve(combo, layout: layout) {
        case let .failed(message):
            return .failed(message)
        case let .send(modifiers, key):
            return await press(modifiers: modifiers, key: key, what: "keys '\(combo.text)'")
        }
    }

    private func press(modifiers: [UInt16], key: UInt16, what: String) async -> ActionResult {
        switch keyboard {
        case let .failure(error):
            return .failed(error.description)
        case let .success(keyboard):
            return await keyboard.press(modifiers: modifiers, key: key)
                ? .succeeded : .failed("\(what): could not send to /dev/uinput")
        }
    }

    // MARK: - Open

    enum OpenTarget: Equatable {
        case program(String, [String])
        case failed(String)
    }

    /// What `open: <target>` runs: `steam` for `steam://`, `xdg-open` for other URLs and existing paths.
    static func route(_ target: String, fileExists: (String) -> Bool = FileManager.default.fileExists(atPath:)) -> OpenTarget {
        if let url = URL(string: target), let scheme = url.scheme, !scheme.isEmpty, !target.hasPrefix("/") {
            return scheme.lowercased() == "steam" ? .program("steam", [target]) : .program("xdg-open", [target])
        }
        let path = (target as NSString).expandingTildeInPath
        guard fileExists(path) else { return .failed("cannot open '\(target)': no such file") }
        return .program("xdg-open", [path])
    }

    private func open(_ target: String) async -> ActionResult {
        switch Self.route(target) {
        case let .failed(message):
            return .failed(message)
        case let .program(program, arguments):
            switch await launcher.launch(program, arguments: arguments, patience: Self.openPatience) {
            case .stillRunning, .exited(status: 0, _):
                return .succeeded
            case let .exited(status, stderr):
                let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                    .split(separator: "\n").suffix(2).joined(separator: " / ")
                let reason = status == 127 ? "\(program) is not installed" : "\(program) exited with status \(status)"
                return .failed("cannot open '\(target)': \(reason)\(detail.isEmpty ? "" : ": \(detail)")")
            case let .failedToStart(message):
                return .failed("cannot open '\(target)': \(message)")
            }
        }
    }
}
