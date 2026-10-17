import Foundation
import Testing
@testable import DeckHID

/// Builds a 512-byte input report like the ones captured in docs/protocol.md.
private func inputReport(pressed: Set<Int>) -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: 512)
    bytes[0...3] = [0x01, 0x00, 0x0f, 0x00]
    for key in pressed { bytes[4 + key] = 1 }
    return bytes
}

@Test func decodesCapturedReport() {
    let captured: [UInt8] = [0x01, 0x00, 0x0f, 0x00, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0]
    let states = ReportCodec.keyStates(fromInputReport: captured)
    #expect(states?.enumerated().filter(\.element).map(\.offset) == [4, 7])
}

@Test func ignoresOtherReportIDs() {
    var bytes = inputReport(pressed: [0])
    bytes[0] = 0x02
    #expect(ReportCodec.keyStates(fromInputReport: bytes) == nil)
}

@Test func singleKeyPressAndRelease() throws {
    let idle = try #require(ReportCodec.keyStates(fromInputReport: inputReport(pressed: [])))
    let down = try #require(ReportCodec.keyStates(fromInputReport: inputReport(pressed: [0])))
    #expect(ReportCodec.events(from: idle, to: down) == [KeyEvent(key: 0, edge: .down)])
    #expect(ReportCodec.events(from: down, to: idle) == [KeyEvent(key: 0, edge: .up)])
}

@Test func twoKeysHeldTogether() throws {
    let idle = try #require(ReportCodec.keyStates(fromInputReport: inputReport(pressed: [])))
    let first = try #require(ReportCodec.keyStates(fromInputReport: inputReport(pressed: [3])))
    let both = try #require(ReportCodec.keyStates(fromInputReport: inputReport(pressed: [3, 7])))
    #expect(ReportCodec.events(from: idle, to: first) == [KeyEvent(key: 3, edge: .down)])
    #expect(ReportCodec.events(from: first, to: both) == [KeyEvent(key: 7, edge: .down)])
}

@Test func imageSplitsIntoPages() {
    let jpeg = Data((0 ..< 2500).map { UInt8($0 % 251) })
    let reports = ReportCodec.imageReports(key: 5, jpeg: jpeg)

    #expect(reports.count == 3)
    #expect(reports.allSatisfy { $0.count == 1024 })
    #expect(reports.map { $0[3] } == [0, 0, 1])
    #expect(reports.map { Int($0[4]) | Int($0[5]) << 8 } == [1016, 1016, 468])
    #expect(reports.map { Int($0[6]) | Int($0[7]) << 8 } == [0, 1, 2])
    #expect(reports.allSatisfy { $0[0...2] == [0x02, 0x07, 5] })

    let payload = reports.flatMap { r in r[8 ..< 8 + (Int(r[4]) | Int(r[5]) << 8)] }
    #expect(payload == [UInt8](jpeg))
}

@Test func smallImageIsSingleLastPage() {
    let reports = ReportCodec.imageReports(key: 0, jpeg: Data([1, 2, 3]))
    #expect(reports.count == 1)
    #expect(reports[0][3] == 1)
    #expect(reports[0][8 ..< 11] == [1, 2, 3])
    #expect(reports[0][11] == 0)
}

@Test(arguments: [(30, 30), (150, 100), (-5, 0)])
func brightnessClamped(input: Int, expected: Int) {
    let report = ReportCodec.brightnessReport(percent: input)
    #expect(report.count == 32)
    #expect(report[0...2] == [0x03, 0x08, UInt8(expected)])
}

@Test func parsesCapturedFeatureStrings() {
    let firmware: [UInt8] = [0x05, 0x0c, 0x91, 0x90, 0xb1, 0xe4] + Array("1.02.007".utf8) + [0, 0]
    let serial: [UInt8] = [0x06, 0x0c] + Array("AL22K2C76666".utf8) + [0, 0]
    #expect(ReportCodec.string(fromFeatureReport: firmware, offset: ReportCodec.firmwareOffset) == "1.02.007")
    #expect(ReportCodec.string(fromFeatureReport: serial, offset: ReportCodec.serialOffset) == "AL22K2C76666")
}
