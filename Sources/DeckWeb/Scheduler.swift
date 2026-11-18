import Foundation

/// Time and timers on the main actor, injectable so tests can move time forward.
@MainActor
public protocol Scheduler: AnyObject {
    var now: Date { get }
    /// Runs `action` after `seconds` unless the returned timer is cancelled first.
    func after(_ seconds: TimeInterval, _ action: @escaping @MainActor () -> Void) -> ScheduledTimer
}

@MainActor
public final class ScheduledTimer {
    private var cancelAction: (() -> Void)?

    init(cancel: @escaping () -> Void) {
        cancelAction = cancel
    }

    public func cancel() {
        cancelAction?()
        cancelAction = nil
    }
}

/// Timers on the main dispatch queue.
@MainActor
public final class MainQueueScheduler: Scheduler {
    public init() {}

    public var now: Date { Date() }

    public func after(_ seconds: TimeInterval, _ action: @escaping @MainActor () -> Void) -> ScheduledTimer {
        let item = DispatchWorkItem { MainActor.assumeIsolated { action() } }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
        return ScheduledTimer { item.cancel() }
    }
}

/// A clock that only moves when told to; for tests.
@MainActor
public final class ManualScheduler: Scheduler {
    private struct Pending {
        let id: Int
        let due: Date
        let action: @MainActor () -> Void
    }

    public private(set) var now: Date
    private var pending: [Pending] = []
    private var nextID = 0

    public init(now: Date = Date(timeIntervalSince1970: 1_800_000_000)) {
        self.now = now
    }

    public func after(_ seconds: TimeInterval, _ action: @escaping @MainActor () -> Void) -> ScheduledTimer {
        nextID += 1
        let id = nextID
        pending.append(Pending(id: id, due: now.addingTimeInterval(seconds), action: action))
        return ScheduledTimer { [weak self] in
            MainActor.assumeIsolated { self?.pending.removeAll { $0.id == id } }
        }
    }

    /// Moves time forward, running every timer that falls due, in order.
    public func advance(by seconds: TimeInterval) {
        let target = now.addingTimeInterval(seconds)
        while let next = pending.filter({ $0.due <= target }).min(by: { $0.due < $1.due }) {
            pending.removeAll { $0.id == next.id }
            now = next.due
            next.action()
        }
        now = target
    }
}
