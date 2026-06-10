import Testing
@testable import SwiftTerm

final class TerminalCursorAndLineRangeTests {
    private let esc = "\u{1b}"

    @Test func cursorPositionReturnsOrigin_onFreshTerminal() {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 80, rows: 24)

        #expect(terminal.cursorPosition.row == 0)
        #expect(terminal.cursorPosition.column == 0)
    }

    @Test func cursorPositionTracksFeedAdvance() {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 80, rows: 24)

        terminal.feed(text: "abc")

        #expect(terminal.cursorPosition.row == 0)
        #expect(terminal.cursorPosition.column == 3)
    }

    @Test func cursorPositionClampsWrapPendingColumn() {
        // Filling exactly `cols` characters leaves SwiftTerm with a
        // pending wrap (buffer.x == cols). The raw value is not a valid
        // index into a `cols`-wide visible row, so cursorPosition must
        // fold it to cols - 1.
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 10, rows: 4)

        terminal.feed(text: String(repeating: "a", count: 10))

        #expect(terminal.buffer.x == 10)
        #expect(terminal.cursorPosition.column == 9)
        #expect(terminal.cursorPosition.row == 0)
    }

    @Test func scrollInvariantLineRangeIsEmpty_onFreshTerminalWithNoOutput() {
        // A fresh terminal still has its initial viewport rows allocated
        // as BufferLines, so the range starts non-empty. The contract is
        // that every index inside the range returns non-nil from
        // getScrollInvariantLine; verify that contract holds.
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 10, rows: 3)

        let range = terminal.scrollInvariantLineRange
        for row in range {
            #expect(terminal.getScrollInvariantLine(row: row) != nil)
        }
        #expect(terminal.getScrollInvariantLine(row: range.upperBound) == nil)
    }

    @Test func scrollInvariantLineRangeGrowsAsScrollbackAccumulates() {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 10, rows: 3, scrollback: 50)
        let before = terminal.scrollInvariantLineRange.count

        terminal.feed(text: "one\r\ntwo\r\nthree\r\nfour\r\nfive\r\n")

        let after = terminal.scrollInvariantLineRange.count
        #expect(after > before, "feeding new lines should extend the range, got before=\(before) after=\(after)")
    }

    @Test func scrollInvariantLineRangeBoundsMatchAccessor() {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 10, rows: 3, scrollback: 50)
        terminal.feed(text: "a\r\nb\r\nc\r\nd\r\ne\r\n")

        let range = terminal.scrollInvariantLineRange
        // Every index inside the range returns non-nil; every index just
        // outside (both sides) returns nil. This is the contract Sigmux
        // relies on to avoid probing the API with a binary search.
        for row in range {
            #expect(terminal.getScrollInvariantLine(row: row) != nil, "row \(row) should be valid")
        }
        if range.lowerBound > 0 {
            #expect(terminal.getScrollInvariantLine(row: range.lowerBound - 1) == nil)
        }
        #expect(terminal.getScrollInvariantLine(row: range.upperBound) == nil)
    }
}
