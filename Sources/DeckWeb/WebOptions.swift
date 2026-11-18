import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif

/// `streamdeckd`'s web editor options: `--web-listen <host:port>` and `--no-web`.
public struct WebOptions: Equatable, Sendable {
    public var enabled = true
    public var host = "0.0.0.0"
    public var port = WebServer.defaultPort

    public init() {}

    public static let usage = "usage: streamdeckd [--web-listen <address>:<port>] [--no-web]"

    /// Parses the arguments after the program name. Fails with a message for anything else.
    public static func parse(_ arguments: [String]) -> Result<WebOptions, UsageError> {
        var options = WebOptions()
        var remaining = arguments[...]
        while let argument = remaining.popFirst() {
            switch argument {
            case "--no-web":
                options.enabled = false
            case "--web-listen":
                guard let value = remaining.popFirst() else { return .failure(UsageError("--web-listen needs <address>:<port>")) }
                guard let (host, port) = splitHostPort(value) else {
                    return .failure(UsageError("--web-listen: expected <address>:<port>, such as 0.0.0.0:3325, not '\(value)'"))
                }
                options.host = host
                options.port = port
            default:
                return .failure(UsageError("unknown argument '\(argument)'"))
            }
        }
        return .success(options)
    }

    /// `0.0.0.0:3325`, `[::]:3325` or `localhost:80`.
    static func splitHostPort(_ text: String) -> (String, Int)? {
        guard let colon = text.lastIndex(of: ":"), let port = Int(text[text.index(after: colon)...]), (1 ... 65535).contains(port) else {
            return nil
        }
        var host = String(text[..<colon])
        if host.hasPrefix("["), host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        guard !host.isEmpty else { return nil }
        return (host, port)
    }

    /// The URLs to log at startup: the host name and each IPv4 address when listening on all
    /// interfaces, otherwise the address given.
    public func urls(hostName: String = WebOptions.hostName(), addresses: [String] = WebOptions.ipv4Addresses()) -> [String] {
        let hosts = ["0.0.0.0", "::"].contains(host) ? ["\(hostName).local"] + addresses : [host.contains(":") ? "[\(host)]" : host]
        return hosts.map { "http://\($0):\(port)/" }
    }

    public static func hostName() -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        guard gethostname(&buffer, buffer.count) == 0 else { return "localhost" }
        let name = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        // A fully qualified name already has a domain; .local is for the bare one.
        return String(name.split(separator: ".").first ?? "localhost")
    }

    /// Non-loopback IPv4 addresses of this machine.
    public static func ipv4Addresses() -> [String] {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0 else { return [] }
        defer { freeifaddrs(first) }
        var result: [String] = []
        var cursor = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            guard let address = entry.pointee.ifa_addr, address.pointee.sa_family == sa_family_t(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(MemoryLayout<sockaddr_in>.size), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let text = String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            if !text.hasPrefix("127."), !result.contains(text) { result.append(text) }
        }
        return result
    }
}

public struct UsageError: Error, Equatable, CustomStringConvertible, Sendable {
    public let description: String
    init(_ description: String) { self.description = description }
}
