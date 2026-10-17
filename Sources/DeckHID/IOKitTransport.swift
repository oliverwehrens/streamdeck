import Foundation
import IOKit.hid

/// `DeckTransport` backed by IOKit HID. All IOKit callbacks and writes run on one serial queue.
public final class IOKitTransport: DeckTransport, @unchecked Sendable {
    public static let vendorID = 0x0fd9
    public static let productID = 0x006d
    static let inputBufferSize = 512

    public let events: AsyncStream<DeviceEvent>
    private let continuation: AsyncStream<DeviceEvent>.Continuation
    private let queue = DispatchQueue(label: "de.wehrens.streamdeck.hid")
    private let manager: IOHIDManager

    // Accessed only on `queue`.
    private var device: IOHIDDevice?
    /// The manager's object for the same device; removal callbacks identify devices by it.
    private var matchedDevice: IOHIDDevice?
    private var keyStates = [Bool](repeating: false, count: ReportCodec.keyCount)

    public init() {
        (events, continuation) = AsyncStream.makeStream(of: DeviceEvent.self)
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDVendorIDKey: Self.vendorID,
            kIOHIDProductIDKey: Self.productID,
        ] as CFDictionary)
    }

    public func start() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            Unmanaged<IOKitTransport>.fromOpaque(context!).takeUnretainedValue().attach(device)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            Unmanaged<IOKitTransport>.fromOpaque(context!).takeUnretainedValue().detach(device)
        }, context)
        IOHIDManagerSetDispatchQueue(manager, queue)
        // Activation delivers matches for already-attached devices on the calling thread.
        queue.sync { IOHIDManagerActivate(manager) }
    }

    public func stop() {
        queue.sync { closeDevice() }
        IOHIDManagerCancel(manager)
        continuation.finish()
    }

    public func setImage(key: Int, jpeg: Data) {
        queue.async { [self] in
            guard let device else { return }
            for report in ReportCodec.imageReports(key: key, jpeg: jpeg) {
                send(report, type: kIOHIDReportTypeOutput, to: device)
            }
        }
    }

    public func setBrightness(_ percent: Int) {
        queue.async { [self] in
            guard let device else { return }
            send(ReportCodec.brightnessReport(percent: percent), type: kIOHIDReportTypeFeature, to: device)
        }
    }

    public func reset() {
        queue.async { [self] in
            guard let device else { return }
            send(ReportCodec.resetReport(), type: kIOHIDReportTypeFeature, to: device)
        }
    }

    // MARK: - Queue-confined

    /// The manager's device object is already activated, and IOKit traps when callbacks are
    /// registered on an activated device. So each match gets its own device object for the same
    /// IOService, configured before activation.
    private func attach(_ matched: IOHIDDevice) {
        guard device == nil,
              let own = IOHIDDeviceCreate(kCFAllocatorDefault, IOHIDDeviceGetService(matched)) else { return }
        let result = IOHIDDeviceOpen(own, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else {
            continuation.yield(.openFailed(result))
            return
        }
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Self.inputBufferSize)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceSetDispatchQueue(own, queue)
        IOHIDDeviceRegisterInputReportCallback(own, buffer, Self.inputBufferSize, { context, _, _, _, _, bytes, length in
            let transport = Unmanaged<IOKitTransport>.fromOpaque(context!).takeUnretainedValue()
            transport.handleInput(Array(UnsafeBufferPointer(start: bytes, count: length)))
        }, context)
        IOHIDDeviceSetCancelHandler(own) { buffer.deallocate() }
        IOHIDDeviceActivate(own)

        device = own
        matchedDevice = matched
        keyStates = [Bool](repeating: false, count: ReportCodec.keyCount)
        let info = DeviceInfo(
            serial: featureString(ReportCodec.serialReportID, offset: ReportCodec.serialOffset, from: own),
            firmware: featureString(ReportCodec.firmwareReportID, offset: ReportCodec.firmwareOffset, from: own)
        )
        continuation.yield(.connected(info))
    }

    private func detach(_ removed: IOHIDDevice) {
        guard let matchedDevice, CFEqual(matchedDevice, removed) else { return }
        closeDevice()
        continuation.yield(.disconnected)
    }

    private func closeDevice() {
        guard let device else { return }
        IOHIDDeviceCancel(device)
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        self.device = nil
        matchedDevice = nil
    }

    private func handleInput(_ bytes: [UInt8]) {
        guard let states = ReportCodec.keyStates(fromInputReport: bytes) else { return }
        for event in ReportCodec.events(from: keyStates, to: states) {
            continuation.yield(.key(event))
        }
        keyStates = states
    }

    private func send(_ report: [UInt8], type: IOHIDReportType, to device: IOHIDDevice) {
        report.withUnsafeBufferPointer { buffer in
            _ = IOHIDDeviceSetReport(device, type, CFIndex(report[0]), buffer.baseAddress!, buffer.count)
        }
    }

    private func featureString(_ id: UInt8, offset: Int, from device: IOHIDDevice) -> String {
        var buffer = [UInt8](repeating: 0, count: ReportCodec.featureReportSize)
        var length = CFIndex(buffer.count)
        guard IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, CFIndex(id), &buffer, &length) == kIOReturnSuccess else {
            return ""
        }
        return ReportCodec.string(fromFeatureReport: Array(buffer.prefix(length)), offset: offset)
    }
}
