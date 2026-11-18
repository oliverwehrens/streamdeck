import DeckConfig
import DeckEditor
import DeckHID
import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import Testing
@testable import DeckEngine
@testable import DeckWeb

/// Waits until `condition` holds on the main actor.
@MainActor
func eventually(_ condition: @MainActor () -> Bool, timeout: Duration = .seconds(3)) async {
    let deadline = ContinuousClock.now + timeout
    while !condition(), ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
}

/// Parses an SSE body into (event, data) pairs; comment lines come back as ("comment", text).
func events(_ text: String) -> [(event: String, data: String)] {
    text.components(separatedBy: "\n\n").compactMap { block in
        if block.hasPrefix(":") { return ("comment", block) }
        var event = "", data = ""
        for line in block.split(separator: "\n") {
            if line.hasPrefix("event: ") { event = String(line.dropFirst(7)) }
            if line.hasPrefix("data: ") { data = String(line.dropFirst(6)) }
        }
        return event.isEmpty ? nil : (event, data)
    }
}

// MARK: - 4.4 Events

@MainActor @Test func streamSendsStateKeysAndHeartbeat() async throws {
    let fixture = try Fixture(heartbeat: .milliseconds(50))
    let cookie = try fixture.pairedCookie()
    let app = fixture.app()
    let hub = fixture.web.hub
    let editor = fixture.editor
    let body = try await app.test(.router) { client in
        async let response = client.execute(uri: "/api/events?tab=t1", method: .get, headers: headers(cookie: cookie))
        await eventually { hub.count == 1 }
        await MainActor.run { editor.setKey(page: "home", index: 3, KeyDocument(label: "New")) }
        try await Task.sleep(for: .milliseconds(150))
        await MainActor.run { hub.closeAll() }
        let finished = try await response
        #expect(finished.headers[.contentType] == "text/event-stream")
        return text(finished)
    }
    let received = events(body)
    #expect(received.first?.event == "state")
    #expect(received.filter { $0.event == "key" }.count >= 16)
    let newState = try #require(received.last { $0.event == "state" })
    let revision = try #require((try JSONSerialization.jsonObject(with: Data(newState.data.utf8)) as? [String: Any])?["revision"] as? Int)
    #expect(revision == fixture.editor.revision)
    let keyEvents = received.filter { $0.event == "key" }.map { try? JSONSerialization.jsonObject(with: Data($0.data.utf8)) as? [String: Any] }
    let lastKey3 = try #require(keyEvents.last { $0?["index"] as? Int == 3 } ?? nil)
    let jpeg = try #require(Data(base64Encoded: lastKey3["jpeg"] as? String ?? ""))
    #expect(String(decoding: jpeg, as: UTF8.self).contains("New"))
    #expect(received.contains { $0.event == "comment" && $0.data.contains("ping") })
}

@MainActor @Test func streamNeedsPairing() async throws {
    let fixture = try Fixture()
    try await fixture.app().test(.router) { client in
        let response = try await client.execute(uri: "/api/events", method: .get)
        #expect(response.status == .unauthorized)
    }
}

// MARK: - 4.5 Presence

@MainActor private func shown(_ fixture: Fixture, _ key: Int) -> String {
    fixture.engine.keyImages[key].map { String(decoding: $0, as: UTF8.self) } ?? ""
}

@MainActor @Test func firstStreamPreviewsTheDraft() throws {
    let fixture = try Fixture()
    fixture.editor.setKey(page: "home", index: 0, KeyDocument(label: "Draft"))
    #expect(shown(fixture, 0).contains("Hi"))
    let stream = fixture.web.hub.open(tab: "t1")
    defer { withExtendedLifetime(stream) {} }
    #expect(fixture.web.holdsDeck)
    #expect(shown(fixture, 0).contains("Draft"))
    fixture.editor.setKey(page: "home", index: 0, KeyDocument(label: "Live"))
    #expect(shown(fixture, 0).contains("Live"))
}

@MainActor @Test func visibleTabOwnsThePage() throws {
    let fixture = try Fixture()
    let streams = [fixture.web.hub.open(tab: "t1"), fixture.web.hub.open(tab: "t2")]
    defer { withExtendedLifetime(streams) {} }
    fixture.web.presence.report(tab: "t1", visible: true, page: "media")
    #expect(fixture.engine.editorPage == "media")
    fixture.web.presence.report(tab: "t2", visible: true, page: "home")
    #expect(fixture.engine.editorPage == "home")
    #expect(fixture.web.presence.holder?.tab == "t2")
    fixture.web.presence.report(tab: "t2", visible: false, page: "home")
    #expect(fixture.web.presence.holder?.tab == "t1")
    fixture.web.presence.report(tab: "t1", visible: false, page: "media")
    #expect(fixture.engine.editorPage == nil)
    #expect(fixture.engine.onEditorKeyPress == nil)
}

@MainActor @Test func deckKeyGoesOnlyToTheHolder() async throws {
    let fixture = try Fixture()
    let one = fixture.web.hub.open(tab: "t1")
    let two = fixture.web.hub.open(tab: "t2")
    fixture.web.presence.report(tab: "t2", visible: true, page: "home")
    fixture.engine.handle(.key(KeyEvent(key: 7, edge: .down)))
    fixture.web.hub.closeAll()
    var oneText = "", twoText = ""
    for await chunk in one { oneText += String(buffer: chunk) }
    for await chunk in two { twoText += String(buffer: chunk) }
    #expect(!oneText.contains("event: deckKey"))
    #expect(twoText.contains("event: deckKey\ndata: {\"index\":7}"))
}

@MainActor @Test func lastStreamReleasesAfterGrace() async throws {
    let fixture = try Fixture()
    fixture.editor.setKey(page: "home", index: 0, KeyDocument(label: "Draft"))
    let stream = fixture.web.hub.open(tab: "t1")
    fixture.web.presence.report(tab: "t1", visible: true, page: "media")
    fixture.web.hub.closeAll()
    for await _ in stream {}
    await eventually { fixture.web.hub.count == 0 }
    #expect(fixture.engine.editorPage == nil)
    fixture.scheduler.advance(by: 59)
    #expect(fixture.web.holdsDeck)
    #expect(fixture.shownSaved == 0)
    fixture.scheduler.advance(by: 2)
    #expect(!fixture.web.holdsDeck)
    #expect(fixture.shownSaved == 1)
}

@MainActor @Test func reconnectWithinGraceKeepsTheHold() async throws {
    let fixture = try Fixture()
    let stream = fixture.web.hub.open(tab: "t1")
    fixture.web.hub.closeAll()
    for await _ in stream {}
    await eventually { fixture.web.hub.count == 0 }
    fixture.scheduler.advance(by: 30)
    let again = fixture.web.hub.open(tab: "t1")
    defer { withExtendedLifetime(again) {} }
    fixture.scheduler.advance(by: 120)
    #expect(fixture.web.holdsDeck)
    #expect(fixture.shownSaved == 0)
}

@MainActor @Test func presenceRoute() async throws {
    let fixture = try Fixture()
    let cookie = try fixture.pairedCookie()
    let stream = fixture.web.hub.open(tab: "t1")
    defer { withExtendedLifetime(stream) {} }
    let engine = fixture.engine
    try await fixture.app().test(.router) { client in
        let response = try await client.execute(uri: "/api/presence", method: .post, headers: headers(cookie: cookie),
                                                body: body(#"{"tab":"t1","visible":true,"page":"media"}"#))
        let holder = try #require(try jsonObject(response)["holder"] as? [String: Any])
        #expect(holder["tab"] as? String == "t1")
        #expect(holder["page"] as? String == "media")
        #expect(await engine.editorPage == "media")
    }
}
