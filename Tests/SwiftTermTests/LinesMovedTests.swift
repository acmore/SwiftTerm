import Foundation
import Testing

@testable import SwiftTerm

/// `linesMoved` fires whenever row content shifts in place, so a holder of
/// row positions (a live selection) can drop them; it stays quiet when
/// lines simply flow into scrollback, where absolute rows are stable.
final class LinesMovedTests: TerminalDelegate {
    private var moves: [ClosedRange<Int>] = []

    func send(source: Terminal, data: ArraySlice<UInt8>) {}

    func linesMoved(source: Terminal, startRow: Int, endRow: Int) {
        moves.append(startRow...endRow)
    }

    private func terminal() -> Terminal {
        moves = []
        return Terminal(delegate: self, options: TerminalOptions(cols: 20, rows: 10, scrollback: 50))
    }

    @Test func testFullScreenLinefeedIntoScrollbackIsQuiet() {
        let t = terminal()
        t.feed(text: String(repeating: "line\r\n", count: 30))
        #expect(moves.isEmpty)
    }

    @Test func testRegionScrollReportsTheRegion() {
        let t = terminal()
        t.feed(text: "\u{1b}[3;8r")          // region rows 3...8 (1-based)
        t.feed(text: "\u{1b}[8;1H\n")        // LF at the region bottom scrolls it
        #expect(moves.contains(2...7))
    }

    @Test func testScrollUpDeleteInsertAndReverseIndexReport() {
        let t = terminal()
        t.feed(text: "\u{1b}[2S")
        #expect(!moves.isEmpty)

        let t2 = terminal()
        t2.feed(text: "\u{1b}[4;1H\u{1b}[2M")   // DL at row 4
        #expect(moves.first?.lowerBound == 3)

        let t3 = terminal()
        t3.feed(text: "\u{1b}[4;1H\u{1b}[2L")   // IL at row 4
        #expect(moves.first?.lowerBound == 3)

        let t4 = terminal()
        t4.feed(text: "\u{1b}[1;1H\u{1b}M")     // RI at the top scrolls down
        #expect(!moves.isEmpty)
        _ = (t, t2, t3, t4)
    }

    @Test func testInPlaceWritesAreQuiet() {
        let t = terminal()
        t.feed(text: "\u{1b}[s\u{1b}[1;15H12:00\u{1b}[u\u{1b}[2K spinner")
        #expect(moves.isEmpty)
    }
}
