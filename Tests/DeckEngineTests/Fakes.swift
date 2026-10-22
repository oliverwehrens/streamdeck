import DeckConfig
import DeckHID
import Foundation
import os
@testable import DeckEngine

let testConfigDirectory = URL(fileURLWithPath: "/Users/test/.config/streamdeck")

final class FakeTransport: DeckTransport, @unchecked Sendable {
    let events: AsyncStream<DeviceEvent>
    let continuation: AsyncStream<DeviceEvent>.Continuation
    private let lock = OSAllocatedUnfairLock<(images: [(key: Int, jpeg: Data)], brightness: [Int])>(initialState: ([], []))
    private(set) var stopped = false

    init() {
        (events, continuation) = AsyncStream.makeStream(of: DeviceEvent.self)
    }

    var images: [(key: Int, jpeg: Data)] { lock.withLock { $0.images } }
    var imageKeys: [Int] { images.map(\.key) }
    var brightness: [Int] { lock.withLock { $0.brightness } }
    func clear() { lock.withLock { $0 = ([], []) } }

    func setImage(key: Int, jpeg: Data) { lock.withLock { $0.images.append((key, jpeg)) } }
    func setBrightness(_ percent: Int) { lock.withLock { $0.brightness.append(percent) } }
    func reset() {}
    func start() {}
    func stop() { stopped = true }
}

final class FakePerformer: ActionPerformer, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock<[Action]>(initialState: [])
    let result: ActionResult

    init(result: ActionResult = .succeeded) {
        self.result = result
    }

    var performed: [Action] { lock.withLock { $0 } }

    func perform(_ action: Action) async -> ActionResult {
        lock.withLock { $0.append(action) }
        return result
    }
}

/// Returns scripted results per command; counts calls and tracks overlap.
final class FakeCommands: CommandRunner, @unchecked Sendable {
    struct State {
        var calls: [String: Int] = [:]
        var running: [String: Int] = [:]
        var maxConcurrent: [String: Int] = [:]
    }

    private let lock = OSAllocatedUnfairLock(initialState: State())
    let handler: @Sendable (String, Int) async -> CommandResult

    init(handler: @escaping @Sendable (String, Int) async -> CommandResult) {
        self.handler = handler
    }

    var state: State { lock.withLock { $0 } }

    func run(_ command: String, timeout: TimeInterval?) async -> CommandResult {
        let call = lock.withLock { state -> Int in
            state.calls[command, default: 0] += 1
            state.running[command, default: 0] += 1
            state.maxConcurrent[command] = max(state.maxConcurrent[command] ?? 0, state.running[command]!)
            return state.calls[command]!
        }
        let result = await handler(command, call)
        lock.withLock { $0.running[command]! -= 1 }
        return result
    }
}

let noCommands = FakeCommands { _, _ in CommandResult(exitCode: 0) }

/// Waits until `condition` holds, polling the main actor.
@MainActor
func eventually(_ condition: @MainActor () -> Bool, timeout: Duration = .seconds(3)) async {
    let deadline = ContinuousClock.now + timeout
    while !condition(), ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
}

/// German (QWERTZ) without modifiers: Y and Z swapped, no key types `[`, `]`, `;`, `'`, `\`, `/`, `=` or `` ` ``.
let germanLayout: TableKeyboardLayout = {
    var codes = TableKeyboardLayout.us.codes
    for character in "[];'\\/=`-" { codes[character] = nil }
    codes["z"] = 0x10
    codes["y"] = 0x06
    codes["-"] = 0x2C
    codes["ß"] = 0x1B
    codes["ü"] = 0x21
    codes["ö"] = 0x29
    codes["ä"] = 0x27
    codes["+"] = 0x1E
    codes["#"] = 0x2A
    return TableKeyboardLayout(name: "German", codes: codes)
}()
