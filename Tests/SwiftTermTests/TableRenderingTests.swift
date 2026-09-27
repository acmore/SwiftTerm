import XCTest
@testable import SwiftTerm

final class TableRenderingTests: XCTestCase {
    func test_wideContinuationInheritsPrintedAttributes() {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 20, rows: 3)
        terminal.feed(text: "中")
        XCTAssertEqual(terminal.getCharData(col: 1, row: 0)?.attribute,
                       terminal.getCharData(col: 0, row: 0)?.attribute)
        terminal.feed(text: "\u{1b}[31;44m文")
        XCTAssertEqual(terminal.getCharData(col: 3, row: 0)?.attribute,
                       terminal.getCharData(col: 2, row: 0)?.attribute)
    }

    func test_clearingWideHeadsLeavesNoInverseBackground() {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 20, rows: 3)
        terminal.feed(text: "中文表格")
        for col in stride(from: 1, through: 7, by: 2) {
            terminal.feed(text: "\u{1b}[1;\(col)H ")
        }
        for col in 0..<8 {
            let cell = terminal.getCharData(col: col, row: 0)!
            XCTAssertEqual(cell.attribute.bg, .defaultColor, "column \(col)")
            XCTAssertEqual(cell.width, 1, "column \(col)")
        }
    }

    func test_asciiRunStartingInContinuationClearsOldHead() {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 20, rows: 3)
        terminal.feed(text: "中文AB")
        terminal.feed(text: "\u{1b}[2Gxyz")
        XCTAssertEqual(terminal.getCharData(col: 0, row: 0)?.width, 1)
        XCTAssertEqual(terminal.getCharacter(col: 0, row: 0), "\u{0}")
        XCTAssertEqual(terminal.getCharacter(col: 1, row: 0), "x")
        XCTAssertEqual(terminal.getCharacter(col: 3, row: 0), "z")
        XCTAssertEqual(terminal.getCharacter(col: 4, row: 0), "A")
    }

    func test_nonASCIIOverwriteClearsContinuationWithCurrentBackground() {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 20, rows: 3)
        terminal.feed(text: "\u{1b}[41m中\u{1b}[42m\u{1b}[1Gé")
        XCTAssertEqual(terminal.getCharacter(col: 0, row: 0), "é")
        XCTAssertEqual(terminal.getCharData(col: 1, row: 0)?.width, 1)
        XCTAssertEqual(terminal.getCharData(col: 1, row: 0)?.attribute.bg, .ansi256(code: 2))
    }

    func test_wideOverwriteAcrossTwoOldGlyphsClearsBothEdges() {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 20, rows: 3)
        terminal.feed(text: "中文\u{1b}[2G界")
        XCTAssertEqual(terminal.getCharData(col: 0, row: 0)?.width, 1)
        XCTAssertEqual(terminal.getCharacter(col: 1, row: 0), "界")
        XCTAssertEqual(terminal.getCharData(col: 2, row: 0)?.width, 0)
        XCTAssertEqual(terminal.getCharData(col: 3, row: 0)?.width, 1)
    }

    func test_clearingWideGlyphAtRightMarginDoesNotWrapOrDamageNextRow() {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 6, rows: 3)
        terminal.feed(text: "abcd中\r\nnext\u{1b}[1;5H ")
        XCTAssertEqual(terminal.getCharData(col: 5, row: 0)?.width, 1)
        XCTAssertEqual(terminal.getCharData(col: 5, row: 0)?.attribute.bg, .defaultColor)
        XCTAssertEqual(terminal.getCharacter(col: 0, row: 1), "n")
        XCTAssertEqual(terminal.buffer.x, 5)
        XCTAssertEqual(terminal.buffer.y, 0)
    }

    func test_fragmentedUTF8HasSameContinuationAndOverwriteBehavior() {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 20, rows: 3)
        for byte in "中\u{1b}[1G ".utf8 {
            terminal.feed(byteArray: [byte])
        }
        XCTAssertEqual(terminal.getCharData(col: 1, row: 0)?.width, 1)
        XCTAssertEqual(terminal.getCharData(col: 1, row: 0)?.attribute.bg, .defaultColor)
    }
}
