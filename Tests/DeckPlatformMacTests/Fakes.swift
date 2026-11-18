import DeckEngine
import Foundation
import Testing

/// Fails the test if a command runs.
struct NoCommands: CommandRunner {
    func run(_ command: String, timeout: TimeInterval?) async -> CommandResult {
        Issue.record("unexpected command: \(command)")
        return CommandResult(exitCode: 0)
    }
}

let noCommands = NoCommands()

/// German (QWERTZ) without modifiers: Y and Z swapped, no key for `[`.
let germanLayout: TableKeyboardLayout = {
    var codes = TableKeyboardLayout.us.codes
    for character in "[];'\\/=`-" { codes[character] = nil }
    codes["z"] = 0x10
    codes["y"] = 0x06
    return TableKeyboardLayout(name: "German", codes: codes)
}()
