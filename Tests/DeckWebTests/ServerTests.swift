import DeckConfig
import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import Testing
@testable import DeckWeb

// MARK: - 4.1 Assets

@MainActor @Test func indexHasSecurityHeaders() async throws {
    let fixture = try Fixture()
    try await fixture.app().test(.router) { client in
        do {
            let response = try await client.execute(uri: "/", method: .get)
            #expect(response.status == .ok)
            #expect(response.headers[.contentType] == "text/html; charset=utf-8")
            #expect(response.headers[.contentSecurityPolicy]?.contains("default-src 'self'") == true)
            #expect(response.headers[.contentSecurityPolicy]?.contains("frame-ancestors 'none'") == true)
            #expect(response.headers[.xContentTypeOptions] == "nosniff")
            #expect(response.headers[HTTPField.Name("Referrer-Policy")!] == "no-referrer")
            #expect(text(response).contains("<!doctype html>"))
        }
    }
}

@MainActor @Test func unknownAssetIsNotFound() async throws {
    let fixture = try Fixture()
    try await fixture.app().test(.router) { client in
        do {
            let response = try await client.execute(uri: "/assets/nothing.js", method: .get)
            #expect(response.status == .notFound)
            #expect(response.headers[.contentSecurityPolicy] != nil)
        }
    }
}

@MainActor @Test func etagGivesNotModified() async throws {
    let fixture = try Fixture()
    try await fixture.app().test(.router) { client in
        let etag: String
        do {
            let response = try await client.execute(uri: "/assets/app.js", method: .get)
            #expect(response.headers[.contentType] == "text/javascript; charset=utf-8")
            #expect(response.headers[.cacheControl] == "no-cache")
            etag = try #require(response.headers[.eTag])
        }
        do {
            let response = try await client.execute(uri: "/assets/app.js", method: .get, headers: [.ifNoneMatch: etag])
            #expect(response.status == .notModified)
            #expect(response.body.readableBytes == 0)
        }
        do {
            let response = try await client.execute(uri: "/assets/material-filled.ttf", method: .get)
            #expect(response.headers[.contentType] == "font/ttf")
            #expect(response.body.readableBytes > 100_000)
        }
    }
}

@MainActor @Test func symbolsListHasCodepoints() async throws {
    let fixture = try Fixture()
    let cookie = try fixture.pairedCookie()
    try await fixture.app().test(.router) { client in
        do {
            let response = try await client.execute(uri: "/api/symbols", method: .get, headers: headers(cookie: cookie))
            let list = try #require(try JSONSerialization.jsonObject(with: Data(response.body.readableBytesView)) as? [[Any]])
            let home = try #require(list.first { $0.first as? String == "home" })
            #expect(home[1] as? Int == 0xE9B2 || home[1] as? Int == 0xE88A)
            #expect(list.count > 3000)
        }
    }
}

// MARK: - 4.2 Request hardening

@MainActor @Test func crossOriginWritesAreRefused() async throws {
    let fixture = try Fixture()
    let cookie = try fixture.pairedCookie()
    let key = body(#"{"label":"Evil"}"#)
    try await fixture.app().test(.router) { client in
        for fields in [headers(cookie: cookie, origin: "http://evil.example"), headers(cookie: cookie, origin: nil)] {
            do {
            let response = try await client.execute(uri: "/api/draft/pages/home/keys/0", method: .put, headers: fields, body: key)
                #expect(response.status == .forbidden)
            }
        }
        var form = headers(cookie: cookie, json: false)
        form[.contentType] = "application/x-www-form-urlencoded"
        do {
            let response = try await client.execute(uri: "/api/draft/pages/home/keys/0", method: .put, headers: form, body: body("label=Evil"))
            #expect(response.status == .forbidden)
        }
        let large = body(#"{"label":""# + String(repeating: "x", count: 300 * 1024) + #""}"#)
        do {
            let response = try await client.execute(uri: "/api/draft/pages/home/keys/0", method: .put, headers: headers(cookie: cookie), body: large)
            #expect(response.status == .contentTooLarge)
        }
        do {
            let response = try await client.execute(uri: "/api/draft/pages/home/keys/0", method: .put, headers: headers(cookie: cookie), body: key)
            #expect(response.status == .ok)
            #expect(response.headers[HTTPField.Name("Access-Control-Allow-Origin")!] == nil)
        }
    }
    #expect(fixture.editor.draft.page(named: "home")?.keys[0]?.label == "Evil")
}

// MARK: - 4.3 Editor routes

@MainActor @Test func setKeyReturnsState() async throws {
    let fixture = try Fixture()
    let cookie = try fixture.pairedCookie()
    let before = fixture.editor.revision
    try await fixture.app().test(.router) { client in
        do {
            let response = try await client.execute(uri: "/api/draft/pages/home/keys/0", method: .put, headers: headers(cookie: cookie),
                                 body: body(#"{"label":"Term","action":{"kind":"run","value":"true"}}"#))
            let state = try jsonObject(response)
            #expect(state["revision"] as? Int == before + 1)
            #expect(state["isDirty"] as? Bool == true)
            let draft = try #require(state["draft"] as? [String: Any])
            let pages = try #require(draft["pages"] as? [[String: Any]])
            let keys = try #require(pages.first?["keys"] as? [String: Any])
            #expect((keys["0"] as? [String: Any])?["label"] as? String == "Term")
        }
        do {
            let response = try await client.execute(uri: "/api/draft/pages/home/keys/15", method: .put, headers: headers(cookie: cookie), body: body("null"))
            #expect(response.status == .badRequest)
        }
        do {
            let response = try await client.execute(uri: "/api/draft/pages/nowhere/keys/1", method: .put, headers: headers(cookie: cookie), body: body("null"))
            #expect(response.status == .notFound)
        }
        do {
            let response = try await client.execute(uri: "/api/draft/pages/home/keys/0", method: .put, headers: headers(cookie: cookie), body: body("null"))
            #expect(response.status == .ok)
        }
    }
    #expect(fixture.editor.draft.page(named: "home")?.keys[0] == nil)
}

@MainActor @Test func pageRoutes() async throws {
    let fixture = try Fixture()
    let cookie = try fixture.pairedCookie()
    try await fixture.app().test(.router) { client in
        do {
            let response = try await client.execute(uri: "/api/draft/pages/media/rename", method: .post, headers: headers(cookie: cookie),
                                 body: body(#"{"name":"my music"}"#))
            #expect(response.status == .ok)
        }
        do {
            let response = try await client.execute(uri: "/api/draft/pages/my%20music", method: .delete, headers: headers(cookie: cookie))
            #expect(response.status == .conflict)
            #expect(try jsonObject(response)["references"] as? [String] == ["page 'home', key 0"])
        }
        do {
            let response = try await client.execute(uri: "/api/draft/pages", method: .post, headers: headers(cookie: cookie), body: body(#"{"name":"back"}"#))
            #expect(response.status == .badRequest)
            #expect(try jsonObject(response)["error"] as? String == "reserved")
        }
        do {
            let response = try await client.execute(uri: "/api/draft/pages", method: .post, headers: headers(cookie: cookie), body: body(#"{"name":"extra"}"#))
            #expect(response.status == .ok)
        }
        do {
            let response = try await client.execute(uri: "/api/draft/pages/extra", method: .delete, headers: headers(cookie: cookie))
            #expect(response.status == .ok)
        }
    }
    #expect(fixture.editor.draft.page(named: "home")?.keys[0]?.action == ActionDocument(.page, "my music"))
    #expect(fixture.editor.draft.pages.map(\.name) == ["home", "my music"])
}

@MainActor @Test func settingsRoute() async throws {
    let fixture = try Fixture()
    let cookie = try fixture.pairedCookie()
    try await fixture.app().test(.router) { client in
        do {
            let response = try await client.execute(uri: "/api/draft/settings", method: .put, headers: headers(cookie: cookie),
                                 body: body(#"{"brightness":"40","defaultPage":"media","appPages":[{"app":"steam:570","page":"home"}]}"#))
            #expect(response.status == .ok)
        }
    }
    #expect(fixture.editor.draft.brightness == "40")
    #expect(fixture.editor.draft.defaultPage == "media")
    #expect(fixture.editor.draft.appPages == [AppPageDocument(bundleID: "steam:570", page: "home")])
}

@MainActor @Test func saveRoutes() async throws {
    let fixture = try Fixture()
    let cookie = try fixture.pairedCookie()
    try await fixture.app().test(.router) { client in
        _ = try await client.execute(uri: "/api/draft/pages/home/keys/1", method: .put, headers: headers(cookie: cookie),
                                 body: body(#"{"background":"red"}"#))
        do {
            let response = try await client.execute(uri: "/api/save", method: .post, headers: headers(cookie: cookie), body: body("{}"))
            #expect(response.status == .unprocessableContent)
            #expect((try jsonObject(response)["errors"] as? [Any])?.isEmpty == false)
        }
        _ = try await client.execute(uri: "/api/draft/pages/home/keys/1", method: .put, headers: headers(cookie: cookie),
                                 body: body(#"{"label":"Saved"}"#))
        do {
            let response = try await client.execute(uri: "/api/save", method: .post, headers: headers(cookie: cookie), body: body("{}"))
            #expect(response.status == .conflict)
            #expect(try jsonObject(response)["needsOverwriteConfirmation"] as? Bool == true)
        }
        #expect(try await fixture.fileText() == handWritten)
        do {
            let response = try await client.execute(uri: "/api/save", method: .post, headers: headers(cookie: cookie),
                                 body: body(#"{"confirmOverwrite":true}"#))
            #expect(response.status == .ok)
            #expect(try jsonObject(response)["isDirty"] as? Bool == false)
        }
        let backupURL = await fixture.editor.backupURL
        #expect(try String(contentsOf: backupURL, encoding: .utf8) == handWritten)
        _ = try await client.execute(uri: "/api/draft/pages/home/keys/1", method: .put, headers: headers(cookie: cookie),
                                 body: body(#"{"label":"Draft"}"#))
        do {
            let response = try await client.execute(uri: "/api/revert", method: .post, headers: headers(cookie: cookie), body: body("{}"))
            #expect(try jsonObject(response)["isDirty"] as? Bool == false)
        }
    }
    #expect(fixture.editor.draft.page(named: "home")?.keys[1]?.label == "Saved")
}

@MainActor @Test func diskChangeRoute() async throws {
    let fixture = try Fixture()
    let cookie = try fixture.pairedCookie()
    try await fixture.app().test(.router) { client in
        _ = try await client.execute(uri: "/api/draft/pages/home/keys/0", method: .put, headers: headers(cookie: cookie),
                                 body: body(#"{"label":"Mine"}"#))
        try Data(handWritten.replacingOccurrences(of: "label: Hi", with: "label: Disk").utf8).write(to: await fixture.configURL)
        await fixture.web.fileChanged()
        do {
            let response = try await client.execute(uri: "/api/state", method: .get, headers: headers(cookie: cookie))
            #expect(try jsonObject(response)["pendingDisk"] is [String: Any])
        }
        do {
            let response = try await client.execute(uri: "/api/disk-change", method: .post, headers: headers(cookie: cookie),
                                 body: body(#"{"reload":true}"#))
            #expect(try jsonObject(response)["pendingDisk"] == nil)
        }
    }
    #expect(fixture.editor.draft.page(named: "home")?.keys[0]?.label == "Disk")
}
