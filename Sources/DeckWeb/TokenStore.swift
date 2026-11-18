import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif

/// Paired browsers. Only a SHA-256 of each token is kept, in a file only this user can read.
@MainActor
public final class TokenStore {
    public struct Client: Codable, Equatable, Sendable {
        public var id: String
        public var name: String
        public var sha256: String
        public var created: Date
        public var lastUsed: Date
    }

    /// `$XDG_STATE_HOME/streamdeck/web-clients.json`, by default under `~/.local/state`.
    public static var defaultURL: URL {
        let environment = ProcessInfo.processInfo.environment
        let state = environment["XDG_STATE_HOME"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/state")
        return state.appendingPathComponent("streamdeck/web-clients.json")
    }

    /// `lastUsed` is written at most this often.
    static let lastUsedInterval: TimeInterval = 3600

    public let url: URL
    private let scheduler: Scheduler
    private var clients: [Client] = []
    /// Identifies the file's version as last read or written; a change means someone else edited it.
    private struct FileStamp: Equatable {
        var seconds: Int
        var nanoseconds: Int
        var inode: UInt64
        var size: Int64
    }

    private var fileStamp: FileStamp?

    public init(url: URL = TokenStore.defaultURL, scheduler: Scheduler) {
        self.url = url
        self.scheduler = scheduler
        reloadIfChanged()
    }

    public var all: [Client] {
        reloadIfChanged()
        return clients
    }

    /// Creates a client and returns it with its token. The token is not stored.
    public func create(name: String) throws -> (client: Client, token: String) {
        reloadIfChanged()
        let token = Self.base64url(Self.randomBytes(32))
        let client = Client(id: Self.hex(Self.randomBytes(8)), name: name, sha256: SHA256.hex(Array(token.utf8)),
                            created: scheduler.now, lastUsed: scheduler.now)
        clients.append(client)
        try save()
        return (client, token)
    }

    /// The client the token belongs to, or nil. Updates its last use now and then.
    public func validate(_ token: String) -> Client? {
        reloadIfChanged()
        let hash = Array(SHA256.hex(Array(token.utf8)).utf8)
        var found: Int?
        // Check every client, so the time taken doesn't depend on which one matches.
        for (index, client) in clients.enumerated() where constantTimeEqual(Array(client.sha256.utf8), hash) {
            found = index
        }
        guard let index = found else { return nil }
        if scheduler.now.timeIntervalSince(clients[index].lastUsed) >= Self.lastUsedInterval {
            clients[index].lastUsed = scheduler.now
            try? save()
        }
        return clients[index]
    }

    /// Returns false if there's no such client.
    @discardableResult
    public func revoke(id: String) throws -> Bool {
        reloadIfChanged()
        guard clients.contains(where: { $0.id == id }) else { return false }
        clients.removeAll { $0.id == id }
        try save()
        return true
    }

    // MARK: - File

    private func reloadIfChanged() {
        let stamp = currentStamp()
        guard stamp != fileStamp || stamp == nil else { return }
        fileStamp = stamp
        guard stamp != nil, let data = try? Data(contentsOf: url) else {
            clients = []
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        clients = (try? decoder.decode([Client].self, from: data)) ?? []
    }

    private func save() throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(clients)
        // Written with 0600 from the start, then renamed over the old file.
        let temporary = directory.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString)")
        let fd = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw CocoaError(.fileWriteNoPermission, userInfo: [NSFilePathErrorKey: temporary.path]) }
        let written = data.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        close(fd)
        guard written == data.count, rename(temporary.path, url.path) == 0 else {
            unlink(temporary.path)
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
        fileStamp = currentStamp()
    }

    private func currentStamp() -> FileStamp? {
        var info = stat()
        guard stat(url.path, &info) == 0 else { return nil }
        #if canImport(Darwin)
        let time = info.st_mtimespec
        #else
        let time = info.st_mtim
        #endif
        return FileStamp(seconds: Int(time.tv_sec), nanoseconds: Int(time.tv_nsec), inode: UInt64(info.st_ino), size: Int64(info.st_size))
    }

    // MARK: - Randomness and encoding

    static func randomBytes(_ count: Int) -> [UInt8] {
        var generator = SystemRandomNumberGenerator()
        return (0 ..< count).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
    }

    static func base64url(_ bytes: [UInt8]) -> String {
        Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String($0, radix: 16).leftPadded(to: 2) }.joined()
    }
}
