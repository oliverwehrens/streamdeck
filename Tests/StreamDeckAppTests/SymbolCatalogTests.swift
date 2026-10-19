import Foundation
import Testing
@testable import StreamDeckApp

/// Reads the real system files, so a format change in a macOS update fails here.
private func catalog() throws -> SymbolCatalog {
    try SymbolCatalog(directory: SymbolCatalog.systemDirectory)
}

@Test func systemCatalogLoads() throws {
    let catalog = try catalog()
    #expect(catalog.names.count > 3000)
    #expect(catalog.names.contains("microphone.slash.fill"))
    #expect(catalog.categories.contains { $0.key == "media" && $0.title == "Media" })
    #expect(!catalog.categories.contains { $0.key == "all" })
}

@Test func localizedVariantsAreExcluded() throws {
    let catalog = try catalog()
    #expect(!catalog.names.contains("0.circle.ar"))
    #expect(!catalog.names.contains { $0.hasSuffix(".rtl") || $0.hasSuffix(".hi") })
    #expect(catalog.names.contains("0.circle"))
}

@Test func searchMatchesNamesAndKeywords() throws {
    let catalog = try catalog()
    #expect(catalog.symbols(matching: "mic").contains("microphone.slash.fill"))
    #expect(catalog.symbols(matching: "MIC SLASH").contains("microphone.slash.fill"))
    #expect(!catalog.symbols(matching: "mic slash").contains("microphone.fill"))
    #expect(catalog.symbols(matching: "zzzz-no-such-symbol").isEmpty)
    #expect(catalog.symbols(matching: "").count == catalog.names.count)
}

@Test func categoryFilters() throws {
    let catalog = try catalog()
    let media = catalog.symbols(matching: "", category: "media")
    #expect(!media.isEmpty)
    #expect(media.count < catalog.names.count)
    #expect(media.contains("playpause.fill"))
}

@Test func oldNamesResolveAndStaySearchable() throws {
    let catalog = try catalog()
    #expect(catalog.currentName("mic.slash.fill") == "microphone.slash.fill")
    #expect(catalog.currentName("playpause.fill") == "playpause.fill")
    #expect(catalog.symbols(matching: "mic.slash.fill").contains("microphone.slash.fill"))
}

@Test func missingFilesThrow() {
    #expect(throws: (any Error).self) { try SymbolCatalog(directory: URL(fileURLWithPath: "/nonexistent")) }
}
