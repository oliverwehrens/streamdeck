import DeckHID
import DeckSupport
import Foundation
import Testing
@testable import DeckPlatformLinux

// MARK: - Discovery

private func makeSysfs(_ devices: [String: String]) throws -> String {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("sysfs-\(UUID().uuidString)").path
    for (name, uevent) in devices {
        let directory = "\(root)/class/hidraw/\(name)/device"
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try uevent.write(toFile: directory + "/uevent", atomically: true, encoding: .utf8)
    }
    try FileManager.default.createDirectory(atPath: "\(root)/class/hidraw", withIntermediateDirectories: true)
    return root
}

private let deckUevent = """
DRIVER=hid-generic
HID_ID=0003:00000FD9:0000006D
HID_NAME=Elgato Systems Stream Deck
HID_PHYS=usb-0000:00:14.0-2/input0
HID_UNIQ=AL22K2C76666
MODALIAS=hid:b0003g0001v00000FD9p0000006D

"""

private let keyboardUevent = """
DRIVER=hid-generic
HID_ID=0003:0000046D:0000C31C
HID_NAME=Logitech USB Keyboard
HID_UNIQ=

"""

@Test func parsesUevent() {
    let event = HidrawDevices.parseUevent(deckUevent)
    #expect(event == HidrawDevices.Uevent(bus: 3, vendor: 0x0fd9, product: 0x006d, uniq: "AL22K2C76666"))
    #expect(HidrawDevices.parseUevent(keyboardUevent)?.uniq == nil)
    #expect(HidrawDevices.parseUevent("DRIVER=x") == nil)
}

@Test func findsOnlyTheDeck() throws {
    let root = try makeSysfs(["hidraw0": keyboardUevent, "hidraw10": deckUevent, "hidraw2": keyboardUevent])
    #expect(HidrawDevices.find(sysfsRoot: root) == [.init(node: "/dev/hidraw10", serial: "AL22K2C76666")])
}

@Test func findsNothingInEmptyTree() throws {
    #expect(HidrawDevices.find(sysfsRoot: try makeSysfs([:])).isEmpty)
    #expect(HidrawDevices.find(sysfsRoot: "/nonexistent").isEmpty)
}

@Test func permissionMessageNamesNodeAndRules() {
    let message = HidrawDevices.openFailureMessage(node: "/dev/hidraw3", errno: EACCES)
    #expect(message.contains("/dev/hidraw3"))
    #expect(message.contains("permission denied"))
    #expect(message.contains("udev rules"))
}

// MARK: - Transport over a socket pair

private final class Collector: @unchecked Sendable {
    let events = Locked<[DeviceEvent]>(initialState: [])
    init(_ transport: HidrawTransport) {
        Task { [events] in
            for await event in transport.events { events.withLock { $0.append(event) } }
        }
    }
    var all: [DeviceEvent] { events.withLock { $0 } }
    func waitFor(_ condition: ([DeviceEvent]) -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(3)
        while !condition(all), ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(10)) }
    }
}

/// A transport attached to one end of a SOCK_SEQPACKET pair, which keeps report boundaries like hidraw.
private func attachedTransport() throws -> (HidrawTransport, Collector, Int32) {
    var pair: [Int32] = [-1, -1]
    try #require(socketpair(AF_UNIX, Int32(SOCK_SEQPACKET.rawValue), 0, &pair) == 0)
    let transport = HidrawTransport(sysfsRoot: "/nonexistent", devRoot: "/nonexistent")
    let collector = Collector(transport)
    transport.attachOnQueue(fd: pair[0], node: "/dev/hidraw-test", serial: "SERIAL")
    return (transport, collector, pair[1])
}

private func readPacket(_ fd: Int32) -> [UInt8] {
    var buffer = [UInt8](repeating: 0, count: 2048)
    var pollFD = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
    guard poll(&pollFD, 1, 2000) > 0 else { return [] }
    let count = read(fd, &buffer, buffer.count)
    return count > 0 ? Array(buffer.prefix(count)) : []
}

@Test func connectsAndWritesImageReports() async throws {
    let (transport, collector, other) = try attachedTransport()
    defer { close(other) }
    await collector.waitFor { !$0.isEmpty }
    #expect(collector.all.first == .connected(DeviceInfo(serial: "SERIAL", firmware: "")))

    let jpeg = Data((0 ..< 2500).map { UInt8($0 % 251) })
    transport.setImage(key: 7, jpeg: jpeg)
    let expected = ReportCodec.imageReports(key: 7, jpeg: jpeg)
    for report in expected {
        #expect(readPacket(other) == report)
    }
    transport.stop()
}

@Test func inputReportsBecomeKeyEvents() async throws {
    let (transport, collector, other) = try attachedTransport()
    defer { close(other) }
    var report = [UInt8](repeating: 0, count: 512)
    report[0] = 0x01; report[2] = 0x0f
    report[4 + 3] = 1
    #expect(writeAll(other, report))
    report[4 + 3] = 0
    #expect(writeAll(other, report))
    await collector.waitFor { $0.count >= 3 }
    #expect(Array(collector.all.dropFirst()) == [.key(KeyEvent(key: 3, edge: .down)), .key(KeyEvent(key: 3, edge: .up))])
    transport.stop()
}

@Test func closedPeerMeansDisconnected() async throws {
    let (transport, collector, other) = try attachedTransport()
    close(other)
    await collector.waitFor { $0.contains(.disconnected) }
    #expect(collector.all.last == .disconnected)
    transport.stop()
}

@Test func stopFlushesQueuedWrites() async throws {
    let (transport, _, other) = try attachedTransport()
    defer { close(other) }
    let jpeg = Data(repeating: 0xAB, count: 100)
    transport.setImage(key: 0, jpeg: jpeg)
    transport.stop()
    #expect(readPacket(other) == ReportCodec.imageReports(key: 0, jpeg: jpeg)[0])
}

@Test func recognizesHidrawInotifyNames() {
    func event(_ name: String) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 16)
        let padded = Array(name.utf8) + [UInt8](repeating: 0, count: 16 - name.utf8.count % 16)
        withUnsafeBytes(of: UInt32(padded.count).littleEndian) { bytes.replaceSubrange(12 ..< 16, with: $0) }
        return bytes + padded
    }
    let buffer = event("ttyS0") + event("hidraw4")
    #expect(HidrawTransport.namesHidraw(buffer, count: buffer.count))
    let other = event("ttyS0")
    #expect(!HidrawTransport.namesHidraw(other, count: other.count))
}

// MARK: - Resume

@Test func resumeFiresOncePerSuspend() {
    let clocks = Locked(initialState: (boottime: 100.0, monotonic: 50.0))
    let detector = ResumeDetector { clocks.withLock { $0 } }
    #expect(!detector.check())
    clocks.withLock { $0 = (boottime: 102 + 30, monotonic: 52) }
    #expect(detector.check())
    clocks.withLock { $0 = (boottime: 134, monotonic: 54) }
    #expect(!detector.check())
    clocks.withLock { $0 = (boottime: 136.5, monotonic: 56) }
    #expect(!detector.check())
}
