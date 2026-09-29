#if os(iOS)
import UIKit
import XCTest
@testable import SwiftTerm

@MainActor
final class IOSSelectionHandleTests: XCTestCase {
    private final class Pan: SelectionPanGestureRecognizer {
        var point = CGPoint.zero
        private var recordedOrigin: CGPoint?
        override var touchDownLocation: CGPoint? {
            get { recordedOrigin ?? CGPoint(x: point.x - movement.x, y: point.y - movement.y) }
            set { recordedOrigin = newValue }
        }
        var movement = CGPoint.zero
        var phase: UIGestureRecognizer.State = .began
        override var state: UIGestureRecognizer.State {
            get { phase }
            set { phase = newValue }
        }
        override func location(in view: UIView?) -> CGPoint { point }
        override func translation(in view: UIView?) -> CGPoint { movement }
        override func setTranslation(_ translation: CGPoint, in view: UIView?) {}
    }

    private func makeView() -> TerminalView {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        view.showsSelectionEditMenu = false
        view.feed(text: (0..<80).map { "row \($0) abcdefghijklmnopqrstuvwxyz" }.joined(separator: "\r\n"))
        view.selection.setSelection(start: Position(col: 10, row: 10), end: Position(col: 20, row: 12))
        view.contentOffset = .zero
        return view
    }

    private func knob(_ view: TerminalView, start: Bool) -> CGPoint {
        let p = start ? view.selection.start : view.selection.end
        return CGPoint(x: CGFloat(p.col) * view.cellDimension.width,
                       y: CGFloat(p.row + (start ? 0 : 1)) * view.cellDimension.height + (start ? -6 : 6))
    }

    func testGrabbingKnobDoesNotJumpSelection() {
        for start in [true, false] {
            let view = makeView()
            let pan = Pan()
            pan.point = knob(view, start: start)
            view.panSelectionHandler(pan)
            XCTAssertEqual(view.selection.start, Position(col: 10, row: 10))
            XCTAssertEqual(view.selection.end, Position(col: 20, row: 12))
        }
    }

    func testWideHitTargetActuallyDragsAndKeepsOppositeEndFixed() {
        let view = makeView()
        let pan = Pan()
        pan.point = knob(view, start: false)
        pan.point.x += 20
        XCTAssertTrue(view.isNearSelectionHandle(pan.point))
        view.panSelectionHandler(pan)
        pan.phase = .changed
        pan.point.x += view.cellDimension.width
        pan.movement.x = view.cellDimension.width
        view.panSelectionHandler(pan)
        XCTAssertEqual(view.selection.start, Position(col: 10, row: 10))
        XCTAssertEqual(view.selection.end, Position(col: 21, row: 12))
    }

    func testOverlappingHitTargetsPickNearestKnob() {
        let view = makeView()
        view.selection.setSelection(start: Position(col: 10, row: 10), end: Position(col: 11, row: 10))
        let pan = Pan()
        pan.point = knob(view, start: false)
        view.panSelectionHandler(pan)
        pan.phase = .changed
        pan.point.x += view.cellDimension.width
        pan.movement.x = view.cellDimension.width
        view.panSelectionHandler(pan)
        XCTAssertEqual(view.selection.start, Position(col: 10, row: 10))
        XCTAssertEqual(view.selection.end, Position(col: 12, row: 10))
    }

    func testFastDragUsesTouchDownPosition() {
        let view = makeView()
        let pan = Pan()
        pan.movement = CGPoint(x: 60, y: 0)
        pan.point = knob(view, start: false)
        pan.point.x += pan.movement.x
        view.panSelectionHandler(pan)
        XCTAssertEqual(view.selection.start, Position(col: 10, row: 10))
        XCTAssertEqual(view.selection.end.col, 20 + Int((60 / view.cellDimension.width).rounded()))
        XCTAssertEqual(view.selection.end.row, 12)
    }

    func testCancellationPreservesSelection() {
        let view = makeView()
        let pan = Pan()
        pan.point = knob(view, start: false)
        view.panSelectionHandler(pan)
        pan.phase = .cancelled
        view.panSelectionHandler(pan)
        XCTAssertTrue(view.selection.active)
    }

    func testArbitrationUsesOriginalTouchRatherThanRecognitionLocation() {
        let view = makeView()
        let pan = Pan()
        view.panSelectionGesture = pan
        let origin = knob(view, start: false)
        pan.movement = CGPoint(x: 60, y: 0)
        pan.point = CGPoint(x: origin.x + 60, y: origin.y)
        pan.touchDownLocation = origin
        XCTAssertTrue(view.gestureRecognizerShouldBegin(pan))
        // Dragging onto a handle from elsewhere must still scroll.
        pan.point = origin
        pan.touchDownLocation = CGPoint(x: origin.x - 60, y: origin.y)
        XCTAssertFalse(view.gestureRecognizerShouldBegin(pan))
    }

    func testRecognitionSlopDoesNotConsumeShortDrag() {
        let view = makeView()
        let pan = Pan()
        pan.point = knob(view, start: false)
        pan.touchDownLocation = pan.point
        // UIKit reports only 2pt of translation after a 12pt finger move.
        pan.point.x -= 12
        pan.movement.x = -2
        view.panSelectionHandler(pan)
        XCTAssertEqual(view.selection.end.col, 20 - Int((12 / view.cellDimension.width).rounded()))
        XCTAssertEqual(view.selection.end.row, 12)
    }

    func testSmallVerticalJitterAndReturnToOriginDoNotChangeRows() {
        let view = makeView()
        let pan = Pan()
        let origin = knob(view, start: true)
        pan.point = origin
        view.panSelectionHandler(pan)
        pan.phase = .changed
        pan.point.y -= view.cellDimension.height * 0.4
        view.panSelectionHandler(pan)
        XCTAssertEqual(view.selection.start.row, 10)
        pan.point.y -= view.cellDimension.height
        view.panSelectionHandler(pan)
        XCTAssertEqual(view.selection.start.row, 9)
        pan.point = origin
        view.panSelectionHandler(pan)
        XCTAssertEqual(view.selection.start, Position(col: 10, row: 10))
        XCTAssertEqual(view.selection.end, Position(col: 20, row: 12))
    }

    func testDraggingAfterWordSelectionMovesOneCharacter() {
        let view = makeView()
        view.selection.selectionMode = .word
        let pan = Pan()
        pan.point = knob(view, start: false)
        view.panSelectionHandler(pan)
        pan.phase = .changed
        pan.point.x += view.cellDimension.width
        view.panSelectionHandler(pan)
        XCTAssertEqual(view.selection.end, Position(col: 21, row: 12))
    }

    func testEndBoundaryCanReachLastColumnAndCrossOtherHandle() {
        let view = makeView()
        let pan = Pan()
        pan.point = knob(view, start: false)
        let origin = pan.point
        view.panSelectionHandler(pan)
        pan.phase = .changed
        pan.point.x += 1000
        view.panSelectionHandler(pan)
        XCTAssertEqual(view.selection.end.col, view.getTerminal().cols)
        pan.point = CGPoint(x: origin.x, y: origin.y - 4 * view.cellDimension.height)
        view.panSelectionHandler(pan)
        XCTAssertEqual(view.selection.start, Position(col: 20, row: 8))
        XCTAssertEqual(view.selection.end, Position(col: 10, row: 10))
    }

    func testScrolledViewportHitTestingAndStationaryEdgeScroll() {
        let view = makeView()
        let h = view.cellDimension.height
        view.contentOffset.y = 5 * h
        let pan = Pan()
        pan.point = knob(view, start: false)
        XCTAssertTrue(view.isNearSelectionHandle(pan.point))
        view.panSelectionHandler(pan)
        let beforeOffset = view.contentOffset.y
        let outside = CGPoint(x: pan.point.x, y: view.bounds.height + 1)
        view.scrollSelectionHandle(at: outside)
        XCTAssertEqual(view.contentOffset.y, beforeOffset + h, accuracy: 0.01)
        let firstRow = view.selection.end.row
        view.scrollSelectionHandle(at: outside)
        XCTAssertEqual(view.selection.end.row, firstRow + 1)
        pan.phase = .cancelled
        view.panSelectionHandler(pan)
        let offsetAfterCancel = view.contentOffset.y
        view.scrollSelectionHandle(at: outside)
        XCTAssertEqual(view.contentOffset.y, offsetAfterCancel)
        view.contentOffset.y = 40 * h
        XCTAssertFalse(view.isNearSelectionHandle(CGPoint(x: 10 * view.cellDimension.width, y: 10 * h)))
    }
}
#endif
