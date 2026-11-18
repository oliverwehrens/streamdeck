import DeckConfig
import DeckEditor
import Foundation
import Hummingbird
import Logging
import NIOCore

/// The web editor's HTTP server: static files, the JSON API and server-sent events. See design "API".
public enum WebServer {
    public static let defaultPort = 3325
    static let maxBodySize = 256 * 1024
    /// Ten years; the token stays valid until revoked.
    static let cookieMaxAge = 315_360_000

    /// Serves until cancelled. Throws if it cannot listen. `onListening` gets the bound port.
    public static func run(web: WebEditor, host: String, port: Int, onListening: @escaping @Sendable (Int) -> Void = { _ in }) async throws {
        var logger = Logger(label: "streamdeckd.web")
        logger.logLevel = .warning
        let app = Application(
            router: router(web: web),
            configuration: .init(address: .hostname(host, port: port), serverName: nil),
            onServerRunning: { channel in onListening(channel.localAddress?.port ?? port) },
            logger: logger
        )
        try await app.runService(gracefulShutdownSignals: [])
    }

    public static func router(web: WebEditor) -> Router<WebContext> {
        let router = Router(context: WebContext.self)
        router.add(middleware: SecurityHeadersMiddleware())
        router.add(middleware: RequestHardeningMiddleware())
        addAssets(to: router)
        addPairing(to: router.group("api/pair"), web: web)
        let api = router.group("api").add(middleware: AuthMiddleware(web: web))
        addEditor(to: api, web: web)
        addClients(to: api, web: web)
        return router
    }

    // MARK: - Static files

    private static func addAssets(to router: Router<WebContext>) {
        router.get("/") { request, _ in asset("index.html", request: request) }
        router.get("/assets/{name}") { request, context in
            asset(try context.parameters.require("name"), request: request)
        }
    }

    private static func asset(_ name: String, request: Request) -> Response {
        guard let asset = WebAssets.shared.files[name] else { return Response(status: .notFound) }
        var headers: HTTPFields = [.eTag: asset.etag, .cacheControl: "no-cache"]
        if request.headers[.ifNoneMatch] == asset.etag {
            return Response(status: .notModified, headers: headers)
        }
        headers[.contentType] = asset.contentType
        return Response(status: .ok, headers: headers, body: .init(byteBuffer: ByteBuffer(bytes: asset.bytes)))
    }

    // MARK: - Editor

    private struct NameBody: Decodable { var name: String }
    private struct SaveBody: Decodable { var confirmOverwrite: Bool? }
    private struct ReloadBody: Decodable { var reload: Bool }
    private struct PresenceBody: Decodable { var tab: String; var visible: Bool; var page: String? }
    private struct SettingsBody: Decodable {
        var brightness: String?
        var defaultPage: String
        var appPages: [AppPageJSON]
    }

    private static func addEditor(to api: RouterGroup<WebContext>, web: WebEditor) {
        api.get("state") { _, _ in await stateResponse(web) }

        api.get("events") { request, _ in
            let tab = request.uri.queryParameters["tab"].map(String.init) ?? UUID().uuidString
            let stream = await MainActor.run { web.hub.open(tab: tab) }
            return Response(status: .ok, headers: [.contentType: "text/event-stream", .cacheControl: "no-cache"],
                            body: .init(asyncSequence: stream))
        }

        api.put("draft/pages/{page}/keys/{index}") { request, context in
            let page = try pageParameter(context)
            guard let index = context.parameters.get("index", as: Int.self), (0 ..< DeckConfig.keyCount).contains(index) else {
                return error(.badRequest, "key index must be 0-\(DeckConfig.keyCount - 1)")
            }
            let key = try await decode(KeyJSON?.self, request, context)
            return await MainActor.run {
                guard web.editor.draft.page(named: page) != nil else { return error(.notFound, "no page named '\(page)'") }
                web.editor.setKey(page: page, index: index, key?.document)
                return state(web)
            }
        }

        api.put("draft/settings") { request, context in
            let body = try await decode(SettingsBody.self, request, context)
            return await MainActor.run {
                web.editor.setSettings(brightness: body.brightness, defaultPage: body.defaultPage,
                                       appPages: body.appPages.map { AppPageDocument(bundleID: $0.app, page: $0.page) })
                return state(web)
            }
        }

        api.post("draft/pages") { request, context in
            let body = try await decode(NameBody.self, request, context)
            return await MainActor.run {
                do throws(PageNameError) {
                    try web.editor.addPage(named: body.name)
                    return state(web)
                } catch {
                    return pageNameError(error)
                }
            }
        }

        api.post("draft/pages/{page}/rename") { request, context in
            let page = try pageParameter(context)
            let body = try await decode(NameBody.self, request, context)
            return await MainActor.run {
                guard web.editor.draft.page(named: page) != nil else { return error(.notFound, "no page named '\(page)'") }
                do throws(PageNameError) {
                    try web.editor.renamePage(page, to: body.name)
                    return state(web)
                } catch {
                    return pageNameError(error)
                }
            }
        }

        api.delete("draft/pages/{page}") { _, context in
            let page = try pageParameter(context)
            return await MainActor.run {
                guard web.editor.draft.page(named: page) != nil else { return error(.notFound, "no page named '\(page)'") }
                let references = web.editor.deletePage(page)
                guard references.isEmpty else {
                    return json(["references": references.map(\.description)], status: .conflict)
                }
                return state(web)
            }
        }

        api.post("save") { request, context in
            let body = try await decode(SaveBody.self, request, context)
            return await MainActor.run {
                do {
                    try web.editor.save(confirmOverwrite: body.confirmOverwrite ?? false)
                    return state(web)
                } catch ConfigEditor.SaveError.needsOverwriteConfirmation {
                    return json(["needsOverwriteConfirmation": true], status: .conflict)
                } catch ConfigEditor.SaveError.invalid {
                    return json(["errors": web.editor.errors.map(ErrorJSON.init)], status: .unprocessableContent)
                } catch let failure {
                    return error(.internalServerError, "could not save: \(failure.localizedDescription)")
                }
            }
        }

        api.post("revert") { _, _ in
            await MainActor.run {
                web.editor.revert()
                return state(web)
            }
        }

        api.post("disk-change") { request, context in
            let body = try await decode(ReloadBody.self, request, context)
            return await MainActor.run {
                web.editor.resolveDiskChange(reload: body.reload)
                return state(web)
            }
        }

        api.post("presence") { request, context in
            let body = try await decode(PresenceBody.self, request, context)
            return await MainActor.run {
                web.presence.report(tab: body.tab, visible: body.visible, page: body.page)
                return state(web)
            }
        }

        api.get("symbols") { _, _ in
            symbolsResponse
        }
    }

    /// `[[name, codepoint], …]`, encoded once.
    private static let symbolsResponse: Response = {
        let body = "[" + WebAssets.symbols.map { #"["\#($0.name)",\#($0.codepoint)]"# }.joined(separator: ",") + "]"
        return Response(status: .ok, headers: [.contentType: "application/json"], body: .init(byteBuffer: ByteBuffer(string: body)))
    }()

    // MARK: - Pairing and clients

    private struct PairBody: Decodable { var code: String; var name: String? }

    private struct ClientJSON: Encodable {
        var id: String
        var name: String
        var created: Date
        var lastUsed: Date
        var current: Bool
    }

    private static func addPairing(to group: RouterGroup<WebContext>, web: WebEditor) {
        group.post("start") { _, context in
            await MainActor.run {
                do throws(PairingController.StartError) {
                    try web.pairing.start(from: context.remoteAddress)
                    return json([String: String]())
                } catch {
                    switch error {
                    case .noDevice: return Self.error(.conflict, "noDevice")
                    case .lockedOut: return Self.error(.tooManyRequests, "lockedOut")
                    }
                }
            }
        }

        group.post("") { request, context in
            let body = try await decode(PairBody.self, request, context)
            return await MainActor.run {
                do throws(PairingController.CompleteError) {
                    try web.pairing.complete(code: body.code)
                } catch {
                    switch error {
                    case .lockedOut: return Self.error(.tooManyRequests, "lockedOut")
                    case .noCode: return Self.error(.badRequest, "noCode")
                    case .wrongCode: return Self.error(.badRequest, "wrongCode")
                    }
                }
                let name = body.name.map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60)) } ?? ""
                do {
                    let (_, token) = try web.tokens.create(name: name.isEmpty ? "Browser" : name)
                    var response = json([String: String]())
                    response.setCookie(Cookie(name: AuthMiddleware.cookieName, value: token, maxAge: cookieMaxAge,
                                              path: "/", httpOnly: true, sameSite: .strict))
                    return response
                } catch let failure {
                    return error(.internalServerError, "could not store the pairing: \(failure.localizedDescription)")
                }
            }
        }
    }

    private static func addClients(to api: RouterGroup<WebContext>, web: WebEditor) {
        api.get("clients") { _, context in
            await MainActor.run {
                json(web.tokens.all.map {
                    ClientJSON(id: $0.id, name: $0.name, created: $0.created, lastUsed: $0.lastUsed, current: $0.id == context.clientID)
                })
            }
        }

        api.delete("clients/{id}") { _, context in
            let id = try context.parameters.require("id")
            return await MainActor.run {
                guard (try? web.tokens.revoke(id: id)) == true else { return error(.notFound, "no such browser") }
                return json([String: String]())
            }
        }

        api.post("logout") { _, context in
            await MainActor.run {
                if let id = context.clientID { _ = try? web.tokens.revoke(id: id) }
                var response = json([String: String]())
                response.setCookie(Cookie(name: AuthMiddleware.cookieName, value: "", maxAge: 0, path: "/",
                                          httpOnly: true, sameSite: .strict))
                return response
            }
        }
    }

    // MARK: - Helpers

    private static func pageParameter(_ context: WebContext) throws -> String {
        let raw = try context.parameters.require("page")
        return raw.removingPercentEncoding ?? raw
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ request: Request, _ context: WebContext) async throws -> T {
        let buffer = try await request.body.collect(upTo: maxBodySize)
        do {
            return try JSONDecoder().decode(type, from: Data(buffer.readableBytesView))
        } catch {
            throw HTTPError(.badRequest, message: "invalid JSON body")
        }
    }

    @MainActor
    private static func state(_ web: WebEditor) -> Response {
        Response(status: .ok, headers: [.contentType: "application/json"],
                 body: .init(byteBuffer: ByteBuffer(bytes: web.stateJSON())))
    }

    private static func stateResponse(_ web: WebEditor) async -> Response {
        await MainActor.run { state(web) }
    }

    static func json(_ value: some Encodable, status: HTTPResponse.Status = .ok) -> Response {
        Response(status: status, headers: [.contentType: "application/json"],
                 body: .init(byteBuffer: ByteBuffer(bytes: WebEditor.encode(value))))
    }

    static func error(_ status: HTTPResponse.Status, _ message: String) -> Response {
        json(["error": message], status: status)
    }

    private static func pageNameError(_ error: PageNameError) -> Response {
        switch error {
        case .empty: Self.error(.badRequest, "empty")
        case .reserved: Self.error(.badRequest, "reserved")
        case .taken: Self.error(.badRequest, "taken")
        }
    }
}
