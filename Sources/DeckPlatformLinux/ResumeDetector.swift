import Foundation

/// Notices a suspend/resume: `CLOCK_BOOTTIME` keeps counting during suspend, `CLOCK_MONOTONIC` does not,
/// so the gap between them grows by the time spent suspended. Needs no D-Bus or logind.
public final class ResumeDetector: @unchecked Sendable {
    public typealias Clocks = @Sendable () -> (boottime: TimeInterval, monotonic: TimeInterval)

    /// Growth of the gap that counts as a resume. Scheduling jitter stays far below it.
    static let threshold: TimeInterval = 1
    static let interval: TimeInterval = 2

    private let clocks: Clocks
    private var lastGap: TimeInterval
    private let lock = NSLock()

    public init(clocks: @escaping Clocks = ResumeDetector.systemClocks) {
        self.clocks = clocks
        let now = clocks()
        lastGap = now.boottime - now.monotonic
    }

    /// True once per resume since the previous call.
    public func check() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let now = clocks()
        let gap = now.boottime - now.monotonic
        defer { lastGap = gap }
        return gap - lastGap > Self.threshold
    }

    /// Calls `onResume` from a background thread after each resume.
    public func start(onResume: @escaping @Sendable () -> Void) {
        Thread.detachNewThread { [self] in
            while true {
                Thread.sleep(forTimeInterval: Self.interval)
                if check() { onResume() }
            }
        }
    }

    public static let systemClocks: Clocks = {
        (seconds(CLOCK_BOOTTIME), seconds(CLOCK_MONOTONIC))
    }

    private static func seconds(_ clock: clockid_t) -> TimeInterval {
        var spec = timespec()
        clock_gettime(clock, &spec)
        return TimeInterval(spec.tv_sec) + TimeInterval(spec.tv_nsec) / 1_000_000_000
    }
}
