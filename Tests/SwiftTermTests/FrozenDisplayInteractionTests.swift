import Foundation
import Testing
@testable import SwiftTerm

final class FrozenDisplayInteractionTests: TerminalDelegate {
    func send(source: Terminal, data: ArraySlice<UInt8>) {}

    private func terminal(scrollback: Int = 20) -> Terminal {
        let terminal = Terminal(delegate: self, options: TerminalOptions(cols: 40, rows: 5, scrollback: scrollback))
        terminal.freezesDisplayBufferDuringSynchronizedOutput = true
        terminal.synchronizedOutputTimeoutSeconds = 60
        return terminal
    }

    @Test func selectionAndLinksReadFrozenPackedCellsUntilSyncEnds() {
        let terminal = terminal()
        terminal.feed(text: "\u{1b}[?1049hsrc/中文🙂.swift:8")
        let selection = SelectionService(terminal: terminal)
        selection.selectAllContent(in: terminal.displayBuffer)
        terminal.feed(text: "\u{1b}[?2026h\u{1b}[H\u{1b}[2Ksrc/replaced.swift:9")
        #expect(selection.getSelectedText().contains("中文🙂"))
        #expect(terminal.getDisplayText(start: Position(col: 0, row: 0), end: Position(col: 40, row: 0)).contains("中文🙂"))
        #expect(terminal.getText(start: Position(col: 0, row: 0), end: Position(col: 40, row: 0)).contains("replaced"))
        // Repeated enables extend the same frozen frame, not the partial redraw.
        terminal.feed(text: "\u{1b}[?2026h")
        #expect(selection.getSelectedText().contains("中文🙂"))
        terminal.feed(text: "\u{1b}[?2026l")
        #expect(selection.getSelectedText().contains("replaced"))
        #expect(terminal.displayBuffer === terminal.buffer)
    }

    @Test func watchdogReleasesFrozenText() {
        let terminal = terminal()
        terminal.feed(text: "old\u{1b}[?2026h\rnew")
        #expect(terminal.getDisplayText(start: Position(col: 0, row: 0), end: Position(col: 40, row: 0)).contains("old"))
        terminal.synchronizedOutputWatchdogFired(generation: terminal.synchronizedOutputGeneration)
        #expect(!terminal.synchronizedOutputActive)
        #expect(terminal.getDisplayText(start: Position(col: 0, row: 0), end: Position(col: 40, row: 0)).contains("new"))
    }

    @Test func scrollbackTrimMovesSelectionOnlyWhenFrameIsReleased() {
        for watchdog in [false, true] {
            let terminal = terminal(scrollback: 2)
            terminal.feed(text: "0\r\n1\r\n2\r\n3\r\n4\r\n5\r\n6")
            let selection = SelectionService(terminal: terminal)
            selection.selectRows(4...4)
            terminal.feed(text: "\u{1b}[?2026h\r\n7\r\n8")
            #expect(selection.selectedRows == 4...4)
            #expect(selection.getSelectedText().trimmingCharacters(in: .whitespacesAndNewlines) == "4")
            if watchdog {
                terminal.synchronizedOutputWatchdogFired(generation: terminal.synchronizedOutputGeneration)
            } else {
                terminal.feed(text: "\u{1b}[?2026l")
            }
            #expect(selection.selectedRows == 2...2)
            #expect(selection.getSelectedText().trimmingCharacters(in: .whitespacesAndNewlines) == "4")
        }
    }

    @Test func regionScrollMovesSelectionOnlyWhenFrameIsReleased() {
        let terminal = terminal()
        terminal.feed(text: "0\r\n1\r\n2\r\n3\r\n4\u{1b}[2;5r")
        let selection = SelectionService(terminal: terminal)
        selection.selectRows(3...3)
        terminal.feed(text: "\u{1b}[?2026h\u{1b}[5;1H\n")
        #expect(selection.selectedRows == 3...3)
        #expect(selection.getSelectedText().trimmingCharacters(in: .whitespacesAndNewlines) == "3")
        terminal.feed(text: "\u{1b}[?2026l")
        #expect(selection.selectedRows == 2...2)
        #expect(selection.getSelectedText().trimmingCharacters(in: .whitespacesAndNewlines) == "3")
    }
}
