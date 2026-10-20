import AppKit
import DeckConfig
import DeckEngine
import DeckHID

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let bundleID = Bundle.main.bundleIdentifier ?? "de.wehrens.streamdeck"

    private var engine: DeckEngine!
    private var watcher: ConfigWatcher!
    private var menu: StatusMenuController!
    private var editor: EditorWindowController!
    private var observers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let configURL = ConfigFile.defaultURL
        let commands = ShellRunner()
        engine = DeckEngine(
            transport: IOKitTransport(),
            performer: SystemActionPerformer(commands: commands),
            commands: commands,
            configDirectory: configURL.deletingLastPathComponent(),
            ownBundleID: Self.bundleID,
            frontmostApp: NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        )
        editor = EditorWindowController(model: EditorModel(configURL: configURL), engine: engine) {
            StatusMenuController.openInTextEditor(configURL)
        }
        editor.model.onPreview = { [weak self] config in self?.engine.configLoaded(config) }
        editor.onClose = { [weak self] in
            // Back to the file's config, dropping any discarded draft from the device.
            if let config = self?.watcher.config { self?.engine.configLoaded(config) }
        }
        menu = StatusMenuController(engine: engine, configURL: configURL,
                                    reload: { [weak self] in self?.watcher.reload() },
                                    editConfig: { [weak self] in self?.editor.show() })
        engine.onStatusChange = { [weak self] status in self?.menu.update(status) }

        do {
            try ConfigFile.createStarterIfMissing(at: configURL)
        } catch {
            engine.configFailed([ConfigError("cannot create \(configURL.path): \(error.localizedDescription)")])
        }

        // DispatchQueue.main keeps updates in order; Task hops would not guarantee it.
        watcher = ConfigWatcher(url: configURL) { [weak self] update in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.configUpdated(update) }
            }
        }

        NSApp.mainMenu = Self.makeMainMenu()
        observeWorkspace()
        engine.start()
        watcher.start()
        menu.update(engine.status)
    }

    /// While the editor is open it decides what the device shows (see the config-editor spec).
    private func configUpdated(_ update: ConfigWatcher.Update) {
        switch update {
        case let .loaded(config):
            if editor.isOpen { editor.model.fileChanged() } else { engine.configLoaded(config) }
        case let .failed(errors):
            engine.configFailed(errors)
            if editor.isOpen { editor.model.fileChanged() }
        }
    }

    /// Only visible while the editor window is open; gives it Close, Quit and the Edit shortcuts.
    private static func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appMenu.addItem(withTitle: "Quit StreamDeck", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(withTitle: "StreamDeck", action: nil, keyEquivalent: "").submenu = appMenu

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(withTitle: "Edit", action: nil, keyEquivalent: "").submenu = edit
        return main
    }

    func applicationWillTerminate(_ notification: Notification) {
        watcher.stop()
        engine.shutdown()
    }

    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard let bundleID = app?.bundleIdentifier else { return }
            MainActor.assumeIsolated { self?.engine.appActivated(bundleID: bundleID) }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            // The device needs a moment after wake before it accepts writes.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                MainActor.assumeIsolated { self?.engine.redrawAll() }
            }
        })
    }
}
