import DeckConfig
import DeckEditor
import DeckEngine
import DeckHID
import Foundation

/// Everything the web editor's routes act on, on the main actor: the draft, the deck, presence,
/// pairing, paired browsers and the event streams.
@MainActor
public final class WebEditor {
    public let editor: ConfigEditor
    public let engine: DeckEngine
    public let presence: EditorPresence
    public let pairing: PairingController
    public let tokens: TokenStore
    public let hub: EventHub

    /// Puts `config.yaml`'s current content on the deck; called when the editor gives the deck back.
    private let showSavedConfig: () -> Void

    public init(editor: ConfigEditor, engine: DeckEngine, tokens: TokenStore, scheduler: Scheduler,
                hub: EventHub = EventHub(), log: @escaping (String) -> Void,
                makeCode: @escaping () -> String = PairingController.randomCode,
                showSavedConfig: @escaping () -> Void) {
        self.editor = editor
        self.engine = engine
        self.tokens = tokens
        self.hub = hub
        self.showSavedConfig = showSavedConfig
        presence = EditorPresence(engine: engine, scheduler: scheduler)
        pairing = PairingController(engine: engine, scheduler: scheduler, log: log, makeCode: makeCode)

        editor.onChange = { [weak self] _ in self?.broadcastState() }
        editor.onPreview = { [weak self] config in
            guard let self, self.presence.holdsDeck else { return }
            self.engine.configLoaded(config)
        }
        engine.onKeyImage = { [weak self] key, jpeg in
            self?.hub.send("key", json: Self.keyJSON(key, jpeg))
        }
        presence.onHoldChange = { [weak self] holding in
            guard let self else { return }
            if holding {
                if let config = self.editor.lastValid { self.engine.configLoaded(config) }
            } else {
                self.showSavedConfig()
            }
            self.broadcastState()
        }
        presence.onDeckKey = { [weak self] tab, key in
            self?.hub.send("deckKey", json: Data(#"{"index":\#(key)}"#.utf8), toTab: tab)
        }
        presence.onHolderChange = { [weak self] in self?.broadcastState() }
        hub.onOpen = { [weak self] id, tab in
            guard let self else { return }
            self.hub.send("state", json: self.stateJSON(), toConnection: id)
            for (key, jpeg) in self.engine.keyImages.sorted(by: { $0.key < $1.key }) {
                self.hub.send("key", json: Self.keyJSON(key, jpeg), toConnection: id)
            }
            self.presence.streamOpened(tab: tab)
        }
        hub.onClose = { [weak self] _, tab in self?.presence.streamClosed(tab: tab) }
    }

    /// Whether config file changes should go to the editor only, leaving the deck on the draft.
    public var holdsDeck: Bool { presence.holdsDeck }

    /// Call when `config.yaml` may have changed on disk.
    public func fileChanged() {
        editor.fileChanged()
    }

    /// Call with every engine status change, so browsers see problems and the device.
    public func statusChanged(_ status: DeckEngine.Status) {
        if !status.connected, pairing.code != nil { pairing.end() }
        broadcastState()
    }

    func broadcastState() {
        hub.send("state", json: stateJSON())
    }

    // MARK: - State

    func stateJSON() -> Data {
        Self.encode(StateJSON(editor: editor, status: engine.status, holder: presence.holder))
    }

    nonisolated static func encode(_ value: some Encodable) -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        // Encoding our own value types cannot fail.
        return (try? encoder.encode(value)) ?? Data("{}".utf8)
    }

    private static func keyJSON(_ key: Int, _ jpeg: Data) -> Data {
        Data(#"{"index":\#(key),"jpeg":"\#(jpeg.base64EncodedString())"}"#.utf8)
    }
}

/// The editor's full state as the browser sees it. See design "API".
struct StateJSON: Encodable {
    struct Status: Encodable {
        var connected: Bool
        var device: Device?
        var page: String?
        var problems: [ProblemJSON]
    }

    struct Device: Encodable {
        var serial: String
        var firmware: String
    }

    struct ProblemJSON: Encodable {
        var source: String
        var message: String
    }

    struct Holder: Encodable {
        var tab: String
        var page: String?
    }

    var revision: Int
    var draft: DocumentJSON
    var isDirty: Bool
    var canSave: Bool
    var errors: [ErrorJSON]
    var unreadable: [ErrorJSON]?
    var diskErrors: [ErrorJSON]?
    var pendingDisk: DocumentJSON?
    var needsOverwriteWarning: Bool
    var status: Status
    var holder: Holder?

    @MainActor
    init(editor: ConfigEditor, status: DeckEngine.Status, holder: (tab: String, page: String?)?) {
        revision = editor.revision
        draft = DocumentJSON(editor.draft)
        isDirty = editor.isDirty
        canSave = editor.canSave
        errors = editor.errors.map(ErrorJSON.init)
        unreadable = editor.unreadable?.map(ErrorJSON.init)
        diskErrors = editor.diskErrors?.map(ErrorJSON.init)
        pendingDisk = editor.pendingDiskDocument.map(DocumentJSON.init)
        needsOverwriteWarning = editor.needsOverwriteWarning
        self.status = Status(
            connected: status.connected,
            device: status.device.map { Device(serial: $0.serial, firmware: $0.firmware) },
            page: status.page,
            problems: status.problems.map { ProblemJSON(source: Self.name($0.source), message: $0.message) }
        )
        self.holder = holder.map { Holder(tab: $0.tab, page: $0.page) }
    }

    private static func name(_ source: Problem.Source) -> String {
        switch source {
        case .config: "config"
        case .device: "device"
        case .permission: "permission"
        case .web: "web"
        case .icon: "icon"
        case .action: "action"
        case .dynamic: "dynamic"
        }
    }
}
