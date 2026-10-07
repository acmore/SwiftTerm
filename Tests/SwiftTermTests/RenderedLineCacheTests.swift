#if os(macOS)
import AppKit
import XCTest
@testable import SwiftTerm

/// The draw path shapes a row through CoreText only when its cells changed.
final class RenderedLineCacheTests: XCTestCase {
    @MainActor
    private func makeView(rows: Int = 6) -> TerminalView {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 400, height: 240))
        view.resize(cols: 20, rows: rows)
        return view
    }

    /// Distinct text on every row: rows with the same cells share one entry,
    /// so blank rows would hit each other.
    @MainActor
    private func fillRows(_ view: TerminalView) {
        view.feed(text: (0..<view.terminal.rows).map { "row \($0)" }.joined(separator: "\r\n"))
    }

    /// Draws the whole view into a bitmap and returns (hits, misses) for that draw.
    @MainActor
    private func draw(_ view: TerminalView) -> (hits: Int, misses: Int) {
        let hits = view.renderedLines.hits
        let misses = view.renderedLines.misses
        let context = CGContext(data: nil, width: 400, height: 240, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        defer { NSGraphicsContext.current = nil }
        view.drawTerminalContents(dirtyRect: view.bounds, context: context, bufferOffset: view.terminal.displayBuffer.yDisp)
        return (view.renderedLines.hits - hits, view.renderedLines.misses - misses)
    }

    @MainActor
    func testUnchangedRowsAreNotShapedAgain() {
        let view = makeView()
        fillRows(view)
        let rows = view.terminal.rows
        let first = draw(view)
        XCTAssertEqual(first.misses, rows)
        XCTAssertEqual(first.hits, 0)
        let second = draw(view)
        XCTAssertEqual(second.hits, rows)
        XCTAssertEqual(second.misses, 0)
    }

    @MainActor
    func testBlankRowsShareOneEntry() {
        let view = makeView()
        view.feed(text: "one")
        let first = draw(view)
        XCTAssertEqual(first.misses, 2, "the text row and one blank row")
        XCTAssertEqual(first.hits, view.terminal.rows - 2)
    }

    @MainActor
    func testOnlyTheChangedRowIsShaped() {
        let view = makeView()
        fillRows(view)
        _ = draw(view)
        view.feed(text: "\u{1b}[2;1Hchanged")
        let after = draw(view)
        XCTAssertEqual(after.misses, 1)
        XCTAssertEqual(after.hits, view.terminal.rows - 1)
    }

    @MainActor
    func testRowsThatScrolledStillHit() {
        let view = makeView(rows: 4)
        view.feed(text: "a\r\nb\r\nc\r\nd")
        _ = draw(view)
        view.feed(text: "\r\ne")
        let after = draw(view)
        // b, c, d moved up one row and hit; "e" and the blank last row are new.
        XCTAssertEqual(after.hits, 3)
        XCTAssertEqual(after.misses, 1)
    }

    @MainActor
    func testSynchronizedOutputSnapshotHits() {
        let view = makeView()
        view.feed(text: "one\r\ntwo")
        _ = draw(view)
        view.feed(text: "\u{1b}[?2026h")
        XCTAssertFalse(view.terminal.displayBuffer === view.terminal.buffer)
        let frame = draw(view)
        XCTAssertEqual(frame.hits, view.terminal.rows, "the snapshot's copied rows hit by content")
        view.feed(text: "\u{1b}[?2026l")
    }

    @MainActor
    func testSelectedRowsBypassTheCache() {
        let view = makeView()
        view.feed(text: "one\r\ntwo\r\nthree")
        _ = draw(view)
        view.selection.setSoftStart(row: 1, col: 0)
        view.selection.shiftExtend(row: 1, col: 2)
        let selected = draw(view)
        XCTAssertEqual(selected.hits, view.terminal.rows - 1)
        XCTAssertEqual(selected.misses, 0, "a selected row is shaped outside the cache")
        view.selection.selectNone()
        let cleared = draw(view)
        XCTAssertEqual(cleared.hits, view.terminal.rows)
    }

    @MainActor
    func testColorChangeDropsEveryRow() {
        let view = makeView()
        fillRows(view)
        _ = draw(view)
        view.colorsChanged()
        let after = draw(view)
        XCTAssertEqual(after.misses, view.terminal.rows)
        XCTAssertEqual(after.hits, 0)
    }

    @MainActor
    func testCacheStaysBounded() {
        let view = makeView(rows: 4)
        for n in 0..<40 {
            view.feed(text: "line \(n)\r\n")
            _ = draw(view)
        }
        XCTAssertLessThanOrEqual(view.renderedLines.count, 4 * 4)
    }

    func testCopiedLineHashesAndComparesEqual() {
        let line = BufferLine(cols: 8)
        line[0] = CharData(attribute: CharData.defaultAttr, code: 65, size: 1)
        line[1] = CharData(attribute: Attribute(fg: .ansi256(code: 1), bg: .defaultColor, style: .bold), code: 66, size: 1)
        let copy = BufferLine(from: line)
        var a = Hasher(), b = Hasher()
        line.hashCells(cols: 8, into: &a)
        copy.hashCells(cols: 8, into: &b)
        XCTAssertEqual(a.finalize(), b.finalize())
        XCTAssertTrue(copy.cellsEqual(line.cells(cols: 8), cols: 8))
        copy[1] = CharData(attribute: CharData.defaultAttr, code: 66, size: 1)
        XCTAssertFalse(copy.cellsEqual(line.cells(cols: 8), cols: 8), "an attribute change is a different row")
    }
}
#endif
