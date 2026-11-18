import DeckConfig
import Foundation
import Testing
@testable import DeckEditor

// Ported from Tests/StreamDeckAppTests/EditorModelTests.swift, without UI selection state.

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
    let editor: ConfigEditor
    var previews: [DeckConfig] = []
    var revisions: [Int] = []

    init(_ text: String = handWritten) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        editor = ConfigEditor(configURL: directory.appendingPathComponent("config.yaml"))
        try write(text)
        editor.onPreview = { [unowned self] in self.previews.append($0) }
        editor.onChange = { [unowned self] in self.revisions.append($0) }
        editor.loadFromDisk()
    }

    deinit { try? FileManager.default.removeItem(at: directory) }

    func write(_ text: String) throws { try Data(text.utf8).write(to: url, options: .atomic) }
    func read() throws -> String { try String(contentsOf: url, encoding: .utf8) }

    func key(_ index: Int, page: String = "home") -> KeyDocument? {
        editor.draft.page(named: page)?.keys[index]
    }

    func setLabel(_ label: String?, key index: Int = 0) {
        var document = key(index) ?? KeyDocument()
        document.label = label
        editor.setKey(page: "home", index: index, document)
    }
}

// MARK: - Loading

@MainActor @Test func loadsTheFile() throws {
    let fixture = try Fixture()
    #expect(fixture.editor.draft.pages.map(\.name) == ["home", "media"])
    #expect(!fixture.editor.isDirty)
    #expect(fixture.previews.count == 1)
}

@MainActor @Test func unreadableFileIsReported() throws {
    let fixture = try Fixture("default_page: home\npages: [\n")
    #expect(fixture.editor.unreadable?.isEmpty == false)
    #expect(!fixture.editor.canSave)
    #expect(throws: ConfigEditor.SaveError.invalid) { try fixture.editor.save(confirmOverwrite: true) }
    try fixture.write(handWritten)
    fixture.editor.fileChanged()
    #expect(fixture.editor.unreadable == nil)
    #expect(fixture.editor.draft.page(named: "home") != nil)
}

// MARK: - Draft and preview

@MainActor @Test func validEditIsPreviewedNotSaved() throws {
    let fixture = try Fixture()
    fixture.setLabel("Term")
    #expect(fixture.editor.isDirty)
    #expect(fixture.previews.last?.pages["home"]?.keys[0]?.label == "Term")
    #expect(try fixture.read() == handWritten)
}

@MainActor @Test func invalidEditKeepsLastValidPreview() throws {
    let fixture = try Fixture()
    var key = try #require(fixture.key(0))
    key.action = ActionDocument(.keys, "cmd+")
    fixture.editor.setKey(page: "home", index: 0, key)
    #expect(fixture.previews.count == 1)
    #expect(fixture.editor.lastValid?.pages["home"]?.keys[0]?.label == "Hi")
    #expect(fixture.editor.errors.filter { $0.page == "home" && $0.key == 0 }.count == 1)
    #expect(!fixture.editor.canSave)
}

@MainActor @Test func unknownPageErrorIsOnTheKey() throws {
    let fixture = try Fixture()
    fixture.editor.setKey(page: "home", index: 3, KeyDocument(action: ActionDocument(.page, "nowhere")))
    #expect(fixture.editor.errors.filter { $0.page == "home" && $0.key == 3 }.count == 1)
    #expect(fixture.editor.errors.filter { $0.page == nil }.isEmpty)
}

@MainActor @Test func clearingAllFieldsClearsTheKey() throws {
    let fixture = try Fixture()
    fixture.editor.setKey(page: "home", index: 0, KeyDocument())
    #expect(fixture.key(0) == nil)
}

@MainActor @Test func previewFiresOnlyWhenTheValidConfigChanges() throws {
    let fixture = try Fixture()
    fixture.setLabel("A")
    fixture.setLabel("A")
    fixture.editor.setKey(page: "home", index: 5, KeyDocument(background: "red"))
    #expect(fixture.previews.count == 2)
}

@MainActor @Test func everyOperationIncrementsRevisionOnce() throws {
    let fixture = try Fixture()
    let start = fixture.editor.revision
    fixture.setLabel("A")
    fixture.editor.setSettings(brightness: "50", defaultPage: "home", appPages: [])
    try fixture.editor.addPage(named: "extra")
    try fixture.editor.renamePage("extra", to: "more")
    #expect(fixture.editor.deletePage("more").isEmpty)
    #expect(fixture.editor.revision == start + 5)
    #expect(fixture.revisions.filter { $0 > start } == Array(start + 1 ... start + 5))
}

// MARK: - Pages and settings

@MainActor @Test func renameUpdatesReferences() throws {
    let fixture = try Fixture()
    try fixture.editor.renamePage("media", to: "music")
    #expect(fixture.key(0)?.action == ActionDocument(.page, "music"))
}

@MainActor @Test func deletingAReferencedPageIsRefused() throws {
    let fixture = try Fixture()
    let start = fixture.editor.revision
    #expect(fixture.editor.deletePage("media") == [.key(page: "home", index: 0)])
    #expect(fixture.editor.draft.page(named: "media") != nil)
    #expect(fixture.editor.revision == start)
}

@MainActor @Test func reservedAndTakenNames() throws {
    let fixture = try Fixture()
    #expect(throws: PageNameError.reserved) { try fixture.editor.addPage(named: "back") }
    #expect(throws: PageNameError.taken("media")) { try fixture.editor.addPage(named: " media ") }
    #expect(throws: PageNameError.empty) { try fixture.editor.renamePage("media", to: "  ") }
}

@MainActor @Test func settingsAreValidated() throws {
    let fixture = try Fixture()
    fixture.editor.setSettings(brightness: "150", defaultPage: "home", appPages: [AppPageDocument(bundleID: "steam:570", page: "media")])
    #expect(fixture.editor.draft.appPages == [AppPageDocument(bundleID: "steam:570", page: "media")])
    #expect(!fixture.editor.errors.filter { $0.page == nil }.isEmpty)
}

// MARK: - Save

@MainActor @Test func handWrittenFileNeedsConfirmation() throws {
    let fixture = try Fixture()
    fixture.setLabel("Saved")
    #expect(fixture.editor.needsOverwriteWarning)
    #expect(throws: ConfigEditor.SaveError.needsOverwriteConfirmation) { try fixture.editor.save(confirmOverwrite: false) }
    #expect(try fixture.read() == handWritten)
    #expect(!FileManager.default.fileExists(atPath: fixture.editor.backupURL.path))
    #expect(fixture.editor.isDirty)
}

@MainActor @Test func confirmedSaveBacksUp() throws {
    let fixture = try Fixture()
    fixture.setLabel("Saved")
    try fixture.editor.save(confirmOverwrite: true)
    #expect(try String(contentsOf: fixture.editor.backupURL, encoding: .utf8) == handWritten)
    #expect(ConfigDocument.isEditorWritten(text: try fixture.read()))
    #expect(!fixture.editor.isDirty)
    #expect(!fixture.editor.needsOverwriteWarning)
}

@MainActor @Test func editorWrittenFileSavesWithoutBackup() throws {
    let fixture = try Fixture()
    try fixture.editor.save(confirmOverwrite: true)
    try FileManager.default.removeItem(at: fixture.editor.backupURL)
    fixture.setLabel("Again")
    try fixture.editor.save(confirmOverwrite: false)
    #expect(!FileManager.default.fileExists(atPath: fixture.editor.backupURL.path))
}

@MainActor @Test func savedFileLoadsAsTheDraft() throws {
    let fixture = try Fixture()
    fixture.setLabel("Saved")
    try fixture.editor.save(confirmOverwrite: true)
    let loaded = try ConfigLoader.load(contentsOf: fixture.url).get()
    #expect(loaded == fixture.editor.lastValid)
    #expect(try ConfigDocument.read(yaml: fixture.read()).get() == fixture.editor.draft)
}

@MainActor @Test func invalidDraftIsNotSaved() throws {
    let fixture = try Fixture()
    fixture.editor.setKey(page: "home", index: 1, KeyDocument(background: "red"))
    #expect(throws: ConfigEditor.SaveError.invalid) { try fixture.editor.save(confirmOverwrite: true) }
    #expect(try fixture.read() == handWritten)
    #expect(fixture.editor.isDirty)
}

@MainActor @Test func revertDropsEdits() throws {
    let fixture = try Fixture()
    fixture.setLabel("Draft")
    fixture.editor.revert()
    #expect(!fixture.editor.isDirty)
    #expect(fixture.previews.last?.pages["home"]?.keys[0]?.label == "Hi")
}

// MARK: - External changes

@MainActor @Test func ownSaveIsIgnored() throws {
    let fixture = try Fixture()
    fixture.setLabel("Mine")
    try fixture.editor.save(confirmOverwrite: true)
    fixture.setLabel("Next")
    fixture.editor.fileChanged()
    #expect(fixture.editor.pendingDiskDocument == nil)
    #expect(fixture.key(0)?.label == "Next")
}

@MainActor @Test func cleanDraftFollowsDisk() throws {
    let fixture = try Fixture()
    try fixture.write(handWritten.replacingOccurrences(of: "label: Hi", with: "label: Disk"))
    fixture.editor.fileChanged()
    #expect(fixture.key(0)?.label == "Disk")
    #expect(!fixture.editor.isDirty)
    #expect(fixture.previews.last?.pages["home"]?.keys[0]?.label == "Disk")
}

@MainActor @Test func dirtyDraftAsksAndCanKeepChanges() throws {
    let fixture = try Fixture()
    fixture.setLabel("Mine")
    try fixture.write(handWritten.replacingOccurrences(of: "label: Hi", with: "label: Disk"))
    fixture.editor.fileChanged()
    #expect(fixture.editor.pendingDiskDocument != nil)
    #expect(fixture.key(0)?.label == "Mine")
    fixture.editor.resolveDiskChange(reload: false)
    #expect(fixture.editor.pendingDiskDocument == nil)
    #expect(fixture.key(0)?.label == "Mine")
    #expect(fixture.editor.isDirty)
    #expect(fixture.editor.needsOverwriteWarning)
}

@MainActor @Test func dirtyDraftCanReloadFromDisk() throws {
    let fixture = try Fixture()
    fixture.setLabel("Mine")
    try fixture.write(handWritten.replacingOccurrences(of: "label: Hi", with: "label: Disk"))
    fixture.editor.fileChanged()
    fixture.editor.resolveDiskChange(reload: true)
    #expect(fixture.key(0)?.label == "Disk")
    #expect(!fixture.editor.isDirty)
}

@MainActor @Test func invalidDiskFileKeepsDraft() throws {
    let fixture = try Fixture()
    fixture.setLabel("Mine")
    try fixture.write("default_page: home\npages: [\n")
    fixture.editor.fileChanged()
    #expect(fixture.editor.diskErrors?.isEmpty == false)
    #expect(fixture.key(0)?.label == "Mine")
    #expect(fixture.editor.pendingDiskDocument == nil)
}
