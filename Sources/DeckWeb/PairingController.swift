import DeckConfig
import DeckEngine
import Foundation

/// Pairing a browser: a code shown on the deck, typed into the browser. See the web-pairing spec.
@MainActor
public final class PairingController {
    public enum StartError: Error, Equatable {
        case noDevice
        case lockedOut
    }

    public enum CompleteError: Error, Equatable {
        /// No code is shown, or it stopped working.
        case noCode
        case wrongCode
        case lockedOut
    }

    static let codeLifetime: TimeInterval = 120
    static let triesPerCode = 5
    static let lockoutFailures = 10
    static let lockoutWindow: TimeInterval = 600
    static let lockoutDuration: TimeInterval = 600

    static let cancelKey = DeckEngine.statusKey
    static let background = HexColor(red: 0x0D, green: 0x2B, blue: 0x55)

    private let engine: DeckEngine
    private let scheduler: Scheduler
    private let makeCode: () -> String
    private let log: (String) -> Void

    public private(set) var code: String?
    private var triesLeft = 0
    private var expiry: ScheduledTimer?
    private var failures: [Date] = []
    private var lockedUntil: Date?

    public init(engine: DeckEngine, scheduler: Scheduler, log: @escaping (String) -> Void,
                makeCode: @escaping () -> String = PairingController.randomCode) {
        self.engine = engine
        self.scheduler = scheduler
        self.log = log
        self.makeCode = makeCode
    }

    /// Six digits from the system's random generator.
    public nonisolated static func randomCode() -> String {
        var generator = SystemRandomNumberGenerator()
        return String(Int.random(in: 0 ..< 1_000_000, using: &generator)).leftPadded(to: 6)
    }

    public var isLockedOut: Bool {
        guard let lockedUntil else { return false }
        if scheduler.now >= lockedUntil {
            self.lockedUntil = nil
            return false
        }
        return true
    }

    /// Shows a new code on the deck, replacing any pending one.
    public func start(from address: String) throws(StartError) {
        guard !isLockedOut else { throw .lockedOut }
        guard engine.status.connected else { throw .noDevice }
        let code = makeCode()
        self.code = code
        triesLeft = Self.triesPerCode
        expiry?.cancel()
        expiry = scheduler.after(Self.codeLifetime) { [weak self] in
            self?.log("pairing code expired")
            self?.end()
        }
        engine.onOverlayKeyPress = { [weak self] key in
            guard key == Self.cancelKey else { return }
            self?.log("pairing cancelled on the deck")
            self?.end()
        }
        engine.overlay = Self.overlay(code: code)
        log("pairing requested from \(address)")
    }

    /// Checks the code; on success pairing ends and the caller creates the token.
    public func complete(code entered: String) throws(CompleteError) {
        guard !isLockedOut else { throw .lockedOut }
        guard let code else { throw .noCode }
        let digits = entered.filter(\.isNumber)
        if constantTimeEqual(Array(digits.utf8), Array(code.utf8)) {
            log("pairing succeeded")
            end()
            return
        }
        failures.append(scheduler.now)
        failures.removeAll { scheduler.now.timeIntervalSince($0) > Self.lockoutWindow }
        triesLeft -= 1
        log("pairing: wrong code entered")
        if failures.count >= Self.lockoutFailures {
            lockedUntil = scheduler.now.addingTimeInterval(Self.lockoutDuration)
            failures.removeAll()
            log("pairing locked for \(Int(Self.lockoutDuration / 60)) minutes after \(Self.lockoutFailures) wrong codes")
            end()
            throw .lockedOut
        }
        if triesLeft <= 0 {
            log("pairing code stopped working after \(Self.triesPerCode) wrong entries")
            end()
        }
        throw .wrongCode
    }

    /// Clears the code and gives the deck back; also when the deck disconnects.
    public func end() {
        code = nil
        expiry?.cancel()
        expiry = nil
        if engine.overlay != nil { engine.overlay = nil }
        engine.onOverlayKeyPress = nil
    }

    /// The deck while a code is shown; see design "Pairing".
    static func overlay(code: String) -> [Int: KeyAppearance] {
        let digits = Array(code)
        func pair(_ index: Int) -> KeyAppearance {
            KeyAppearance(background: background, label: String(digits[index * 2 ..< index * 2 + 2]))
        }
        return [
            2: KeyAppearance(background: background, icon: .material(name: "link", filled: false)),
            6: pair(0),
            7: pair(1),
            8: pair(2),
            12: KeyAppearance(background: background, label: "Pair this browser?"),
            cancelKey: KeyAppearance(background: .black, icon: .material(name: "close", filled: false), label: "Cancel"),
        ]
    }
}
