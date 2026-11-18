import DeckSupport
import Testing

@Test func concurrentIncrementsAddUp() async {
    let counter = Locked(initialState: 0)
    await withTaskGroup(of: Void.self) { group in
        for _ in 0 ..< 100 {
            group.addTask {
                for _ in 0 ..< 1000 { counter.withLock { $0 += 1 } }
            }
        }
    }
    #expect(counter.withLock { $0 } == 100_000)
}

@Test func withLockReturnsTheBodysResult() {
    let names = Locked(initialState: ["a"])
    let count = names.withLock { names -> Int in
        names.append("b")
        return names.count
    }
    #expect(count == 2)
}
