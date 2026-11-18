import Testing
@testable import DeckRender

private let width = 72.0 - 8

@Test func shortLabelUsesLargestSize() {
    let layout = LabelLayout("Play", width: width, height: KeyRenderer.labelAreaHeight)
    #expect(layout.lines.count == 1)
    #expect(layout.size == LabelLayout.maxSize)
}

@Test func longLabelFitsInTwoLinesWithEllipsis() throws {
    let layout = LabelLayout("Deploy production environment", width: width, height: KeyRenderer.labelAreaHeight)
    #expect(layout.lines.count <= 2)
    #expect(layout.lines.allSatisfy { $0.width <= width + 0.001 })
    #expect(layout.lineHeight * Double(layout.lines.count) <= KeyRenderer.labelAreaHeight + 0.001
        || layout.size == LabelLayout.minSize)
    let last = try #require(layout.lines.last)
    #expect(!last.glyphs.isEmpty)
    #expect(last.text.hasSuffix("\u{2026}"))
}

@Test func veryLongLabelStaysInsideWidth() {
    let layout = LabelLayout(String(repeating: "Supercalifragilistic ", count: 4), width: width, height: 64)
    #expect(layout.lines.count == 2)
    #expect(layout.lines.allSatisfy { $0.width <= width + 0.001 })
    #expect(layout.lines.last?.text.hasSuffix("\u{2026}") == true)
}

@Test func twoWordsWrapAtTheSpace() {
    let layout = LabelLayout("Deploy production", width: width, height: 64)
    #expect(layout.lines.map(\.text) == ["Deploy ", "production"])
}

@Test func wordTooLongBreaksBetweenCharacters() {
    let lines = LabelLayout.wrap(Array("Supercalifragilisticexpialidocious"), width: width, font: .inter,
                                 scale: Font.inter.scale(forSize: 14))
    #expect(lines.count > 1)
    #expect(lines.joined().map { $0 } == Array("Supercalifragilisticexpialidocious"))
}

@Test func newlineBreaksTheLine() {
    let layout = LabelLayout("A\nB", width: width, height: 64)
    #expect(layout.lines.map(\.text) == ["A", "B"])
}

@Test func missingCharacterUsesFallbackGlyph() {
    let layout = LabelLayout("Party 🎉", width: width, height: 64)
    let glyphs = layout.lines.flatMap(\.glyphs).map(\.glyph)
    #expect(layout.lines.map(\.text).joined() == "Party 🎉")
    #expect(glyphs.last == 0)
    #expect(glyphs.dropLast().allSatisfy { $0 != 0 })
}
