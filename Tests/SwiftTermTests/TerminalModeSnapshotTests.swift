import Testing
@testable import SwiftTerm

final class TerminalModeSnapshotTests {
    private let esc = "\u{1b}"

    @Test func testModeSnapshotTracksAlternateBufferMouseAndBracketedPaste() {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 80, rows: 24)

        terminal.feed(text: "\(esc)[?1049h\(esc)[?1000h\(esc)[?1006h\(esc)[?2004h")

        let snapshot = terminal.modeSnapshot
        #expect(snapshot.isAlternateBuffer)
        #expect(snapshot.isMouseReportingEnabled)
        #expect(snapshot.mouseMode == .vt200)
        #expect(snapshot.mouseProtocol == .sgr)
        #expect(snapshot.isBracketedPasteEnabled)
        #expect(terminal.currentMouseProtocol == .sgr)
    }

    @Test func testModeSnapshotTracksApplicationAndCursorModes() {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 80, rows: 24)

        terminal.feed(text: "\(esc)[?1h\(esc)[?66h\(esc)[?6h\(esc)[?7l")

        let snapshot = terminal.modeSnapshot
        #expect(snapshot.isApplicationCursorEnabled)
        #expect(snapshot.isApplicationKeypadEnabled)
        #expect(snapshot.isOriginModeEnabled)
        #expect(!snapshot.isWraparoundEnabled)
    }

    @Test func testModeSnapshotTracksModeReset() {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 80, rows: 24)

        terminal.feed(text: "\(esc)[?1h\(esc)[?1l")

        #expect(!terminal.modeSnapshot.isApplicationCursorEnabled)
    }

    @Test func testInitialStateResetRestoresMouseProtocol() {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 80, rows: 24)

        terminal.feed(text: "\(esc)[?1006h")

        #expect(terminal.currentMouseProtocol == .sgr)
        #expect(terminal.modeSnapshot.mouseProtocol == .sgr)

        terminal.resetToInitialState()

        #expect(terminal.currentMouseProtocol == .x10)
        #expect(terminal.modeSnapshot.mouseProtocol == .x10)
    }
}
