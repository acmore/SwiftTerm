import Foundation
import Testing

@testable import SwiftTerm

/// Block / line / all / extend: the structured units a touch host offers so
/// long output can be selected without dragging across screens.
final class StructuredSelectionTests: TerminalDelegate {
    func send(source: Terminal, data: ArraySlice<UInt8>) {}

    private func terminal(_ lines: [String], cols: Int = 40) -> Terminal {
        let t = Terminal(delegate: self, options: TerminalOptions(cols: cols, rows: 30, scrollback: 100))
        t.feed(text: lines.joined(separator: "\r\n"))
        return t
    }

    private let agentReply = [
        "● Read(Sources/Sync.swift)",      // 0
        "  ⎿  Read 212 lines",              // 1
        "",                                 // 2
        "● Found it. The retry loop",       // 3
        "  drops the last chunk:",          // 4
        "",                                 // 5
        "  1. pending is cleared early",    // 6
        "  2. the retry sees nothing",      // 7
        "",                                 // 8
        "● Done. Tests pass.",              // 9
        "",                                 // 10
        "$ ls",                             // 11
        "README.md",                        // 12
        "Sources",                          // 13
    ]

    @Test func testBlockTakesTheWholeHangingIndentReplyAcrossBlankLines() {
        let t = terminal(agentReply)
        let s = SelectionService(terminal: t)
        #expect(s.blockRange(containing: 7, in: t.buffer) == 3...7)
        #expect(s.blockRange(containing: 3, in: t.buffer) == 3...7)
        #expect(s.blockRange(containing: 5, in: t.buffer) == 3...7)
    }

    @Test func testBlockForAToolCallIncludesItsOutput() {
        let t = terminal(agentReply)
        let s = SelectionService(terminal: t)
        #expect(s.blockRange(containing: 0, in: t.buffer) == 0...1)
    }

    @Test func testBlockFallsBackToParagraphForFlushLeftOutput() {
        let t = terminal(agentReply)
        let s = SelectionService(terminal: t)
        #expect(s.blockRange(containing: 12, in: t.buffer) == 11...13)
        #expect(s.blockRange(containing: 9, in: t.buffer) == 9...9)
    }

    @Test func testLogicalLineJoinsSoftWrappedRows() {
        let t = terminal([String(repeating: "x", count: 25) + " tail"], cols: 10)
        let s = SelectionService(terminal: t)
        #expect(s.logicalLineRange(containing: 1, in: t.buffer) == 0...2)
    }

    @Test func testSelectAllContentSkipsTrailingBlankRows() {
        let t = terminal(agentReply)
        let s = SelectionService(terminal: t)
        s.selectAllContent(in: t.buffer)
        #expect(s.selectedRows == 0...13)
    }

    @Test func testExtendGrowsFromTheAnchorInWholeRowsBothWays() {
        let t = terminal(agentReply)
        let s = SelectionService(terminal: t)
        s.selectRows(6...6)

        s.extend(toRow: 9)
        #expect(s.selectedRows == 6...9)
        #expect(s.getSelectedText().contains("● Done. Tests pass."))

        s.extend(toRow: 3)
        #expect(s.selectedRows == 3...6)

        s.extend(toRow: 6)
        #expect(s.selectedRows == 6...6)
    }

    @Test func testAnchorFollowsTrimmedLines() {
        let t = Terminal(delegate: self, options: TerminalOptions(cols: 10, rows: 3, scrollback: 2))
        t.feed(text: "a\r\nb\r\nc\r\nd\r\ne")
        let s = SelectionService(terminal: t)
        s.selectRows(3...3)
        s.shiftForTrimmedLines(2)
        s.extend(toRow: 2)
        #expect(s.selectedRows == 1...2)
    }
}
