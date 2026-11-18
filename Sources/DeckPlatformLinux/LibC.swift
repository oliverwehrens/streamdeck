#if canImport(Glibc)
@_exported import Glibc
#elseif canImport(Musl)
@_exported import Musl
#endif

/// `strerror` as a Swift string.
func errorText(_ code: Int32) -> String {
    String(cString: strerror(code))
}

/// Writes all of `bytes`, retrying on EINTR. Returns false on error.
func writeAll(_ fd: Int32, _ bytes: [UInt8]) -> Bool {
    bytes.withUnsafeBytes { buffer in
        var offset = 0
        while offset < buffer.count {
            let written = write(fd, buffer.baseAddress! + offset, buffer.count - offset)
            if written < 0 {
                if errno == EINTR { continue }
                return false
            }
            offset += written
        }
        return true
    }
}
