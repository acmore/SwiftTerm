import Testing
@testable import SwiftTerm

final class SynchronizedOutputTests {
    private class TestDelegate: TerminalDelegate {
        func showCursor(source: Terminal) {}
        func hideCursor(source: Terminal) {}
        func setTerminalTitle(source: Terminal, title: String) {}
        func setTerminalIconTitle(source: Terminal, title: String) {}
        func windowCommand(source: Terminal, command: Terminal.WindowManipulationCommand) -> [UInt8]? { return nil }
        func sizeChanged(source: Terminal) {}
        func send(source: Terminal, data: ArraySlice<UInt8>) {}
        func scrolled(source: Terminal, yDisp: Int) {}
        func linefeed(source: Terminal) {}
        func bufferActivated(source: Terminal) {}
        func bell(source: Terminal) {}
    }

    private func topLineText(from buffer: Buffer, terminal: Terminal? = nil) -> String {
        let characterProvider: ((CharData) -> Character)?
        if let terminal {
            characterProvider = { terminal.getCharacter(for: $0) }
        } else {
            characterProvider = nil
        }
        return buffer.translateBufferLineToString(
            lineIndex: buffer.yDisp,
            trimRight: true,
            startCol: 0,
            endCol: -1,
            skipNullCellsFollowingWide: true,
            characterProvider: characterProvider
        ).replacingOccurrences(of: "\u{0}", with: " ")
    }

    @Test func testSynchronizedOutputBlocksDisplayUntilReset() {
        let terminal = Terminal(
            delegate: TestDelegate(),
            options: TerminalOptions(cols: 20, rows: 5, scrollback: 0)
        )
        let esc = "\u{1b}"

        terminal.feed(text: "\(esc)[2J\(esc)[HOLD")
        #expect(topLineText(from: terminal.displayBuffer).hasPrefix("OLD"))

        terminal.feed(text: "\(esc)[?2026h")
        terminal.feed(text: "\(esc)[2J\(esc)[HNEW")

        #expect(topLineText(from: terminal.displayBuffer).hasPrefix("OLD"))
        #expect(topLineText(from: terminal.buffer).hasPrefix("NEW"))

        terminal.feed(text: "\(esc)[?2026l")
        #expect(topLineText(from: terminal.displayBuffer).hasPrefix("NEW"))
    }

    /// tmux 3.7 redraws a pane as ?2026h ?25l … ?25h CUP ?2026l. When that
    /// frame arrives in two reads, the caret must not see the mid-frame hide.
    @Test func testSynchronizedOutputFreezesCursorVisibility() {
        let terminal = Terminal(
            delegate: TestDelegate(),
            options: TerminalOptions(cols: 20, rows: 5, scrollback: 0)
        )
        let esc = "\u{1b}"

        terminal.feed(text: "\(esc)[?2026h\(esc)[?25l\(esc)[HREDRAW")
        #expect(terminal.cursorHidden)
        #expect(terminal.displayCursorHidden == false, "the first read of the frame hides the cursor; the display must not")

        terminal.feed(text: "\(esc)[?25h\(esc)[3;1H\(esc)[?2026l")
        #expect(terminal.displayCursorHidden == false)

        terminal.feed(text: "\(esc)[?2026h\(esc)[?25l\(esc)[?2026l")
        #expect(terminal.displayCursorHidden, "a frame that ends hidden hides the cursor once it is released")
    }
}

final class SynchronizedOutputSnapshotTests {
    private class Delegate: TerminalDelegate {
        func send(source: Terminal, data: ArraySlice<UInt8>) {}
    }

    /// The snapshot deep-copies the screen rows and shares the history: a
    /// write during the frame must not show through, and history lines are
    /// the same objects (no per-frame copy of the scrollback).
    @Test func snapshotCopiesTheScreenAndSharesTheHistory() {
        let terminal = Terminal(delegate: Delegate(), options: TerminalOptions(cols: 20, rows: 4, scrollback: 100))
        for n in 1...30 { terminal.feed(text: "line \(n)\r\n") }
        let live = terminal.buffer
        terminal.feed(text: "\u{1B}[?2026h")
        let shown = terminal.displayBuffer
        #expect(shown !== live)
        #expect(shown.lines.count == live.lines.count)
        #expect(shown.lines[0] === live.lines[0], "history is shared")
        let screenTop = live.yBase
        #expect(shown.lines[screenTop] !== live.lines[screenTop], "screen rows are copied")
        let before = shown.translateBufferLineToString(lineIndex: screenTop, trimRight: true)
        terminal.feed(text: "\u{1B}[1;1Hchanged")
        #expect(shown.translateBufferLineToString(lineIndex: screenTop, trimRight: true) == before, "a write during the frame does not show")
        terminal.feed(text: "\u{1B}[?2026l")
        #expect(terminal.displayBuffer === live)
        #expect(live.translateBufferLineToString(lineIndex: screenTop, trimRight: true).hasPrefix("changed"))
    }
}
