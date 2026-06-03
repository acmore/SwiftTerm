#if canImport(AppKit) || canImport(UIKit)
import XCTest
@testable import SwiftTerm

@MainActor
final class TerminalScrollIntentTests: XCTestCase {
    private let esc = "\u{1b}"

    func testNormalBufferScrollIntentMovesLocalViewportWithoutSendingRemoteBytes() {
        let delegate = CapturingTerminalViewDelegate()
        let view = TerminalView(frame: .zero)
        view.terminalDelegate = delegate
        view.resize(cols: 10, rows: 3)
        view.feed(text: "one\r\ntwo\r\nthree\r\nfour\r\nfive\r\nsix\r\n")
        let bottom = view.maxTopVisibleRow
        XCTAssertGreaterThan(bottom, 0)

        let action = view.handleScroll(lines: 2, x: 0, y: 0)

        XCTAssertEqual(action, .localViewport(lines: 2, topVisibleRow: max(0, bottom - 2)))
        XCTAssertEqual(view.topVisibleRow, max(0, bottom - 2))
        XCTAssertTrue(delegate.sentData.isEmpty)
    }

    func testMouseReportingScrollIntentSendsMouseWheelInsteadOfMovingViewport() {
        let delegate = CapturingTerminalViewDelegate()
        let view = TerminalView(frame: .zero)
        view.terminalDelegate = delegate
        view.resize(cols: 80, rows: 24)
        view.feed(text: "\(esc)[?1000h\(esc)[?1006h")

        let action = view.handleScroll(lines: 2, x: 12, y: 5)

        XCTAssertEqual(action, .mouseWheel(lines: 2))
        XCTAssertEqual(sentString(delegate), "\(esc)[<64;13;6M\(esc)[<64;13;6M")
    }

    func testAlternateBufferScrollIntentUsesCursorKeysWhenMouseReportingIsOff() {
        let delegate = CapturingTerminalViewDelegate()
        let view = TerminalView(frame: .zero)
        view.terminalDelegate = delegate
        view.resize(cols: 80, rows: 24)
        view.feed(text: "\(esc)[?1049h")

        let action = view.handleScroll(lines: -2, x: 12, y: 5)

        XCTAssertEqual(action, .alternateScrollKeys(lines: -2))
        XCTAssertEqual(sentString(delegate), "\(esc)[B\(esc)[B")
    }

    func testAlternateBufferScrollIntentIgnoresWhenAlternateScrollModeIsReset() {
        let delegate = CapturingTerminalViewDelegate()
        let view = TerminalView(frame: .zero)
        view.terminalDelegate = delegate
        view.resize(cols: 80, rows: 24)
        view.feed(text: "\(esc)[?1049h\(esc)[?1007l")

        let action = view.handleScroll(lines: 2, x: 12, y: 5)

        XCTAssertEqual(action, .ignored)
        XCTAssertTrue(delegate.sentData.isEmpty)
    }

    func testScrollDeltaAccumulatesPreciseDeltasBeforeDispatching() {
        let delegate = CapturingTerminalViewDelegate()
        let view = TerminalView(frame: .zero)
        view.terminalDelegate = delegate
        view.resize(cols: 10, rows: 3)
        view.feed(text: "one\r\ntwo\r\nthree\r\nfour\r\nfive\r\nsix\r\n")
        let bottom = view.maxTopVisibleRow

        XCTAssertEqual(view.handleScrollDelta(deltaY: 0.4, x: 0, y: 0, pointsPerLine: 1), .ignored)
        XCTAssertEqual(view.handleScrollDelta(deltaY: 0.4, x: 0, y: 0, pointsPerLine: 1), .ignored)

        let action = view.handleScrollDelta(deltaY: 0.4, x: 0, y: 0, pointsPerLine: 1)

        XCTAssertEqual(action, .localViewport(lines: 1, topVisibleRow: max(0, bottom - 1)))
        XCTAssertEqual(view.topVisibleRow, max(0, bottom - 1))
        XCTAssertTrue(delegate.sentData.isEmpty)
    }

    func testScrollDeltaCapsLinesAndDropsWholeLineOverflow() {
        let delegate = CapturingTerminalViewDelegate()
        let view = TerminalView(frame: .zero)
        view.terminalDelegate = delegate
        view.maximumScrollLinesPerEvent = 3
        view.resize(cols: 80, rows: 24)
        view.feed(text: "\(esc)[?1049h")

        let action = view.handleScrollDelta(deltaY: 10, x: 12, y: 5, pointsPerLine: 1)

        XCTAssertEqual(action, .alternateScrollKeys(lines: 3))
        XCTAssertEqual(sentString(delegate), "\(esc)[A\(esc)[A\(esc)[A")

        XCTAssertEqual(view.handleScrollDelta(deltaY: 0.1, x: 12, y: 5, pointsPerLine: 1), .ignored)
    }

    func testScrollDeltaResetsFractionalRemainderWhenDirectionChanges() {
        var accumulator = TerminalScrollDeltaAccumulator()

        XCTAssertEqual(accumulator.consume(deltaY: 0.75, pointsPerLine: 1, maximumLinesPerEvent: 10), 0)
        XCTAssertEqual(accumulator.consume(deltaY: -0.4, pointsPerLine: 1, maximumLinesPerEvent: 10), 0)
        XCTAssertEqual(accumulator.consume(deltaY: -0.6, pointsPerLine: 1, maximumLinesPerEvent: 10), -1)
    }

    private func sentString(_ delegate: CapturingTerminalViewDelegate) -> String {
        String(decoding: delegate.sentData.flatMap { $0 }, as: UTF8.self)
    }
}

private final class CapturingTerminalViewDelegate: TerminalViewDelegate {
    private(set) var sentData: [[UInt8]] = []

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: TerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        sentData.append(Array(data))
    }
    func scrolled(source: TerminalView, position: Double) {}
    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}
    func clipboardCopy(source: TerminalView, content: Data) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}
#endif
