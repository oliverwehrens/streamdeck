import AppKit
import DeckEngine
import SwiftUI

/// Owns the single editor window. Shows a Dock icon while it is open, and hands the device's
/// page and key presses to the editor while the window is focused.
@MainActor
final class EditorWindowController: NSObject, NSWindowDelegate {
    let model: EditorModel
    private let engine: DeckEngine
    private let openConfigFile: () -> Void
    private var window: NSWindow?
    /// Called after the window closed and the editor released the device.
    var onClose: (() -> Void)?

    var isOpen: Bool { window != nil }

    init(model: EditorModel, engine: DeckEngine, openConfigFile: @escaping () -> Void) {
        self.model = model
        self.engine = engine
        self.openConfigFile = openConfigFile
        super.init()
        model.onSelectedPageChange = { [weak self] page in
            guard let self, self.window?.isKeyWindow == true else { return }
            self.engine.editorPage = page
        }
    }

    func show() {
        if window == nil {
            model.loadFromDisk()
            window = makeWindow()
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let view = EditorView(model: model, actions: EditorActions(
            save: { [weak self] in self?.save() },
            revert: { [weak self] in self?.model.loadFromDisk() },
            openConfigFile: openConfigFile
        ))
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "Stream Deck Config"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 980, height: 640))
        window.contentMinSize = NSSize(width: 860, height: 560)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }

    // MARK: - Saving

    /// Saves, asking first when the file on disk was not written by the editor. Returns true if saved.
    @discardableResult
    func save() -> Bool {
        guard model.canSave else { return false }
        var backup = false
        if model.saveNeedsOverwriteWarning {
            let alert = NSAlert()
            alert.messageText = "Replace the hand-edited config?"
            alert.informativeText = """
            Saving rewrites config.yaml in the editor's format. Comments and formatting in the file are lost. \
            The current file is copied to config.yaml.bak first.
            """
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return false }
            backup = true
        }
        do {
            try model.save(backup: backup)
            return true
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Could not save the config"
            alert.runModal()
            return false
        }
    }

    // MARK: - NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard model.isDirty, model.unreadable == nil else { return true }
        let alert = NSAlert()
        alert.messageText = "Save changes to the config?"
        alert.informativeText = model.canSave
            ? "The deck shows your unsaved changes. Discarding them returns it to the saved config."
            : "The config has errors and cannot be saved. Discarding returns the deck to the saved config."
        if model.canSave { alert.addButton(withTitle: "Save") }
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        let offset = model.canSave ? 0 : 1
        switch response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue + offset {
        case 0: return save()
        case 1: return true
        default: return false
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        engine.editorPage = model.selectedPage
        engine.onEditorKeyPress = { [weak self] key in
            guard let model = self?.model else { return }
            model.showsSettings = false
            model.selectedKey = key
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        releaseDevice()
    }

    func windowWillClose(_ notification: Notification) {
        releaseDevice()
        window = nil
        NSApp.setActivationPolicy(.accessory)
        onClose?()
    }

    private func releaseDevice() {
        engine.onEditorKeyPress = nil
        engine.editorPage = nil
    }
}

/// What the editor view asks its window to do.
struct EditorActions {
    var save: () -> Void
    var revert: () -> Void
    var openConfigFile: () -> Void
}
