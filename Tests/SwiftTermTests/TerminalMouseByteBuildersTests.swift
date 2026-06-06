import Foundation
import Testing
@testable import SwiftTerm

final class TerminalMouseByteBuildersTests {
    private let esc = "\u{1b}"

    @Test func testEventBytesMatchesSendEventForSGRMode() {
        let (terminal, delegate) = TerminalTestHarness.makeTerminal(cols: 80, rows: 24)
        terminal.feed(text: "\(esc)[?1000h\(esc)[?1006h")
        let baseline = delegate.sentData.count

        terminal.sendEvent(buttonFlags: 0, x: 4, y: 7, pixelX: 64, pixelY: 112)
        let sent = sentString(delegate, after: baseline)
        let computed = String(
            decoding: terminal.eventBytes(buttonFlags: 0, x: 4, y: 7, pixelX: 64, pixelY: 112),
            as: UTF8.self)

        #expect(sent == computed)
    }

    @Test func testEventBytesMatchesSendEventForX10Mode() {
        let (terminal, delegate) = TerminalTestHarness.makeTerminal(cols: 80, rows: 24)
        terminal.feed(text: "\(esc)[?1000h")
        let baseline = delegate.sentData.count

        terminal.sendEvent(buttonFlags: 0, x: 4, y: 7, pixelX: 64, pixelY: 112)
        let sent = sentString(delegate, after: baseline)
        let computed = String(
            decoding: terminal.eventBytes(buttonFlags: 0, x: 4, y: 7, pixelX: 64, pixelY: 112),
            as: UTF8.self)

        #expect(sent == computed)
    }

    @Test func testMouseWheelBytesUpInSGRMode() {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 80, rows: 24)
        terminal.feed(text: "\(esc)[?1000h\(esc)[?1006h")

        let bytes = terminal.mouseWheelBytes(direction: .up, x: 12, y: 5)

        #expect(String(decoding: bytes, as: UTF8.self) == "\(esc)[<64;13;6M")
    }

    @Test func testMouseWheelBytesDownInSGRMode() {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 80, rows: 24)
        terminal.feed(text: "\(esc)[?1000h\(esc)[?1006h")

        let bytes = terminal.mouseWheelBytes(direction: .down, x: 12, y: 5)

        #expect(String(decoding: bytes, as: UTF8.self) == "\(esc)[<65;13;6M")
    }

    @Test func testMouseWheelBytesClampsNegativeCoordinates() {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 80, rows: 24)
        terminal.feed(text: "\(esc)[?1000h\(esc)[?1006h")

        let bytes = terminal.mouseWheelBytes(direction: .up, x: -5, y: -2)

        #expect(String(decoding: bytes, as: UTF8.self) == "\(esc)[<64;1;1M")
    }

    @Test func testMouseWheelBytesClampsToTerminalDimensions() {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 80, rows: 24)
        terminal.feed(text: "\(esc)[?1000h\(esc)[?1006h")

        let bytes = terminal.mouseWheelBytes(direction: .down, x: 999, y: 999)

        #expect(String(decoding: bytes, as: UTF8.self) == "\(esc)[<65;80;24M")
    }

    @Test func testPrimaryClickBytesReturnsNilWhenMouseModeIsOff() {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 80, rows: 24)
        // No mouse mode enabled.

        let result = terminal.primaryClickBytes(cellX: 4, cellY: 7, pixelX: 64, pixelY: 112, control: false)

        #expect(result == nil)
    }

    @Test func testPrimaryClickBytesPressOnlyInX10Mode() {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 80, rows: 24)
        terminal.feed(text: "\(esc)[?9h")

        let result = terminal.primaryClickBytes(cellX: 4, cellY: 7, pixelX: 64, pixelY: 112, control: false)

        #expect(result != nil)
        #expect(result?.release == nil)
        #expect(result?.press.isEmpty == false)
    }

    @Test func testPrimaryClickBytesPressAndReleaseInSGRMode() {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 80, rows: 24)
        terminal.feed(text: "\(esc)[?1000h\(esc)[?1006h")

        let result = terminal.primaryClickBytes(cellX: 4, cellY: 7, pixelX: 64, pixelY: 112, control: false)

        #expect(result != nil)
        #expect(String(decoding: result!.press, as: UTF8.self) == "\(esc)[<0;5;8M")
        #expect(String(decoding: result!.release ?? [], as: UTF8.self) == "\(esc)[<0;5;8m")
    }

    @Test func testPrimaryClickBytesClampsCellCoordinates() {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 80, rows: 24)
        terminal.feed(text: "\(esc)[?1000h\(esc)[?1006h")

        let result = terminal.primaryClickBytes(cellX: -10, cellY: 999, pixelX: 0, pixelY: 0, control: false)

        #expect(String(decoding: result!.press, as: UTF8.self) == "\(esc)[<0;1;24M")
    }

    private func sentString(_ delegate: TerminalTestDelegate, after baseline: Int = 0) -> String {
        String(decoding: delegate.sentData.dropFirst(baseline).flatMap { $0 }, as: UTF8.self)
    }
}
