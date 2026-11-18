import Testing
@testable import DeckWeb

@Test func defaultOptions() throws {
    let options = try WebOptions.parse([]).get()
    #expect(options.enabled)
    #expect(options.host == "0.0.0.0")
    #expect(options.port == 3325)
}

@Test func listenAndNoWeb() throws {
    #expect(try WebOptions.parse(["--web-listen", "127.0.0.1:4000"]).get().host == "127.0.0.1")
    #expect(try WebOptions.parse(["--web-listen", "127.0.0.1:4000"]).get().port == 4000)
    #expect(try WebOptions.parse(["--web-listen", "[::]:3325"]).get().host == "::")
    #expect(try !WebOptions.parse(["--no-web"]).get().enabled)
}

@Test(arguments: [["--bogus"], ["--web-listen"], ["--web-listen", "3325"], ["--web-listen", "host:0"], ["--web-listen", ":80"]])
func badArguments(arguments: [String]) {
    #expect(throws: UsageError.self) { try WebOptions.parse(arguments).get() }
}

@Test func loggedURLs() throws {
    let all = try WebOptions.parse([]).get()
    #expect(all.urls(hostName: "steammachine", addresses: ["192.168.1.20"]) == ["http://steammachine.local:3325/", "http://192.168.1.20:3325/"])
    let one = try WebOptions.parse(["--web-listen", "127.0.0.1:4000"]).get()
    #expect(one.urls(hostName: "x", addresses: ["10.0.0.1"]) == ["http://127.0.0.1:4000/"])
}
