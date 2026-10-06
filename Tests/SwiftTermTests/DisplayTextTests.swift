import Testing
import SwiftTerm

final class DisplayTextTests {
    private final class Delegate: TerminalDelegate {
        func send(source: Terminal, data: ArraySlice<UInt8>) {}
    }

    /// Upstream renders synchronized output (DEC 2026) from a per-frame
    /// snapshot in the view; the terminal's readers see the live buffer.
    @Test func publicReaderReadsTheLiveBuffer() {
        let terminal = Terminal(delegate: Delegate(), options: TerminalOptions(cols: 40, rows: 5))
        let start = Position(col: 0, row: 0)
        let end = Position(col: 40, row: 0)
        terminal.feed(text: "src/original.swift:8")
        #expect(terminal.getDisplayText(start: start, end: end) == "src/original.swift:8")
        terminal.feed(text: "\u{1B}[?2026h\u{1B}[H\u{1B}[2Ksrc/replaced.swift:9")
        #expect(terminal.getDisplayText(start: start, end: end) == "src/replaced.swift:9")
        terminal.feed(text: "\u{1B}[?2026l")
        #expect(terminal.getDisplayText(start: start, end: end) == "src/replaced.swift:9")
    }

    @Test func publicReaderKeepsSoftWrapsAndWideCharacters() {
        let terminal = Terminal(delegate: Delegate(), options: TerminalOptions(cols: 10, rows: 8))
        terminal.feed(text: "中🙂 src/a.swift:42\r\nnext")
        #expect(terminal.getDisplayText(start: Position(col: 0, row: 0), end: Position(col: 10, row: 2)) == "中🙂 src/a.swift:42\nnext")
        #expect(terminal.getDisplayText(start: Position(col: 0, row: 0), end: Position(col: 5, row: 0)) == "中🙂 ")
    }

    @Test func displayRowWidthTellsAFullRowFromAShortOne() {
        let terminal = Terminal(delegate: Delegate(), options: TerminalOptions(cols: 10, rows: 6))
        terminal.feed(text: "0123456789\r\nshort\r\n中文中文中\r\n")
        #expect(terminal.displayRowWidth(row: 0) == 10)
        #expect(terminal.displayRowWidth(row: 1) == 5)
        #expect(terminal.displayRowWidth(row: 2) == 10)
        #expect(terminal.displayRowWidth(row: 3) == 0)
        #expect(terminal.displayRowWidth(row: -1) == 0)
        #expect(terminal.displayRowWidth(row: 99) == 0)
    }
}
