#if canImport(AppKit) || canImport(UIKit)
import XCTest
@testable import SwiftTerm

final class TerminalViewportPolicyTests: XCTestCase {
    @MainActor
    func testSetTopVisibleRowClampsToValidScrollbackRange() {
        let view = TerminalView(frame: .zero)
        view.resize(cols: 10, rows: 3)
        view.feed(text: "one\r\ntwo\r\nthree\r\nfour\r\nfive\r\n")

        view.setTopVisibleRow(100, notifyAccessibility: false)

        XCTAssertEqual(view.topVisibleRow, view.maxTopVisibleRow)
    }

    @MainActor
    func testPreserveViewportPolicyKeepsPinnedRowAcrossScrollerUpdate() {
        let view = TerminalView(frame: .zero)
        view.resize(cols: 10, rows: 3)
        view.feed(text: "one\r\ntwo\r\nthree\r\nfour\r\nfive\r\n")
        view.setTopVisibleRow(1, notifyAccessibility: false)
        view.viewportFollowPolicy = .preserveUserPosition

        view.feed(text: "six\r\n")

        XCTAssertEqual(view.topVisibleRow, 1)
    }

    @MainActor
    func testFollowCursorPolicyMovesToBottomAfterOutput() {
        let view = TerminalView(frame: .zero)
        view.resize(cols: 10, rows: 3)
        view.feed(text: "one\r\ntwo\r\nthree\r\nfour\r\n")
        view.setTopVisibleRow(0, notifyAccessibility: false)
        view.viewportFollowPolicy = .followCursor

        view.feed(text: "five\r\nsix\r\n")

        XCTAssertEqual(view.topVisibleRow, view.maxTopVisibleRow)
    }
}
#endif
