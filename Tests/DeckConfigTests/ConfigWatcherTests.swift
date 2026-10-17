import Foundation
import os
import Testing
@testable import DeckConfig

private final class Recorder: Sendable {
    let updates = OSAllocatedUnfairLock<[ConfigWatcher.Update]>(initialState: [])

    var labels: [String] {
        updates.withLock { $0.compactMap { if case let .loaded(c) = $0 { c.pages["home"]?.keys[0]?.label } else { nil } } }
    }

    var failures: Int {
        updates.withLock { $0.filter { if case .failed = $0 { true } else { false } }.count }
    }

    func wait(until condition: () -> Bool) async throws {
        for _ in 0 ..< 50 where !condition() {
            try await Task.sleep(for: .milliseconds(100))
        }
    }
}

private func config(label: String) -> String {
    "default_page: home\npages:\n  home:\n    keys:\n      0: { label: \(label) }\n"
}

@Test(.timeLimit(.minutes(1)))
func reloadsValidAndKeepsLastValid() async throws {
    let dir = try temporaryDirectory()
    let url = dir.appendingPathComponent("config.yaml")
    try config(label: "A").write(to: url, atomically: false, encoding: .utf8)

    let recorder = Recorder()
    let watcher = ConfigWatcher(url: url) { update in recorder.updates.withLock { $0.append(update) } }
    watcher.start()
    defer { watcher.stop() }
    try await recorder.wait { recorder.labels == ["A"] }
    #expect(recorder.labels == ["A"])

    // Direct write.
    try await Task.sleep(for: .milliseconds(300))
    let handle = try FileHandle(forWritingTo: url)
    try handle.truncate(atOffset: 0)
    try handle.write(contentsOf: Data(config(label: "B").utf8))
    try handle.close()
    try await recorder.wait { recorder.labels.last == "B" }
    #expect(recorder.labels.last == "B")

    // Atomic save: write a temp file and rename it over the config.
    let temp = dir.appendingPathComponent(".config.yaml.tmp")
    try config(label: "C").write(to: temp, atomically: false, encoding: .utf8)
    _ = try FileManager.default.replaceItemAt(url, withItemAt: temp)
    try await recorder.wait { recorder.labels.last == "C" }
    #expect(recorder.labels.last == "C")

    // Invalid save: reported, last valid config stays.
    try "default_page: home\npages: [broken\n".write(to: url, atomically: true, encoding: .utf8)
    try await recorder.wait { recorder.failures > 0 }
    #expect(recorder.failures > 0)
    #expect(recorder.labels.last == "C")
    #expect(watcher.config?.pages["home"]?.keys[0]?.label == "C")
}

@Test func manualReloadUsesSameRules() async throws {
    let url = try temporaryDirectory().appendingPathComponent("config.yaml")
    try "pages: {}\n".write(to: url, atomically: true, encoding: .utf8)
    let recorder = Recorder()
    let watcher = ConfigWatcher(url: url) { update in recorder.updates.withLock { $0.append(update) } }
    watcher.reload()
    try await recorder.wait { recorder.failures == 1 }
    #expect(recorder.failures == 1)
    #expect(watcher.config == nil)
}
