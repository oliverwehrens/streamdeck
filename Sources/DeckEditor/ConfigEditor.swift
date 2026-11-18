import DeckConfig
import Foundation

/// The editor's draft of the config, its validation and saving, without any UI.
/// The web editor uses it; it follows the Mac `EditorModel` (see the config-editor and web-editor specs).
@MainActor
public final class ConfigEditor {
    public enum SaveError: Error, Equatable {
        /// The file on disk was not written by the editor; saving needs `confirmOverwrite`.
        case needsOverwriteConfirmation
        /// The draft has errors or the file could not be read.
        case invalid
    }

    public let configURL: URL
    public var configDirectory: URL { configURL.deletingLastPathComponent() }
    public var backupURL: URL { configURL.appendingPathExtension("bak") }

    /// The config as last read from or written to disk.
    public private(set) var saved = ConfigDocument(defaultPage: "", pages: [])
    public private(set) var draft = ConfigDocument(defaultPage: "", pages: [])
    public var isDirty: Bool { draft != saved }

    /// Errors in the draft, from the same loader that reads the file.
    public private(set) var errors: [ConfigError] = []
    /// The last draft that passed validation; the deck previews it.
    public private(set) var lastValid: DeckConfig?
    /// Set when the file cannot be opened as a document (bad YAML or unknown structure).
    public private(set) var unreadable: [ConfigError]?
    /// Set when the file on disk changed to something invalid while editing.
    public private(set) var diskErrors: [ConfigError]?
    /// A newer file on disk, waiting for the user to choose between it and the unsaved draft.
    public private(set) var pendingDiskDocument: ConfigDocument?

    /// Increases on every change of the state above.
    public private(set) var revision = 0

    /// Called after every change, with the new revision.
    public var onChange: ((Int) -> Void)?
    /// Called when the last valid draft changes.
    public var onPreview: ((DeckConfig) -> Void)?

    /// The text of our last save or load, to tell our own write apart from someone else's.
    private var lastWrittenText: String?

    public init(configURL: URL) {
        self.configURL = configURL
    }

    public var canSave: Bool { unreadable == nil && errors.isEmpty }

    /// Whether saving would overwrite a file the editor did not write.
    public var needsOverwriteWarning: Bool {
        guard let text = try? String(contentsOf: configURL, encoding: .utf8) else { return false }
        return !ConfigDocument.isEditorWritten(text: text)
    }

    // MARK: - Loading

    /// Reads the file into a fresh draft, dropping unsaved edits.
    public func loadFromDisk() {
        pendingDiskDocument = nil
        diskErrors = nil
        switch readDisk() {
        case let .success((text, document)):
            unreadable = nil
            lastWrittenText = text
            saved = document
            draft = document
        case let .failure(failure):
            unreadable = failure.errors
        }
        changed()
    }

    /// Revert: the same as loading, named for the API.
    public func revert() { loadFromDisk() }

    private func readDisk() -> Result<(String, ConfigDocument), ConfigErrors> {
        let text: String
        do {
            text = try String(contentsOf: configURL, encoding: .utf8)
        } catch {
            return .failure(ConfigErrors([ConfigError("cannot read \(configURL.path): \(error.localizedDescription)")]))
        }
        return ConfigDocument.read(yaml: text).map { (text, $0) }
    }

    // MARK: - Editing

    /// Sets or clears (nil) a key. A key with no fields is cleared. Unknown pages are ignored.
    public func setKey(page: String, index: Int, _ key: KeyDocument?) {
        guard let position = draft.pages.firstIndex(where: { $0.name == page }) else { return }
        draft.pages[position].keys[index] = key == KeyDocument() ? nil : key
        changed()
    }

    public func setSettings(brightness: String?, defaultPage: String, appPages: [AppPageDocument]) {
        draft.brightness = brightness
        draft.defaultPage = defaultPage
        draft.appPages = appPages
        changed()
    }

    /// Returns the trimmed name the page was added under.
    @discardableResult
    public func addPage(named name: String) throws(PageNameError) -> String {
        let added = try draft.addPage(named: name)
        changed()
        return added
    }

    public func renamePage(_ old: String, to new: String) throws(PageNameError) {
        try draft.renamePage(old, to: new)
        changed()
    }

    /// Returns the references that prevent deletion, or [] when deleted.
    public func deletePage(_ name: String) -> [PageReference] {
        let references = draft.deletePage(name)
        if references.isEmpty { changed() }
        return references
    }

    // MARK: - Saving

    /// Writes the draft. A file the editor did not write needs `confirmOverwrite`, and is then
    /// copied to `config.yaml.bak` first.
    public func save(confirmOverwrite: Bool) throws {
        guard canSave else { throw SaveError.invalid }
        let backup = needsOverwriteWarning
        if backup, !confirmOverwrite { throw SaveError.needsOverwriteConfirmation }
        let text = draft.yaml()
        if backup, FileManager.default.fileExists(atPath: configURL.path) {
            try? FileManager.default.removeItem(at: backupURL)
            try FileManager.default.copyItem(at: configURL, to: backupURL)
        }
        try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: configURL, options: .atomic)
        lastWrittenText = text
        saved = draft
        diskErrors = nil
        pendingDiskDocument = nil
        changed()
    }

    // MARK: - External changes

    /// Called when the config file may have changed on disk.
    public func fileChanged() {
        guard let text = try? String(contentsOf: configURL, encoding: .utf8), text != lastWrittenText else { return }
        if unreadable != nil {
            loadFromDisk()
            return
        }
        switch ConfigDocument.read(yaml: text) {
        case let .failure(failure):
            diskErrors = failure.errors
        case let .success(document):
            lastWrittenText = text
            if case let .failure(failure) = ConfigLoader.load(yaml: text, baseDirectory: configDirectory) {
                diskErrors = failure.errors
            } else {
                diskErrors = nil
                if document != saved {
                    if isDirty {
                        pendingDiskDocument = document
                    } else {
                        saved = document
                        draft = document
                    }
                }
            }
        }
        changed()
    }

    /// Answers the question about a newer file on disk.
    public func resolveDiskChange(reload: Bool) {
        guard let document = pendingDiskDocument else { return }
        pendingDiskDocument = nil
        if reload {
            draft = document
        }
        // Keeping the draft: it now differs from the file, so it stays unsaved.
        saved = document
        changed()
    }

    // MARK: - Validation

    private func changed() {
        validate()
        revision += 1
        onChange?(revision)
    }

    private func validate() {
        guard unreadable == nil else {
            errors = []
            return
        }
        switch ConfigLoader.load(yaml: draft.yaml(), baseDirectory: configDirectory) {
        case let .success(config):
            errors = []
            if config != lastValid {
                lastValid = config
                onPreview?(config)
            }
        case let .failure(failure):
            errors = failure.errors
        }
    }
}
