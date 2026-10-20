import DeckConfig
import Foundation
import Testing
@testable import DeckEngine

private let directory = URL(fileURLWithPath: "/Users/test/.config/streamdeck")

private func parse(_ stdout: String) -> Result<DynamicOutput, DynamicOutput.Rejected> {
    DynamicOutput.parse(stdout, configDirectory: directory)
}

private func reason(_ stdout: String) -> String? {
    if case let .failure(rejected) = parse(stdout) { return rejected.reason }
    return nil
}

// MARK: - Plain text

@Test func plainTextFirstLineIsLabel() {
    #expect(parse("  12:34  \nsecond") == .success(DynamicOutput(label: "12:34")))
}

@Test func emptyOutputIsEmptyLabel() {
    #expect(parse("") == .success(DynamicOutput(label: "")))
}

// MARK: - JSON

@Test func jsonSetsAllFields() {
    #expect(parse(##"{"label":"on","icon":"sf:lightbulb.fill","background":"#c08000"}"##) == .success(DynamicOutput(
        label: "on", icon: .symbol("lightbulb.fill"), background: HexColor(red: 0xc0, green: 0x80, blue: 0))))
}

@Test func jsonOmittedFieldsStayNil() {
    #expect(parse(##"{"label":"67250","background":"#802020"}"##) == .success(DynamicOutput(
        label: "67250", background: HexColor(red: 0x80, green: 0x20, blue: 0x20))))
}

@Test func jsonAfterLeadingWhitespace() {
    #expect(parse("\n  {\"label\":\"ok\"}\n") == .success(DynamicOutput(label: "ok")))
}

@Test func jsonUnknownFieldIgnored() {
    #expect(parse(#"{"label":"ok","progress":0.5}"#) == .success(DynamicOutput(label: "ok")))
}

@Test func jsonEmptyLabelKept() {
    #expect(parse(#"{"label":""}"#) == .success(DynamicOutput(label: "")))
}

@Test func jsonRelativeIconResolvesAgainstConfigDirectory() {
    #expect(parse(#"{"icon":"icons/on.png"}"#) == .success(DynamicOutput(icon: .file("/Users/test/.config/streamdeck/icons/on.png"))))
}

@Test func jsonUnknownSymbolIsPassedToRenderer() {
    #expect(parse(#"{"icon":"sf:no.such.symbol"}"#) == .success(DynamicOutput(icon: .symbol("no.such.symbol"))))
}

// MARK: - Rejected

@Test func invalidColorRejected() {
    #expect(reason(#"{"background":"yellow"}"#) == "background 'yellow' must be #RRGGBB")
}

@Test func truncatedJSONRejected() {
    #expect(reason(#"{"label":"#) == "not valid JSON")
}

@Test func nonStringFieldRejected() {
    #expect(reason(#"{"label":67250}"#) == "label must be a string")
    #expect(reason(#"{"icon":true}"#) == "icon must be a string")
}

@Test func topLevelArrayIsPlainText() {
    // Only output starting with `{` is JSON.
    #expect(parse(#"["a"]"#) == .success(DynamicOutput(label: #"["a"]"#)))
}
