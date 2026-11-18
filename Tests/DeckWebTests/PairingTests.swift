import DeckConfig
import DeckHID
import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import Testing
@testable import DeckEngine
@testable import DeckWeb

// MARK: - 5.1 SHA-256

@Test(arguments: [
    ("", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),
    ("abc", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"),
    ("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq", "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"),
])
func sha256Vectors(message: String, digest: String) {
    #expect(SHA256.hex(Array(message.utf8)) == digest)
}

@Test func sha256MillionA() {
    #expect(SHA256.hex([UInt8](repeating: 0x61, count: 1_000_000)) == "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")
}

// MARK: - 5.2 Token store

@MainActor @Test func tokenStore() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("tokens-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("streamdeck/web-clients.json")
    let scheduler = ManualScheduler()
    let store = TokenStore(url: url, scheduler: scheduler)
    let (client, token) = try store.create(name: "Phone")
    #expect(store.validate(token)?.id == client.id)
    #expect(store.validate(token + "x") == nil)
    #expect(store.validate("") == nil)

    let text = try String(contentsOf: url, encoding: .utf8)
    #expect(!text.contains(token))
    #expect(text.contains(SHA256.hex(Array(token.utf8))))
    let fileMode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
    let directoryMode = try FileManager.default.attributesOfItem(atPath: url.deletingLastPathComponent().path)[.posixPermissions] as? Int
    #expect(fileMode == 0o600)
    #expect(directoryMode == 0o700)

    let other = TokenStore(url: url, scheduler: scheduler)
    #expect(other.validate(token)?.name == "Phone")

    #expect(try store.revoke(id: client.id))
    #expect(store.validate(token) == nil)
    #expect(other.validate(token) == nil)
    #expect(try !store.revoke(id: client.id))
}

@MainActor @Test func lastUseIsWrittenAtMostHourly() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("tokens-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("web-clients.json")
    let scheduler = ManualScheduler()
    let store = TokenStore(url: url, scheduler: scheduler)
    let (client, token) = try store.create(name: "Phone")
    scheduler.advance(by: 600)
    _ = store.validate(token)
    #expect(TokenStore(url: url, scheduler: scheduler).all.first?.lastUsed == client.lastUsed)
    scheduler.advance(by: 3600)
    _ = store.validate(token)
    #expect(TokenStore(url: url, scheduler: scheduler).all.first?.lastUsed == scheduler.now)
}

@MainActor @Test func deletedFileRevokesEveryone() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("tokens-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("web-clients.json")
    let store = TokenStore(url: url, scheduler: ManualScheduler())
    let (_, token) = try store.create(name: "Phone")
    try FileManager.default.removeItem(at: url)
    #expect(store.validate(token) == nil)
}

// MARK: - 5.3 Pairing controller

@MainActor private func label(_ fixture: Fixture, _ key: Int) -> String {
    fixture.engine.keyImages[key].map { String(decoding: $0, as: UTF8.self) } ?? ""
}

@MainActor @Test func codeIsShownOnTheDeck() throws {
    let fixture = try Fixture()
    try fixture.web.pairing.start(from: "192.168.1.20")
    #expect(label(fixture, 6).contains(#"label: Optional("48")"#))
    #expect(label(fixture, 7).contains(#"label: Optional("21")"#))
    #expect(label(fixture, 8).contains(#"label: Optional("93")"#))
    #expect(label(fixture, 14).contains("Cancel"))
    #expect(!label(fixture, 0).contains("Hi"))
    #expect(fixture.log.contains("pairing requested from 192.168.1.20"))
}

@MainActor @Test func cancelOnTheDeckEndsPairing() throws {
    let fixture = try Fixture()
    try fixture.web.pairing.start(from: "a")
    fixture.engine.handle(.key(KeyEvent(key: 14, edge: .down)))
    #expect(fixture.engine.overlay == nil)
    #expect(label(fixture, 0).contains("Hi"))
    #expect(throws: PairingController.CompleteError.noCode) { try fixture.web.pairing.complete(code: "482193") }
}

@MainActor @Test func codeExpiresAfterTwoMinutes() throws {
    let fixture = try Fixture()
    try fixture.web.pairing.start(from: "a")
    fixture.scheduler.advance(by: 119)
    #expect(fixture.engine.overlay != nil)
    fixture.scheduler.advance(by: 2)
    #expect(fixture.engine.overlay == nil)
    #expect(throws: PairingController.CompleteError.noCode) { try fixture.web.pairing.complete(code: "482193") }
}

@MainActor @Test func fiveWrongEntriesKillTheCode() throws {
    let fixture = try Fixture()
    try fixture.web.pairing.start(from: "a")
    for _ in 0 ..< 5 {
        #expect(throws: PairingController.CompleteError.wrongCode) { try fixture.web.pairing.complete(code: "000000") }
    }
    #expect(throws: PairingController.CompleteError.noCode) { try fixture.web.pairing.complete(code: "482193") }
    #expect(fixture.engine.overlay == nil)
}

@MainActor @Test func tenFailuresLockOut() throws {
    let fixture = try Fixture()
    for attempt in 1 ... 10 {
        if (attempt - 1) % 5 == 0 { try fixture.web.pairing.start(from: "a") }
        let expected: PairingController.CompleteError = attempt == 10 ? .lockedOut : .wrongCode
        #expect(throws: expected) { try fixture.web.pairing.complete(code: "000000") }
    }
    #expect(throws: PairingController.StartError.lockedOut) { try fixture.web.pairing.start(from: "a") }
    #expect(fixture.log.contains { $0.contains("locked") })
    fixture.scheduler.advance(by: 601)
    try fixture.web.pairing.start(from: "a")
    try fixture.web.pairing.complete(code: "482193")
}

@MainActor @Test func pairingNeedsADevice() throws {
    let fixture = try Fixture(connected: false)
    #expect(throws: PairingController.StartError.noDevice) { try fixture.web.pairing.start(from: "a") }
}

@MainActor @Test func disconnectEndsPairing() throws {
    let fixture = try Fixture()
    try fixture.web.pairing.start(from: "a")
    fixture.engine.handle(.disconnected)
    #expect(fixture.web.pairing.code == nil)
    #expect(fixture.engine.overlay == nil)
}

// MARK: - 5.4 Auth routes

@MainActor @Test func everythingNeedsPairing() async throws {
    let fixture = try Fixture()
    try await fixture.app().test(.router) { client in
        #expect(try await client.execute(uri: "/api/state", method: .get).status == .unauthorized)
        #expect(try await client.execute(uri: "/api/state", method: .get, headers: [.cookie: "streamdeck_token=wrong"]).status == .unauthorized)
        let put = try await client.execute(uri: "/api/draft/pages/home/keys/0", method: .put, headers: headers(), body: body(#"{"label":"x"}"#))
        #expect(put.status == .unauthorized)
        #expect(try await client.execute(uri: "/", method: .get).status == .ok)
        #expect(try await client.execute(uri: "/assets/app.js", method: .get).status == .ok)
    }
    #expect(fixture.editor.draft.page(named: "home")?.keys[0]?.label == "Hi")
}

@MainActor @Test func pairingFlowSetsCookie() async throws {
    let fixture = try Fixture()
    let tokens = fixture.web.tokens
    try await fixture.app().test(.router) { client in
        #expect(try await client.execute(uri: "/api/pair/start", method: .post, headers: headers(), body: body("{}")).status == .ok)
        let wrong = try await client.execute(uri: "/api/pair", method: .post, headers: headers(), body: body(#"{"code":"111111"}"#))
        #expect(wrong.status == .badRequest)
        #expect(try jsonObject(wrong)["error"] as? String == "wrongCode")
        let paired = try await client.execute(uri: "/api/pair", method: .post, headers: headers(),
                                              body: body(#"{"code":"482 193","name":"Firefox on Android"}"#))
        #expect(paired.status == .ok)
        let setCookie = try #require(paired.headers[.setCookie])
        #expect(setCookie.hasPrefix("streamdeck_token="))
        #expect(setCookie.contains("HttpOnly"))
        #expect(setCookie.contains("SameSite=Strict"))
        #expect(setCookie.contains("Path=/"))
        let cookie = String(setCookie.split(separator: ";")[0])
        #expect(try await client.execute(uri: "/api/state", method: .get, headers: [.cookie: cookie]).status == .ok)

        let list = try await client.execute(uri: "/api/clients", method: .get, headers: [.cookie: cookie])
        let clients = try #require(try JSONSerialization.jsonObject(with: Data(list.body.readableBytesView)) as? [[String: Any]])
        #expect(clients.count == 1)
        #expect(clients[0]["name"] as? String == "Firefox on Android")
        #expect(clients[0]["current"] as? Bool == true)
        let id = try #require(clients[0]["id"] as? String)
        #expect(await tokens.all.count == 1)

        let revoke = try await client.execute(uri: "/api/clients/\(id)", method: .delete, headers: headers(cookie: cookie))
        #expect(revoke.status == .ok)
        #expect(try await client.execute(uri: "/api/state", method: .get, headers: [.cookie: cookie]).status == .unauthorized)
    }
    #expect(fixture.engine.overlay == nil)
}

@MainActor @Test func pairStartWithoutDevice() async throws {
    let fixture = try Fixture(connected: false)
    try await fixture.app().test(.router) { client in
        let response = try await client.execute(uri: "/api/pair/start", method: .post, headers: headers(), body: body("{}"))
        #expect(response.status == .conflict)
        #expect(try jsonObject(response)["error"] as? String == "noDevice")
    }
}

@MainActor @Test func logoutRevokesOwnToken() async throws {
    let fixture = try Fixture()
    let cookie = try fixture.pairedCookie()
    try await fixture.app().test(.router) { client in
        let response = try await client.execute(uri: "/api/logout", method: .post, headers: headers(cookie: cookie), body: body("{}"))
        #expect(response.status == .ok)
        #expect(response.headers[.setCookie]?.contains("Max-Age=0") == true)
        #expect(try await client.execute(uri: "/api/state", method: .get, headers: [.cookie: cookie]).status == .unauthorized)
    }
}
