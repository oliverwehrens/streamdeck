import DeckConfig
import Foundation

/// Outcome of a key action other than page switching.
public enum ActionResult: Equatable, Sendable {
    case succeeded
    case failed(String)
    /// Keystroke and media actions need the Accessibility permission.
    case needsAccessibility
}

extension ActionResult {
    /// The result of a `run` action: succeeded, or the exit status with the last lines of stderr.
    public init(_ result: CommandResult, command: String) {
        guard !result.succeeded else {
            self = .succeeded
            return
        }
        let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = stderr.isEmpty ? "" : ": \(stderr.split(separator: "\n").suffix(3).joined(separator: " / "))"
        self = .failed("'\(command)' exited with status \(result.exitCode)\(detail)")
    }
}

/// Performs run/open/keys/media actions. Page actions are handled by the engine.
public protocol ActionPerformer: Sendable {
    func perform(_ action: Action) async -> ActionResult
}

public struct CommandResult: Equatable, Sendable {
    public var exitCode: Int32
    public var stdout: String
    public var stderr: String
    public var timedOut: Bool

    public init(exitCode: Int32, stdout: String = "", stderr: String = "", timedOut: Bool = false) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.timedOut = timedOut
    }

    public var succeeded: Bool { exitCode == 0 && !timedOut }
}

/// Runs shell commands; used for dynamic keys.
public protocol CommandRunner: Sendable {
    func run(_ command: String, timeout: TimeInterval?) async -> CommandResult
}

/// Something the user should know about, shown in the menu.
public struct Problem: Equatable, Sendable, CustomStringConvertible {
    public enum Source: Hashable, Sendable, Comparable {
        case config
        case device
        case permission
        /// The web editor cannot run, e.g. its port is in use.
        case web
        case icon(key: Int)
        case action(page: String, key: Int)
        case dynamic(key: Int)
    }

    public var source: Source
    public var message: String

    public var description: String { message }
}
