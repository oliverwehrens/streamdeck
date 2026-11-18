import CLinux
import Foundation

/// Where input events go: the uinput device, or a recorder in tests.
public protocol InputEventSink: Sendable {
    func emit(type: UInt16, code: UInt16, value: Int32) -> Bool
}

public struct InputEvent: Equatable, Sendable, CustomStringConvertible {
    public var type: UInt16
    public var code: UInt16
    public var value: Int32

    public init(type: UInt16, code: UInt16, value: Int32) {
        self.type = type
        self.code = code
        self.value = value
    }

    public var description: String { "\(type):\(code)=\(value)" }
}

/// One virtual keyboard for the life of the process. Presses are serialized.
public actor UinputKeyboard {
    /// Time between key down and key up, so games that poll see the press.
    static let holdTime: Duration = .milliseconds(20)

    private let sink: any InputEventSink

    public init(sink: any InputEventSink) {
        self.sink = sink
    }

    /// Opens `/dev/uinput` and creates the device, or returns the message for the user.
    public static func create(path: String = "/dev/uinput") -> Result<UinputKeyboard, UinputError> {
        let fd = open(path, O_WRONLY | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { return .failure(UinputError(path: path, errno: errno)) }
        let keys = EvdevKeys.all
        guard deck_uinput_create(fd, "streamdeckd keyboard", keys, keys.count) == 0 else {
            let code = errno
            close(fd)
            return .failure(UinputError(path: path, errno: code))
        }
        return .success(UinputKeyboard(sink: DeviceSink(fd: fd)))
    }

    /// Presses `modifiers` (in order), taps `key`, releases the modifiers in reverse order.
    public func press(modifiers: [UInt16], key: UInt16) async -> Bool {
        let down = modifiers.map { InputEvent(type: UInt16(EV_KEY), code: $0, value: 1) }
            + [InputEvent(type: UInt16(EV_KEY), code: key, value: 1), Self.syn]
        let up = [InputEvent(type: UInt16(EV_KEY), code: key, value: 0)]
            + modifiers.reversed().map { InputEvent(type: UInt16(EV_KEY), code: $0, value: 0) } + [Self.syn]
        guard emit(down) else { return false }
        try? await Task.sleep(for: Self.holdTime)
        return emit(up)
    }

    static let syn = InputEvent(type: UInt16(EV_SYN), code: UInt16(SYN_REPORT), value: 0)

    private func emit(_ events: [InputEvent]) -> Bool {
        events.allSatisfy { sink.emit(type: $0.type, code: $0.code, value: $0.value) }
    }

    struct DeviceSink: InputEventSink {
        let fd: Int32
        func emit(type: UInt16, code: UInt16, value: Int32) -> Bool {
            deck_uinput_emit(fd, type, code, value) == 0
        }
    }
}

public struct UinputError: Error, Equatable, Sendable, CustomStringConvertible {
    public var path: String
    public var errno: Int32

    public var description: String {
        let reason = switch errno {
        case EACCES, EPERM: "permission denied. Install the udev rules with scripts/install-linux.sh."
        case ENOENT, ENODEV: "it does not exist. Load the uinput kernel module (scripts/install-linux.sh sets that up)."
        default: errorText(errno) + "."
        }
        return "Keystroke and media keys are unavailable: cannot use \(path): \(reason)"
    }
}
