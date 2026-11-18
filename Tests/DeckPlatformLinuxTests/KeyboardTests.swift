import CLinux
import DeckConfig
import DeckSupport
import Foundation
import Testing
@testable import DeckPlatformLinux

private let fixtures = Bundle.module.resourceURL!.appendingPathComponent("Fixtures")
private let symbolsDirectory = fixtures.appendingPathComponent("xkb/symbols").path
private let parser = XKBSymbolsParser(symbolsDirectory: symbolsDirectory)

private func layout(_ name: String, _ variant: String? = nil, parser: XKBSymbolsParser = parser) -> XKBLayout {
    XKBLayout(parser: parser) { XKBLayout.Selection(layout: name, variant: variant) }
}

// MARK: - Evdev tables

@Test func everyNamedKeyHasAnEvdevCode() {
    var named = 0
    for code in UInt16(0) ..< 256 {
        guard let key = KeyCombo.namedKey(forKeyCode: code) else { continue }
        named += 1
        #expect(EvdevKeys.code(for: key) != nil, "\(KeyCombo.name(of: key))")
    }
    #expect(named >= 34)
}

@Test func namedKeyExamples() throws {
    #expect(EvdevKeys.code(for: try KeyCombo.parse("f20").get().key) == UInt16(KEY_F20))
    #expect(EvdevKeys.code(for: try KeyCombo.parse("return").get().key) == UInt16(KEY_ENTER))
    #expect(EvdevKeys.code(for: try KeyCombo.parse("backspace").get().key) == UInt16(KEY_BACKSPACE))
    #expect(EvdevKeys.code(for: .character("a")) == nil)
}

@Test func everyMediaKeyMaps() {
    let codes = MediaKey.allCases.map(EvdevKeys.code(for:))
    #expect(Set(codes).count == MediaKey.allCases.count)
    #expect(EvdevKeys.code(for: .playpause) == UInt16(KEY_PLAYPAUSE))
}

@Test func modifiers() {
    #expect(EvdevKeys.code(for: .cmd) == UInt16(KEY_LEFTMETA))
    #expect(EvdevKeys.code(for: .fn) == nil)
    #expect(EvdevKeys.all.contains(UInt16(KEY_LEFTMETA)))
    #expect(EvdevKeys.all.contains(UInt16(KEY_Z)))
}

// MARK: - XKB parsing

@Test func builtInUSMatchesTheFixture() throws {
    let parsed = try #require(parser.symbols(layout: "us", variant: nil))
    #expect(parsed.evdevCodes == XKBSymbols.us.evdevCodes)
    #expect(XKBLayout.us.keyCode(typing: "a") == UInt16(KEY_A))
    #expect(XKBLayout.us.keyCode(typing: "[") == UInt16(KEY_LEFTBRACE))
    #expect(XKBLayout.us.codes.count == 47)
}

@Test func germanSwapsYAndZ() {
    let german = layout("de")
    #expect(german.keyCode(typing: "z") == UInt16(KEY_Y))
    #expect(german.keyCode(typing: "y") == UInt16(KEY_Z))
    #expect(german.keyCode(typing: "-") == UInt16(KEY_SLASH))
    #expect(german.keyCode(typing: "[") == nil)
    #expect(german.name == "de")
}

@Test func frenchIsAzerty() {
    let french = layout("fr")
    #expect(french.keyCode(typing: "a") == UInt16(KEY_Q))
    #expect(french.keyCode(typing: "q") == UInt16(KEY_A))
    #expect(french.keyCode(typing: "m") == UInt16(KEY_SEMICOLON))
}

@Test func variantResolvesIncludes() {
    let nodeadkeys = layout("de", "nodeadkeys")
    #expect(nodeadkeys.keyCode(typing: "z") == UInt16(KEY_Y))
    #expect(nodeadkeys.name == "de(nodeadkeys)")
}

@Test func russianFallsBackToUS() {
    let russian = layout("ru")
    #expect(russian.keyCode(typing: "c") == UInt16(KEY_C))
    #expect(russian.name == "us")
}

@Test func missingFilesFallBackToUS() {
    let none = XKBSymbolsParser(symbolsDirectory: "/nonexistent")
    #expect(layout("de", parser: none).keyCode(typing: "z") == UInt16(KEY_Z))
    #expect(layout("de", "nosuchvariant").name == "us")
    #expect(layout("../etc/passwd").name == "us")
}

@Test func parsesKeyBodyForms() {
    #expect(XKBSymbolsParser.levelOne(" [ q, Q ] ") == "q")
    #expect(XKBSymbolsParser.levelOne(#"type[Group1]="FOUR_LEVEL", [ ssharp, question ]"#) == "ssharp")
    #expect(XKBSymbolsParser.levelOne(#"[ ssharp, question ], type[group1]="FOUR_LEVEL_PLUS_LOCK" "#) == "ssharp")
    #expect(XKBSymbolsParser.levelOne(" symbols[Group1]= [ 1, exclam ] ") == "1")
    #expect(XKBSymbolsParser.levelOne(" actions[Group1]= [ SetMods(modifiers=Shift) ], symbols[Group1]= [ a ] ") == "a")
    #expect(XKBSymbolsParser.levelOne(" [] ") == nil)
}

@Test func parsesIncludeSpecs() {
    let parsed = XKBSymbolsParser.parseInclude("pc+us(basic)|inet(evdev)+group(alt_shift_toggle):2")
    #expect(parsed.map(\.0) == ["pc", "us", "inet"])
    #expect(parsed.map(\.1) == [nil, "basic", "evdev"])
}

@Test func unicodeKeysyms() {
    #expect(XKBSymbols.character(forKeysym: "U0061") == "a")
    #expect(XKBSymbols.character(forKeysym: "U00E4") == nil)
    #expect(XKBSymbols.character(forKeysym: "Q") == nil)
}

// MARK: - Layout detection

private func tree(_ files: [String: Data]) throws -> String {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("layout-\(UUID().uuidString)").path
    try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
    for (path, data) in files {
        let url = URL(fileURLWithPath: root + "/" + path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }
    return root
}

private func gamescope(pid: Int, uid: Int, layout: String, comm: String = "gamescope-wl") -> [String: Data] {
    [
        "proc/\(pid)/comm": Data("\(comm)\n".utf8),
        "proc/\(pid)/status": Data("Name:\t\(comm)\nUid:\t\(uid)\t\(uid)\t\(uid)\t\(uid)\n".utf8),
        "proc/\(pid)/environ": Data("HOME=/home/deck\0XKB_DEFAULT_LAYOUT=\(layout)\0XKB_DEFAULT_VARIANT=\0".utf8),
    ]
}

private let xorgConf = Data("""
Section "InputClass"
        Identifier "system-keyboard"
        MatchIsKeyboard "on"
        Option "XkbLayout" "fr,us"
        Option "XkbVariant" "azerty,"
EndSection
""".utf8)

private let vconsole = Data("KEYMAP=de\nXKBLAYOUT=\"ch\"\nXKBVARIANT=fr\n".utf8)

@Test func gamescopeEnvironmentWins() throws {
    let root = try tree(gamescope(pid: 812, uid: 1000, layout: "de,us")
        .merging(["etc/X11/xorg.conf.d/00-keyboard.conf": xorgConf, "proc/1/comm": Data("systemd\n".utf8)]) { $1 })
    let detection = LayoutDetection(procRoot: root + "/proc", etcRoot: root + "/etc", environment: ["XKB_DEFAULT_LAYOUT": "it"], uid: 1000)
    #expect(detection.current() == XKBLayout.Selection(layout: "de"))
    #expect(detection.detect()?.source == "gamescope environment")
}

@Test func otherUsersGamescopeIsIgnored() throws {
    let root = try tree(gamescope(pid: 812, uid: 0, layout: "de"))
    let detection = LayoutDetection(procRoot: root + "/proc", etcRoot: root + "/etc", environment: ["XKB_DEFAULT_LAYOUT": "it"], uid: 1000)
    #expect(detection.current() == XKBLayout.Selection(layout: "it"))
}

@Test func xorgConfWinsOverVconsole() throws {
    let root = try tree(["etc/X11/xorg.conf.d/00-keyboard.conf": xorgConf, "etc/vconsole.conf": vconsole])
    let detection = LayoutDetection(procRoot: root + "/proc", etcRoot: root + "/etc", environment: [:], uid: 1000)
    #expect(detection.current() == XKBLayout.Selection(layout: "fr", variant: "azerty"))
}

@Test func vconsoleIsUsedLast() throws {
    let root = try tree(["etc/vconsole.conf": vconsole])
    let detection = LayoutDetection(procRoot: root + "/proc", etcRoot: root + "/etc", environment: [:], uid: 1000)
    #expect(detection.current() == XKBLayout.Selection(layout: "ch", variant: "fr"))
}

@Test func nothingFoundMeansUS() throws {
    let root = try tree([:])
    let detection = LayoutDetection(procRoot: root + "/proc", etcRoot: root + "/etc", environment: [:], uid: 1000)
    #expect(detection.detect() == nil)
    #expect(detection.current() == XKBLayout.Selection(layout: "us"))
}

// MARK: - Virtual keyboard

final class RecordingSink: InputEventSink, @unchecked Sendable {
    let events = Locked<[InputEvent]>(initialState: [])
    func emit(type: UInt16, code: UInt16, value: Int32) -> Bool {
        events.withLock { $0.append(InputEvent(type: type, code: code, value: value)) }
        return true
    }
    var all: [InputEvent] { events.withLock { $0 } }
}

@Test func pressSendsModifiersKeyAndSyncInOrder() async {
    let sink = RecordingSink()
    let keyboard = UinputKeyboard(sink: sink)
    let ok = await keyboard.press(modifiers: [UInt16(KEY_LEFTSHIFT), UInt16(KEY_LEFTMETA)], key: UInt16(KEY_Y))
    #expect(ok)
    func key(_ code: Int32, _ value: Int32) -> InputEvent { InputEvent(type: UInt16(EV_KEY), code: UInt16(code), value: value) }
    #expect(sink.all == [
        key(KEY_LEFTSHIFT, 1), key(KEY_LEFTMETA, 1), key(KEY_Y, 1), UinputKeyboard.syn,
        key(KEY_Y, 0), key(KEY_LEFTMETA, 0), key(KEY_LEFTSHIFT, 0), UinputKeyboard.syn,
    ])
}

@Test func uinputErrorsExplainTheFix() {
    #expect(UinputError(path: "/dev/uinput", errno: EACCES).description.contains("udev rules"))
    #expect(UinputError(path: "/dev/uinput", errno: ENOENT).description.contains("uinput kernel module"))
    if case let .failure(error) = UinputKeyboard.create(path: "/nonexistent/uinput") {
        #expect(error.errno == ENOENT)
    } else {
        Issue.record("expected a failure")
    }
}
