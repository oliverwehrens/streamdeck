import AppKit
import ApplicationServices
import DeckConfig

/// Performs actions against the real system: shell, NSWorkspace, synthesized key events.
public struct SystemActionPerformer: ActionPerformer {
    let commands: CommandRunner
    let isTrusted: @Sendable () -> Bool
    let layout: any KeyboardLayout

    public init(
        commands: CommandRunner = ShellRunner(),
        isTrusted: @escaping @Sendable () -> Bool = { AXIsProcessTrusted() },
        layout: any KeyboardLayout = SystemKeyboardLayout()
    ) {
        self.commands = commands
        self.isTrusted = isTrusted
        self.layout = layout
    }

    public func perform(_ action: Action) async -> ActionResult {
        switch action {
        case let .run(command):
            return Self.describe(await commands.run(command, timeout: nil), command: command)
        case let .open(target):
            return await open(target)
        case let .keys(combo):
            guard isTrusted() else { return .needsAccessibility }
            return await MainActor.run {
                switch Self.resolve(combo, layout: layout) {
                case let .success(key):
                    Self.post(key)
                    return .succeeded
                case let .failure(.noKey(character, layout)):
                    return .failed("keys '\(combo.text)': keyboard layout '\(layout)' has no key for '\(character)'")
                }
            }
        case let .media(key):
            guard isTrusted() else { return .needsAccessibility }
            await MainActor.run { Self.post(key) }
            return .succeeded
        case .page:
            return .succeeded
        }
    }

    static func describe(_ result: CommandResult, command: String) -> ActionResult {
        guard !result.succeeded else { return .succeeded }
        let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = stderr.isEmpty ? "" : ": \(stderr.split(separator: "\n").suffix(3).joined(separator: " / "))"
        return .failed("'\(command)' exited with status \(result.exitCode)\(detail)")
    }

    // MARK: - Open

    private func open(_ target: String) async -> ActionResult {
        let url: URL
        if let parsed = URL(string: target), let scheme = parsed.scheme, !scheme.isEmpty, !target.hasPrefix("/") {
            url = parsed
        } else {
            let path = (target as NSString).expandingTildeInPath
            guard FileManager.default.fileExists(atPath: path) else { return .failed("cannot open '\(target)': no such file") }
            url = URL(fileURLWithPath: path)
        }
        let configuration = NSWorkspace.OpenConfiguration()
        do {
            if url.pathExtension == "app" {
                try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            } else {
                try await NSWorkspace.shared.open(url, configuration: configuration)
            }
            return .succeeded
        } catch {
            return .failed("cannot open '\(target)': \(error.localizedDescription)")
        }
    }

    // MARK: - Keystrokes

    static func flags(for modifiers: Set<KeyCombo.Modifier>) -> CGEventFlags {
        var flags: CGEventFlags = []
        if modifiers.contains(.cmd) { flags.insert(.maskCommand) }
        if modifiers.contains(.shift) { flags.insert(.maskShift) }
        if modifiers.contains(.alt) { flags.insert(.maskAlternate) }
        if modifiers.contains(.ctrl) { flags.insert(.maskControl) }
        if modifiers.contains(.fn) { flags.insert(.maskSecondaryFn) }
        return flags
    }

    struct ResolvedKey: Equatable {
        var keyCode: UInt16
        var flags: CGEventFlags
    }

    enum ResolutionError: Error, Equatable {
        case noKey(Character, layout: String)
    }

    /// Characters go through the layout; named keys keep their code.
    static func resolve(_ combo: KeyCombo, layout: some KeyboardLayout) -> Result<ResolvedKey, ResolutionError> {
        let code: UInt16
        switch combo.key {
        case let .named(named):
            code = named
        case let .character(character):
            guard let typed = layout.keyCode(typing: character) else { return .failure(.noKey(character, layout: layout.name)) }
            code = typed
        }
        return .success(ResolvedKey(keyCode: code, flags: flags(for: combo.modifiers)))
    }

    static func post(_ key: ResolvedKey) {
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: key.keyCode, keyDown: down) else { continue }
            event.flags = key.flags
            event.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Media keys

    /// NX_KEYTYPE_* values from IOKit/hidsystem/ev_keymap.h.
    static func keyType(for key: MediaKey) -> Int {
        switch key {
        case .volumeup: 0
        case .volumedown: 1
        case .brightnessup: 2
        case .brightnessdown: 3
        case .mute: 7
        case .playpause: 16
        case .next: 17
        case .previous: 18
        }
    }

    @MainActor
    static func post(_ key: MediaKey) {
        let type = keyType(for: key)
        for down in [true, false] {
            let state = down ? 0xA : 0xB
            let event = NSEvent.otherEvent(
                with: .systemDefined, location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8)),
                timestamp: 0, windowNumber: 0, context: nil,
                subtype: 8, data1: (type << 16) | (state << 8), data2: -1
            )
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
    }
}
