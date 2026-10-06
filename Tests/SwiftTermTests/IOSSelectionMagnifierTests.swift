#if os(iOS)
import UIKit
import XCTest
@testable import SwiftTerm

@MainActor
final class IOSSelectionMagnifierTests: XCTestCase {
    private final class Press: UILongPressGestureRecognizer {
        var point = CGPoint.zero
        var phase: UIGestureRecognizer.State = .began
        override var state: UIGestureRecognizer.State { get { phase } set { phase = newValue } }
        override func location(in view: UIView?) -> CGPoint { point }
    }

    private final class Pan: SelectionPanGestureRecognizer {
        var point = CGPoint.zero
        var origin = CGPoint.zero
        var phase: UIGestureRecognizer.State = .began
        override var touchDownLocation: CGPoint? { get { origin } set {} }
        override var state: UIGestureRecognizer.State { get { phase } set { phase = newValue } }
        override func location(in view: UIView?) -> CGPoint { point }
    }

    private final class Recorder {
        var begins = 0
        var invalidations = 0
        var hosts: [UIView] = []
        /// Loupe geometry arrives in the host's (window's) coordinates.
        var moves: [(CGPoint, CGRect)] = []
    }

    private func make() -> (UIWindow, TerminalView, Recorder) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 800))
        let view = TerminalView(frame: CGRect(x: 0, y: 80, width: 390, height: 600))
        window.addSubview(view)
        view.longPressSelectsWord = true
        view.showsSelectionEditMenu = false
        view.feed(text: (0..<80).map { "row \($0) abcdefghijklmnopqrstuvwxyz" }.joined(separator: "\r\n"))
        view.contentOffset = .zero
        let recorder = Recorder()
        view.makeSelectionMagnifier = { _, host in
            recorder.begins += 1
            recorder.hosts.append(host)
            return SelectionMagnifierSession(move: { recorder.moves.append(($0, $1)) },
                                             invalidate: { recorder.invalidations += 1 })
        }
        return (window, view, recorder)
    }

    /// The last caret the loupe was moved to, in the terminal view's space.
    private func lastCaret(_ recorder: Recorder, in view: TerminalView, _ window: UIWindow) throws -> CGRect {
        window.convert(try XCTUnwrap(recorder.moves.last).1, to: view)
    }

    func testLongPressMagnifiesSelectedWordWithoutChangingGeometryOrFocus() throws {
        let (window, view, recorder) = make()
        defer { window.isHidden = true }
        let press = Press()
        press.point = CGPoint(x: 12.5 * view.cellDimension.width, y: 10.5 * view.cellDimension.height)
        view.longPress(press)
        XCTAssertEqual(recorder.begins, 0, "Library clients must opt in")
        view.clearSelection()
        view.showsSelectionMagnifier = true
        let bounds = view.bounds
        view.longPress(press)
        XCTAssertEqual(recorder.begins, 1)
        let originalText = view.selectedText
        let first = try lastCaret(recorder, in: view, window)
        press.phase = .changed
        press.point.x += 5
        view.longPress(press)
        XCTAssertEqual(recorder.begins, 1, "Reuse the loupe during the gesture")
        XCTAssertEqual(try lastCaret(recorder, in: view, window), first, "Magnify the selected word even if the finger jitters")
        XCTAssertEqual(view.selectedText, originalText)
        XCTAssertEqual(view.bounds, bounds)
        XCTAssertFalse(view.isFirstResponder)
        press.phase = .ended
        view.longPress(press)
        XCTAssertEqual(recorder.invalidations, 1)
        XCTAssertTrue(view.selectionActive)
    }

    func testOffsetHandleDragTracksMovingBoundaryIncludingCrossingTheAnchor() throws {
        for isStart in [true, false] {
            let (window, view, recorder) = make()
            defer { window.isHidden = true }
            view.showsSelectionMagnifier = true
            view.selection.setSelection(start: Position(col: 10, row: 10), end: Position(col: 20, row: 12))
            let moving = isStart ? view.selection.start : view.selection.end
            let pan = Pan()
            pan.origin = CGPoint(x: CGFloat(moving.col) * view.cellDimension.width + 20,
                                 y: CGFloat(moving.row + (isStart ? 0 : 1)) * view.cellDimension.height + (isStart ? -6 : 6))
            pan.point = pan.origin
            view.panSelectionHandler(pan)
            XCTAssertEqual(try lastCaret(recorder, in: view, window).minX, CGFloat(moving.col) * view.cellDimension.width, accuracy: 0.01)
            pan.phase = .changed
            pan.point.x += view.cellDimension.width
            pan.point.y += (isStart ? 4 : -4) * view.cellDimension.height
            view.panSelectionHandler(pan)
            let caret = try lastCaret(recorder, in: view, window)
            XCTAssertEqual(caret.minX, CGFloat(moving.col + 1) * view.cellDimension.width, accuracy: 0.01)
            XCTAssertEqual(caret.minY, CGFloat(moving.row + (isStart ? 4 : -4)) * view.cellDimension.height, accuracy: 0.01)
            let selected = view.selectedText
            pan.phase = .cancelled
            view.panSelectionHandler(pan)
            XCTAssertEqual(recorder.invalidations, 1)
            XCTAssertEqual(view.selectedText, selected)
        }
    }

    func testLoupeDismissesWhenSelectionClearsViewDetachesOrAppDeactivates() {
        for reason in 0..<4 {
            let (window, view, recorder) = make()
            defer { window.isHidden = true }
            view.showsSelectionMagnifier = true
            let press = Press()
            press.point = CGPoint(x: 12 * view.cellDimension.width, y: 10 * view.cellDimension.height)
            view.longPress(press)
            XCTAssertEqual(recorder.begins, 1)
            switch reason {
            case 0: view.clearSelection()
            case 1: view.removeFromSuperview()
            case 2: NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
            default: view.showsSelectionMagnifier = false
            }
            XCTAssertEqual(recorder.invalidations, 1)
            press.phase = .changed
            view.longPress(press)
            XCTAssertEqual(recorder.begins, 1, "Lifecycle cancellation must not reopen the loupe")
            press.phase = .cancelled
            view.longPress(press)
            XCTAssertEqual(recorder.invalidations, 1)
        }
    }

    func testScrolledCoordinatesAndEdgeScrollKeepSampleInsideViewport() throws {
        let (window, view, recorder) = make()
        defer { window.isHidden = true }
        view.showsSelectionMagnifier = true
        view.selection.setSelection(start: Position(col: 10, row: 10), end: Position(col: 20, row: 12))
        let h = view.cellDimension.height
        view.contentOffset.y = 5 * h
        let pan = Pan()
        pan.origin = CGPoint(x: 20 * view.cellDimension.width, y: 13 * h + 6)
        pan.point = pan.origin
        view.panSelectionHandler(pan)
        XCTAssertEqual(try lastCaret(recorder, in: view, window).minY, 12 * h, accuracy: 0.01)
        view.scrollSelectionHandle(at: CGPoint(x: pan.point.x, y: view.bounds.height + 1))
        XCTAssertTrue(view.bounds.contains(try lastCaret(recorder, in: view, window)))
        pan.phase = .ended
        view.panSelectionHandler(pan)
        XCTAssertEqual(recorder.invalidations, 1)
    }

    func testLoupeIsHostedInTheWindowSoEdgeSamplesAreNotClipped() throws {
        let (window, view, recorder) = make()
        defer { window.isHidden = true }
        view.showsSelectionMagnifier = true
        view.selection.setSelection(start: Position(col: 10, row: 10), end: Position(col: 20, row: 12))
        let pan = Pan()
        pan.origin = CGPoint(x: 20 * view.cellDimension.width, y: 13 * view.cellDimension.height + 6)
        pan.point = pan.origin
        view.panSelectionHandler(pan)
        XCTAssertTrue(recorder.hosts.last === window, "the loupe samples the window, which nothing clips")
        // The finger drags past the right edge and below the terminal onto a
        // key bar: the loupe keeps following, with its caret on screen.
        pan.phase = .changed
        pan.point = CGPoint(x: view.bounds.width + 30, y: view.bounds.height + 20)
        view.panSelectionHandler(pan)
        let move = try XCTUnwrap(recorder.moves.last)
        XCTAssertEqual(move.0, view.convert(pan.point, to: window))
        XCTAssertTrue(window.bounds.contains(move.1))
        XCTAssertEqual(recorder.invalidations, 0, "leaving the view must not dismiss the loupe")
        pan.phase = .cancelled
        view.panSelectionHandler(pan)
        XCTAssertEqual(recorder.invalidations, 1)
    }

    func testLongPressShowsTheMenuOnReleaseNotOnTouchDown() {
        let (window, view, _) = make()
        defer { window.isHidden = true }
        view.showsSelectionEditMenu = true
        let press = Press()
        press.point = CGPoint(x: 12 * view.cellDimension.width, y: 10 * view.cellDimension.height)
        view.longPress(press)
        XCTAssertTrue(view.selectionActive)
        XCTAssertEqual(view.lastLongSelectRegion, .zero, "no menu while the finger is down")
        press.phase = .ended
        view.longPress(press)
        XCTAssertNotEqual(view.lastLongSelectRegion, .zero, "the menu is presented on release")
    }
}
#endif
