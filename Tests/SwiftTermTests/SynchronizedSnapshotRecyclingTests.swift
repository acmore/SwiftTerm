import XCTest
@testable import SwiftTerm

final class SynchronizedSnapshotRecyclingTests: XCTestCase {
    private class Delegate: TerminalDelegate {
        func send(source: Terminal, data: ArraySlice<UInt8>) {}
    }

    func test_historySnapshotSurvivesMoreThanOneScreenOfScrolling() {
        let terminal = Terminal(delegate: Delegate(), options: TerminalOptions(cols: 20, rows: 4, scrollback: 20))
        for n in 1...40 { terminal.feed(text: "old \(n)\r\n") }
        XCTAssertTrue(terminal.buffer.lines.isFull)
        terminal.feed(text: "\u{1B}[?2026h")
        let snapshot = terminal.displayBuffer
        let before = snapshot.translateBufferLineToString(lineIndex: 4, trimRight: true)
        for n in 1...8 { terminal.feed(text: "new \(n)\r\n") }
        XCTAssertEqual(snapshot.translateBufferLineToString(lineIndex: 4, trimRight: true), before,
                       "shared history must not change until synchronized output ends")
        terminal.feed(text: "\u{1B}[?2026l")
    }

    func test_historySnapshotSurvivesRingBecomingFullDuringFrame() {
        let terminal = Terminal(delegate: Delegate(), options: TerminalOptions(cols: 20, rows: 4, scrollback: 20))
        var n = 0
        while terminal.buffer.lines.count < terminal.buffer.lines.maxLength - 1 {
            terminal.feed(text: "old \(n)\r\n")
            n += 1
        }
        XCTAssertFalse(terminal.buffer.lines.isFull)
        terminal.feed(text: "\u{1B}[?2026h")
        let snapshot = terminal.displayBuffer
        let before = snapshot.translateBufferLineToString(lineIndex: 0, trimRight: true)
        for n in 1...4 { terminal.feed(text: "new \(n)\r\n") }
        XCTAssertEqual(snapshot.translateBufferLineToString(lineIndex: 0, trimRight: true), before,
                       "growing into a full ring must not recycle a line shared with the snapshot")
        terminal.feed(text: "\u{1B}[?2026l")
    }
}
