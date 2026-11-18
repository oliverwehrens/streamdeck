import DeckEngine

/// Journal lines for a status change. Pure, so the daemon's logging is testable.
public enum StatusLog {
    public static func lines(from old: DeckEngine.Status, to new: DeckEngine.Status) -> [String] {
        var lines: [String] = []
        if new.connected != old.connected || new.device != old.device {
            if new.connected, let device = new.device {
                lines.append("connected: Stream Deck \(device.serial) (firmware \(device.firmware))")
            } else if old.connected {
                lines.append("disconnected")
            }
        }
        let oldMessages = Set(old.problems.map(\.message))
        let newMessages = Set(new.problems.map(\.message))
        for problem in new.problems where !oldMessages.contains(problem.message) {
            lines.append("problem: " + oneLine(problem.message))
        }
        for problem in old.problems where !newMessages.contains(problem.message) {
            lines.append("resolved: " + oneLine(problem.message))
        }
        return lines
    }

    /// Every current problem, for the status key.
    public static func allProblems(_ status: DeckEngine.Status) -> [String] {
        status.problems.isEmpty ? ["no problems"] : status.problems.map { "problem: " + oneLine($0.message) }
    }

    /// Config errors are multi-line; the journal keeps one entry per line, so join them.
    static func oneLine(_ message: String) -> String {
        message.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
    }
}
