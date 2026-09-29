import Testing
import SwiftTerm

final class DisplayTextTests {
    private final class Delegate: TerminalDelegate {
        func send(source: Terminal, data: ArraySlice<UInt8>) {}
    }

    @Test func publicReaderUsesDisplayedSynchronizedFrame() {
        let terminal = Terminal(delegate: Delegate(), options: TerminalOptions(cols: 40, rows: 5))
        let start = Position(col: 0, row: 0)
        let end = Position(col: 40, row: 0)
        terminal.feed(text: "src/original.swift:8")
        terminal.feed(text: "\u{1B}[?2026h\u{1B}[H\u{1B}[2Ksrc/replaced.swift:9")
        #expect(terminal.getDisplayText(start: start, end: end) == "src/original.swift:8")
        #expect(terminal.getText(start: start, end: end) == "src/replaced.swift:9")
        terminal.feed(text: "\u{1B}[?2026l")
        #expect(terminal.getDisplayText(start: start, end: end) == "src/replaced.swift:9")
    }

    @Test func publicReaderKeepsSoftWrapsAndWideCharacters() {
        let terminal = Terminal(delegate: Delegate(), options: TerminalOptions(cols: 10, rows: 8))
        terminal.feed(text: "中🙂 src/a.swift:42\r\nnext")
        #expect(terminal.getDisplayText(start: Position(col: 0, row: 0), end: Position(col: 10, row: 2)) == "中🙂 src/a.swift:42\nnext")
        #expect(terminal.getDisplayText(start: Position(col: 0, row: 0), end: Position(col: 5, row: 0)) == "中🙂 ")
    }
}
