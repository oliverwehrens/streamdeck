import DeckConfig
import Foundation

/// Outcome of a key action other than page switching.
public enum ActionResult: Equatable, Sendable {
    case succeeded
    case failed(String)
    /// Keystroke and media actions need the Accessibility permission.
    case needsAccessibility
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
        case icon(key: Int)
        case action(page: String, key: Int)
        case dynamic(key: Int)
    }

    public var source: Source
    public var message: String

    public var description: String { message }
}
