import Foundation
import os

/// Runs commands through the user's login shell, so PATH matches their terminal.
public struct ShellRunner: CommandRunner {
    public let shell: String

    public init(shell: String = ShellRunner.userShell()) {
        self.shell = shell
    }

    public static func userShell() -> String {
        if let entry = getpwuid(getuid()), let path = entry.pointee.pw_shell {
            let shell = String(cString: path)
            if FileManager.default.isExecutableFile(atPath: shell) { return shell }
        }
        return "/bin/zsh"
    }

    public func run(_ command: String, timeout: TimeInterval?) async -> CommandResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(returning: runBlocking(command, timeout: timeout))
            }
        }
    }

    private func runBlocking(_ command: String, timeout: TimeInterval?) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-l", "-c", command]
        let stdout = Pipe(), stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return CommandResult(exitCode: -1, stderr: "cannot start \(shell): \(error.localizedDescription)")
        }

        let timedOut = OSAllocatedUnfairLock(initialState: false)
        if let timeout {
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                guard process.isRunning else { return }
                timedOut.withLock { $0 = true }
                process.terminate()
                DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                    if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                }
            }
        }

        // Drain both pipes concurrently so a chatty command cannot fill a pipe and block.
        let output = OSAllocatedUnfairLock(initialState: (out: Data(), err: Data()))
        let group = DispatchGroup()
        for (pipe, isOut) in [(stdout, true), (stderr, false)] {
            DispatchQueue.global().async(group: group) {
                let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
                output.withLock { if isOut { $0.out = data } else { $0.err = data } }
            }
        }
        process.waitUntilExit()
        group.wait()

        let (out, err) = output.withLock { ($0.out, $0.err) }
        return CommandResult(
            exitCode: process.terminationStatus,
            stdout: String(decoding: out, as: UTF8.self),
            stderr: String(decoding: err, as: UTF8.self),
            timedOut: timedOut.withLock { $0 }
        )
    }
}
