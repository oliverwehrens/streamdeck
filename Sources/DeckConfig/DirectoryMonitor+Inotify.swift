#if os(Linux)
import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// Reports changes anywhere under a directory through inotify. inotify is not recursive, so every
/// subdirectory gets its own watch, including ones created or moved in later. Bursts of events
/// coalesce into one `onChange`, 0.2 s after the first event, like the FSEvents latency on macOS.
final class DirectoryMonitor: @unchecked Sendable {
    static let latency: DispatchTimeInterval = .milliseconds(200)
    static let mask = UInt32(IN_CLOSE_WRITE) | UInt32(IN_MOVED_TO) | UInt32(IN_MOVED_FROM) | UInt32(IN_CREATE)
        | UInt32(IN_DELETE) | UInt32(IN_MODIFY) | UInt32(IN_ATTRIB)

    private let directory: URL
    private let queue: DispatchQueue
    private let onChange: @Sendable () -> Void

    // Accessed only on `queue` after `start()`.
    private var source: DispatchSourceRead?
    private var watches: [Int32: String] = [:]
    private var changeScheduled = false

    /// `onChange` runs on `queue`.
    init(directory: URL, queue: DispatchQueue, onChange: @escaping @Sendable () -> Void) {
        self.directory = directory
        self.queue = queue
        self.onChange = onChange
    }

    /// Returns false if watching could not start.
    func start() -> Bool {
        queue.sync {
            let fd = inotify_init1(Int32(IN_NONBLOCK) | Int32(IN_CLOEXEC))
            guard fd >= 0 else { return false }
            guard addWatches(fd: fd, path: directory.path) else {
                close(fd)
                return false
            }
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            source.setEventHandler { [weak self] in self?.readEvents(fd: fd) }
            source.setCancelHandler { close(fd) }
            source.resume()
            self.source = source
            return true
        }
    }

    func stop() {
        queue.async {
            self.source?.cancel()
            self.source = nil
            self.watches = [:]
        }
    }

    /// Watches `path` and every directory below it. Returns false if `path` itself cannot be watched.
    private func addWatches(fd: Int32, path: String) -> Bool {
        let wd = inotify_add_watch(fd, path, Self.mask)
        guard wd >= 0 else { return false }
        watches[wd] = path
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
        for name in entries {
            let child = (path as NSString).appendingPathComponent(name)
            if isDirectory(child) { _ = addWatches(fd: fd, path: child) }
        }
        return true
    }

    /// True for a real directory; symlinks are not followed, as with FSEvents.
    private func isDirectory(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFDIR
    }

    private func readEvents(fd: Int32) {
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            guard count > 0 else { break }
            handle(Array(buffer.prefix(count)), fd: fd)
        }
        scheduleChange()
    }

    /// Parses `struct inotify_event` records: wd, mask, cookie, len, then `len` bytes of name.
    private func handle(_ bytes: [UInt8], fd: Int32) {
        let headerSize = 16
        var offset = 0
        while offset + headerSize <= bytes.count {
            let (wd, mask, length) = bytes.withUnsafeBytes { raw in
                (raw.loadUnaligned(fromByteOffset: offset, as: Int32.self),
                 raw.loadUnaligned(fromByteOffset: offset + 4, as: UInt32.self),
                 Int(raw.loadUnaligned(fromByteOffset: offset + 12, as: UInt32.self)))
            }
            let nameBytes = bytes[(offset + headerSize) ..< min(offset + headerSize + length, bytes.count)]
            let name = String(decoding: nameBytes.prefix { $0 != 0 }, as: UTF8.self)
            offset += headerSize + length

            if mask & UInt32(IN_IGNORED) != 0 {
                watches[wd] = nil
            } else if mask & UInt32(IN_ISDIR) != 0, mask & (UInt32(IN_CREATE) | UInt32(IN_MOVED_TO)) != 0,
                      let parent = watches[wd], !name.isEmpty {
                _ = addWatches(fd: fd, path: (parent as NSString).appendingPathComponent(name))
            }
        }
    }

    private func scheduleChange() {
        guard !changeScheduled else { return }
        changeScheduled = true
        queue.asyncAfter(deadline: .now() + Self.latency) { [weak self] in
            guard let self else { return }
            changeScheduled = false
            if source != nil { onChange() }
        }
    }
}
#endif
