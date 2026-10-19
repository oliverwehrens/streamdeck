import AppKit
import ApplicationServices
import DeckEngine
import ServiceManagement

@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let engine: DeckEngine
    private let configURL: URL
    private let reload: () -> Void
    private let editConfig: () -> Void
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private var status = DeckEngine.Status()

    init(engine: DeckEngine, configURL: URL, reload: @escaping () -> Void, editConfig: @escaping () -> Void) {
        self.engine = engine
        self.configURL = configURL
        self.reload = reload
        self.editConfig = editConfig
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        updateIcon()
    }

    func update(_ status: DeckEngine.Status) {
        self.status = status
        updateIcon()
    }

    private func updateIcon() {
        let symbol = !status.connected ? "rectangle.dashed"
            : status.problems.isEmpty ? "square.grid.3x2.fill" : "exclamationmark.triangle.fill"
        let description = !status.connected ? "Stream Deck disconnected"
            : status.problems.isEmpty ? "Stream Deck" : "Stream Deck has problems"
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)
        statusItem.button?.toolTip = description
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        if AXIsProcessTrusted(), status.problems.contains(where: { $0.source == .permission }) {
            engine.setPermissionProblem(nil)
        }
        menu.removeAllItems()

        let connection = status.connected
            ? "Connected" + (status.device.map { " — \($0.serial), firmware \($0.firmware)" } ?? "")
            : "Not connected"
        menu.addItem(info(connection))
        menu.addItem(info("Page: \(status.page ?? "–")"))
        menu.addItem(.separator())

        menu.addItem(item("Automatic Page Switching", #selector(toggleAutoSwitch), state: status.autoSwitch))
        menu.addItem(brightnessItem())

        if !status.problems.isEmpty {
            menu.addItem(.separator())
            menu.addItem(info("Problems"))
            for problem in status.problems {
                menu.addItem(problemItem(problem.message))
                if problem.source == .permission {
                    menu.addItem(item("Open Accessibility Settings…", #selector(openAccessibilitySettings)))
                }
            }
        }

        menu.addItem(.separator())
        menu.addItem(item("Edit Config…", #selector(editConfigSelected), key: ","))
        menu.addItem(item("Open Config", #selector(openConfig)))
        menu.addItem(item("Reveal Config in Finder", #selector(revealConfig)))
        menu.addItem(item("Reload Config", #selector(reloadConfig), key: "r"))
        menu.addItem(.separator())
        menu.addItem(item("Launch at Login", #selector(toggleLaunchAtLogin), state: SMAppService.mainApp.status == .enabled))
        menu.addItem(item("Quit", #selector(quit), key: "q"))
    }

    private func info(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func problemItem(_ message: String) -> NSMenuItem {
        let item = NSMenuItem(title: message, action: nil, keyEquivalent: "")
        item.attributedTitle = NSAttributedString(string: message, attributes: [
            .font: NSFont.menuFont(ofSize: 0),
            .foregroundColor: NSColor.systemRed,
        ])
        item.isEnabled = true
        return item
    }

    private func item(_ title: String, _ action: Selector, key: String = "", state: Bool? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        if let state { item.state = state ? .on : .off }
        return item
    }

    private func brightnessItem() -> NSMenuItem {
        let slider = NSSlider(value: Double(engine.effectiveBrightness), minValue: 0, maxValue: 100,
                              target: self, action: #selector(brightnessChanged(_:)))
        slider.isContinuous = true
        slider.frame = NSRect(x: 0, y: 0, width: 160, height: 22)

        let label = NSTextField(labelWithString: "Brightness")
        label.font = .menuFont(ofSize: 0)
        let stack = NSStackView(views: [label, slider])
        stack.orientation = .horizontal
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 20, bottom: 4, right: 14)
        stack.frame = NSRect(x: 0, y: 0, width: 270, height: 30)

        let item = NSMenuItem()
        item.view = stack
        return item
    }

    // MARK: - Actions

    @objc private func toggleAutoSwitch() {
        engine.setAutoSwitch(!status.autoSwitch)
    }

    @objc private func brightnessChanged(_ slider: NSSlider) {
        engine.setSessionBrightness(Int(slider.doubleValue.rounded()))
    }

    @objc private func openAccessibilitySettings() {
        // The value of kAXTrustedCheckOptionPrompt; the global itself is not concurrency-safe in Swift 6.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }

    @objc private func editConfigSelected() {
        editConfig()
    }

    @objc private func openConfig() {
        Self.openInTextEditor(configURL)
    }

    static func openInTextEditor(_ url: URL) {
        // YAML often has no default app; fall back to TextEdit.
        if NSWorkspace.shared.urlForApplication(toOpen: url) != nil {
            NSWorkspace.shared.open(url)
        } else if let textEdit = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") {
            NSWorkspace.shared.open([url], withApplicationAt: textEdit, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    @objc private func revealConfig() {
        NSWorkspace.shared.activateFileViewerSelecting([configURL])
    }

    @objc private func reloadConfig() {
        reload()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Could not change Launch at Login"
            alert.runModal()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
