import CoreServices
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
    private var stream: FSEventStreamRef?

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
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            Unmanaged<ConfigWatcher>.fromOpaque(info!).takeUnretainedValue().reloadOnQueue()
        }
        let directory = url.deletingLastPathComponent().path as CFString
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &context, [directory] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.2,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        ) else { return }
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    public func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
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
