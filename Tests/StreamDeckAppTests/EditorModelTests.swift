import DeckConfig
import Foundation
import Testing
@testable import StreamDeckApp

private let handWritten = """
# My deck
default_page: home
pages:
  home:
    keys:
      0: { label: Hi, action: { page: media } }
  media:
    keys:
      14: { label: Back, action: { page: back } }
"""

/// An editor on a temporary config file.
@MainActor
private final class Fixture {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    var url: URL { directory.appendingPathComponent("config.yaml") }
    let model: EditorModel
    var previews: [DeckConfig] = []

    init(_ text: String = handWritten) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        model = EditorModel(configURL: directory.appendingPathComponent("config.yaml"))
        try write(text)
        model.onPreview = { [unowned self] in self.previews.append($0) }
        model.loadFromDisk()
    }

    deinit { try? FileManager.default.removeItem(at: directory) }

    func write(_ text: String) throws { try Data(text.utf8).write(to: url, options: .atomic) }
    func read() throws -> String { try String(contentsOf: url, encoding: .utf8) }

    func setLabel(_ label: String?, key: Int = 0) {
        var document = model.key(key) ?? KeyDocument()
        document.label = label
        model.setKey(key, document)
    }

    /// Waits past the validation debounce.
    func settle() async { try? await Task.sleep(for: EditorModel.validationDelay * 3) }
}

// MARK: - Loading

@MainActor @Test func opensOnDefaultPage() throws {
    let fixture = try Fixture()
    #expect(fixture.model.selectedPage == "home")
    #expect(fixture.model.draft.pages.map(\.name) == ["home", "media"])
    #expect(!fixture.model.isDirty)
    #expect(fixture.previews.count == 1)
}

@MainActor @Test func unreadableFileIsReported() throws {
    let fixture = try Fixture("default_page: home\npages: [\n")
    #expect(fixture.model.unreadable?.isEmpty == false)
    #expect(!fixture.model.canSave)
    try fixture.write(handWritten)
    fixture.model.fileChanged()
    #expect(fixture.model.unreadable == nil)
    #expect(fixture.model.draft.page(named: "home") != nil)
}

// MARK: - Draft and preview

@MainActor @Test func validEditIsPreviewedNotSaved() async throws {
    let fixture = try Fixture()
    fixture.setLabel("Term")
    #expect(fixture.model.isDirty)
    await fixture.settle()
    #expect(fixture.previews.last?.pages["home"]?.keys[0]?.label == "Term")
    #expect(try fixture.read() == handWritten)
}

@MainActor @Test func invalidEditKeepsLastValidPreview() async throws {
    let fixture = try Fixture()
    var key = try #require(fixture.model.key(0))
    key.action = ActionDocument(.keys, "cmd+")
    fixture.model.setKey(0, key)
    await fixture.settle()
    #expect(fixture.previews.count == 1)
    #expect(fixture.model.lastValid?.pages["home"]?.keys[0]?.label == "Hi")
    #expect(fixture.model.errors(page: "home", key: 0).count == 1)
    #expect(!fixture.model.canSave)
}

@MainActor @Test func unknownPageErrorIsOnTheKey() async throws {
    let fixture = try Fixture()
    fixture.model.setKey(3, KeyDocument(action: ActionDocument(.page, "nowhere")))
    await fixture.settle()
    #expect(fixture.model.errors(page: "home", key: 3).count == 1)
    #expect(fixture.model.settingsErrors.isEmpty)
}

@MainActor @Test func clearingAllFieldsClearsTheKey() throws {
    let fixture = try Fixture()
    fixture.model.setKey(0, KeyDocument())
    #expect(fixture.model.key(0) == nil)
}

@MainActor @Test func renameFollowsSelection() throws {
    let fixture = try Fixture()
    var selections: [String?] = []
    fixture.model.onSelectedPageChange = { selections.append($0) }
    try fixture.model.renamePage("home", to: "start")
    #expect(fixture.model.selectedPage == "start")
    #expect(selections == ["start"])
    #expect(fixture.model.draft.defaultPage == "start")
}

// MARK: - Save

@MainActor @Test func firstSaveOverHandWrittenFileBacksUp() throws {
    let fixture = try Fixture()
    #expect(fixture.model.saveNeedsOverwriteWarning)
    fixture.setLabel("Saved")
    try fixture.model.save(backup: true)
    #expect(try String(contentsOf: fixture.model.backupURL, encoding: .utf8) == handWritten)
    #expect(ConfigDocument.isEditorWritten(text: try fixture.read()))
    #expect(!fixture.model.isDirty)
    #expect(!fixture.model.saveNeedsOverwriteWarning)
}

@MainActor @Test func savedFileLoadsAsTheDraft() throws {
    let fixture = try Fixture()
    fixture.setLabel("Saved")
    try fixture.model.save(backup: false)
    let loaded = try ConfigLoader.load(contentsOf: fixture.url).get()
    #expect(loaded == fixture.model.lastValid)
    #expect(try ConfigDocument.read(yaml: fixture.read()).get() == fixture.model.draft)
}

@MainActor @Test func invalidDraftIsNotSaved() throws {
    let fixture = try Fixture()
    fixture.model.setKey(1, KeyDocument(background: "red"))
    try fixture.model.save(backup: false)
    #expect(try fixture.read() == handWritten)
    #expect(fixture.model.isDirty)
}

@MainActor @Test func revertDropsEdits() async throws {
    let fixture = try Fixture()
    fixture.setLabel("Draft")
    await fixture.settle()
    fixture.model.loadFromDisk()
    #expect(!fixture.model.isDirty)
    #expect(fixture.previews.last?.pages["home"]?.keys[0]?.label == "Hi")
}

// MARK: - External changes

@MainActor @Test func ownSaveIsIgnored() throws {
    let fixture = try Fixture()
    fixture.setLabel("Mine")
    try fixture.model.save(backup: false)
    fixture.setLabel("Next")
    fixture.model.fileChanged()
    #expect(fixture.model.pendingDiskDocument == nil)
    #expect(fixture.model.key(0)?.label == "Next")
}

@MainActor @Test func cleanDraftFollowsDisk() throws {
    let fixture = try Fixture()
    try fixture.write(handWritten.replacingOccurrences(of: "label: Hi", with: "label: Disk"))
    fixture.model.fileChanged()
    #expect(fixture.model.key(0)?.label == "Disk")
    #expect(!fixture.model.isDirty)
    #expect(fixture.previews.last?.pages["home"]?.keys[0]?.label == "Disk")
}

@MainActor @Test func dirtyDraftAsksAndCanKeepChanges() throws {
    let fixture = try Fixture()
    fixture.setLabel("Mine")
    try fixture.write(handWritten.replacingOccurrences(of: "label: Hi", with: "label: Disk"))
    fixture.model.fileChanged()
    #expect(fixture.model.pendingDiskDocument != nil)
    #expect(fixture.model.key(0)?.label == "Mine")
    fixture.model.resolveDiskChange(reload: false)
    #expect(fixture.model.pendingDiskDocument == nil)
    #expect(fixture.model.key(0)?.label == "Mine")
    #expect(fixture.model.isDirty)
    #expect(fixture.model.saveNeedsOverwriteWarning)
}

@MainActor @Test func dirtyDraftCanReloadFromDisk() throws {
    let fixture = try Fixture()
    fixture.setLabel("Mine")
    try fixture.write(handWritten.replacingOccurrences(of: "label: Hi", with: "label: Disk"))
    fixture.model.fileChanged()
    fixture.model.resolveDiskChange(reload: true)
    #expect(fixture.model.key(0)?.label == "Disk")
    #expect(!fixture.model.isDirty)
}

@MainActor @Test func invalidDiskFileKeepsDraft() throws {
    let fixture = try Fixture()
    fixture.setLabel("Mine")
    try fixture.write("default_page: home\npages: [\n")
    fixture.model.fileChanged()
    #expect(fixture.model.diskErrors?.isEmpty == false)
    #expect(fixture.model.key(0)?.label == "Mine")
    #expect(fixture.model.pendingDiskDocument == nil)
}
