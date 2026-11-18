import DeckSupport
import Foundation

/// Starts a program found on PATH, without a shell, so a target needs no quoting.
public protocol ProgramLauncher: Sendable {
    /// Waits up to `patience` for the program to exit. One still running then counts as started:
    /// `steam` with a URL starts the Steam client when it is not running yet, and never returns.
    func launch(_ program: String, arguments: [String], patience: TimeInterval) async -> LaunchResult
}

public enum LaunchResult: Equatable, Sendable {
    case exited(status: Int32, stderr: String)
    case stillRunning
    case failedToStart(String)
}

public struct ProcessLauncher: ProgramLauncher {
    public init() {}

    public func launch(_ program: String, arguments: [String], patience: TimeInterval) async -> LaunchResult {
        // Waiting blocks, so it gets its own thread (see ShellRunner).
        await withCheckedContinuation { continuation in
            Thread.detachNewThread {
                continuation.resume(returning: launchBlocking(program, arguments: arguments, patience: patience))
            }
        }
    }

    private func launchBlocking(_ program: String, arguments: [String], patience: TimeInterval) -> LaunchResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [program] + arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        let stderr = Pipe()
        process.standardError = stderr
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do {
            try process.run()
        } catch {
            return .failedToStart(error.localizedDescription)
        }
        // Drained on its own thread so a chatty program never blocks on a full pipe, even after we stop waiting.
        let errorOutput = Locked(initialState: Data())
        let drained = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            let data = (try? stderr.fileHandleForReading.readToEnd()) ?? Data()
            errorOutput.withLock { $0 = data }
            drained.signal()
        }
        guard exited.wait(timeout: .now() + patience) == .success else { return .stillRunning }
        // A child the program left running may hold stderr open; don't wait for it long.
        _ = drained.wait(timeout: .now() + 1)
        let text = String(decoding: errorOutput.withLock { $0 }, as: UTF8.self)
        // `env` exits 127 when the program is not on PATH.
        return .exited(status: process.terminationStatus, stderr: text)
    }
}
