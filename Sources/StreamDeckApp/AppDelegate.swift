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
    private var observers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let configURL = ConfigFile.defaultURL
        let commands = ShellRunner()
        engine = DeckEngine(
            transport: IOKitTransport(),
            performer: SystemActionPerformer(commands: commands),
            commands: commands,
            ownBundleID: Self.bundleID,
            frontmostApp: NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        )
        menu = StatusMenuController(engine: engine, configURL: configURL, reload: { [weak self] in self?.watcher.reload() })
        engine.onStatusChange = { [weak self] status in self?.menu.update(status) }

        do {
            try ConfigFile.createStarterIfMissing(at: configURL)
        } catch {
            engine.configFailed([ConfigError("cannot create \(configURL.path): \(error.localizedDescription)")])
        }

        // DispatchQueue.main keeps updates in order; Task hops would not guarantee it.
        watcher = ConfigWatcher(url: configURL) { [weak self] update in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    switch update {
                    case let .loaded(config): self?.engine.configLoaded(config)
                    case let .failed(errors): self?.engine.configFailed(errors)
                    }
                }
            }
        }

        observeWorkspace()
        engine.start()
        watcher.start()
        menu.update(engine.status)
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
