#if canImport(CoreServices)
import CoreServices
import Foundation

/// Reports changes anywhere under a directory, recursively, through FSEvents.
final class DirectoryMonitor: @unchecked Sendable {
    private let directory: URL
    private let queue: DispatchQueue
    private let onChange: @Sendable () -> Void
    private var stream: FSEventStreamRef?

    /// `onChange` runs on `queue`.
    init(directory: URL, queue: DispatchQueue, onChange: @escaping @Sendable () -> Void) {
        self.directory = directory
        self.queue = queue
        self.onChange = onChange
    }

    /// Returns false if watching could not start.
    func start() -> Bool {
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            Unmanaged<DirectoryMonitor>.fromOpaque(info!).takeUnretainedValue().onChange()
        }
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &context, [directory.path as CFString] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.2,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        ) else { return false }
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        self.stream = stream
        return true
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}
#endif
