import Foundation

public struct DeviceInfo: Equatable, Sendable {
    public let serial: String
    public let firmware: String

    public init(serial: String, firmware: String) {
        self.serial = serial
        self.firmware = firmware
    }
}

public enum DeviceEvent: Equatable, Sendable {
    case connected(DeviceInfo)
    case disconnected
    /// The device was found but could not be opened; carries the IOReturn code.
    case openFailed(Int32)
    case key(KeyEvent)
}

/// The boundary between the engine and the hardware.
public protocol DeckTransport: AnyObject, Sendable {
    var events: AsyncStream<DeviceEvent> { get }
    /// Shows a 72x72 JPEG (already flipped) on one key. Ignored while disconnected.
    func setImage(key: Int, jpeg: Data)
    func setBrightness(_ percent: Int)
    func reset()
    func start()
    func stop()
}
