import CLinux
import DeckHID
import Foundation

/// `DeckTransport` over Linux hidraw. Device state lives on one serial queue; a dedicated thread
/// blocks in `poll`/`read` for input reports (blocking the global pool would stall Swift tasks on Linux).
public final class HidrawTransport: DeckTransport, @unchecked Sendable {
    static let inputReportSize = 512
    /// How long an `EACCES` node is retried before it is reported; udev sets permissions just after creating it.
    static let permissionRetries = 8
    static let permissionRetryInterval: TimeInterval = 0.25

    public let events: AsyncStream<DeviceEvent>
    private let continuation: AsyncStream<DeviceEvent>.Continuation
    private let queue = DispatchQueue(label: "de.wehrens.streamdeck.hidraw")
    private let sysfsRoot: String
    private let devRoot: String

    // Accessed only on `queue`.
    private var device: OpenDevice?
    private var keyStates = [Bool](repeating: false, count: ReportCodec.keyCount)
    private var hotplug: DispatchSourceRead?
    private var retryScheduled = false
    private var lastFailure: String?
    private var stopped = false

    /// One open node and its reader thread.
    final class OpenDevice: @unchecked Sendable {
        let fd: Int32
        let node: String
        /// Written to wake the reader thread so it exits.
        let wake: (read: Int32, write: Int32)
        let readerExited = DispatchSemaphore(value: 0)

        init(fd: Int32, node: String) {
            self.fd = fd
            self.node = node
            var pipeFDs: [Int32] = [-1, -1]
            if pipe(&pipeFDs) == 0 {
                for descriptor in pipeFDs { _ = fcntl(descriptor, F_SETFD, FD_CLOEXEC) }
            }
            wake = (pipeFDs[0], pipeFDs[1])
        }
    }

    public init(sysfsRoot: String = "/sys", devRoot: String = "/dev") {
        self.sysfsRoot = sysfsRoot
        self.devRoot = devRoot
        (events, continuation) = AsyncStream.makeStream(of: DeviceEvent.self)
    }

    public func start() {
        queue.async { [self] in
            watchDevDirectory()
            scan(retriesLeft: Self.permissionRetries)
        }
    }

    /// Closes the device after every queued write has gone out.
    public func stop() {
        queue.sync {
            stopped = true
            hotplug?.cancel()
            hotplug = nil
            closeDevice()
        }
        continuation.finish()
    }

    public func setImage(key: Int, jpeg: Data) {
        queue.async { [self] in
            guard let device else { return }
            for report in ReportCodec.imageReports(key: key, jpeg: jpeg) {
                guard writeAll(device.fd, report) else { return }
            }
        }
    }

    public func setBrightness(_ percent: Int) {
        queue.async { [self] in
            guard let device else { return }
            setFeature(ReportCodec.brightnessReport(percent: percent), on: device.fd)
        }
    }

    public func reset() {
        queue.async { [self] in
            guard let device else { return }
            setFeature(ReportCodec.resetReport(), on: device.fd)
        }
    }

    // MARK: - Discovery (queue-confined)

    private func scan(retriesLeft: Int) {
        guard device == nil, !stopped else { return }
        guard let found = HidrawDevices.find(sysfsRoot: sysfsRoot, devRoot: devRoot).first else {
            lastFailure = nil
            return
        }
        let fd = open(found.node, O_RDWR | O_CLOEXEC)
        guard fd >= 0 else {
            let code = errno
            if (code == EACCES || code == EPERM), retriesLeft > 0 {
                scheduleRescan(retriesLeft: retriesLeft - 1)
                return
            }
            let message = HidrawDevices.openFailureMessage(node: found.node, errno: code)
            if message != lastFailure {
                lastFailure = message
                continuation.yield(.openFailed(message))
            }
            return
        }
        attach(fd: fd, node: found.node, serial: found.serial)
    }

    private func scheduleRescan(retriesLeft: Int) {
        guard !retryScheduled else { return }
        retryScheduled = true
        queue.asyncAfter(deadline: .now() + Self.permissionRetryInterval) { [self] in
            retryScheduled = false
            scan(retriesLeft: retriesLeft)
        }
    }

    /// inotify on the device directory: new, changed (permissions) and removed `hidraw*` nodes.
    private func watchDevDirectory() {
        let fd = inotify_init1(Int32(IN_NONBLOCK | IN_CLOEXEC))
        guard fd >= 0 else { return }
        guard inotify_add_watch(fd, devRoot, UInt32(IN_CREATE | IN_ATTRIB | IN_DELETE)) >= 0 else {
            close(fd)
            return
        }
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            var buffer = [UInt8](repeating: 0, count: 4096)
            var relevant = false
            while true {
                let count = read(fd, &buffer, buffer.count)
                guard count > 0 else { break }
                relevant = relevant || Self.namesHidraw(buffer, count: count)
            }
            if relevant { scan(retriesLeft: Self.permissionRetries) }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        hotplug = source
    }

    /// Whether any inotify event in the buffer names a `hidraw*` entry.
    static func namesHidraw(_ buffer: [UInt8], count: Int) -> Bool {
        let headerSize = MemoryLayout<inotify_event>.size
        var offset = 0
        var found = false
        buffer.withUnsafeBytes { raw in
            while offset + headerSize <= count {
                let length = Int(raw.load(fromByteOffset: offset + headerSize - 4, as: UInt32.self))
                let nameStart = offset + headerSize
                let nameBytes = raw[nameStart ..< min(nameStart + length, count)].prefix { $0 != 0 }
                if String(decoding: nameBytes, as: UTF8.self).hasPrefix("hidraw") { found = true }
                offset = nameStart + length
            }
        }
        return found
    }

    // MARK: - Open device (queue-confined)

    /// Takes over an open node. Internal so tests can pass one end of a socket pair.
    func attach(fd: Int32, node: String, serial: String?) {
        let opened = OpenDevice(fd: fd, node: node)
        device = opened
        lastFailure = nil
        keyStates = [Bool](repeating: false, count: ReportCodec.keyCount)
        startReader(opened)
        let info = DeviceInfo(
            serial: serial ?? featureString(ReportCodec.serialReportID, offset: ReportCodec.serialOffset, from: fd),
            firmware: featureString(ReportCodec.firmwareReportID, offset: ReportCodec.firmwareOffset, from: fd)
        )
        continuation.yield(.connected(info))
    }

    /// Internal for tests, which call it through the queue.
    func attachOnQueue(fd: Int32, node: String, serial: String?) {
        queue.sync { attach(fd: fd, node: node, serial: serial) }
    }

    private func closeDevice() {
        guard let device else { return }
        var byte: UInt8 = 1
        _ = write(device.wake.write, &byte, 1)
        device.readerExited.wait()
        close(device.fd)
        close(device.wake.read)
        close(device.wake.write)
        self.device = nil
    }

    private func readerEnded(_ ended: OpenDevice) {
        guard let device, device === ended else { return }
        closeDevice()
        continuation.yield(.disconnected)
        scan(retriesLeft: Self.permissionRetries)
    }

    private func startReader(_ device: OpenDevice) {
        // The thread holds the transport until the device closes; that ends the loop.
        Thread.detachNewThread { [self] in
            Self.readLoop(device) { bytes in
                queue.async { self.handleInput(bytes, from: device) }
            }
            device.readerExited.signal()
            // Woken on purpose, the device is already gone; otherwise this tells the queue the device went away.
            queue.async { self.readerEnded(device) }
        }
    }

    /// Reads input reports until the device goes away or the wake pipe is written.
    private static func readLoop(_ device: OpenDevice, deliver: ([UInt8]) -> Void) {
        var buffer = [UInt8](repeating: 0, count: inputReportSize)
        var fds = [
            pollfd(fd: device.fd, events: Int16(POLLIN), revents: 0),
            pollfd(fd: device.wake.read, events: Int16(POLLIN), revents: 0),
        ]
        while true {
            fds[0].revents = 0
            fds[1].revents = 0
            let ready = poll(&fds, 2, -1)
            if ready < 0 {
                if errno == EINTR { continue }
                return
            }
            if fds[1].revents != 0 { return }
            let revents = Int32(fds[0].revents)
            if revents & Int32(POLLIN) != 0 {
                let count = read(device.fd, &buffer, buffer.count)
                if count < 0, errno == EINTR || errno == EAGAIN { continue }
                guard count > 0 else { return }
                deliver(Array(buffer.prefix(count)))
            } else if revents & Int32(POLLHUP | POLLERR | POLLNVAL) != 0 {
                return
            }
        }
    }

    private func handleInput(_ bytes: [UInt8], from source: OpenDevice) {
        guard device === source, let states = ReportCodec.keyStates(fromInputReport: bytes) else { return }
        for event in ReportCodec.events(from: keyStates, to: states) {
            continuation.yield(.key(event))
        }
        keyStates = states
    }

    private func setFeature(_ report: [UInt8], on fd: Int32) {
        _ = report.withUnsafeBufferPointer { deck_hid_set_feature(fd, $0.baseAddress, $0.count) }
    }

    private func featureString(_ id: UInt8, offset: Int, from fd: Int32) -> String {
        var buffer = [UInt8](repeating: 0, count: ReportCodec.featureReportSize)
        buffer[0] = id
        let length = buffer.withUnsafeMutableBufferPointer { deck_hid_get_feature(fd, $0.baseAddress, $0.count) }
        guard length > 0 else { return "" }
        return ReportCodec.string(fromFeatureReport: Array(buffer.prefix(Int(length))), offset: offset)
    }
}
