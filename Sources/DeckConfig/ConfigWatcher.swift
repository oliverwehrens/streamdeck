import Foundation

/// Watches the config directory and reloads on any change, including atomic rename-saves
/// and edited icon files. Invalid configs are reported but never replace the last valid one.
public final class ConfigWatcher: @unchecked Sendable {
    public enum Update: Sendable {
        case loaded(DeckConfig)
        case failed([ConfigError])
    }

    public let url: URL
    private let onUpdate: @Sendable (Update) -> Void
    private let queue = DispatchQueue(label: "de.wehrens.streamdeck.config")
    private var monitor: DirectoryMonitor?

    // Accessed only on `queue`.
    private var current: DeckConfig?

    public init(url: URL, onUpdate: @escaping @Sendable (Update) -> Void) {
        self.url = url
        self.onUpdate = onUpdate
    }

    /// The last valid config, if any.
    public var config: DeckConfig? {
        queue.sync { current }
    }

    /// Loads once, then watches for changes.
    public func start() {
        reload()
        let monitor = DirectoryMonitor(directory: url.deletingLastPathComponent(), queue: queue) { [weak self] in
            self?.reloadOnQueue()
        }
        // If watching cannot start, the loaded config stays and later changes are not picked up.
        guard monitor.start() else { return }
        self.monitor = monitor
    }

    public func stop() {
        monitor?.stop()
        monitor = nil
    }

    /// Reloads now, with the same rules as a change on disk.
    public func reload() {
        queue.async { self.reloadOnQueue() }
    }

    private func reloadOnQueue() {
        switch ConfigLoader.load(contentsOf: url) {
        case let .success(config):
            current = config
            onUpdate(.loaded(config))
        case let .failure(failure):
            onUpdate(.failed(failure.errors))
        }
    }
}
