import DeckConfig
import DeckEditor
@testable import DeckEngine
import DeckHID
import DeckSupport
import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import NIOCore
@testable import DeckWeb

final class FakeTransport: DeckTransport, @unchecked Sendable {
    let events: AsyncStream<DeviceEvent>
    private let lock = Locked<[(key: Int, jpeg: Data)]>(initialState: [])

    init() { (events, _) = AsyncStream.makeStream(of: DeviceEvent.self) }

    var images: [(key: Int, jpeg: Data)] { lock.withLock { $0 } }
    func setImage(key: Int, jpeg: Data) { lock.withLock { $0.append((key, jpeg)) } }
    func setBrightness(_ percent: Int) {}
    func reset() {}
    func start() {}
    func stop() {}
}

struct FakePerformer: ActionPerformer {
    func perform(_ action: Action) async -> ActionResult { .succeeded }
}

struct NoCommands: CommandRunner {
    func run(_ command: String, timeout: TimeInterval?) async -> CommandResult { CommandResult(exitCode: 0) }
}

/// Draws the appearance as its description, so tests can read what a key shows.
struct FakeRenderer: KeyRendering {
    func render(_ appearance: KeyAppearance) -> RenderedKey {
        RenderedKey(jpeg: Data(String(describing: appearance).utf8))
    }
}

let handWritten = """
# Written by hand
default_page: home
pages:
  home:
    keys:
      0: { label: Hi, action: { page: media } }
  media:
    keys:
      14: { label: Back, action: { page: back } }
"""

/// A web editor over a temporary config directory and token file, with a fake deck and a manual clock.
@MainActor
final class Fixture {
    let directory: URL
    let configURL: URL
    let tokensURL: URL
    let scheduler = ManualScheduler()
    let transport = FakeTransport()
    let engine: DeckEngine
    let editor: ConfigEditor
    let web: WebEditor
    var log: [String] = []
    var shownSaved = 0
    var code = "482193"

    init(_ text: String = handWritten, connected: Bool = true, heartbeat: Duration = .seconds(15)) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("deckweb-\(UUID().uuidString)")
        configURL = directory.appendingPathComponent("config/config.yaml")
        tokensURL = directory.appendingPathComponent("state/streamdeck/web-clients.json")
        try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: configURL)
        engine = DeckEngine(transport: transport, renderer: FakeRenderer(), performer: FakePerformer(), commands: NoCommands(),
                            configDirectory: configURL.deletingLastPathComponent(), ownBundleID: "streamdeckd",
                            frontmostApp: nil, showsProblemsOnDeck: true)
        editor = ConfigEditor(configURL: configURL)
        editor.loadFromDisk()
        let tokens = TokenStore(url: tokensURL, scheduler: scheduler)
        var logLines: (String) -> Void = { _ in }
        var codeSource: () -> String = { "" }
        var showSaved: () -> Void = {}
        web = WebEditor(editor: editor, engine: engine, tokens: tokens, scheduler: scheduler, hub: EventHub(heartbeatInterval: heartbeat),
                        log: { logLines($0) }, makeCode: { codeSource() }, showSavedConfig: { showSaved() })
        logLines = { [unowned self] in self.log.append($0) }
        codeSource = { [unowned self] in self.code }
        showSaved = { [unowned self] in self.shownSaved += 1 }
        if let config = editor.lastValid { engine.configLoaded(config) }
        engine.start()
        if connected { engine.handle(.connected(DeviceInfo(serial: "S", firmware: "F"))) }
        engine.onStatusChange = { [unowned self] in self.web.statusChanged($0) }
    }

    deinit { try? FileManager.default.removeItem(at: directory) }

    func app() -> some ApplicationProtocol {
        Application(router: WebServer.router(web: web))
    }

    /// A paired browser's cookie header value.
    func pairedCookie(name: String = "Laptop") throws -> String {
        "\(AuthMiddleware.cookieName)=\(try web.tokens.create(name: name).token)"
    }

    func fileText() throws -> String { try String(contentsOf: configURL, encoding: .utf8) }
}

/// Same-origin JSON headers as the browser sends them, with an optional cookie.
func headers(cookie: String? = nil, origin: String? = "http://localhost", json: Bool = true) -> HTTPFields {
    var fields: HTTPFields = [:]
    if let origin { fields[.origin] = origin }
    if json { fields[.contentType] = "application/json" }
    if let cookie { fields[.cookie] = cookie }
    return fields
}

func body(_ text: String) -> ByteBuffer { ByteBuffer(string: text) }

func jsonObject(_ response: TestResponse) throws -> [String: Any] {
    try JSONSerialization.jsonObject(with: Data(response.body.readableBytesView)) as? [String: Any] ?? [:]
}

func text(_ response: TestResponse) -> String { String(buffer: response.body) }
