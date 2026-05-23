#if canImport(AppKit) || canImport(UIKit)
import XCTest
@testable import SwiftTerm

final class TerminalFeedTransactionTests: XCTestCase {
    @MainActor
    func testHistorySeedTransactionPreservesTopVisibleRowAcrossFedOutput() {
        let view = TerminalView(frame: .zero)
        view.resize(cols: 20, rows: 4)
        view.feed(text: "a\r\nb\r\nc\r\nd\r\ne\r\nf\r\n")
        view.setTopVisibleRow(1, notifyAccessibility: false)

        view.performFeedTransaction(.historySeedPreservingViewport) {
            view.feed(text: "g\r\nh\r\n")
        }

        XCTAssertEqual(view.topVisibleRow, 1)
    }

    @MainActor
    func testNormalTransactionFollowsCursor() {
        let view = TerminalView(frame: .zero)
        view.resize(cols: 20, rows: 4)
        view.feed(text: "a\r\nb\r\nc\r\nd\r\ne\r\n")
        view.setTopVisibleRow(0, notifyAccessibility: false)

        view.performFeedTransaction(.normal) {
            view.feed(text: "f\r\ng\r\n")
        }

        XCTAssertEqual(view.topVisibleRow, view.maxTopVisibleRow)
    }

    @MainActor
    func testHistorySeedTransactionRestoresPreviousViewportPolicy() {
        let view = TerminalView(frame: .zero)
        view.resize(cols: 20, rows: 4)
        view.viewportFollowPolicy = .followCursor

        view.performFeedTransaction(.historySeedPreservingViewport) {
            XCTAssertEqual(view.viewportFollowPolicy, .preserveUserPosition)
            view.feed(text: "a\r\n")
        }

        XCTAssertEqual(view.viewportFollowPolicy, .followCursor)
    }

    @MainActor
    func testHistorySeedTransactionClampsRestoredTopRowAfterReset() {
        let view = TerminalView(frame: .zero)
        view.resize(cols: 20, rows: 4)
        view.feed(text: "a\r\nb\r\nc\r\nd\r\ne\r\nf\r\n")
        view.setTopVisibleRow(view.maxTopVisibleRow, notifyAccessibility: false)
        XCTAssertGreaterThan(view.topVisibleRow, 0)

        view.performFeedTransaction(.historySeedPreservingViewport) {
            view.feed(text: "\u{1b}c")
        }

        XCTAssertEqual(view.topVisibleRow, 0)
        XCTAssertEqual(view.topVisibleRow, view.maxTopVisibleRow)
    }
}
#endif
