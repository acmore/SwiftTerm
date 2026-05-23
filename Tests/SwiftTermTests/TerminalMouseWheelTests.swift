import Testing
@testable import SwiftTerm

final class TerminalMouseWheelTests {
    private let esc = "\u{1b}"

    @Test func testSendMouseWheelUpUsesSGRCoordinatesWhenSGRMouseProtocolIsActive() {
        let (terminal, delegate) = TerminalTestHarness.makeTerminal(cols: 80, rows: 24)
        terminal.feed(text: "\(esc)[?1000h\(esc)[?1006h")

        terminal.sendMouseWheel(.up, x: 12, y: 5)

        #expect(sentString(delegate) == "\(esc)[<64;13;6M")
    }

    @Test func testSendMouseWheelDownUsesSGRCoordinatesWhenSGRMouseProtocolIsActive() {
        let (terminal, delegate) = TerminalTestHarness.makeTerminal(cols: 80, rows: 24)
        terminal.feed(text: "\(esc)[?1000h\(esc)[?1006h")

        terminal.sendMouseWheel(.down, x: 12, y: 5)

        #expect(sentString(delegate) == "\(esc)[<65;13;6M")
    }

    @Test func testSendMouseWheelClampsNegativeCoordinatesBeforeEncoding() {
        let (terminal, delegate) = TerminalTestHarness.makeTerminal(cols: 80, rows: 24)
        terminal.feed(text: "\(esc)[?1000h\(esc)[?1006h")

        terminal.sendMouseWheel(.up, x: -5, y: -2)

        #expect(sentString(delegate) == "\(esc)[<64;1;1M")
    }

    @Test func testSendMouseWheelClampsOversizedCoordinatesBeforeX10Encoding() {
        let (terminal, delegate) = TerminalTestHarness.makeTerminal(cols: 300, rows: 300)
        terminal.feed(text: "\(esc)[?1000h")

        terminal.sendMouseWheel(.up, x: 1_000, y: 1_000)

        #expect(sentBytes(delegate) == [0x1b, 0x5b, 0x4d, 96, 255, 255])
    }

    @Test func testSendMouseWheelUsesPixelCoordinatesWhenSGRPixelMouseProtocolIsActive() {
        let (terminal, delegate) = TerminalTestHarness.makeTerminal(cols: 80, rows: 24)
        terminal.feed(text: "\(esc)[?1000h\(esc)[?1016h")

        terminal.sendMouseWheel(.up, x: 12, y: 5, pixelX: 120, pixelY: 50)

        #expect(sentString(delegate) == "\(esc)[<64;120;50M")
    }

    private func sentString(_ delegate: TerminalTestDelegate) -> String {
        String(decoding: delegate.sentData.flatMap { $0 }, as: UTF8.self)
    }

    private func sentBytes(_ delegate: TerminalTestDelegate) -> [UInt8] {
        delegate.sentData.flatMap { $0 }
    }
}
