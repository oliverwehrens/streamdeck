import CLinux
import Foundation
import Glibc
import Testing

private let uinputWritable = access("/dev/uinput", W_OK) == 0

@Test(.enabled(if: uinputWritable, "needs a writable /dev/uinput"))
func createsAndDestroysUinputDevice() throws {
    let fd = open("/dev/uinput", O_WRONLY | O_NONBLOCK | O_CLOEXEC)
    try #require(fd >= 0)
    defer { close(fd) }
    let keys: [UInt16] = [UInt16(KEY_A), UInt16(KEY_LEFTCTRL)]
    #expect(deck_uinput_create(fd, "streamdeckd test", keys, keys.count) == 0)
    #expect(deck_uinput_emit(fd, UInt16(EV_SYN), UInt16(SYN_REPORT), 0) == 0)
    #expect(deck_uinput_destroy(fd) == 0)
}

@Test func featureIoctlOnNonHidFails() {
    // A pipe is not a hidraw node: the wrapper must return -1, not crash.
    var fds: [Int32] = [0, 0]
    #expect(pipe(&fds) == 0)
    defer { close(fds[0]); close(fds[1]) }
    var buffer = [UInt8](repeating: 0, count: 32)
    buffer[0] = 0x05
    #expect(deck_hid_get_feature(fds[0], &buffer, buffer.count) == -1)
}

/// The hand-written key codes in deck_linux.h must equal the kernel's (checked where kernel headers exist).
@Test(.enabled(if: FileManager.default.fileExists(atPath: "/usr/include/linux/input-event-codes.h")))
func keyCodesMatchKernelHeader() throws {
    let header = try String(contentsOfFile: "/usr/include/linux/input-event-codes.h", encoding: .utf8)
    var kernel: [String: Int] = [:]
    for line in header.split(separator: "\n") {
        let parts = line.split(whereSeparator: \.isWhitespace)
        guard parts.count >= 3, parts[0] == "#define", let value = Int(parts[2]) ?? Int(parts[2].dropFirst(2), radix: 16) else { continue }
        kernel[String(parts[1])] = value
    }
    let ours: [String: Int32] = [
        "EV_SYN": EV_SYN, "EV_KEY": EV_KEY, "SYN_REPORT": SYN_REPORT, "BUS_VIRTUAL": BUS_VIRTUAL,
        "KEY_ESC": KEY_ESC, "KEY_1": KEY_1, "KEY_0": KEY_0, "KEY_MINUS": KEY_MINUS, "KEY_EQUAL": KEY_EQUAL,
        "KEY_BACKSPACE": KEY_BACKSPACE, "KEY_TAB": KEY_TAB, "KEY_Q": KEY_Q, "KEY_Y": KEY_Y, "KEY_P": KEY_P,
        "KEY_LEFTBRACE": KEY_LEFTBRACE, "KEY_RIGHTBRACE": KEY_RIGHTBRACE, "KEY_ENTER": KEY_ENTER,
        "KEY_LEFTCTRL": KEY_LEFTCTRL, "KEY_A": KEY_A, "KEY_L": KEY_L, "KEY_SEMICOLON": KEY_SEMICOLON,
        "KEY_APOSTROPHE": KEY_APOSTROPHE, "KEY_GRAVE": KEY_GRAVE, "KEY_LEFTSHIFT": KEY_LEFTSHIFT,
        "KEY_BACKSLASH": KEY_BACKSLASH, "KEY_Z": KEY_Z, "KEY_M": KEY_M, "KEY_COMMA": KEY_COMMA, "KEY_DOT": KEY_DOT,
        "KEY_SLASH": KEY_SLASH, "KEY_LEFTALT": KEY_LEFTALT, "KEY_SPACE": KEY_SPACE, "KEY_F1": KEY_F1,
        "KEY_F10": KEY_F10, "KEY_102ND": KEY_102ND, "KEY_F11": KEY_F11, "KEY_F12": KEY_F12, "KEY_RO": KEY_RO,
        "KEY_HOME": KEY_HOME, "KEY_UP": KEY_UP, "KEY_PAGEUP": KEY_PAGEUP, "KEY_LEFT": KEY_LEFT, "KEY_RIGHT": KEY_RIGHT,
        "KEY_END": KEY_END, "KEY_DOWN": KEY_DOWN, "KEY_PAGEDOWN": KEY_PAGEDOWN, "KEY_DELETE": KEY_DELETE,
        "KEY_MUTE": KEY_MUTE, "KEY_VOLUMEDOWN": KEY_VOLUMEDOWN, "KEY_VOLUMEUP": KEY_VOLUMEUP, "KEY_YEN": KEY_YEN,
        "KEY_LEFTMETA": KEY_LEFTMETA, "KEY_NEXTSONG": KEY_NEXTSONG, "KEY_PLAYPAUSE": KEY_PLAYPAUSE,
        "KEY_PREVIOUSSONG": KEY_PREVIOUSSONG, "KEY_F13": KEY_F13, "KEY_F20": KEY_F20,
        "KEY_BRIGHTNESSDOWN": KEY_BRIGHTNESSDOWN, "KEY_BRIGHTNESSUP": KEY_BRIGHTNESSUP,
    ]
    for (name, value) in ours where name != "BUS_VIRTUAL" {
        #expect(kernel[name] == Int(value), "\(name)")
    }
    // The XKB evdev table relies on contiguous letter rows; spot-check the ends against the kernel.
    #expect(kernel["KEY_W"] == Int(KEY_W) && kernel["KEY_K"] == Int(KEY_K) && kernel["KEY_N"] == Int(KEY_N))
}
