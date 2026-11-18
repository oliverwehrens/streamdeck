import DeckEngine
import Foundation

/// Which browser tabs have the editor open and which one the deck follows. See design "Holding the deck".
@MainActor
public final class EditorPresence {
    public static let releaseDelay: TimeInterval = 60

    private let engine: DeckEngine
    private let scheduler: Scheduler

    /// Open streams per tab (a tab may briefly have two while reconnecting).
    private var streams: [String: Int] = [:]
    /// Visible tabs, least recently reported first.
    private var visibleOrder: [String] = []
    private var pages: [String: String] = [:]
    private var releaseTimer: ScheduledTimer?

    /// True from the first open stream until `releaseDelay` after the last one closed.
    public private(set) var holdsDeck = false

    /// Called when the hold starts (true) or ends (false).
    var onHoldChange: ((Bool) -> Void)?
    /// Called when a deck key is pressed while a tab holds the selection.
    var onDeckKey: ((String, Int) -> Void)?
    /// Called when the holder or its page changes.
    var onHolderChange: (() -> Void)?

    public init(engine: DeckEngine, scheduler: Scheduler) {
        self.engine = engine
        self.scheduler = scheduler
    }

    /// The most recently reported visible tab that has an open stream.
    public var holder: (tab: String, page: String?)? {
        guard holdsDeck, let tab = visibleOrder.last(where: { streams[$0, default: 0] > 0 }) else { return nil }
        return (tab, pages[tab])
    }

    func streamOpened(tab: String) {
        streams[tab, default: 0] += 1
        releaseTimer?.cancel()
        releaseTimer = nil
        if !holdsDeck {
            holdsDeck = true
            onHoldChange?(true)
        }
        apply()
    }

    func streamClosed(tab: String) {
        streams[tab, default: 1] -= 1
        if streams[tab] == 0 {
            streams[tab] = nil
            visibleOrder.removeAll { $0 == tab }
            pages[tab] = nil
        }
        apply()
        if streams.isEmpty, holdsDeck, releaseTimer == nil {
            releaseTimer = scheduler.after(Self.releaseDelay) { [weak self] in self?.release() }
        }
    }

    /// A tab reports whether it is visible and which page it has selected.
    public func report(tab: String, visible: Bool, page: String?) {
        pages[tab] = page
        visibleOrder.removeAll { $0 == tab }
        if visible { visibleOrder.append(tab) }
        apply()
    }

    private func release() {
        releaseTimer = nil
        guard holdsDeck, streams.isEmpty else { return }
        holdsDeck = false
        visibleOrder.removeAll()
        pages.removeAll()
        apply()
        onHoldChange?(false)
    }

    private var applied: (tab: String, page: String?)?

    private func apply() {
        let holder = holder
        engine.editorPage = holder?.page
        if let tab = holder?.tab {
            engine.onEditorKeyPress = { [weak self] key in self?.onDeckKey?(tab, key) }
        } else {
            engine.onEditorKeyPress = nil
        }
        if holder?.tab != applied?.tab || holder?.page != applied?.page {
            applied = holder
            onHolderChange?()
        }
    }
}
