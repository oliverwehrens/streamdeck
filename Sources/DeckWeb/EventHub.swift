import Foundation
import Hummingbird

/// The open server-sent-event streams, one per browser tab connection. See design "Events".
@MainActor
public final class EventHub {
    struct Connection {
        let tab: String
        let continuation: AsyncStream<ByteBuffer>.Continuation
    }

    private var connections: [Int: Connection] = [:]
    private var nextID = 0
    private var heartbeat: Task<Void, Never>?

    /// Called after a stream opens (with its tab) and after it closes.
    var onOpen: ((Int, String) -> Void)?
    var onClose: ((Int, String) -> Void)?

    public init(heartbeatInterval: Duration = .seconds(15)) {
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: heartbeatInterval)
                self?.sendRaw(": ping\n\n", to: nil)
            }
        }
    }

    isolated deinit {
        heartbeat?.cancel()
    }

    var count: Int { connections.count }

    /// Opens a stream for `tab`. Call `onOpen` work (initial events) right after.
    func open(tab: String) -> AsyncStream<ByteBuffer> {
        nextID += 1
        let id = nextID
        let (stream, continuation) = AsyncStream.makeStream(of: ByteBuffer.self)
        connections[id] = Connection(tab: tab, continuation: continuation)
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.closed(id) }
        }
        onOpen?(id, tab)
        return stream
    }

    private func closed(_ id: Int) {
        guard let connection = connections.removeValue(forKey: id) else { return }
        onClose?(id, connection.tab)
    }

    /// Sends an event to one connection, every connection of a tab, or (nil) everyone.
    func send(_ event: String, json: Data, toConnection id: Int? = nil, toTab tab: String? = nil) {
        let text = "event: \(event)\ndata: \(String(decoding: json, as: UTF8.self))\n\n"
        for (connectionID, connection) in connections {
            if let id, connectionID != id { continue }
            if let tab, connection.tab != tab { continue }
            connection.continuation.yield(ByteBuffer(string: text))
        }
    }

    private func sendRaw(_ text: String, to id: Int?) {
        for (connectionID, connection) in connections where id == nil || id == connectionID {
            connection.continuation.yield(ByteBuffer(string: text))
        }
    }

    /// Ends every stream, e.g. at shutdown.
    public func closeAll() {
        for connection in connections.values { connection.continuation.finish() }
    }
}
