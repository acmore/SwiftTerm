#if canImport(AppKit) || canImport(UIKit)
import Foundation
import XCTest
@testable import SwiftTerm

final class TerminalViewportFollowResolverTests: XCTestCase {
    @MainActor
    func testResolverNotSetFallsBackToFollowCursorEnum() {
        let view = TerminalView(frame: .zero)
        view.terminalDelegate = ResolverByteCapture()
        view.resize(cols: 10, rows: 3)
        view.feed(text: "one\r\ntwo\r\nthree\r\nfour\r\n")
        view.setTopVisibleRow(0, notifyAccessibility: false)
        view.viewportFollowPolicy = .followCursor

        view.feed(text: "five\r\nsix\r\n")

        XCTAssertEqual(view.topVisibleRow, view.maxTopVisibleRow)
    }

    @MainActor
    func testResolverReturnsRowOverridesFollowCursor() {
        let view = TerminalView(frame: .zero)
        view.terminalDelegate = ResolverByteCapture()
        view.resize(cols: 10, rows: 3)
        view.feed(text: "one\r\ntwo\r\nthree\r\nfour\r\n")
        view.setTopVisibleRow(0, notifyAccessibility: false)
        view.viewportFollowPolicy = .followCursor
        view.viewportFollowResolver = { _ in 1 }

        view.feed(text: "five\r\nsix\r\n")

        XCTAssertEqual(view.topVisibleRow, 1)
    }

    @MainActor
    func testResolverReturnsNilFallsBackToEnum() {
        let view = TerminalView(frame: .zero)
        view.terminalDelegate = ResolverByteCapture()
        view.resize(cols: 10, rows: 3)
        view.feed(text: "one\r\ntwo\r\nthree\r\nfour\r\n")
        view.setTopVisibleRow(0, notifyAccessibility: false)
        view.viewportFollowPolicy = .followCursor
        view.viewportFollowResolver = { _ in nil }

        view.feed(text: "five\r\nsix\r\n")

        // nil from resolver → enum used (.followCursor → bottom).
        XCTAssertEqual(view.topVisibleRow, view.maxTopVisibleRow)
    }

    @MainActor
    func testResolverOutOfRangeRowGetsClamped() {
        let view = TerminalView(frame: .zero)
        view.terminalDelegate = ResolverByteCapture()
        view.resize(cols: 10, rows: 3)
        view.feed(text: "one\r\ntwo\r\nthree\r\nfour\r\n")
        view.setTopVisibleRow(0, notifyAccessibility: false)
        view.viewportFollowResolver = { _ in 99_999 }

        view.feed(text: "five\r\nsix\r\n")

        XCTAssertEqual(view.topVisibleRow, view.maxTopVisibleRow)
    }

    @MainActor
    func testResolverOutOfRangeNegativeRowGetsClamped() {
        let view = TerminalView(frame: .zero)
        view.terminalDelegate = ResolverByteCapture()
        view.resize(cols: 10, rows: 3)
        view.feed(text: "one\r\ntwo\r\nthree\r\nfour\r\n")
        view.setTopVisibleRow(0, notifyAccessibility: false)
        view.viewportFollowResolver = { _ in -50 }

        view.feed(text: "five\r\nsix\r\n")

        XCTAssertEqual(view.topVisibleRow, 0)
    }

    @MainActor
    func testEnsureCaretIsVisibleDoesNotConsultResolver() {
        #if canImport(UIKit)
        let view = TerminalView(frame: .zero)
        view.terminalDelegate = ResolverByteCapture()
        view.resize(cols: 10, rows: 3)
        view.feed(text: "one\r\ntwo\r\nthree\r\nfour\r\n")

        // Pin viewport away from the bottom via the resolver.
        view.viewportFollowResolver = { _ in 1 }
        view.feed(text: "five\r\n")
        XCTAssertEqual(view.topVisibleRow, 1)

        // ensureCaretIsVisible writes contentOffset directly, bypassing
        // updateScroller() — the resolver is not consulted here. This
        // test pins that contract.
        view.ensureCaretIsVisible()

        // ensureCaretIsVisible doesn't change yDisp on its own — it only
        // moves contentOffset. But since we can't easily assert on
        // contentOffset under zero-frame UIScrollView, instead set a
        // counter and confirm the resolver wasn't reinvoked.
        var calls = 0
        view.viewportFollowResolver = { _ in
            calls += 1
            return 1
        }
        view.ensureCaretIsVisible()
        XCTAssertEqual(calls, 0, "ensureCaretIsVisible must not invoke the viewportFollowResolver")
        #endif
    }

    @MainActor
    func testResolverIsConsultedOnFeedCompletion() {
        let view = TerminalView(frame: .zero)
        view.terminalDelegate = ResolverByteCapture()
        view.resize(cols: 10, rows: 3)
        view.feed(text: "one\r\ntwo\r\nthree\r\nfour\r\n")
        var calls = 0
        view.viewportFollowResolver = { _ in
            calls += 1
            return nil
        }

        view.feed(text: "five\r\n")

        XCTAssertGreaterThan(calls, 0, "feedFinish() should consult the resolver")
    }
}

private final class ResolverByteCapture: TerminalViewDelegate {
    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: TerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func send(source: TerminalView, data: ArraySlice<UInt8>) {}
    func scrolled(source: TerminalView, position: Double) {}
    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}
    func bell(source: TerminalView) {}
    func clipboardCopy(source: TerminalView, content: Data) {}
    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}
#endif
