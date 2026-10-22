import AppKit
import SwiftUI
import DeckConfig
import DeckEngine

/// Turns a pressed key into a combo for the Keystroke action.
enum KeyRecorder {
    enum Recording: Equatable {
        case combo(KeyCombo)
        case unsupported(keyCode: UInt16)
    }

    /// macOS sets `.function` on these keys whether or not fn is held.
    static let implicitFunctionKeyCodes: Set<UInt16> = {
        let names = ["left", "right", "up", "down", "home", "end", "pageup", "pagedown", "forwarddelete"] + (1...20).map { "f\($0)" }
        return Set(names.compactMap { name in
            if case let .success(combo) = KeyCombo.parse(name), case let .named(code) = combo.key { code } else { nil }
        })
    }()

    /// Named keys first, then the character the layout types without modifiers.
    static func recording(keyCode: UInt16, flags: NSEvent.ModifierFlags, layout: some KeyboardLayout) -> Recording {
        let key: KeyCombo.Key
        if let named = KeyCombo.namedKey(forKeyCode: keyCode) {
            key = named
        } else if let character = layout.character(forKeyCode: keyCode), KeyCombo.isCharacterName(character) {
            key = .character(character)
        } else {
            return .unsupported(keyCode: keyCode)
        }
        var modifiers = modifiers(flags)
        if implicitFunctionKeyCodes.contains(keyCode) { modifiers.remove(.fn) }
        return .combo(KeyCombo(modifiers: modifiers, key: key))
    }

    static func modifiers(_ flags: NSEvent.ModifierFlags) -> Set<KeyCombo.Modifier> {
        let mapping: [(NSEvent.ModifierFlags, KeyCombo.Modifier)] = [
            (.command, .cmd), (.control, .ctrl), (.option, .alt), (.shift, .shift), (.function, .fn),
        ]
        return Set(mapping.filter { flags.contains($0.0) }.map(\.1))
    }
}

// MARK: - Recording session

/// Captures key presses for the app while recording. A local monitor sees only this app's events and needs no permission.
@MainActor @Observable
final class KeyRecorderSession {
    private(set) var isRecording = false
    private(set) var held: Set<KeyCombo.Modifier> = []
    private(set) var message: String?
    private var monitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var onRecord: ((KeyCombo) -> Void)?

    func start(onRecord: @escaping (KeyCombo) -> Void) {
        stop()
        isRecording = true
        self.onRecord = onRecord
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            let consumed = MainActor.assumeIsolated { self?.consumes(event) ?? false }
            return consumed ? nil : event
        }
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
    }

    /// Ends recording without changing the value. Safe to call when not recording.
    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        monitor = nil
        resignObserver = nil
        onRecord = nil
        isRecording = false
        held = []
        message = nil
    }

    /// Consumed events never reach menus or shortcuts.
    private func consumes(_ event: NSEvent) -> Bool {
        switch event.type {
        case .keyDown:
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if event.keyCode == 0x35, KeyRecorder.modifiers(flags).subtracting([.fn]).isEmpty {
                stop()
                return true
            }
            switch KeyRecorder.recording(keyCode: event.keyCode, flags: flags, layout: SystemKeyboardLayout()) {
            case let .combo(combo):
                let onRecord = onRecord
                stop()
                onRecord?(combo)
            case let .unsupported(keyCode):
                message = String(format: "This key (code 0x%02X) has no name in the config. Use a letter, digit, punctuation, F-key or named key.", keyCode)
            }
            return true
        case .flagsChanged:
            held = KeyRecorder.modifiers(event.modifierFlags.intersection(.deviceIndependentFlagsMask))
            return true
        default:
            stop()
            return false
        }
    }
}

// MARK: - Keystroke field

/// The Keystroke action's value: click to record, clear, or edit as text.
struct KeystrokeField: View {
    @Binding var value: String
    /// Recording stops when the inspected key changes.
    let keyIndex: Int
    @State private var session = KeyRecorderSession()
    @State private var editingText = false

    var body: some View {
        Group { field }
            .onChange(of: keyIndex) { session.stop() }
            .onDisappear { session.stop() }
    }

    @ViewBuilder private var field: some View {
        LabeledContent("Keys") {
            if editingText {
                HStack {
                    TextField("Keys", text: $value, prompt: Text("cmd+shift+m"))
                        .labelsHidden()
                        .font(.body.monospaced())
                    Button("Done") { editingText = false }
                }
            } else {
                HStack {
                    recorder
                    if !value.isEmpty, !session.isRecording {
                        Button { value = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                            .help("Clear the keystroke")
                    }
                    Button("Edit as Text") {
                        session.stop()
                        editingText = true
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        if let message = session.message {
            Text(message).font(.caption).foregroundStyle(.red)
        }
    }

    private var recorder: some View {
        Button {
            if !session.isRecording { session.start { value = $0.text } }
        } label: {
            Text(recorderText)
                .font(value.isEmpty || session.isRecording ? .body : .body.monospaced())
                .foregroundStyle(value.isEmpty && !session.isRecording ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(session.isRecording ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: session.isRecording ? 2 : 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(session.isRecording ? "Press a key combination. Esc cancels." : "Click and press a key combination")
    }

    private var recorderText: String {
        guard session.isRecording else { return value.isEmpty ? "Click to record" : value }
        let order: [KeyCombo.Modifier] = [.cmd, .ctrl, .alt, .shift, .fn]
        let held = order.filter(session.held.contains).map(\.rawValue)
        return held.isEmpty ? "Type shortcut…" : held.joined(separator: "+") + "+…"
    }
}
