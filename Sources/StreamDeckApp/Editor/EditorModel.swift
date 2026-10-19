import DeckConfig
import Foundation
import Observation

/// The editor's draft of the config, its validation, and saving. See the config-editor spec.
@Observable
@MainActor
final class EditorModel {
    static let validationDelay: Duration = .milliseconds(150)

    let configURL: URL
    var configDirectory: URL { configURL.deletingLastPathComponent() }
    var backupURL: URL { configURL.appendingPathExtension("bak") }

    /// The config as last read from or written to disk.
    private(set) var saved = ConfigDocument(defaultPage: "", pages: [])
    var draft = ConfigDocument(defaultPage: "", pages: []) {
        didSet { if draft != oldValue { scheduleValidation() } }
    }
    var isDirty: Bool { draft != saved }

    /// Errors in the draft, from the same loader that reads the file.
    private(set) var errors: [ConfigError] = []
    /// The last draft that passed validation; shown on the device and in the grid.
    private(set) var lastValid: DeckConfig?
    /// Set when the file cannot be opened as a document (bad YAML or unknown structure).
    private(set) var unreadable: [ConfigError]?
    /// Set when the file on disk changed to something invalid while the editor is open.
    private(set) var diskErrors: [ConfigError]?
    /// A newer file on disk, waiting for the user to choose between it and the unsaved draft.
    private(set) var pendingDiskDocument: ConfigDocument?

    var selectedPage: String? {
        didSet { if selectedPage != oldValue { onSelectedPageChange?(selectedPage) } }
    }
    var selectedKey: Int?
    /// The sidebar shows the settings instead of a page.
    var showsSettings = false

    @ObservationIgnored var onSelectedPageChange: ((String?) -> Void)?

    /// Pushes a valid draft to the device.
    @ObservationIgnored var onPreview: ((DeckConfig) -> Void)?
    @ObservationIgnored private var validationTask: Task<Void, Never>?
    /// The text of our last save, to tell our own write apart from someone else's.
    @ObservationIgnored private var lastWrittenText: String?

    init(configURL: URL) {
        self.configURL = configURL
    }

    // MARK: - Loading

    /// Reads the file into a fresh draft, dropping unsaved edits.
    func loadFromDisk() {
        pendingDiskDocument = nil
        diskErrors = nil
        switch readDisk() {
        case let .success((text, document)):
            unreadable = nil
            lastWrittenText = text
            replaceDraft(with: document)
        case let .failure(failure):
            unreadable = failure.errors
        }
    }

    private func replaceDraft(with document: ConfigDocument) {
        saved = document
        draft = document
        if selectedPage.flatMap(document.page(named:)) == nil {
            selectedPage = document.page(named: document.defaultPage)?.name ?? document.pages.first?.name
        }
        validateNow()
    }

    private func readDisk() -> Result<(String, ConfigDocument), ConfigErrors> {
        let text: String
        do {
            text = try String(contentsOf: configURL, encoding: .utf8)
        } catch {
            return .failure(ConfigErrors([ConfigError("cannot read \(configURL.path): \(error.localizedDescription)")]))
        }
        return ConfigDocument.read(yaml: text).map { (text, $0) }
    }

    // MARK: - Validation and preview

    private func scheduleValidation() {
        validationTask?.cancel()
        validationTask = Task { [weak self] in
            try? await Task.sleep(for: Self.validationDelay)
            guard !Task.isCancelled else { return }
            self?.validateNow()
        }
    }

    private func validateNow() {
        validationTask?.cancel()
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

    func errors(page: String, key: Int) -> [ConfigError] {
        errors.filter { $0.page == page && $0.key == key }
    }

    /// Errors on the page itself, including keys outside the grid.
    func errors(page: String) -> [ConfigError] {
        errors.filter { $0.page == page && ($0.key.map { !(0 ..< DeckConfig.keyCount).contains($0) } ?? true) }
    }

    /// Errors that belong to no page: brightness, default page, app pages, and structure.
    var settingsErrors: [ConfigError] {
        errors.filter { $0.page == nil }
    }

    // MARK: - Saving

    /// Whether saving would overwrite a file the editor did not write.
    var saveNeedsOverwriteWarning: Bool {
        guard let text = try? String(contentsOf: configURL, encoding: .utf8) else { return false }
        return !ConfigDocument.isEditorWritten(text: text)
    }

    var canSave: Bool { unreadable == nil && errors.isEmpty }

    /// Writes the draft. With `backup`, the current file is first copied to `config.yaml.bak`.
    func save(backup: Bool) throws {
        validateNow()
        guard canSave else { return }
        let text = draft.yaml()
        if backup, FileManager.default.fileExists(atPath: configURL.path) {
            try? FileManager.default.removeItem(at: backupURL)
            try FileManager.default.copyItem(at: configURL, to: backupURL)
        }
        try Data(text.utf8).write(to: configURL, options: .atomic)
        lastWrittenText = text
        saved = draft
        diskErrors = nil
        pendingDiskDocument = nil
    }

    // MARK: - External changes

    /// Called when the config file may have changed on disk.
    func fileChanged() {
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
                return
            }
            diskErrors = nil
            if document == saved { return }
            if isDirty {
                pendingDiskDocument = document
            } else {
                replaceDraft(with: document)
            }
        }
    }

    /// Answers the prompt for a newer file on disk.
    func resolveDiskChange(reload: Bool) {
        guard let document = pendingDiskDocument else { return }
        pendingDiskDocument = nil
        if reload {
            replaceDraft(with: document)
        } else {
            // Keep the draft; it now differs from the file, so it stays unsaved.
            saved = document
        }
    }

    // MARK: - Editing

    func key(_ index: Int) -> KeyDocument? {
        guard let page = selectedPage, let position = draft.pages.firstIndex(where: { $0.name == page }) else { return nil }
        return draft.pages[position].keys[index]
    }

    /// Sets or clears (nil) a key on the selected page. A key with no fields is cleared.
    func setKey(_ index: Int, _ key: KeyDocument?) {
        guard let page = selectedPage, let position = draft.pages.firstIndex(where: { $0.name == page }) else { return }
        draft.pages[position].keys[index] = key == KeyDocument() ? nil : key
    }

    func addPage(named name: String) throws(PageNameError) {
        selectedPage = try draft.addPage(named: name)
    }

    func renamePage(_ old: String, to new: String) throws(PageNameError) {
        try draft.renamePage(old, to: new)
        if selectedPage == old { selectedPage = new.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    /// Returns the references that prevent deletion, or [] when deleted.
    func deletePage(_ name: String) -> [PageReference] {
        let references = draft.deletePage(name)
        if references.isEmpty, selectedPage == name {
            selectedPage = draft.page(named: draft.defaultPage)?.name ?? draft.pages.first?.name
        }
        return references
    }
}
